import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
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

  // Rýchlosť a akcelerácia
  double linearSpeed = 250.0; // Predvolená rýchlosť (mm/s)

  // Kalibrované Z-výšky
  double penUpZ = 15.0; // Východzia pozícia / výška vo vzduchu (15 mm)
  double penDownZ = 0.0; // Kontakt s papierom (0 mm)

  // Všetky ťahy zobrazené na Canvas
  final List<List<StrokePoint>> _strokes = [];

  // FIFO Fronta pre asynchrónne spracovanie pohybov
  final List<List<StrokePoint>> _motionQueue = [];
  bool _isProcessingQueue = false;

  RobotStatus get status => _status;
  String get ipAddress => _ipAddress;
  bool get isConnecting => _isConnecting;
  List<List<StrokePoint>> get strokes => _strokes;
  bool get isProcessingQueue => _isProcessingQueue;

  RobotProvider() {
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    _ipAddress = prefs.getString('robot_ip') ?? '192.168.101.166';
    linearSpeed = prefs.getDouble('linear_speed') ?? 250.0;
    notifyListeners();
  }

  Future<void> setIpAddress(String ip) async {
    _ipAddress = ip;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('robot_ip', ip);
    notifyListeners();
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
            final json = jsonDecode(message as String);

            if (json.containsKey('code') && json['code'] != 0) {
              debugPrint(
                  "🛑 [CONTROLLER ERROR] ID: ${json['id']} | Code: ${json['code']} | Msg: ${json['msg'] ?? json['info'] ?? 'Unknown Error'}");
            }

            if (json['action'] == 'getCurCPos') {
              _status = RobotStatus.fromCartJson(
                json,
                previousStatus: _status,
              );
              notifyListeners();
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
    notifyListeners();
  }

  void _sendJson(Map<String, dynamic> payload) {
    if (_channel != null) {
      _channel!.sink.add(jsonEncode(payload));
    }
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
    if (_isProcessingQueue || _motionQueue.isEmpty || _channel == null || !_status.isConnected) {
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
