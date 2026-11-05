import 'package:flutter/foundation.dart';

class RobotStatus {
  final CartesianPosition cartPosition;
  final String robotMode;
  final bool isConnected;
  final bool isMoving; // 👈 1. Nové pole pre pohyb robota

  /// Režim z `getRobotStates` (Idle / Jogging / ToPoint / AutoRunning / Fault…).
  final String deviceMode;

  /// Bitová maska z `getRobotStates` (bit 3 = Moving, bit 15 = Error).
  final int statusFlag;

  /// 1 = Normamode, 2 = E-stop, 3 = Rescue, 4 = Reduction, 0 = Error existed.
  final int safetyMode;

  /// Posledná chybová správa z controllerа (prázdny reťazec = bez chyby).
  final String lastError;

  RobotStatus({
    CartesianPosition? cartPosition,
    this.robotMode = 'Disconnected',
    this.isConnected = false,
    this.isMoving = false, // 👈 Predvolená hodnota false
    this.deviceMode = '',
    this.statusFlag = 0,
    this.safetyMode = 1,
    this.lastError = '',
  }) : cartPosition = cartPosition ?? CartesianPosition();

  double get x => cartPosition.x;
  double get y => cartPosition.y;
  double get z => cartPosition.z;

  /// Bit 3 v `statusFlag` znamená "Moving" (viď dokumentácia GetRobotStateFlag).
  bool get isMovingFlag => (statusFlag >> 3) & 1 == 1;

  /// Bit 15 = Error, alebo režim Fault, alebo safetyMode 0 ("Error existed").
  bool get isFault =>
      (statusFlag >> 15) & 1 == 1 || deviceMode == 'Fault' || safetyMode == 0;

  RobotStatus copyWith({
    CartesianPosition? cartPosition,
    String? robotMode,
    bool? isConnected,
    bool? isMoving,
    String? deviceMode,
    int? statusFlag,
    int? safetyMode,
    String? lastError,
  }) {
    return RobotStatus(
      cartPosition: cartPosition ?? this.cartPosition,
      robotMode: robotMode ?? this.robotMode,
      isConnected: isConnected ?? this.isConnected,
      isMoving: isMoving ?? this.isMoving,
      deviceMode: deviceMode ?? this.deviceMode,
      statusFlag: statusFlag ?? this.statusFlag,
      safetyMode: safetyMode ?? this.safetyMode,
      lastError: lastError ?? this.lastError,
    );
  }

  factory RobotStatus.fromCartJson(
    Map<String, dynamic> json, {
    RobotStatus? previousStatus, // 👈 Voliteľný predchádzajúci stav pre výpočet delty
  }) {
    debugPrint("📊 [getCurCPos TELEMETRY]: $json");

    final newPos = CartesianPosition.fromJson(json);

    // Detekcia pohybu z JSON-u Codroidu
    bool moving = false;
    final data = json['data'] ?? json;

    if (data is Map) {
      // Controller môže príznak pohybu poslať priamo v `data`
      // alebo o úroveň nižšie v `data.data` (viď príklad getCurCPos v API).
      final Map nodes = {...data};
      final nested = data['data'];
      if (nested is Map) nodes.addAll(nested);

      if (nodes.containsKey('moving')) {
        moving = nodes['moving'] == true || nodes['moving'] == 1;
      } else if (nodes.containsKey('is_moving')) {
        moving = nodes['is_moving'] == true || nodes['is_moving'] == 1;
      } else if (nodes.containsKey('exec_state')) {
        moving = nodes['exec_state'] == 1 || nodes['exec_state'] == 'RUNNING';
      }
    }

    // Záložný výpočet z delty súradníc (ak JSON neobsahuje pole moving).
    // API getCurCPos príznak pohybu nevracia, takže toto je hlavná detekcia.
    if (!moving && previousStatus != null && previousStatus.isConnected) {
      double dx = (newPos.x - previousStatus.x).abs();
      double dy = (newPos.y - previousStatus.y).abs();
      double dz = (newPos.z - previousStatus.z).abs();
      if (dx > 0.05 || dy > 0.05 || dz > 0.05) {
        moving = true;
      }
    }

    return RobotStatus(
      cartPosition: newPos,
      robotMode: 'Connected',
      isConnected: true,
      isMoving: moving, // 👈 Odovzdanie hodnoty
      deviceMode: previousStatus?.deviceMode ?? '',
      statusFlag: previousStatus?.statusFlag ?? 0,
      safetyMode: previousStatus?.safetyMode ?? 1,
      lastError: previousStatus?.lastError ?? '',
    );
  }

