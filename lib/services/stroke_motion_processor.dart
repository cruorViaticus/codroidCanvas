import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../models/stroke_point.dart';
import '../providers/robot_provider.dart';

class StrokeMotionProcessor {
  final RobotProvider provider;

  StrokeMotionProcessor(this.provider);

  /// Spracuje celú FIFO frontu ťahov čistým odosielaním balíkov movMulti
  Future<void> processQueue(List<List<StrokePoint>> queue) async {
    if (queue.isEmpty || !provider.status.isConnected) return;

    while (queue.isNotEmpty) {
      // Ak sa robot ešte hýbe z predchádzajúceho ťahu, počkáme
      while (provider.status.isMoving) {
        await Future.delayed(const Duration(milliseconds: 100));
      }

      final currentStroke = queue.removeAt(0);
      if (currentStroke.length < 2) continue;

      // Filtrovanie bodov (min. 5 mm krok)
      List<StrokePoint> filtered = [currentStroke.first];
      for (int i = 1; i < currentStroke.length; i++) {
        double dx = (currentStroke[i].y - filtered.last.y) * 297.0;
        double dy = (currentStroke[i].x - filtered.last.x) * 210.0;
        if ((dx * dx + dy * dy) >= 25.0) {
          filtered.add(currentStroke[i]);
        }
      }

      if (filtered.last != currentStroke.last) {
        filtered.add(currentStroke.last);
      }

      if (filtered.length < 2) continue;

      // Generovanie 3D bodov trajektórie
      final fullStrokePoints = buildFullStrokePoints(filtered);

      // Výpočet dĺžky 3D dráhy v mm
      double totalDistanceMm = 0.0;
      for (int i = 0; i < fullStrokePoints.length - 1; i++) {
        final c1 = fullStrokePoints[i]['target']['cpos'];
        final c2 = fullStrokePoints[i + 1]['target']['cpos'];
        double dx = (c2['x'] as double) - (c1['x'] as double);
        double dy = (c2['y'] as double) - (c1['y'] as double);
        double dz = (c2['z'] as double) - (c1['z'] as double);
        totalDistanceMm += math.sqrt(dx * dx + dy * dy + dz * dz);
      }

      // Reálny čas trvania dráhy (35 mm/s priemerná rýchlosť + 1.2s rezerva na Z nájazd)
      int minPhysicalTimeMs = ((totalDistanceMm / 35.0) * 1000).toInt() + 1200;

      debugPrint(
          "✍️ [ODOSIELAM ŤAH] ${fullStrokePoints.length} bodov (${totalDistanceMm.toStringAsFixed(1)} mm). Čakám min. ${minPhysicalTimeMs} ms...");

      final payload = {
        "id": DateTime.now().millisecondsSinceEpoch,
        "type": "common",
        "action": "movMulti",
        "data": {
          "type": "movCart",
          "user": 1,
          "tool": 1,
          "points": fullStrokePoints,
        }
      };

      // Odoslanie čistého movMulti bez akýchkoľvek sprievodných Power On príkazov
      provider.sendPayload(payload);

      // Čakanie na fyzické dokončenie dráhy v Codroide
      await Future.delayed(Duration(milliseconds: minPhysicalTimeMs));

      // Overenie kľudu cez telemetriu (2 cykly = 200 ms kľud)
      int stopConfirmations = 0;
      int safetyCounter = 0;
      while (stopConfirmations < 2 && safetyCounter < 40) {
        await Future.delayed(const Duration(milliseconds: 100));
        safetyCounter++;
        if (!provider.status.isMoving) {
          stopConfirmations++;
        } else {
          stopConfirmations = 0;
        }
      }
    }
  }

  /// Zostaví kompletný zoznam Carteskych bodov pre 1 ťah
  List<Map<String, dynamic>> buildFullStrokePoints(List<StrokePoint> stroke) {
    List<Map<String, dynamic>> points = [];

    double startX = (1.0 - stroke.first.y) * 297.0;
    double startY = (1.0 - stroke.first.x) * 210.0;

    // 1. Presun vo vzduchu nad štart (Z = penUpZ, FINE)
    points.add(buildCartPoint(startX, startY, provider.penUpZ, zoneType: "FINE"));

    // 2. Klesnutie na papier (Z = penDownZ, FINE)
    points.add(buildCartPoint(startX, startY, provider.penDownZ, zoneType: "FINE"));

    // 3. Stredné body na papieri (Z = penDownZ, RELATIVE)
    for (int i = 1; i < stroke.length - 1; i++) {
      double px = (1.0 - stroke[i].y) * 297.0;
      double py = (1.0 - stroke[i].x) * 210.0;
      points.add(buildCartPoint(px, py, provider.penDownZ, zoneType: "RELATIVE", zdis: 4.0));
    }

    // 4. Koniec na papieri (Z = penDownZ, FINE)
    double lastX = (1.0 - stroke.last.y) * 297.0;
    double lastY = (1.0 - stroke.last.x) * 210.0;
    points.add(buildCartPoint(lastX, lastY, provider.penDownZ, zoneType: "FINE"));

    // 5. Zdvih do vzduchu (Z = penUpZ, FINE)
    points.add(buildCartPoint(lastX, lastY, provider.penUpZ, zoneType: "FINE"));

    return points;
  }

  /// Tvorba bodu pre Codroid controller
  Map<String, dynamic> buildCartPoint(double x, double y, double z,
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
            "cf1": -1, "cf2": -1, "cf3": -1, "cf4": -1, "cf5": -1, "cf6": -1, "cf7": -1
          }
        }
      },
      "speed": {
        "sori": 50.0,
        "sper": 0.0,
        "stcp": provider.linearSpeed,
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
              "data": {
                "zper": 50,
                "zdis": zdis,
                "zvconst": 50
              }
            }
    };
  }
}