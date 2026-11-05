import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/robot_status.dart';
import '../models/stroke_point.dart';
import '../services/stroke_motion_processor.dart';

class RobotProvider with ChangeNotifier {
  WebSocketChannel? _channel;
  RobotStatus _status = RobotStatus();
  String _ipAddress = '192.168.101.166';
  bool _isConnecting = false;

  Timer? _jogHeartbeatTimer;
  Timer? _heartbeatTimer;

  // Kalibrácia pre papier A4 (297 mm v smere X+)
  double paperWidthMm = 210.0;
  double paperHeightMm = 297.0;

  // --- RÝCHLOSŤ & Z KOREKCIA (nastaviteľné v Settings) ---

  /// Maximálna povolená TCP rýchlosť (mm/s).
  static const double maxLinearSpeed = 500.0;

  /// Minimálna použiteľná TCP rýchlosť (mm/s).
  static const double minLinearSpeed = 10.0;

  /// Maximálna Z korekcia (mm) – papier môže byť vyššie/nížšie o 3 cm.
  static const double maxZOffsetMm = 30.0;

  /// Predvolená rýchlosť (mm/s).
  static const double defaultLinearSpeed = 250.0;

  double _linearSpeed = defaultLinearSpeed;

  /// TCP rýchlosť v mm/s (automaticky orezaná na [minLinearSpeed]..[maxLinearSpeed]).
  double get linearSpeed => _linearSpeed;

  set linearSpeed(double value) => _linearSpeed = _clampSpeed(value);

  /// Nominálna (mechanická) výška pera vo vzduchu bez korekcie papiera (mm).
  double penUpNominalZ = 15.0;

  /// Nominálna výška pera v kontakte s papierom bez korekcie (mm).
  double penDownNominalZ = 0.0;

  double _zOffsetMm = 0.0;

  /// Korekcia Z podľa výšky papiera (mm), rozsah ±[maxZOffsetMm].
  ///
  /// Kladná hodnota = papier je vyššie, pero ide vyššie (celá dráha sa
  /// posunie v +Z), záporná = papier je nižšie, pero ide nižšie.
  double get zOffsetMm => _zOffsetMm;

  set zOffsetMm(double value) =>
      _zOffsetMm = value.clamp(-maxZOffsetMm, maxZOffsetMm).toDouble();

  /// Výška pera vo vzduchu včetne korekcie papiera – posiela sa robotovi.
  double get penUpZ => penUpNominalZ + _zOffsetMm;

  /// Výška pera na papieri včetne korekcie papiera – posiela sa robotovi.
  double get penDownZ => penDownNominalZ + _zOffsetMm;

  static double _clampSpeed(double value) =>
      value.clamp(minLinearSpeed, maxLinearSpeed).toDouble();

  // Všetky ťahy zobrazené na Canvas
  final List<List<StrokePoint>> _strokes = [];

  // FIFO Fronta pre asynchrónne spracovanie pohybov
  final List<List<StrokePoint>> _motionQueue = [];
  bool _isProcessingQueue = false;

  // --- STAV POSLEDNEJ ODPOVEDE Z CONTROLLERA ---
  String _lastControllerError = '';
  bool _motionRejected = false;
  DateTime _motionDeadline = DateTime.fromMillisecondsSinceEpoch(0);

  RobotStatus get status => _status;
  String get ipAddress => _ipAddress;
  bool get isConnecting => _isConnecting;
  List<List<StrokePoint>> get strokes => _strokes;
  bool get isProcessingQueue => _isProcessingQueue;

  /// Počet ťahov čakajúcich vo fronte (kým ich robot vykreslí).
  int get pendingStrokes => _motionQueue.length;

  /// Posledná chybová správa z controllerа (prázdny reťazec = bez chyby).
  String get lastControllerError => _lastControllerError;

  /// Controller odmietol posledný pohybový príkaz (code != 0).
  bool get wasMotionRejected => _motionRejected;

  /// Robot hlási poruchu (Fault / statusFlag bit 15 / safetyMode 0).
  bool get hasFault => _status.isFault;

  /// Robot sa hýbe, alebo ešte len dobieha naplánovanú trajektóriu.
  ///
  /// `getCurCPos` v API nevracia príznak pohybu, takže okrem zmeny súradníc
  /// držíme aj "watchdog" – čas, dokedy má pohyb podľa odhadu trvať.
  bool get isRobotBusy =>
      _status.isMoving || DateTime.now().isBefore(_motionDeadline);

