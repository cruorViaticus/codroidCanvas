import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

import '../models/stroke_point.dart';
import '../providers/robot_provider.dart';

/// Prekladá ťahy z canvasu na balíky `movMulti` pre Codroid controller.
///
/// Tri pravidlá z API dokumentácie, ktoré musia byť dodržané, inak robot
/// spadne do alarmu:
///  1. `movMulti` / MovLSegments prijme **maximálne 30 pozícií** v balíku.
///  2. Nový pohybový príkaz sa posiela až keď controller hlási pokoj –
///     dva súbežné pohyby = konflikt trajektórie a alarm.
///  3. Body vnútri balíka idú so `zone.type = RELATIVE` (blending), takže
///     robot nebrzdí v každom bode a kreslí plynule.
class StrokeMotionProcessor {
  /// API: "continous line motion (30 positions maximum)".
  static const int maxPointsPerPacket = 30;

  /// Minimálna vzdialenosť dvoch bodov ťahu v mm (filtrovanie vstupu).
  static const double minPointSpacingMm = 5.0;

  final RobotProvider provider;

  StrokeMotionProcessor(this.provider);

  /// Polomer zaoblenia (blending) pre plynulý prejazd bodov v mm.
  ///
  /// Hodnota > 0 zapne `zone.type = RELATIVE` so `zdis` – robot prejde bod
  /// bez zastavenia (0 = presné FINE rohy, najpomalšie).
  double get blendMm => provider.blendDistanceMm;

  /// Spracuje celú FIFO frontu ťahov.
  ///
  /// Ťahy, ktoré už čakajú vo fronte, sa spájajú do jednej spojitej dráhy –
  /// robot medzi nimi nezastavuje, iba zdvihne pero o [RobotProvider.penUpZ].
  Future<void> processQueue(List<List<StrokePoint>> queue) async {
    if (!provider.status.isConnected) return;

    while (queue.isNotEmpty) {
      if (!provider.status.isConnected) return;

      // Do jedného balíka (max 30 bodov) naberieme viac ťahov za sebou.
      final batch = <List<StrokePoint>>[];
      int plannedPoints = 0;

      while (queue.isNotEmpty && plannedPoints < maxPointsPerPacket) {
        final stroke = queue.first;
        final path = toMillimetrePath(stroke);

        if (queue.isNotEmpty && identical(queue.first, stroke)) {
          queue.removeAt(0);
        }
        if (path.length < 2) {
          debugPrint("⏭️ Príliš krátky ťah preskočený (${path.length} body).");
          continue;
        }

        batch.add(stroke);
        // kreslenie + zdvih + prejazd + klesnutie
        plannedPoints += path.length + 3;
      }

      if (batch.isEmpty) continue;

      final success = await plotStrokes(batch);
      if (!success) {
        queue.clear();
        debugPrint(
            "⛔ Kreslenie prerušené (chyba robota / timeout), fronta vyčistená.");
        return;
      }
    }
  }

  /// Vykreslí jeden ťah.
  Future<bool> plotStroke(List<StrokePoint> stroke) => plotStrokes([stroke]);

  /// Vykreslí zadané ťahy ako **jednu spojitú dráhu**.
  ///
  /// Medzi ťahmi pero len zdvihne na [RobotProvider.penUpZ] a hneď pokračuje
  /// prejazdom na začiatok ďalšieho ťahu. Body dráhy sa zaobliavajú
  /// (`zone.type = RELATIVE`, `zdis = blendMm`), takže robot nezastavuje
  /// v každom bode. FINE (presné zastavenie) ostáva len tam, kde pero
  /// dopadá na papier a na konci každého balíka.
  Future<bool> plotStrokes(List<List<StrokePoint>> strokes) async {
    final points = <Map<String, dynamic>>[];
    bool firstStroke = true;

    for (final stroke in strokes) {
      final path = toMillimetrePath(stroke);
      if (path.length < 2) continue;

      if (firstStroke) {
        // Pero musí byť vo vzduchu, až potom klesneme na štart.
        points.addAll(_approachPoints(path.first));
        firstStroke = false;
      } else {
        // Pero visí nad koncom predchádzajúceho ťahu – stačí prejazd.
        points.add(_blendPoint(path.first, provider.penUpZ));
      }

      // Klesnutie na papier – presný dotyk, aby čiara začínala presne.
      points.add(buildCartPoint(
        path.first.dx,
        path.first.dy,
        provider.penDownZ,
        zoneType: "FINE",
      ));

      // Kreslenie – všetky body sa zaoblia (blending = žiadne brzdenie).
      for (int i = 1; i < path.length; i++) {
        points.add(_blendPoint(path[i], provider.penDownZ));
      }

      // Zdvih pera na konci ťahu – plynulo do prejazdu na ďalší ťah.
      points.add(_blendPoint(path.last, provider.penUpZ));
    }

    if (points.isEmpty) return true;

    // Posledný bod celej dráhy musí presne zastaviť.
    points[points.length - 1] = _withFineZone(points.last);

    // Rozdelenie na balíky po [maxPointsPerPacket] bodoch.
    for (int start = 0; start < points.length; start += maxPointsPerPacket) {
      final end = math.min(start + maxPointsPerPacket, points.length);
      final packet = points.sublist(start, end);

      // Koniec balíka = presná pozícia (controller medzi balíkmi zastaví).
      packet[packet.length - 1] = _withFineZone(packet.last);

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
  ///
  /// Slúži len ako watchdog – `waitUntilIdle` skončí skôr, akonáhle telemetria
  /// potvrdí, že TCP je na cieľovej pozícii. Preto môže byť odhad mierne
  /// nadhodnotený (blending znamená, že robot ide takmer plnou rýchlosťou).
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
    // Zaoblené rohy (blending) = takmer plná rýchlosť; 500 ms rezerva na
    // akceleráciu a dorovnanie na presný koncový bod.
    return ((distanceMm / (speed * 0.8)) * 1000).toInt() + 500;
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

  /// Bod dráhy so zaoblením (blending) – robot ním prejde bez zastavenia.
  Map<String, dynamic> _blendPoint(Offset point, double z) => buildCartPoint(
        point.dx,
        point.dy,
        z,
        zoneType: "RELATIVE",
        zdis: blendMm,
      );

  /// Tvorba bodu pre Codroid controller
  Map<String, dynamic> buildCartPoint(double x, double y, double z,
      {required String zoneType, double? zdis}) {
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
                "zdis": zdis ?? blendMm,
                "zvconst": 50
              }
            }
    };
  }
}