  /// Overí odpoveď controllera a vráti text chyby (alebo `null`, ak je OK).
  ///
  /// API posiela `code: 200` (transport OK) a `data.code: 0` (príkaz OK).
  /// Akýkoľvek iný `data.code` = controller príkaz odmietol.
  static String? errorFromJson(Map<String, dynamic> json) {
    final transportCode = (json['code'] as num?)?.toInt() ?? 0;
    final data = json['data'];

    int payloadCode = 0;
    String payloadMsg = '';
    if (data is Map) {
      if (data['code'] is num) {
        payloadCode = (data['code'] as num).toInt();
      }
      payloadMsg = (data['msg'] ?? '').toString();
    }

    final transportError = transportCode != 0 && transportCode != 200;
    if (!transportError && payloadCode == 0) return null;

    final message =
        payloadMsg.isNotEmpty ? payloadMsg : (json['msg'] ?? '').toString();
    return '${json['action']} → code $transportCode/$payloadCode: '
        '${message.isEmpty ? 'Unknown error' : message}';
  }

  /// Stav robota z odpovede `getRobotStates`
  /// (`data.data` obsahuje robotMode / safetyMode / statusFlag).
  factory RobotStatus.fromStateJson(
    Map<String, dynamic> json, {
    RobotStatus? previousStatus,
  }) {
    final data = json['data'];
    Map<dynamic, dynamic>? state;
    if (data is Map) {
      final nested = data['data'];
      state = nested is Map ? nested : data;
    }

    final mode = (state?['robotMode'] ?? '').toString();
    final flag = (state?['statusFlag'] as num?)?.toInt() ?? 0;
    final safety = (state?['safetyMode'] as num?)?.toInt() ?? 1;

    return RobotStatus(
      cartPosition: previousStatus?.cartPosition ?? CartesianPosition(),
      robotMode: previousStatus?.robotMode ?? 'Connected',
      isConnected: true,
      isMoving: (flag >> 3) & 1 == 1,
      deviceMode: mode,
      statusFlag: flag,
      safetyMode: safety,
      lastError: previousStatus?.lastError ?? '',
    );
  }
}

class CartesianPosition {
  final double x;
  final double y;
  final double z;

  CartesianPosition({this.x = 0.0, this.y = 0.0, this.z = 0.0});

  factory CartesianPosition.fromJson(Map<String, dynamic> json) {
    try {
      final cposData = _findPositionNode(json);

      if (cposData is Map) {
        return CartesianPosition(
          x: (cposData['x'] as num?)?.toDouble() ?? 0.0,
          y: (cposData['y'] as num?)?.toDouble() ?? 0.0,
          z: (cposData['z'] as num?)?.toDouble() ?? 0.0,
        );
      } else if (cposData is List && cposData.length >= 3) {
        return CartesianPosition(
          x: (cposData[0] as num).toDouble(),
          y: (cposData[1] as num).toDouble(),
          z: (cposData[2] as num).toDouble(),
        );
      }
    } catch (e) {
      debugPrint("⚠️ Telemetry parsing error: $e");
    }

    return CartesianPosition();
  }

  /// API vracia súradnice v rôzne hlbokých obaloch, napr.
  ///   `{"data": {"msg": "", "code": 0, "data": {"x": ...}}}`
  /// alebo `{"data": {"cpos": {...}}}`. Táto metóda nájde prvý uzol s x/y/z.
  static dynamic _findPositionNode(dynamic node, [int depth = 0]) {
    if (node == null || depth > 4) return null;

    if (node is List) {
      // Krátky zoznam čísel = [x, y, z]
      if (node.length >= 3 && node.every((item) => item is num)) return node;
      for (final item in node) {
        final found = _findPositionNode(item, depth + 1);
        if (found != null) return found;
      }
      return null;
    }

    if (node is Map) {
      if (node.containsKey('x') && node.containsKey('y')) return node;
      for (final key in ['data', 'cpos', 'target', 'pos', 'position']) {
        if (node.containsKey(key)) {
          final found = _findPositionNode(node[key], depth + 1);
          if (found != null) return found;
        }
      }
      for (final value in node.values) {
        if (value is Map || value is List) {
          final found = _findPositionNode(value, depth + 1);
          if (found != null) return found;
        }
      }
    }

    return null;
  }
}