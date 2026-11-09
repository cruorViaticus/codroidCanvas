import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:codroid_pen_plotter/models/queued_stroke.dart';
import 'package:codroid_pen_plotter/models/stroke_point.dart';
import 'package:codroid_pen_plotter/providers/robot_provider.dart';
import 'package:codroid_pen_plotter/services/stroke_motion_processor.dart';

/// Zvislý ťah, ktorého body sú od seba [stepMm] milimetrov na papieri.
///
/// `toMillimetres` otáča osi (`Offset((1-y)*297, (1-x)*210)`), takže krok
/// v `y` o `stepMm / 297` znamená krok `stepMm` v milimetroch.
List<StrokePoint> _line({int count = 6, double stepMm = 1.0}) => [
      for (var i = 0; i < count; i++)
        StrokePoint(x: 0.5, y: 0.5 + i * stepMm / 297.0, pressure: 1.0),
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StrokeMotionProcessor processor;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    processor = StrokeMotionProcessor(RobotProvider());
  });

  group('QueuedStroke', () {
    test('voľná kresba necháva rozlíšenie na predvolenej hodnote', () {
      final stroke = QueuedStroke(_line());

      expect(stroke.minPointSpacingMm, isNull);
      expect(StrokeMotionProcessor.minPointSpacingMm, 5.0);
    });

    test('jemné rozlíšenie pre text/obrázok sa zapamätá', () {
      final stroke = QueuedStroke(_line(), minPointSpacingMm: 0.3);

      expect(stroke.minPointSpacingMm, 0.3);
      expect(stroke.toString(), contains('0.3'));
    });
  });

  group('toMillimetrePath s vlastným rozlíšením', () {
    test('predvolených 5 mm zahodí jemné body', () {
      final path = processor.toMillimetrePath(_line(count: 6, stepMm: 1.0));

      expect(path, hasLength(2)); // prvý a posledný bod
      expect((path.last - path.first).distance, closeTo(5.0, 0.001));
    });

    test('0,3 mm pre text/obrázok zachová všetky body', () {
      final path = processor.toMillimetrePath(
        _line(count: 6, stepMm: 1.0),
        minPointSpacing: 0.3,
      );

      expect(path, hasLength(6));
      for (var i = 1; i < path.length; i++) {
        expect((path[i] - path[i - 1]).distance, closeTo(1.0, 0.001));
      }
    });

    test('hustejšie rozlíšenie vráti viac bodov ako predvolené', () {
      final stroke = _line(count: 40, stepMm: 0.8);

      final coarse = processor.toMillimetrePath(stroke);
      final fine = processor.toMillimetrePath(stroke, minPointSpacing: 0.4);

      expect(fine.length, greaterThan(coarse.length));
      // krajné body ostávajú rovnaké
      expect((fine.first - coarse.first).distance, closeTo(0.0, 0.001));
      expect((fine.last - coarse.last).distance, closeTo(0.0, 0.001));
    });

    test('posledný bod ťahu sa nikdy nestratí', () {
      // body bližšie ako rozlíšenie – filter by ich zahodil, koniec musí ostať
      final stroke = _line(count: 4, stepMm: 0.1);

      final path = processor.toMillimetrePath(stroke, minPointSpacing: 5.0);

      expect(path, hasLength(2));
      expect(
        (path.last - processor.toMillimetres(stroke.last)).distance,
        closeTo(0.0, 0.001),
      );
    });

    test('body sú v milimetroch papiera A4', () {
      final path = processor.toMillimetrePath(
        [
          StrokePoint(x: 0.5, y: 0.5, pressure: 1.0),
          StrokePoint(x: 0.0, y: 1.0, pressure: 1.0),
        ],
        minPointSpacing: 0.1,
      );

      expect(path.first, const Offset(148.5, 105.0));
      expect(path.last, const Offset(0.0, 210.0));
    });
  });

  group('RobotProvider.addStrokes', () {
    test('pridá celú sadu ťahov do fronty naraz', () async {
      final provider = RobotProvider();
      await provider.initialized;

      provider.addStrokes([_line(), _line(), _line()], minPointSpacingMm: 0.4);

      expect(provider.pendingStrokes, 3);
      expect(provider.strokes, hasLength(3));
    });

    test('prázdne ťahy sa preskočia', () async {
      final provider = RobotProvider();
      await provider.initialized;

      provider.addStrokes([<StrokePoint>[], _line()]);
      provider.addStrokes([]);

      expect(provider.pendingStrokes, 1);
      expect(provider.strokes, hasLength(1));
    });

    test('clearCanvas vyprázdni frontu aj nakreslené ťahy', () async {
      final provider = RobotProvider();
      await provider.initialized;
      provider.addStrokes([_line()]);

      provider.clearCanvas();

      expect(provider.pendingStrokes, 0);
      expect(provider.strokes, isEmpty);
    });
  });
}
