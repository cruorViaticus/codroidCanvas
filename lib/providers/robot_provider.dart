import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/robot_status.dart';
import '../models/stroke_point.dart';

class RobotProvider with ChangeNotifier {
  WebSocketChannel? _channel;
  RobotStatus _status = RobotStatus();
  String _ipAddress = '192.168.101.166';
  bool _isConnecting = false;

  Timer? _telemetryTimer;
  Timer? _jogHeartbeatTimer;
  Timer? _heartbeatTimer;

  // Kalibrácia pre papier A4 (297 mm v smere X+)
  double paperWidthMm = 210.0;
  double paperHeightMm = 297.0;

  double linearSpeed = 50.0;

  // Kalibrované Z-výšky
  double penUpZ = 15.0; // Výška vo vzduchu (mm)
  double penDownZ = -3.0; // Kontakt s papierom (mm)

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
    linearSpeed = prefs.getDouble('linear_speed') ?? 50.0;
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

            // 1. Kompletný výpis všetkých prichádzajúcich správ
            debugPrint("📩 [ROBOT RAW LOG]: $message");

            // 2. Kontrola chýb v reakcii na mov / movMulti
            if (json.containsKey('code') && json['code'] != 0) {
              debugPrint(
                  "🛑 [CONTROLLER ERROR] ID: ${json['id']} | Code: ${json['code']} | Msg: ${json['msg'] ?? json['info'] ?? 'Unknown Error'}");
            }

            // 3. Reakcia na stav zmov/movMulti
            if (json['action'] == 'movMulti' || json['action'] == 'mov') {
              debugPrint(
                  "🟢 [MOTION ACK]: Movement received by controller: $json");
            }

