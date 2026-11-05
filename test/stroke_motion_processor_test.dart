import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:codroid_pen_plotter/models/robot_status.dart';
import 'package:codroid_pen_plotter/models/stroke_point.dart';
import 'package:codroid_pen_plotter/providers/robot_provider.dart';
import 'package:codroid_pen_plotter/services/stroke_motion_processor.dart';

/// Procesor, ktorý namiesto odosielania balíkov do robota len zaznamená,
/// čo by poslal. Umožňuje testovať delenie ťahu bez pripojeného robota.
class _CapturingProcessor extends StrokeMotionProcessor {
  final List<List<Map<String, dynamic>>> packets = [];

  _CapturingProcessor(super.provider);

  @override
  Future<bool> sendPacket(List<Map<String, dynamic>> points) async {
    packets.add(List<Map<String, dynamic>>.from(points));
    return true;
  }
}

Map<String, dynamic> _telemetry(double x, double y, double z) => {
      'id': 1,
      'type': 'common',
      'action': 'getCurCPos',
      'code': 200,
      'msg': '',
      'data': {
        'msg': '',
        'code': 0,
        'data': {'x': x, 'y': y, 'z': z, 'a': -180.0, 'b': 0.0, 'c': 90.0},
      },
    };

Map<String, dynamic> _cpos(Map<String, dynamic> point) =>
    point['target']['cpos'] as Map<String, dynamic>;

