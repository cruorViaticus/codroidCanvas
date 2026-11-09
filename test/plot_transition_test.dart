import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:codroid_pen_plotter/models/stroke_point.dart';
import 'package:codroid_pen_plotter/providers/robot_provider.dart';
import 'package:codroid_pen_plotter/services/stroke_motion_processor.dart';

/// Procesor, ktorĂ˝ balĂ­ky neposiela robotovi, len si ich zapamĂ¤tĂˇ.
class _CapturingProcessor extends StrokeMotionProcessor {
  final List<List<Map<String, dynamic>>> packets = [];

  _CapturingProcessor(super.provider);

  @override
  Future<bool> sendPacket(List<Map<String, dynamic>> points) async {
    packets.add(List<Map<String, dynamic>>.from(points));
    return true;
  }
}

Map<String, dynamic> _cpos(Map<String, dynamic> point) =>
    point['target']['cpos'] as Map<String, dynamic>;

double _x(Map<String, dynamic> point) => (_cpos(point)['x'] as num).toDouble();
double _y(Map<String, dynamic> point) => (_cpos(point)['y'] as num).toDouble();
double _z(Map<String, dynamic> point) => (_cpos(point)['z'] as num).toDouble();

String _zoneType(Map<String, dynamic> point) =>
    (point['zone'] as Map)['type'] as String;

