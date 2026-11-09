import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:codroid_pen_plotter/providers/robot_provider.dart';
import 'package:codroid_pen_plotter/services/stroke_motion_processor.dart';

/// `cpos` z `movl` / `movMulti` bodu.
Map<String, dynamic> _cpos(Map<String, dynamic> point) =>
    point['target']['cpos'] as Map<String, dynamic>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Orientácia nástroja pre body A a B', () {
    test('konštanty sú a = 180°, b = 0°, c = -90°', () {
      expect(RobotProvider.orientationA, 180.0);
      expect(RobotProvider.orientationB, 0.0);
      expect(RobotProvider.orientationC, -90.0);
    });

    test('dráha (A) aj parkovanie (B) posielajú rovnakú orientáciu', () async {
      final provider = RobotProvider();
      await provider.initialized;
      final processor = StrokeMotionProcessor(provider);

      final pointA = provider.buildCartPoint(
        RobotProvider.pointAX,
        RobotProvider.pointAY,
        provider.penUpZ,
        zoneType: 'FINE',
      );
      final pointB = provider.buildCartPoint(
        RobotProvider.pointBX,
        RobotProvider.pointBY,
        RobotProvider.pointBZ,
        zoneType: 'FINE',
      );
      final pathPoint = processor.buildCartPoint(
        12.0,
        34.0,
        provider.penDownZ,
        zoneType: 'RELATIVE',
        zdis: 5.0,
      );

      for (final point in [pointA, pointB, pathPoint]) {
        final cpos = _cpos(point);
        expect(cpos['a'], RobotProvider.orientationA);
        expect(cpos['b'], RobotProvider.orientationB);
        expect(cpos['c'], RobotProvider.orientationC);
        // POSCFG mode 7 = rovnaký frame ako na teaching pendante
        expect((cpos['poscfg'] as Map)['mode'], 7);
      }
    });

    test('bod B je presne 100, 100, 200', () async {
      final provider = RobotProvider();
      await provider.initialized;

      final cpos = _cpos(provider.buildCartPoint(
        RobotProvider.pointBX,
        RobotProvider.pointBY,
        RobotProvider.pointBZ,
        zoneType: 'FINE',
      ));

      expect(cpos['x'], 100.0);
      expect(cpos['y'], 100.0);
      expect(cpos['z'], 200.0);
      expect(RobotProvider.pointBLabel, '100, 100, 200 mm');
    });

    test('bod A sedí na X = 50, Y = 100 a rešpektuje Z korekciu', () async {
      final provider = RobotProvider();
      await provider.initialized;
      provider.zOffsetMm = 10.0;

      final cpos = _cpos(provider.buildCartPoint(
        RobotProvider.pointAX,
        RobotProvider.pointAY,
        provider.penUpZ,
        zoneType: 'FINE',
      ));

      expect(cpos['x'], 50.0);
      expect(cpos['y'], 100.0);
      expect(cpos['z'], closeTo(provider.penUpNominalZ + 10.0, 0.001));
    });

    test('presun na A / B bez pripojenia nič neodošle a nespadne', () async {
      final provider = RobotProvider();
      await provider.initialized;

      await provider.moveToPointA();
      await provider.moveToPointB();

      expect(provider.status.isConnected, isFalse);
      expect(provider.pendingStrokes, 0);
    });
  });
}