String _zoneType(Map<String, dynamic> point) =>
    (point['zone'] as Map)['type'] as String;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Telemetria z controllerа', () {
    test('CartesianPosition rozpozná súradnice z vnoreného data.data', () {
      final position =
          CartesianPosition.fromJson(_telemetry(876.6, 57.3, 126.6));

      expect(position.x, closeTo(876.6, 0.001));
      expect(position.y, closeTo(57.3, 0.001));
      expect(position.z, closeTo(126.6, 0.001));
    });

    test('RobotStatus označí pohyb pri zmene súradníc', () {
      final first = RobotStatus.fromCartJson(_telemetry(100, 100, 15));
      final second = RobotStatus.fromCartJson(
        _telemetry(101, 100, 15),
        previousStatus: first,
      );
      final third = RobotStatus.fromCartJson(
        _telemetry(101, 100, 15),
        previousStatus: second,
      );

      expect(second.isMoving, isTrue);
      expect(third.isMoving, isFalse);
    });

    test('úspešnú odpoveď (code 200 / data.code 0) nehlási ako chybu', () {
      expect(RobotStatus.errorFromJson(_telemetry(100, 100, 15)), isNull);
    });

    test('odmietnutý príkaz (data.code != 0) vráti chybovú správu', () {
      final json = {
        'action': 'movMulti',
        'code': 200,
        'msg': '',
        'data': {'code': 7, 'msg': 'Robot is moving'},
      };

      final error = RobotStatus.errorFromJson(json);

      expect(error, isNotNull);
      expect(error, contains('Robot is moving'));
      expect(error, contains('movMulti'));
    });
  });

  group('Rozdelenie ťahu na balíky movMulti', () {
    test('balík nikdy nepresiahne 30 bodov a pero ide hore/dole správne',
        () async {
      final provider = RobotProvider();
      final processor = _CapturingProcessor(provider);

      // ~200 mm dlhý ťah -> po filtri na 5 mm ostane ~40 bodov = viac balíkov
      final stroke = List<StrokePoint>.generate(
        400,
        (i) => StrokePoint(x: 0.03 + i * 0.00233, y: 0.5, pressure: 1.0),
      );

      final success = await processor.plotStroke(stroke);

      expect(success, isTrue);
      expect(processor.packets.length, greaterThan(1));

      for (final packet in processor.packets) {
        expect(
          packet.length,
          lessThanOrEqualTo(StrokeMotionProcessor.maxPointsPerPacket),
          reason: 'Controller prijme max 30 pozícií v jednom movMulti',
        );
        // Posledný bod balíka = presné zastavenie (FINE)
        expect(_zoneType(packet.last), 'FINE');
      }

      // Prvý balík: nájazd vo výške pera + klesnutie na papier
      final firstPacket = processor.packets.first;
      expect(_cpos(firstPacket[0])['z'], provider.penUpZ);
      expect(_cpos(firstPacket[1])['z'], provider.penDownZ);
      expect(_cpos(firstPacket[1])['x'],
          closeTo(_cpos(firstPacket[0])['x'], 0.001));

      // Posledný balík: zdvih pera na koncovej pozícii
      final lastPacket = processor.packets.last;
      expect(_cpos(lastPacket.last)['z'], provider.penUpZ);
      expect(
        _cpos(lastPacket.last)['x'],
        closeTo(_cpos(lastPacket[lastPacket.length - 2])['x'], 0.001),
      );
    });

    test('krátky ťah sa zmestí do jedného balíka', () async {
      final provider = RobotProvider();
      final processor = _CapturingProcessor(provider);

      final stroke = [
        StrokePoint(x: 0.10, y: 0.10, pressure: 1.0),
        StrokePoint(x: 0.20, y: 0.10, pressure: 1.0),
        StrokePoint(x: 0.20, y: 0.20, pressure: 1.0),
      ];

      final success = await processor.plotStroke(stroke);

      expect(success, isTrue);
      expect(processor.packets.length, 1);

      // nájazd + klesnutie + 1 stredný bod + koniec + zdvih = 5 bodov
      expect(processor.packets.single.length, 5);
    });

    test('balík sa dá serializovať a odhad trvania je kladný', () {
      final provider = RobotProvider();
      final processor = StrokeMotionProcessor(provider);

      final packet = [
        processor.buildCartPoint(50, 50, provider.penUpZ, zoneType: 'FINE'),
        processor.buildCartPoint(50, 50, provider.penDownZ, zoneType: 'FINE'),
        processor.buildCartPoint(150, 150, provider.penDownZ,
            zoneType: 'RELATIVE'),
      ];

      final json = jsonEncode({
        'action': 'movMulti',
        'data': {'type': 'movCart', 'user': 1, 'tool': 1, 'points': packet},
      });

      expect(json, contains('movMulti'));
      expect(processor.estimatePacketDurationMs(packet), greaterThan(0));

      // ~141 mm dráhy pri 250 mm/s (60 %) => cca 1 s + rezerva 700 ms
      expect(
        processor.estimatePacketDurationMs(packet),
        greaterThanOrEqualTo(700),
      );
    });
  });

  group('Nastavenia rýchlosti a Z korekcie', () {
    test('predvolené hodnoty a posun pera o korekciu', () async {
      final provider = RobotProvider();
      await provider.initialized;

      expect(provider.linearSpeed, RobotProvider.defaultLinearSpeed);
      expect(provider.zOffsetMm, 0.0);
      expect(provider.penUpZ, provider.penUpNominalZ);
      expect(provider.penDownZ, provider.penDownNominalZ);

      provider.zOffsetMm = 12.5;

      expect(provider.penUpZ, closeTo(provider.penUpNominalZ + 12.5, 0.001));
      expect(
          provider.penDownZ, closeTo(provider.penDownNominalZ + 12.5, 0.001));

      // záporná korekcia = pero nižšie (papier/podložka nižšie)
      provider.zOffsetMm = -20.0;

      expect(provider.penUpZ, closeTo(provider.penUpNominalZ - 20.0, 0.001));
      expect(
          provider.penDownZ, closeTo(provider.penDownNominalZ - 20.0, 0.001));
    });

    test('korekcia je obmedzená na ±30 mm', () async {
      final provider = RobotProvider();
      await provider.initialized;

      provider.zOffsetMm = 45.0;
      expect(provider.zOffsetMm, RobotProvider.maxZOffsetMm);

      provider.zOffsetMm = -45.0;
      expect(provider.zOffsetMm, -RobotProvider.maxZOffsetMm);
    });

    test('rýchlosť je obmedzená na 10 – 500 mm/s', () async {
      final provider = RobotProvider();
      await provider.initialized;

      provider.linearSpeed = 900.0;
      expect(provider.linearSpeed, RobotProvider.maxLinearSpeed);
      expect(RobotProvider.maxLinearSpeed, 500.0);

      provider.linearSpeed = 0.0;
      expect(provider.linearSpeed, RobotProvider.minLinearSpeed);

      provider.linearSpeed = 375.0;
      expect(provider.linearSpeed, 375.0);
    });

    test('uložené hodnoty sa zapíšu do SharedPreferences', () async {
      final provider = RobotProvider();
      await provider.initialized;

      await provider.setLinearSpeed(420.0);
      await provider.setZOffset(-8.0);

      final prefs = await SharedPreferences.getInstance();

      expect(prefs.getDouble('linear_speed'), 420.0);
      expect(prefs.getDouble('z_offset_mm'), -8.0);
      expect(provider.linearSpeed, 420.0);
      expect(provider.zOffsetMm, -8.0);
    });

    test('korekcia sa prejaví v balíkoch (pero hore aj dole)', () async {
      final provider = RobotProvider();
      await provider.initialized;
      provider.zOffsetMm = 10.0;

      final processor = _CapturingProcessor(provider);
      final stroke = [
        StrokePoint(x: 0.10, y: 0.10, pressure: 1.0),
        StrokePoint(x: 0.20, y: 0.10, pressure: 1.0),
      ];

      await processor.plotStroke(stroke);

      final packet = processor.packets.single;
      final expectedUpZ = provider.penUpNominalZ + 10.0;
      final expectedDownZ = provider.penDownNominalZ + 10.0;

      // prvý bod = nájazd vo výške pera hore (s korekciou)
      expect(_cpos(packet.first)['z'], closeTo(expectedUpZ, 0.001));
      // pero dole = nominál + korekcia
      expect(_cpos(packet[1])['z'], closeTo(expectedDownZ, 0.001));
      // zdvih na konci = opäť hore
      expect(_cpos(packet.last)['z'], closeTo(expectedUpZ, 0.001));
    });

    test('rýchlosť ovplyvní odhad trvania pohybu (watchdog)', () {
      final provider = RobotProvider();
      final processor = StrokeMotionProcessor(provider);

      final packet = [
        processor.buildCartPoint(0, 0, 0, zoneType: 'FINE'),
        processor.buildCartPoint(250, 0, 0, zoneType: 'FINE'),
      ];

      provider.linearSpeed = 100.0;
      final slow = processor.estimatePacketDurationMs(packet);

      provider.linearSpeed = 500.0;
      final fast = processor.estimatePacketDurationMs(packet);

      expect(slow, greaterThan(fast));
    });
  });
}