/// KosĂ­nus uhla medzi dvoma po sebe idĂşcimi segmentmi balĂ­ka.
double _cosine(
  Map<String, dynamic> a,
  Map<String, dynamic> b,
  Map<String, dynamic> c,
) {
  final first = [_x(b) - _x(a), _y(b) - _y(a), _z(b) - _z(a)];
  final second = [_x(c) - _x(b), _y(c) - _y(b), _z(c) - _z(b)];
  final firstLength = math
      .sqrt(first[0] * first[0] + first[1] * first[1] + first[2] * first[2]);
  final secondLength = math.sqrt(
      second[0] * second[0] + second[1] * second[1] + second[2] * second[2]);
  if (firstLength == 0 || secondLength == 0) return 0.0;
  return (first[0] * second[0] + first[1] * second[1] + first[2] * second[2]) /
      (firstLength * secondLength);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late RobotProvider provider;
  late StrokeMotionProcessor processor;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    provider = RobotProvider();
    processor = StrokeMotionProcessor(provider);
  });

  Map<String, dynamic> point(double x, double y, double z) =>
      processor.buildCartPoint(x, y, z, zoneType: 'RELATIVE');

  group('StrokeMotionProcessor.sanitizePoints', () {
    test('zahodĂ­ totoĹľnĂ© body za sebou', () {
      final cleaned = StrokeMotionProcessor.sanitizePoints([
        point(10, 10, 0),
        point(20, 10, 0),
        point(20, 10, 0),
        point(30, 10, 0),
      ]);

      expect(cleaned, hasLength(3));
      expect(_x(cleaned[1]), 20);
      expect(_x(cleaned[2]), 30);
    });

    test('zruĹˇĂ­ zbytoÄŤnĂ˝ vĂ˝let tam a hneÄŹ spĂ¤ĹĄ', () {
      final cleaned = StrokeMotionProcessor.sanitizePoints([
        point(10, 10, 0),
        point(20, 10, 0),
        point(10, 10, 0),
        point(10, 20, 0),
      ]);

      // A â†’ B â†’ A sa vyhodĂ­ celĂ©, pero ostane v A a pokraÄŤuje do C
      expect(cleaned, hasLength(2));
      expect(_x(cleaned.first), 10);
      expect(_y(cleaned.first), 10);
      expect(_y(cleaned.last), 20);
    });

    test('obrat o 180Â° dostane FINE (controller ho nezaoblĂ­)', () {
      final cleaned = StrokeMotionProcessor.sanitizePoints([
        point(10, 10, 0),
        point(30, 10, 0),
        point(20, 10, 0),
      ]);

      expect(cleaned, hasLength(3));
      expect(_zoneType(cleaned[1]), 'FINE');
      // susednĂ© body ostĂˇvajĂş zaoblenĂ©
      expect(_zoneType(cleaned[0]), 'RELATIVE');
    });

    test('obyÄŤajnĂ˝ roh FINE nedostane', () {
      final cleaned = StrokeMotionProcessor.sanitizePoints([
        point(10, 10, 0),
        point(20, 10, 0),
        point(20, 20, 0),
        point(30, 20, 0),
      ]);

      for (final p in cleaned) {
        expect(_zoneType(p), 'RELATIVE');
      }
    });

    test('zvislĂ˝ zdvih a klesnutie na tom istom mieste sa zruĹˇĂ­', () {
      final cleaned = StrokeMotionProcessor.sanitizePoints([
        point(10, 10, 0),
        point(10, 10, 3),
        point(10, 10, 0),
        point(20, 10, 0),
      ]);

      expect(cleaned, hasLength(2));
      expect(_x(cleaned.first), 10);
      expect(_x(cleaned.last), 20);
    });
  });

  group('Spojovanie ĹĄahov a obraty v balĂ­koch', () {
    test(
        'ĹĄah, ktorĂ˝ zaÄŤĂ­na tam, kde predchĂˇdzajĂşci skonÄŤil, pero nezdvihne',
        () async {
      final capturing = _CapturingProcessor(provider);

      final first = [
        StrokePoint(x: 0.10, y: 0.10, pressure: 1.0),
        StrokePoint(x: 0.20, y: 0.10, pressure: 1.0),
      ];
      // druhĂ˝ ĹĄah zaÄŤĂ­na presne na konci prvĂ©ho
      final second = [
        StrokePoint(x: 0.20, y: 0.10, pressure: 1.0),
        StrokePoint(x: 0.20, y: 0.20, pressure: 1.0),
      ];

      final success =
          await capturing.plotStrokes([first, second], minPointSpacing: 0.1);

      expect(success, isTrue);
      final packet = capturing.packets.single;

      // Pero kleslo len raz â€“ dva ĹĄahy sĂş jedna ÄŤiara (Ĺľiadny zdvih medzi nimi)
      expect(packet.where((p) => _z(p) == provider.penUpZ), hasLength(2));
      expect(packet.where((p) => _z(p) == provider.penDownZ), hasLength(3));

      // Ĺľiadny bod sa nevracia spĂ¤ĹĄ po tej istej ÄŤiare
      for (var i = 1; i < packet.length - 1; i++) {
        expect(_cosine(packet[i - 1], packet[i], packet[i + 1]),
            greaterThan(-0.999));
      }
    });

    test('ostrĂ˝ obrat v ĹĄahu sa poĹˇle ako FINE a niÄŤ ho nezaoblĂ­',
        () async {
      final capturing = _CapturingProcessor(provider);

      // ĹĄah ide doprava a potom sa vrĂˇti po tej istej ÄŤiare
      final stroke = [
        StrokePoint(x: 0.10, y: 0.50, pressure: 1.0),
        StrokePoint(x: 0.40, y: 0.50, pressure: 1.0),
        StrokePoint(x: 0.20, y: 0.50, pressure: 1.0),
      ];

      await capturing.plotStrokes([stroke], minPointSpacing: 0.1);

      final packet = capturing.packets.single;
      var reversals = 0;
      for (var i = 1; i < packet.length - 1; i++) {
        if (_cosine(packet[i - 1], packet[i], packet[i + 1]) < -0.999) {
          reversals++;
          expect(_zoneType(packet[i]), 'FINE',
              reason: '180Â° obrat musĂ­ zastaviĹĄ (inak Cannot transition!)');
        }
      }
      expect(reversals, greaterThan(0));
    });

    test('balĂ­ky pre veÄľkĂş kresbu ostĂˇvajĂş bez nezaoblenĂ˝ch obratov',
        () async {
      final capturing = _CapturingProcessor(provider);

      // cik-cak drĂˇha, ktorĂˇ sa na konci kaĹľdĂ©ho riadku vracia spĂ¤ĹĄ
      final strokes = <List<StrokePoint>>[];
      for (var row = 0; row < 6; row++) {
        final y = 0.10 + row * 0.10;
        strokes.add(row.isEven
            ? [
                StrokePoint(x: 0.10, y: y, pressure: 1.0),
                StrokePoint(x: 0.80, y: y, pressure: 1.0),
              ]
            : [
                StrokePoint(x: 0.78, y: y, pressure: 1.0),
                StrokePoint(x: 0.12, y: y, pressure: 1.0),
              ]);
      }

      await capturing.plotStrokes(strokes, minPointSpacing: 0.1);

      expect(capturing.packets, isNotEmpty);
      for (final packet in capturing.packets) {
        expect(packet.length,
            lessThanOrEqualTo(StrokeMotionProcessor.maxPointsPerPacket));
        expect(_zoneType(packet.last), 'FINE');
        for (var i = 1; i < packet.length - 1; i++) {
          if (_cosine(packet[i - 1], packet[i], packet[i + 1]) < -0.999) {
            expect(_zoneType(packet[i]), 'FINE');
          }
        }
      }
    });
  });
}