            if (json['action'] == 'getCurCPos') {
              _status = RobotStatus.fromCartJson(json);
              notifyListeners();
            }
          } catch (e) {
            debugPrint("⚠️ Chyba pri dekódovaní JSON: $e");
          }
        },
        // ...
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
    _telemetryTimer?.cancel();
    _jogHeartbeatTimer?.cancel();
    _channel?.sink.close();
    _status = RobotStatus();
    notifyListeners();
  }

  void _sendJson(Map<String, dynamic> payload) {
    if (_channel != null) {
      _channel!.sink.add(jsonEncode(payload));
    }
  }

  /// Rýchla kontrola dostupnosti robota v sieti cez TCP ping na port 80
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
      debugPrint("⚡ Zapínam motory robota (ClearError -> Power On)...");
      await sendControlCommand(100, "ClearError");
      await Future.delayed(const Duration(milliseconds: 300));

      await sendControlCommand(1, "Power On");
      await Future.delayed(const Duration(milliseconds: 500));
    } else {
      debugPrint("🔌 Vypínam motory robota (Power Off)...");
      await sendControlCommand(2, "Power Off");
    }
  }

  Future<void> setRobotMode(bool isAuto) async {
    if (_channel == null || !_status.isConnected) return;

    int modeVal = isAuto ? 5 : 3;
    debugPrint("🔄 Prepínam režim na ${isAuto ? 'Auto (5)' : 'Manual (3)'}...");

    await sendControlCommand(modeVal, isAuto ? "ToAuto" : "ToManual");
    await Future.delayed(const Duration(milliseconds: 400));

    await sendControlCommand(100, "ClearError");
    await Future.delayed(const Duration(milliseconds: 300));

    await sendControlCommand(1, "Power On");
    await Future.delayed(const Duration(milliseconds: 600));
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

  Future<void> _processMotionQueue() async {
    if (_isProcessingQueue || _motionQueue.isEmpty || _channel == null || !_status.isConnected) {
      return;
    }

    _isProcessingQueue = true;
    notifyListeners();

    // 1. Štart sekvencie pre Auto režim a zapnutie motorov
    await sendControlCommand(5, "ToAuto");
    await Future.delayed(const Duration(milliseconds: 200));
    await sendControlCommand(100, "ClearError");
    await Future.delayed(const Duration(milliseconds: 200));
    await sendControlCommand(1, "Power On");
    await Future.delayed(const Duration(milliseconds: 400));

    while (_motionQueue.isNotEmpty) {
      final currentStroke = _motionQueue.removeAt(0);

      if (currentStroke.length < 2) continue;

      // 2. Filtrovanie bodov: odstup min 1.5 mm pre ochranu zrýchlenia
      List<StrokePoint> filtered = [currentStroke.first];
      for (int i = 1; i < currentStroke.length; i++) {
        double dx = (currentStroke[i].y - filtered.last.y) * 297.0;
        double dy = (currentStroke[i].x - filtered.last.x) * 210.0;
        // 1.5 mm prah (1.5 * 1.5 = 2.25)
        if ((dx * dx + dy * dy) >= 2.25) {
          filtered.add(currentStroke[i]);
        }
      }

      if (filtered.length < 2) continue;

      List<Map<String, dynamic>> points = [];

      // Start point - Nájazd vo vzduchu (FINE) + Klesnutie na papier (Z1)
      double startX = (1.0 - filtered.first.y) * 297.0;
      double startY = (1.0 - filtered.first.x) * 210.0;
      points.add(_buildCartPoint(startX, startY, penUpZ, zoneType: "FINE"));
      points.add(_buildCartPoint(startX, startY, penDownZ, zoneType: "Z1"));

      // Stredné body: jemná prechodová zóna Z1 (1.0 mm) vhodná pre malé úseky S Penu
      for (int i = 1; i < filtered.length - 1; i++) {
        double px = (1.0 - filtered[i].y) * 297.0;
        double py = (1.0 - filtered[i].x) * 210.0;
        points.add(_buildCartPoint(px, py, penDownZ, zoneType: "Z1"));
      }

      // End point - Posledný bod na papieri (FINE) + Dvihnutie pera (FINE)
      double lastX = (1.0 - filtered.last.y) * 297.0;
      double lastY = (1.0 - filtered.last.x) * 210.0;
      points.add(_buildCartPoint(lastX, lastY, penDownZ, zoneType: "FINE"));
      points.add(_buildCartPoint(lastX, lastY, penUpZ, zoneType: "FINE"));

      debugPrint("📦 Odosielam trajektóriu (${points.length} bodov) v movMulti...");

      // 3. Odoslanie celého ťahu v jednom movMulti balíku
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

      // Čakacia doba podľa počtu bodov
      int estimatedTravelTimeMs = (points.length * 60) + 800;
      await Future.delayed(Duration(milliseconds: estimatedTravelTimeMs));
    }

    _isProcessingQueue = false;
    notifyListeners();
  }

  /// Pomocná metóda pre tvorbu bodu s podporou jemnej zóny Z1 (1.0 mm)
  Map<String, dynamic> _buildCartPoint(double x, double y, double z,
      {required String zoneType}) {
    return {
      "type": "movl",
      "target": {
        "type": "cpos",
        "cpos": {
          "x": x,
          "y": y,
          "z": z,
          "a": -180.0, // Zhoda s otestovanou A/B orientáciou
          "b": 0.0,
          "c": 90.0,
          "poscfg": {
            "mode": 7,
            "cf1": 0, "cf2": 0, "cf3": 0, "cf4": 0, "cf5": 0, "cf6": 0, "cf7": 0
          }
        }
      },
      "speed": {
        "sori": 30.0,
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
              "type": "Z1", // 👈 Polomer zóny 1.0 mm pre dodržanie podmienky zdis < segment
              "data": {"zper": 0, "zdis": 1.0, "zvconst": 0}
            }
    };
  }

/// Direct test movement to specific Cartesian coordinates using single `mov` action
  Future<void> moveToPoint(double x, double y, double z,
      {double a = -180.0, double b = 0.0, double c = 90.0}) async {
    if (_channel == null || !_status.isConnected) {
      debugPrint("⚠️ Cannot send move: Robot is not connected!");
      return;
    }

    debugPrint("📍 [TEST MOVE] Target -> X: $x, Y: $y, Z: $z, A: $a, B: $b, C: $c");

    // 1. Force Auto mode sequence before movement
    await sendControlCommand(5, "ToAuto");
    await Future.delayed(const Duration(milliseconds: 200));
    await sendControlCommand(100, "ClearError");
    await Future.delayed(const Duration(milliseconds: 200));
    await sendControlCommand(1, "Power On");
    await Future.delayed(const Duration(milliseconds: 400));

    // 2. Single movl payload
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
              "cf1": 0, "cf2": 0, "cf3": 0, "cf4": 0, "cf5": 0, "cf6": 0, "cf7": 0
            }
          }
        },
        "speed": {
          "sori": 30.0,
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
  Future<void> moveToCanvasHome() async {
    if (_channel == null) return;

    await sendControlCommand(5, "ToAuto");
    await Future.delayed(const Duration(milliseconds: 200));
    await sendControlCommand(100, "ClearError");
    await Future.delayed(const Duration(milliseconds: 150));
    await sendControlCommand(1, "Power On");
    await Future.delayed(const Duration(milliseconds: 400));

    final payload = {
      "id": DateTime.now().millisecondsSinceEpoch,
      "type": "common",
      "action": "mov",
      "data": {
        "type": "movl",
        "target": {
          "type": "cpos",
          "cpos": {
            "x": 50.0,
            "y": 100.0,
            "z": 200.0,
            "a": 180.0,
            "b": 0.0,
            "c": 90.0,
            "poscfg": {
              "mode": 7,
              "cf1": 0,
              "cf2": 0,
              "cf3": 0,
              "cf4": 0,
              "cf5": 0,
              "cf6": 0,
              "cf7": 0
            }
          }
        },
        "speed": {
          "sori": 30.0,
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
}
