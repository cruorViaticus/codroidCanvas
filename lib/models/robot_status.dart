import 'package:flutter/foundation.dart';

class RobotStatus {
  final CartesianPosition cartPosition;
  final String robotMode;
  final bool isConnected;
  final bool isMoving; // 👈 1. Nové pole pre pohyb robota

  RobotStatus({
    CartesianPosition? cartPosition,
    this.robotMode = 'Disconnected',
    this.isConnected = false,
    this.isMoving = false, // 👈 Predvolená hodnota false
  }) : cartPosition = cartPosition ?? CartesianPosition();

  double get x => cartPosition.x;
  double get y => cartPosition.y;
  double get z => cartPosition.z;

  factory RobotStatus.fromCartJson(
    Map<String, dynamic> json, {
    RobotStatus? previousStatus, // 👈 Voliteľný predchádzajúci stav pre výpočet delty
  }) {
    debugPrint("📊 [getCurCPos TELEMETRY]: $json");

    final newPos = CartesianPosition.fromJson(json);

    // Detekcia pohybu z JSON-u Codroidu
    bool moving = false;
    final data = json['data'] ?? json;

    if (data is Map<String, dynamic>) {
      if (data.containsKey('moving')) {
        moving = data['moving'] == true || data['moving'] == 1;
      } else if (data.containsKey('is_moving')) {
        moving = data['is_moving'] == true || data['is_moving'] == 1;
      } else if (data.containsKey('exec_state')) {
        moving = data['exec_state'] == 1 || data['exec_state'] == 'RUNNING';
      }
    }

    // Záložný výpočet z delty súradníc (ak JSON neobsahuje pole moving)
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
      dynamic cposData;

      if (json.containsKey('data')) {
        final data = json['data'];
        if (data is Map<String, dynamic>) {
          cposData = data['cpos'] ?? data['target']?['cpos'] ?? data;
        } else if (data is List && data.isNotEmpty) {
          cposData = data[0];
        }
      } else if (json.containsKey('cpos')) {
        cposData = json['cpos'];
      }

      if (cposData is Map<String, dynamic>) {
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
}