  RobotProvider() {
    _initialized = _loadPreferences();
  }

  late final Future<void> _initialized;

  /// Dokončenie načítania uložených nastavení (IP, rýchlosť, Z korekcia).
  Future<void> get initialized => _initialized;

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    _ipAddress = prefs.getString('robot_ip') ?? '192.168.101.166';
    _linearSpeed =
        _clampSpeed(prefs.getDouble('linear_speed') ?? defaultLinearSpeed);
    _zOffsetMm = (prefs.getDouble('z_offset_mm') ?? 0.0)
        .clamp(-maxZOffsetMm, maxZOffsetMm)
        .toDouble();
    notifyListeners();
  }

  Future<void> setIpAddress(String ip) async {
    _ipAddress = ip;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('robot_ip', ip);
    notifyListeners();
  }

  /// Uloží TCP rýchlosť (orezanú na 10..500 mm/s) do SharedPreferences.
  Future<void> setLinearSpeed(double value) async {
    linearSpeed = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('linear_speed', linearSpeed);
    notifyListeners();
    debugPrint(
        "💾 [SETTINGS] Rýchlosť uložená: ${linearSpeed.toStringAsFixed(0)} mm/s");
  }

  /// Uloží Z korekciu papiera (orezanú na ±30 mm) do SharedPreferences.
  Future<void> setZOffset(double value) async {
    zOffsetMm = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('z_offset_mm', zOffsetMm);
    notifyListeners();
    debugPrint(
        "💾 [SETTINGS] Z korekcia uložená: ${zOffsetMm.toStringAsFixed(1)} mm "
        "(pero hore: ${penUpZ.toStringAsFixed(1)} / dole: ${penDownZ.toStringAsFixed(1)})");
  }

  // --- SPOJENIE A SIEŤOVÝ PING ---

  void connect() {
    _isConnecting = true;
    notifyListeners();

    try {
      _stopHeartbeat();
      _channel?.sink.close();
      _channel = IOWebSocketChannel.connect(
        Uri.parse('ws://$_ipAddress:9000'),
      );

      _channel!.stream.listen(
        (message) {
          _isConnecting = false;

          try {
            final decoded = jsonDecode(message as String);
            if (decoded is Map<String, dynamic>) {
              _handleResponse(decoded);
            }
          } catch (e) {
            debugPrint("⚠️ Chyba pri dekódovaní JSON: $e");
          }
        },
        onError: (error) {
          _isConnecting = false;
          _status =
              RobotStatus(robotMode: 'Connection Error', isConnected: false);
          notifyListeners();
        },
        onDone: () {
          _isConnecting = false;
          _status = RobotStatus(robotMode: 'Disconnected', isConnected: false);
          notifyListeners();
        },
      );

      _startHeartbeat();

      // Ak ostali ťahy vo fronte z predchádzajúceho (prerušeného) spojenia,
      // skúsime ich doraziť hneď po nadviazaní komunikácie.
      Future<void>.delayed(const Duration(seconds: 2), () {
        if (_motionQueue.isNotEmpty) _processMotionQueue();
      });
    } catch (e) {
      debugPrint("Výnimka pri pripájaní: $e");
      _isConnecting = false;
      _stopHeartbeat();
      _status = RobotStatus(robotMode: 'Failed to Connect', isConnected: false);
      notifyListeners();
    }
  }

  void disconnect() {
    _stopHeartbeat();
    _jogHeartbeatTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
    _status = RobotStatus();
    _motionRejected = false;
    _motionDeadline = DateTime.fromMillisecondsSinceEpoch(0);
    _lastControllerError = '';
    notifyListeners();
  }

  void _sendJson(Map<String, dynamic> payload) {
    if (_channel != null) {
      _channel!.sink.add(jsonEncode(payload));
    }
  }

  /// Spracuje každú odpoveď z controllerа – chyby, telemetriu aj stav robota.
  void _handleResponse(Map<String, dynamic> json) {
    final action = json['action'];

    // 1. Chyby: `code` (transport, 200 = OK) aj `data.code` (výsledok príkazu).
    final error = RobotStatus.errorFromJson(json);
    if (error != null) {
      _lastControllerError = error;
      debugPrint("🛑 [CONTROLLER ERROR] $_lastControllerError");

      // Ak controller odmietol pohyb (typicky prekrytie dvoch trajektórií),
      // fronta sa nesmie ďalej sypať do robota.
      if (action == 'mov' || action == 'movMulti') {
        _motionRejected = true;
        _motionDeadline = DateTime.fromMillisecondsSinceEpoch(0);
      }
      notifyListeners();
      return;
    }

    // 2. Telemetria / stav
    if (action == 'getCurCPos') {
      _status = RobotStatus.fromCartJson(json, previousStatus: _status);
      notifyListeners();
    } else if (action == 'getRobotStates') {
      _status = RobotStatus.fromStateJson(json, previousStatus: _status);
      notifyListeners();
    }
  }

  /// Čaká na potvrdený pokoj robota (žiadny pohyb + vypršaný watchdog).
  ///
  /// Vráti `false`, ak robot medzitým zhavaroval, odmietol príkaz alebo
  /// sa nezastavil do [timeout].
  Future<bool> waitUntilIdle({
    Duration timeout = const Duration(seconds: 30),
    int stableSamples = 3,
  }) async {
    if (_channel == null || !_status.isConnected) return false;

    final startedAt = DateTime.now();
    int stable = 0;

    while (DateTime.now().difference(startedAt) < timeout) {
      if (_motionRejected) return false;
      if (hasFault) {
        _lastControllerError = 'Robot hlási poruchu (${_status.deviceMode}).';
        notifyListeners();
        return false;
      }

      if (isRobotBusy) {
        stable = 0;
      } else {
        stable++;
        if (stable >= stableSamples) return true;
      }

      await Future<void>.delayed(const Duration(milliseconds: 100));
    }

    _lastControllerError =
        'Timeout: robot sa nezastavil do ${timeout.inSeconds} s.';
    debugPrint("⏱️ [MOTION] $_lastControllerError");
    notifyListeners();
    return false;
  }

  /// Odošle pohybový balík a nastaví watchdog predpokladanej dĺžky pohybu.
  ///
  /// Volajte až po [waitUntilIdle] – dva súbežné pohyby = konflikt
  /// trajektórie v controlleri a následný alarm.
  Future<bool> sendMotionPacket(
    Map<String, dynamic> payload, {
    required int estimatedDurationMs,
  }) async {
    if (_channel == null || !_status.isConnected) return false;

    _motionRejected = false;
    _motionDeadline = DateTime.now().add(
      Duration(milliseconds: estimatedDurationMs.clamp(100, 120000)),
    );
    _sendJson(payload);
    notifyListeners();
    return true;
  }

  /// Zruší chybový stav a pošle controlleru `ClearError` (100).
  Future<void> clearRobotError() async {
    _lastControllerError = '';
    _motionRejected = false;
    _motionDeadline = DateTime.fromMillisecondsSinceEpoch(0);
    notifyListeners();
    await sendControlCommand(100, 'ClearError');
  }

  Future<bool> pingNetworkIP() async {
    try {
      final socket = await Socket.connect(
        _ipAddress,
        80,
        timeout: const Duration(milliseconds: 1500),
      );
      socket.destroy();
      return true;
    } catch (e) {
      return false;
    }
  }

  // --- HEARTBEAT & TELEMETRIA ---

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (_channel != null) {
        getCartesianPosition();
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void getCartesianPosition() {
    _sendJson({
      "id": DateTime.now().millisecondsSinceEpoch,
      "action": "getCurCPos",
      "data": [],
      "type": "common"
    });
  }

  // --- RIADIACE PRÍKAZY (MOTORY & REŽIMY) ---

  Future<void> sendControlCommand(int commandValue, String label) async {
    final payload = {
      "id": DateTime.now().millisecondsSinceEpoch,
      "type": "common",
      "action": "setparam",
      "data": [
        {
          "path": "Robot/Control/command",
          "value": commandValue,
        }
      ]
    };
    _sendJson(payload);
    debugPrint("➡️ Príkaz odoslaný [$label]: value = $commandValue");
  }

  Future<void> setMotorPower(bool turnOn) async {
    if (_channel == null || !_status.isConnected) return;

    if (turnOn) {
      debugPrint("⚡ Zapínam motory robota...");
      await sendControlCommand(100, "ClearError");
      await Future.delayed(const Duration(milliseconds: 200));
      await sendControlCommand(1, "Power On");
      await Future.delayed(const Duration(milliseconds: 300));
    } else {
      debugPrint("🔌 Vypínam motory robota...");
      await sendControlCommand(2, "Power Off");
    }
  }

  Future<void> setRobotMode(bool isAuto) async {
    if (_channel == null || !_status.isConnected) return;

    int modeVal = isAuto ? 5 : 3;
    await sendControlCommand(modeVal, isAuto ? "ToAuto" : "ToManual");
    await Future.delayed(const Duration(milliseconds: 200));
    await sendControlCommand(100, "ClearError");
    await Future.delayed(const Duration(milliseconds: 200));
    await sendControlCommand(1, "Power On");
    await Future.delayed(const Duration(milliseconds: 400));
  }

  void stopMovement() {
    _motionQueue.clear();
    _motionDeadline = DateTime.fromMillisecondsSinceEpoch(0);
    _motionRejected = false;
    stopTcpJog();
    _sendJson({
      "id": DateTime.now().millisecondsSinceEpoch,
      "action": "stopMov",
      "data": [],
      "type": "common"
    });
  }

  // --- TCP JOGGING ---

  void startTcpJog(int jogIndex, int speedDirection) {
    final payload = {
      "action": "setparam",
      "id": DateTime.now().millisecondsSinceEpoch,
      "type": "common",
      "data": [
        {"path": "Robot/Control/jogMode", "value": 2},
        {"path": "Robot/Control/jogSpeed", "value": speedDirection},
        {"path": "Robot/Control/jogIndex", "value": jogIndex}
      ]
    };
    _sendJson(payload);

    _jogHeartbeatTimer?.cancel();
    _jogHeartbeatTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      _sendJogHeartbeat();
    });
  }

  void _sendJogHeartbeat() {
    final payload = {
      "action": "setparam",
      "id": DateTime.now().millisecondsSinceEpoch,
      "type": "common",
      "data": [
        {
          "path": "Robot/Control/commandHeart",
          "value": DateTime.now().millisecondsSinceEpoch
        }
      ]
    };
    _sendJson(payload);
  }

  void stopTcpJog() {
    _jogHeartbeatTimer?.cancel();
    final payload = {
      "action": "setparam",
      "id": DateTime.now().millisecondsSinceEpoch,
      "type": "common",
      "data": [
        {"path": "Robot/Control/jogMode", "value": 0},
        {"path": "Robot/Control/jogSpeed", "value": 0},
        {"path": "Robot/Control/jogIndex", "value": 0}
      ]
    };
    _sendJson(payload);
  }

  // --- FIFO SPRACUVOVANIE ŤAHOV & KRESLENIE ---

  void addStroke(List<StrokePoint> stroke) {
    if (stroke.isNotEmpty) {
      _strokes.add(stroke);
      _motionQueue.add(stroke);
      notifyListeners();

      _processMotionQueue();
    }
  }

  void clearCanvas() {
    _strokes.clear();
    _motionQueue.clear();
    notifyListeners();
  }

  /// Hlavný asynchrónny cyklus: Posiela ťahy postupne a čaká na úplné zastavenie robota
  // V RobotProvider dodaj verejný getter pre odoslanie JSON-u:
  void sendPayload(Map<String, dynamic> payload) => _sendJson(payload);

  // A _processMotionQueue sa skráti na jednoduché volanie servisu:
  Future<void> _processMotionQueue() async {
    if (_isProcessingQueue ||
        _motionQueue.isEmpty ||
        _channel == null ||
        !_status.isConnected) {
      return;
    }

    _isProcessingQueue = true;
    notifyListeners();

    try {
      final processor = StrokeMotionProcessor(this);
      await processor.processQueue(_motionQueue);
    } finally {
      _isProcessingQueue = false;
      notifyListeners();
    }
  }

  /// Tvorba bodu pre Codroid controller
  Map<String, dynamic> _buildCartPoint(double x, double y, double z,
      {required String zoneType, double zdis = 4.0}) {
    return {
      "type": "movl",
      "target": {
        "type": "cpos",
        "cpos": {
          "x": x,
          "y": y,
          "z": z,
          "a": -180.0,
          "b": 0.0,
          "c": 90.0,
          "poscfg": {
            "mode": 7,
            "cf1": -1,
            "cf2": -1,
            "cf3": -1,
            "cf4": -1,
            "cf5": -1,
            "cf6": -1,
            "cf7": -1
          }
        }
      },
      "speed": {
        "sori": 50.0,
        "sper": 0.0,
        "stcp": linearSpeed,
        "sexjl": 0.0,
        "sexjr": 0.0
      },
      "acc": {
        "aori": 50.0,
        "aper": 0.0,
        "atcp": 100.0,
        "aexjl": 0.0,
        "aexjr": 0.0
      },
      "zone": zoneType == "FINE"
          ? {
              "type": "FINE",
              "data": {"zper": 0, "zdis": 0, "zvconst": 0}
            }
          : {
              "type": "RELATIVE",
              "data": {"zper": 50, "zdis": zdis, "zvconst": 50}
            }
    };
  }

  /// Odoslanie jedného zvislého pohybu (Nájazd / Klesnutie / Zdvih pera)
  Future<void> _sendSingleMovl(double x, double y, double z,
      {required String zoneType}) async {
    final payload = {
      "id": DateTime.now().millisecondsSinceEpoch,
      "type": "common",
      "action": "mov",
      "data": {
        "type": "movl",
        "target": {
          "type": "cpos",
          "cpos": {
            "x": x,
            "y": y,
            "z": z,
            "a": -180.0,
            "b": 0.0,
            "c": 90.0,
            "poscfg": {
              "mode": 7,
              "cf1": -1,
              "cf2": -1,
              "cf3": -1,
              "cf4": -1,
              "cf5": -1,
              "cf6": -1,
              "cf7": -1
            }
          }
        },
        "speed": {
          "sori": 50.0,
          "sper": 0.0,
          "stcp": linearSpeed,
          "sexjl": 0.0,
          "sexjr": 0.0
        },
        "acc": {
          "aori": 50.0,
          "aper": 0.0,
          "atcp": 100.0,
          "aexjl": 0.0,
          "aexjr": 0.0
        },
        "zone": zoneType == "FINE"
            ? {
                "type": "FINE",
                "data": {"zper": 0, "zdis": 0, "zvconst": 0}
              }
            : {
                "type": "RELATIVE",
                "data": {"zper": 50, "zdis": 4.0, "zvconst": 50}
              }
      }
    };
    _sendJson(payload);
    await Future.delayed(const Duration(milliseconds: 350));
  }

  // --- OBNOVENÉ TESTOVACIE POMOCNÉ FUNKCIE ---

  /// Relative movement: moves dx in X, then dy in Y from current Cartesian position
  Future<void> moveRelativeXthenY(double dx, double dy) async {
    if (_channel == null || !_status.isConnected) {
      debugPrint("⚠️ Cannot send relative move: Robot is not connected!");
      return;
    }

    double startX = _status.cartPosition.x;
    double startY = _status.cartPosition.y;
    double startZ = _status.cartPosition.z;

    if (startX == 0.0 && startY == 0.0 && startZ == 0.0) {
      startX = 50.0;
      startY = 100.0;
      startZ = penUpZ;
    }

    double step1X = startX + dx;
    double step1Y = startY;

    double step2X = startX + dx;
    double step2Y = startY + dy;

    debugPrint(
        "📍 [RELATIVE STEP] Start: ($startX, $startY) -> Step 1 X+: ($step1X, $step1Y) -> Step 2 Y+: ($step2X, $step2Y)");

    await sendControlCommand(5, "ToAuto");
    await Future.delayed(const Duration(milliseconds: 150));
    await sendControlCommand(100, "ClearError");
    await Future.delayed(const Duration(milliseconds: 150));
    await sendControlCommand(1, "Power On");
    await Future.delayed(const Duration(milliseconds: 300));

    List<Map<String, dynamic>> points = [
      _buildCartPoint(step1X, step1Y, startZ, zoneType: "FINE"),
      _buildCartPoint(step2X, step2Y, startZ, zoneType: "FINE"),
    ];

    final payload = {
      "id": DateTime.now().millisecondsSinceEpoch,
      "type": "common",
      "action": "movMulti",
      "data": {
        "type": "movCart",
        "user": 1,
        "tool": 1,
        "points": points,
      }
    };

    _sendJson(payload);
  }

  /// Generuje a odosiela balík 10 bodov s odstupom 5 mm v smere +X
  Future<void> sendTenPointsTest() async {
    if (_channel == null || !_status.isConnected) {
      debugPrint("⚠️ Robot nie je pripojený!");
      return;
    }

    double startX = _status.cartPosition.x;
    double startY = _status.cartPosition.y;
    double startZ = _status.cartPosition.z;

    if (startX == 0.0 && startY == 0.0 && startZ == 0.0) {
      startX = 50.0;
      startY = 100.0;
      startZ = penUpZ;
    }

    List<Map<String, dynamic>> points = [];

    for (int i = 1; i <= 10; i++) {
      double px = startX + (i * 5.0);
      double py = startY;
      double pz = startZ;

      String zone = (i == 10) ? "FINE" : "RELATIVE";
      points.add(_buildCartPoint(px, py, pz, zoneType: zone, zdis: 4.0));
    }

    debugPrint(
        "📍 [10-POINT TEST] Odosielam 10 bodov (5 mm krok, RELATIVE) v movMulti...");

    await sendControlCommand(5, "ToAuto");
    await Future.delayed(const Duration(milliseconds: 150));
    await sendControlCommand(100, "ClearError");
    await Future.delayed(const Duration(milliseconds: 150));
    await sendControlCommand(1, "Power On");
    await Future.delayed(const Duration(milliseconds: 300));

    final payload = {
      "id": DateTime.now().millisecondsSinceEpoch,
      "type": "common",
      "action": "movMulti",
      "data": {
        "type": "movCart",
        "user": 1,
        "tool": 1,
        "points": points,
      }
    };

    _sendJson(payload);
  }

  /// Priamy testovací pohyb na konkrétne kartézske súradnice cez príkaz `mov`
  Future<void> moveToPoint(double x, double y, double z,
      {double a = -180.0, double b = 0.0, double c = 90.0}) async {
    if (_channel == null || !_status.isConnected) {
      debugPrint("⚠️ Cannot send move: Robot is not connected!");
      return;
    }

    debugPrint(
        "📍 [TEST MOVE] Target -> X: $x, Y: $y, Z: $z, A: $a, B: $b, C: $c");

    await sendControlCommand(5, "ToAuto");
    await Future.delayed(const Duration(milliseconds: 150));
    await sendControlCommand(100, "ClearError");
    await Future.delayed(const Duration(milliseconds: 150));
    await sendControlCommand(1, "Power On");
    await Future.delayed(const Duration(milliseconds: 300));

    final payload = {
      "id": DateTime.now().millisecondsSinceEpoch,
      "type": "common",
      "action": "mov",
      "data": {
        "type": "movl",
        "target": {
          "type": "cpos",
          "cpos": {
            "x": x,
            "y": y,
            "z": z,
            "a": a,
            "b": b,
            "c": c,
            "poscfg": {
              "mode": 7,
              "cf1": -1,
              "cf2": -1,
              "cf3": -1,
              "cf4": -1,
              "cf5": -1,
              "cf6": -1,
              "cf7": -1
            }
          }
        },
        "speed": {
          "sori": 50.0,
          "sper": 0.0,
          "stcp": linearSpeed,
          "sexjl": 0.0,
          "sexjr": 0.0
        },
        "acc": {
          "aori": 50.0,
          "aper": 0.0,
          "atcp": 100.0,
          "aexjl": 0.0,
          "aexjr": 0.0
        },
        "zone": {
          "type": "FINE",
          "data": {"zper": 0, "zdis": 0, "zvconst": 0}
        }
      }
    };

    _sendJson(payload);
  }

  /// Presun robota do domovskej pozície (Z = 15 mm)
  Future<void> moveToCanvasHome() async {
    if (_channel == null || !_status.isConnected) return;

    await sendControlCommand(5, "ToAuto");
    await Future.delayed(const Duration(milliseconds: 150));
    await sendControlCommand(100, "ClearError");
    await Future.delayed(const Duration(milliseconds: 150));
    await sendControlCommand(1, "Power On");
    await Future.delayed(const Duration(milliseconds: 300));

    await _sendSingleMovl(50.0, 100.0, penUpZ, zoneType: "FINE");
  }

  /// Skúšobný zvislý pohyb pera na aktuálnom X/Y – kontrola Z korekcie papiera.
  ///
  /// [down] = `true` → pero klesne na [penDownZ], `false` → zdvihne na [penUpZ].
  /// Vráti `false`, ak robot nie je pripojený / je zaneprázdnený / nemá
  /// známu pozíciu.
  Future<bool> movePenToHeight({required bool down}) async {
    if (_channel == null || !_status.isConnected) return false;
    if (_isProcessingQueue || isRobotBusy) {
      debugPrint("⚠️ [Z TEST] Robot je zaneprázdnený – Z test preskočený.");
      return false;
    }

    final c = _status.cartPosition;
    if (c.x == 0.0 && c.y == 0.0 && c.z == 0.0) {
      debugPrint(
          "⚠️ [Z TEST] Neznáma pozícia robota – najprv načítaj telemetriu.");
      return false;
    }

    final targetZ = down ? penDownZ : penUpZ;
    debugPrint("📐 [Z TEST] Pero ${down ? 'dole' : 'hore'} na Z = "
        "${targetZ.toStringAsFixed(1)} mm (korekcia ${zOffsetMm.toStringAsFixed(1)} mm)");

    await _sendSingleMovl(c.x, c.y, targetZ, zoneType: "FINE");
    return true;
  }

  /// Test 2 bodov v jednom movMulti balíku (+10mm X, potom +20mm Y)
  Future<void> sendTwoPointsTest() async {
    if (_channel == null || !_status.isConnected) {
      debugPrint("⚠️ Robot nie je pripojený!");
      return;
    }

    double startX = _status.cartPosition.x;
    double startY = _status.cartPosition.y;
    double startZ = _status.cartPosition.z;

    if (startX == 0.0 && startY == 0.0 && startZ == 0.0) {
      startX = 50.0;
      startY = 100.0;
      startZ = penUpZ;
    }

    double p1X = startX + 10.0;
    double p1Y = startY;

    double p2X = startX + 10.0;
    double p2Y = startY + 20.0;

    List<Map<String, dynamic>> points = [
      _buildCartPoint(p1X, p1Y, startZ, zoneType: "FINE"),
      _buildCartPoint(p2X, p2Y, startZ, zoneType: "FINE"),
    ];

    debugPrint("📍 [2-POINT TEST] Odosielam 2 body (FINE) v movMulti...");

    await sendControlCommand(5, "ToAuto");
    await Future.delayed(const Duration(milliseconds: 150));
    await sendControlCommand(100, "ClearError");
    await Future.delayed(const Duration(milliseconds: 150));
    await sendControlCommand(1, "Power On");
    await Future.delayed(const Duration(milliseconds: 300));

    final payload = {
      "id": DateTime.now().millisecondsSinceEpoch,
      "type": "common",
      "action": "movMulti",
      "data": {
        "type": "movCart",
        "user": 1,
        "tool": 1,
        "points": points,
      }
    };

    _sendJson(payload);
  }

  /// Test 3 bodov v jednom movMulti balíku so zónou RELATIVE na strednom bode
  Future<void> sendThreePointsTest() async {
    if (_channel == null || !_status.isConnected) {
      debugPrint("⚠️ Robot nie je pripojený!");
      return;
    }

    double startX = _status.cartPosition.x;
    double startY = _status.cartPosition.y;
    double startZ = _status.cartPosition.z;

    if (startX == 0.0 && startY == 0.0 && startZ == 0.0) {
      startX = 50.0;
      startY = 100.0;
      startZ = penUpZ;
    }

    List<Map<String, dynamic>> points = [
      _buildCartPoint(startX + 10.0, startY, startZ, zoneType: "FINE"),
      _buildCartPoint(startX + 10.0, startY + 10.0, startZ,
          zoneType: "RELATIVE", zdis: 4.0),
      _buildCartPoint(startX + 10.0, startY + 20.0, startZ, zoneType: "FINE"),
    ];

    debugPrint(
        "📍 [3-POINT RELATIVE TEST] Odosielam 3 body (stredný RELATIVE) v movMulti...");

    await sendControlCommand(5, "ToAuto");
    await Future.delayed(const Duration(milliseconds: 150));
    await sendControlCommand(100, "ClearError");
    await Future.delayed(const Duration(milliseconds: 150));
    await sendControlCommand(1, "Power On");
    await Future.delayed(const Duration(milliseconds: 300));

    final payload = {
      "id": DateTime.now().millisecondsSinceEpoch,
      "type": "common",
      "action": "movMulti",
      "data": {
        "type": "movCart",
        "user": 1,
        "tool": 1,
        "points": points,
      }
    };

    _sendJson(payload);
  }
}
