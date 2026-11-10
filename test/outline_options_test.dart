import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:codroid_pen_plotter/models/outline_options.dart';
import 'package:codroid_pen_plotter/models/paper_format.dart';
import 'package:codroid_pen_plotter/models/plot_pattern.dart';
import 'package:codroid_pen_plotter/models/stroke_point.dart';
import 'package:codroid_pen_plotter/services/image_stroke_generator.dart';

/// Obrázok poskladaný z pixelov – [isInk] vráti `true` pre atrament.
GrayImage _image(int width, int height, bool Function(int x, int y) isInk) {
  final gray = Uint8List(width * height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      gray[y * width + x] = isInk(x, y) ? 0 : 255;
    }
  }
  return GrayImage(width: width, height: height, gray: gray);
}

/// Kruh so stredom [cx], [cy] a polomerom [r] (v pixeloch).
bool Function(int x, int y) _circle(int cx, int cy, int r) =>
    (x, y) => (x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r;

/// Vzdialenosť dvoch bodov ťahu v mm papiera A4.
double _distanceMm(StrokePoint a, StrokePoint b) {
  const paper = PaperFormat.a4;
  final dx = (a.x - b.x) * paper.widthMm;
  final dy = (a.y - b.y) * paper.heightMm;
  return math.sqrt(dx * dx + dy * dy);
}

/// Koľko pero prejde so zdvihnutým perom medzi ťahmi (súčet prejazdov).
double _travelMm(List<List<StrokePoint>> strokes) {
  var total = 0.0;
  for (var i = 1; i < strokes.length; i++) {
    total += _distanceMm(strokes[i - 1].last, strokes[i].first);
  }
  return total;
}

/// Najmenšia vzdialenosť dvoch susedných bodov v mm papiera.
double _minStepMm(List<List<StrokePoint>> strokes) {
  var minStep = double.infinity;
  for (final stroke in strokes) {
    for (var i = 1; i < stroke.length; i++) {
      minStep = math.min(minStep, _distanceMm(stroke[i - 1], stroke[i]));
    }
  }
  return minStep;
}

/// Je ťah uzavretý (začína a končí v tom istom bode)?
void _expectClosed(List<StrokePoint> stroke) {
  expect(_distanceMm(stroke.first, stroke.last), lessThan(1e-6));
}

/// Dva stĺpce po troch štvorcoch – poradie „zhora dole“ tu skáče zľava
/// doprava a späť, presne ako pri obrázku s textom.
GrayImage _twoColumns() => _image(800, 800, (x, y) {
      final row = (y >= 100 && y < 140) ||
          (y >= 350 && y < 390) ||
          (y >= 600 && y < 640);
      final column = (x >= 60 && x < 120) || (x >= 680 && x < 740);
      return row && column;
    });


void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OutlineOptions', () {
    test('predvolené hodnoty sedia s osvedčeným správaním', () {
      const options = OutlineOptions();

      expect(options.stepMm, 0); // 0 = krok podľa patternu
      expect(options.minDetailMm, 0); // 0 = kreslí všetko
      expect(options.smoothing, OutlineSmoothing.auto);
      expect(options.order, OutlineOrder.nearest);
      expect(options.rotateStart, isTrue);
      expect(options.isDefault, isTrue);
      expect(options.hasCustomStep, isFalse);
      expect(OutlineOptions.defaults, options);
    });

    test('copyWith mení len zadané polia', () {
      const options = OutlineOptions();

      final changed = options.copyWith(
        stepMm: 1.2,
        minDetailMm: 0.5,
        smoothing: OutlineSmoothing.off,
        order: OutlineOrder.asFound,
        rotateStart: false,
      );

      expect(changed.stepMm, 1.2);
      expect(changed.minDetailMm, 0.5);
      expect(changed.smoothing, OutlineSmoothing.off);
      expect(changed.order, OutlineOrder.asFound);
      expect(changed.rotateStart, isFalse);
      expect(changed.hasCustomStep, isTrue);
      expect(changed.isDefault, isFalse);

      // pôvodný objekt sa nezmenil
      expect(options, OutlineOptions.defaults);
      expect(options.copyWith(stepMm: 2), isNot(options));
    });

    test('rovnosť a hashCode idú podľa všetkých polí', () {
      const a = OutlineOptions(stepMm: 1, minDetailMm: 1);
      const b = OutlineOptions(stepMm: 1, minDetailMm: 1);
      const c = OutlineOptions(stepMm: 1, minDetailMm: 1, rotateStart: false);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });

    test('každá voľba má popis pre UI', () {
      expect(OutlineOptions.defaults.toString(), contains('OutlineOptions'));

      for (final order in OutlineOrder.values) {
        expect(order.label, isNotEmpty);
        expect(order.description, isNotEmpty);
      }
      for (final smoothing in OutlineSmoothing.values) {
        expect(smoothing.label, isNotEmpty);
        expect(smoothing.description, isNotEmpty);
      }
      expect(OutlineOrder.nearest.label, 'Nearest');
      expect(OutlineSmoothing.auto.label, 'Auto');
    });
  });

  group('Outline – poradie a začiatok ťahov', () {
    test('nearest skráti prejazdy medzi obrysmi', () {
      final image = _twoColumns();

      final asFound = ImageStrokeGenerator.toStrokes(
        image,
        pattern: PlotPattern.contour,
        outline: const OutlineOptions(order: OutlineOrder.asFound),
      );
      final nearest = ImageStrokeGenerator.toStrokes(
        image,
        pattern: PlotPattern.contour,
        outline: const OutlineOptions(order: OutlineOrder.nearest),
      );

      // šesť štvorcov = šesť uzavretých obrysov v oboch prípadoch
      expect(asFound.strokes, hasLength(6));
      expect(nearest.strokes, hasLength(6));

      // to isté pero, len v inom poradí – prejazdy musia byť kratšie
      expect(
        _travelMm(nearest.strokes),
        lessThan(_travelMm(asFound.strokes) * 0.75),
      );
      expect(nearest.pointCount, asFound.pointCount);
    });

    test('asFound ostane v poradí, v akom generátor hrany našiel', () {
      final image = _twoColumns();

      final asFound = ImageStrokeGenerator.toStrokes(
        image,
        pattern: PlotPattern.contour,
        outline: const OutlineOptions(order: OutlineOrder.asFound),
      );
      final noRotation = ImageStrokeGenerator.toStrokes(
        image,
        pattern: PlotPattern.contour,
        outline: const OutlineOptions(
          order: OutlineOrder.asFound,
          rotateStart: false,
        ),
      );

      expect(
        _travelMm(asFound.strokes),
        lessThanOrEqualTo(_travelMm(noRotation.strokes) + 1e-6),
      );
    });

    test('rotateStart začne uzavretý obrys čo najbližšie k peru', () {
      // tri kruhy v jednom rade – pero do druhého vstúpi z boku
      final image = _image(1200, 400, (x, y) {
        return _circle(200, 200, 100)(x, y) ||
            _circle(600, 200, 100)(x, y) ||
            _circle(1000, 200, 100)(x, y);
      });

      final plain = ImageStrokeGenerator.toStrokes(
        image,
        pattern: PlotPattern.contour,
        outline: const OutlineOptions(
          order: OutlineOrder.asFound,
          rotateStart: false,
        ),
      );
      final rotated = ImageStrokeGenerator.toStrokes(
        image,
        pattern: PlotPattern.contour,
        outline: const OutlineOptions(order: OutlineOrder.asFound),
      );

      final plainStrokes = plain.strokes;
      final rotatedStrokes = rotated.strokes;
      expect(plainStrokes, hasLength(3));
      expect(rotatedStrokes, hasLength(3));

      var improved = false;
      for (var i = 1; i < rotatedStrokes.length; i++) {
        final cursor = rotatedStrokes[i - 1].last;
        final withRotation = _distanceMm(cursor, rotatedStrokes[i].first);
        final withoutRotation = _distanceMm(cursor, plainStrokes[i].first);
        // rotácia nikdy nepredĺži prejazd – vyberá najbližší bod obrysu
        expect(withRotation, lessThanOrEqualTo(withoutRotation + 1e-6));
        if (withRotation < withoutRotation - 1e-6) improved = true;
        _expectClosed(rotatedStrokes[i]);
      }
      expect(improved, isTrue);
    });

    test('nearestFlipped nemení kresbu, len smer ťahov', () {
      final image = _twoColumns();

      final nearest = ImageStrokeGenerator.toStrokes(
        image,
        pattern: PlotPattern.contour,
        outline: const OutlineOptions(order: OutlineOrder.nearest),
      );
      final flipped = ImageStrokeGenerator.toStrokes(
        image,
        pattern: PlotPattern.contour,
        outline: const OutlineOptions(order: OutlineOrder.nearestFlipped),
      );

      expect(flipped.strokes, hasLength(nearest.strokes.length));
      expect(
        (flipped.pointCount - nearest.pointCount).abs(),
        lessThanOrEqualTo(2),
      );
    });
  });


  group('Outline – krok, vyhladenie a najmenší detail', () {
    test('vlastný krok dodrží tetivu aspoň 1.5 mm', () {
      final image = _image(800, 800, _circle(400, 400, 250));

      final outline = ImageStrokeGenerator.toStrokes(
        image,
        pattern: PlotPattern.contour,
        pointSpacingMm: 0.3,
        outline: const OutlineOptions(stepMm: 1.5),
      );

      expect(outline.strokes, isNotEmpty);
      expect(_minStepMm(outline.strokes), greaterThanOrEqualTo(1.5 - 1e-6));
      for (final stroke in outline.strokes) {
        _expectClosed(stroke);
      }
    });

    test('sketch ani pri vlastnom kroku nezíde pod minSketchStepMm', () {
      final image = _image(800, 800, _circle(400, 400, 250));

      final sketch = ImageStrokeGenerator.toStrokes(
        image,
        pattern: PlotPattern.sketch,
        outline: const OutlineOptions(stepMm: 0.2),
      );

      expect(sketch.strokes, isNotEmpty);
      expect(
        _minStepMm(sketch.strokes),
        greaterThanOrEqualTo(ImageStrokeGenerator.minSketchStepMm - 1e-6),
      );
    });

    test('smoothing strong zjednoduší aj Outline, auto ostane po pixeloch', () {
      final image = _image(800, 800, _circle(400, 400, 250));

      final auto = ImageStrokeGenerator.toStrokes(
        image,
        pattern: PlotPattern.contour,
      );
      final off = ImageStrokeGenerator.toStrokes(
        image,
        pattern: PlotPattern.contour,
        outline: const OutlineOptions(smoothing: OutlineSmoothing.off),
      );
      final strong = ImageStrokeGenerator.toStrokes(
        image,
        pattern: PlotPattern.contour,
        outline: const OutlineOptions(smoothing: OutlineSmoothing.strong),
      );

      // `auto` sa pri Outline správa ako `off` – presne po pixelových hranách
      expect(off.pointCount, auto.pointCount);
      expect(off.strokes, hasLength(auto.strokes.length));

      expect(strong.strokes, hasLength(auto.strokes.length));
      expect(strong.pointCount, lessThan(auto.pointCount));
      for (final stroke in strong.strokes) {
        _expectClosed(stroke);
      }
    });

    test('minDetailMm vyhodí bodky menšie ako stopa pera', () {
      // 1 px bodka na veľkom obrázku má obvod ~0,5 mm
      final speck = _image(1600, 1600, (x, y) => x == 800 && y == 800);

      expect(
        ImageStrokeGenerator.toStrokes(speck, pattern: PlotPattern.contour)
            .strokes,
        isNotEmpty,
      );
      expect(
        ImageStrokeGenerator.toStrokes(
          speck,
          pattern: PlotPattern.contour,
          outline: const OutlineOptions(minDetailMm: 1.0),
        ).isEmpty,
        isTrue,
      );
    });
  });

}
