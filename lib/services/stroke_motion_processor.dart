import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

import '../models/stroke_point.dart';
import '../providers/robot_provider.dart';

/// Prekladá ťahy z canvasu na balíky `movMulti` pre Codroid controller.
///
/// Dve pravidlá z API dokumentácie, ktoré musia byť dodržané, inak robot
/// spadne do alarmu:
///  1. `movMulti` / MovLSegments prijme **maximálne 30 pozícií** v balíku.
///  2. Nový pohybový príkaz sa posiela až keď controller hlási pokoj –
///     dva súbežné pohyby = konflikt trajektórie a alarm.
class StrokeMotionProcessor {
  /// API: "continous line motion (30 positions maximum)".
  static const int maxPointsPerPacket = 30;

  /// Minimálna vzdialenosť dvoch bodov ťahu v mm (filtrovanie vstupu).
  static const double minPointSpacingMm = 5.0;

  final RobotProvider provider;

  StrokeMotionProcessor(this.provider);

  /// Spracuje celú FIFO frontu ťahov – jeden ťah = jeden alebo viac balíkov.
  Future<void> processQueue(List<List<StrokePoint>> queue) async {
    if (!provider.status.isConnected) return;

    while (queue.isNotEmpty) {
      if (!provider.status.isConnected) return;

      final stroke = queue.first;
      final success = await plotStroke(stroke);

      if (queue.isNotEmpty && identical(queue.first, stroke)) {
        queue.removeAt(0);
      }

      if (!success) {
        queue.clear();
        debugPrint(
            "⛔ Kreslenie prerušené (chyba robota / timeout), fronta vyčistená.");
        return;
      }
    }
  }

  /// Vykreslí jeden ťah.
  ///
  /// Ťah sa rozdelí na balíky s max. [maxPointsPerPacket] bodmi. Každý balík
  /// sa odošle až po potvrdenom zastavení robota a pred odoslaním ďalšieho
  /// sa opäť čaká na pokoj – tým sa nikdy neprekryjú dve trajektórie.
  Future<bool> plotStroke(List<StrokePoint> stroke) async {
    final path = toMillimetrePath(stroke);
    if (path.length < 2) return true;

    int index = 0;
    bool firstPacket = true;

    while (index < path.length) {
      final packet = <Map<String, dynamic>>[];

      if (firstPacket) {
        // Pero musí byť vo vzduchu, až potom klesneme na štart.
        packet.addAll(_approachPoints(path.first));
        packet.add(buildCartPoint(
          path.first.dx,
          path.first.dy,
          provider.penDownZ,
          zoneType: "FINE",
        ));
        index = 1;
        firstPacket = false;
      }

      // Stredné body balíka – posledný bod musí mať FINE (presné zastavenie)
      while (index < path.length) {
        final bool isStrokeEnd = index == path.length - 1;
        final int reserve = isStrokeEnd ? 1 : 0; // miesto pre zdvih pera
        if (packet.length + 1 + reserve > maxPointsPerPacket) break;

        final point = path[index];
        packet.add(buildCartPoint(
          point.dx,
          point.dy,
          provider.penDownZ,
          zoneType: "RELATIVE",
          zdis: 4.0,
        ));
        index++;
      }

      packet[packet.length - 1] = _withFineZone(packet.last);

      if (index >= path.length) {
        // Koniec ťahu – zdvih pera na poslednej pozícii.
        final end = path.last;
        packet.add(buildCartPoint(
          end.dx,
          end.dy,
          provider.penUpZ,
          zoneType: "FINE",
        ));
      }

      final sent = await sendPacket(packet);
      if (!sent) return false;
    }

    return true;
  }

  /// Odošle jeden `movMulti` balík a počká na jeho fyzické dokončenie.
  Future<bool> sendPacket(List<Map<String, dynamic>> points) async {
    if (!provider.status.isConnected) return false;

    // 1. Nikdy neposielame pohyb počas pohybu predchádzajúceho balíka.
    if (!await provider.waitUntilIdle()) {
      debugPrint("⚠️ Robot nezastavil – balík sa neodosiela.");
      return false;
    }

    final durationMs = estimatePacketDurationMs(points);

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

    debugPrint(
        "✍️ [BALÍK] ${points.length}/$maxPointsPerPacket bodov, odhad $durationMs ms");

    if (!await provider.sendMotionPacket(payload,
        estimatedDurationMs: durationMs)) {
      return false;
    }

    // 2. Počkať na dokončenie balíka a potvrdený pokoj.
    if (!await provider.waitUntilIdle()) {
      debugPrint("⚠️ Balík sa nedokončil v časovom limite.");
      return false;
    }

    return !provider.wasMotionRejected;
  }

  /// Odhad trvania balíka v ms (rýchlosť robota + rezerva na akceleráciu).
  int estimatePacketDurationMs(List<Map<String, dynamic>> points) {
    double distanceMm = 0.0;
    for (int i = 0; i < points.length - 1; i++) {
      final c1 = points[i]["target"]["cpos"] as Map;
      final c2 = points[i + 1]["target"]["cpos"] as Map;
      final dx = (c2["x"] as num).toDouble() - (c1["x"] as num).toDouble();
      final dy = (c2["y"] as num).toDouble() - (c1["y"] as num).toDouble();
      final dz = (c2["z"] as num).toDouble() - (c1["z"] as num).toDouble();
      distanceMm += math.sqrt(dx * dx + dy * dy + dz * dz);
    }

    final speed = provider.linearSpeed <= 0 ? 250.0 : provider.linearSpeed;
    // Controller spomaľuje pred každým FINE bodom – počítame s 60 % rýchlosti.
    return ((distanceMm / (speed * 0.6)) * 1000).toInt() + 700;
  }

  /// Prevod normalizovaných bodov canvasu na milimetre robota
  /// (s filtrovaním príliš krátkych úsekov).
  List<Offset> toMillimetrePath(List<StrokePoint> stroke) {
    final path = <Offset>[];

    for (final point in stroke) {
      final mm = toMillimetres(point);
      if (path.isEmpty || (mm - path.last).distance >= minPointSpacingMm) {
        path.add(mm);
      }
    }

    // Posledný bod ťahu musí ostať zachovaný, aby pero zdvihlo na konci ťahu.
    final last = toMillimetres(stroke.last);
    if (path.isEmpty || (path.last - last).distance > 0.1) {
      path.add(last);
    }

    return path;
  }

  Offset toMillimetres(StrokePoint point) =>
      Offset((1.0 - point.y) * 297.0, (1.0 - point.x) * 210.0);

  /// Nájazdové body pred klesnutím pera – pero musí byť vo vzduchu.
  List<Map<String, dynamic>> _approachPoints(Offset target) {
    final points = <Map<String, dynamic>>[];
    final current = provider.status.cartPosition;
    final positionKnown = provider.status.isConnected &&
        !(current.x == 0.0 && current.y == 0.0 && current.z == 0.0);

    if (positionKnown && current.z < provider.penUpZ - 0.5) {
      // Pero je ešte pri papieri (napr. po prerušenom ťahu) – zdvihneme na mieste.
      points.add(buildCartPoint(
        current.x,
        current.y,
        provider.penUpZ,
        zoneType: "FINE",
      ));
    }

    points.add(buildCartPoint(
      target.dx,
      target.dy,
      provider.penUpZ,
      zoneType: "FINE",
    ));

    return points;
  }

  Map<String, dynamic> _withFineZone(Map<String, dynamic> point) => {
        ...point,
        "zone": {
          "type": "FINE",
          "data": {"zper": 0, "zdis": 0, "zvconst": 0}
        }
      };

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