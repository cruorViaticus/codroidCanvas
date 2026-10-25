import 'package:flutter/foundation.dart';

class RobotStatus {
  final CartesianPosition cartPosition;
  final String robotMode;
  final bool isConnected;

  RobotStatus({
    CartesianPosition? cartPosition,
    this.robotMode = 'Disconnected',
    this.isConnected = false,
  }) : cartPosition = cartPosition ?? CartesianPosition();

  double get x => cartPosition.x;
  double get y => cartPosition.y;
  double get z => cartPosition.z;

  factory RobotStatus.fromCartJson(Map<String, dynamic> json) {
    // Print raw telemetry response to inspect exact structure in VS Code
    debugPrint("📊 [getCurCPos TELEMETRY]: $json");

    return RobotStatus(
      cartPosition: CartesianPosition.fromJson(json),
      robotMode: 'Connected',
      isConnected: true,
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

      // Extract cpos from Map or List structures
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