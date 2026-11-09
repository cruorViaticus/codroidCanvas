import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:codroid_pen_plotter/models/paper_format.dart';
import 'package:codroid_pen_plotter/models/plot_pattern.dart';
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

/// Smer ťahu v milimetroch papiera A4 (`x` = šírka, `y` = výška papiera).
({double dx, double dy}) _direction(List<dynamic> stroke) {
  final first = stroke.first;
  final last = stroke.last;
  return (
    dx: (last.x - first.x) * PaperFormat.a4.widthMm,
    dy: (last.y - first.y) * PaperFormat.a4.heightMm,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PlotPattern', () {
    test('neznámy alebo chýbajúci názov padá na horizontal', () {
      expect(PlotPattern.fromName('nonsense'), PlotPattern.horizontal);
      expect(PlotPattern.fromName(null), PlotPattern.horizontal);
      expect(PlotPattern.fromName('dots'), PlotPattern.dots);
      expect(kDefaultPlotPattern, PlotPattern.horizontal);
    });

    test('auto je automatický, dots je bodkový pattern', () {
      expect(PlotPattern.auto.isAutomatic, isTrue);
      expect(PlotPattern.horizontal.isAutomatic, isFalse);
      expect(PlotPattern.dots.isDotPattern, isTrue);
      expect(PlotPattern.diagonal.isDotPattern, isFalse);
      expect(PlotPattern.crossHatch.label, 'Cross-hatch');
      expect(PlotPattern.values, hasLength(9));
    });

    test('nové patterny: vlna, špirála a obrys', () {
      expect(PlotPattern.zigzag.label, 'Wave');
      expect(PlotPattern.spiral.label, 'Spiral');
      expect(PlotPattern.contour.label, 'Outline');

      // dlhé línie = vlna, špirála aj obrys
      expect(PlotPattern.zigzag.usesLongLines, isTrue);
      expect(PlotPattern.spiral.usesLongLines, isTrue);
      expect(PlotPattern.contour.usesLongLines, isTrue);
      expect(PlotPattern.horizontal.usesLongLines, isFalse);

      // obrys kreslí hrany, nie výplň
      expect(PlotPattern.contour.isOutline, isTrue);
      expect(PlotPattern.zigzag.isOutline, isFalse);

      // auto nevyberá obrys ani špirálu (nie sú to výplne)
      expect(PlotPattern.contour.isAutoCandidate, isFalse);
      expect(PlotPattern.spiral.isAutoCandidate, isFalse);
      expect(PlotPattern.zigzag.isAutoCandidate, isTrue);
      expect(PlotPattern.fromName('contour'), PlotPattern.contour);
      expect(PlotPattern.fromName('zigzag'), PlotPattern.zigzag);
    });
  });

  group('ImageStrokeGenerator – patterny', () {
    test('predvolený pattern ostáva horizontal (kompatibilita)', () {
      final result = ImageStrokeGenerator.toStrokes(
        _image(40, 40, (x, y) => true),
        lineSpacingMm: 60,
        pointSpacingMm: 2.0,
      );

      expect(result.pattern, PlotPattern.horizontal);
      expect(result.rowCount, 3);
      expect(result.strokes, hasLength(3));
      // vodorovné čiary: y sa nemení, x áno
      for (final stroke in result.strokes) {
        expect(stroke.first.y, closeTo(stroke.last.y, 1e-9));
        expect(stroke.first.x, isNot(closeTo(stroke.last.x, 1e-9)));
      }
    });

    test('vertical kreslí stĺpce (konštantné x, meniace sa y)', () {
      final result = ImageStrokeGenerator.toStrokes(
        _image(40, 40, (x, y) => true),
        pattern: PlotPattern.vertical,
        lineSpacingMm: 60,
        pointSpacingMm: 2.0,
      );

      expect(result.pattern, PlotPattern.vertical);
      expect(result.rowCount, 3);
      expect(result.strokes, hasLength(3));

      for (final stroke in result.strokes) {
        expect(stroke.first.x, closeTo(stroke.last.x, 1e-9));
        expect(stroke.first.y, isNot(closeTo(stroke.last.y, 1e-9)));
      }

      // serpentína: prvý stĺpec ide dole, druhý hore
      expect(result.strokes[0].last.y, greaterThan(result.strokes[0].first.y));
      expect(result.strokes[1].last.y, lessThan(result.strokes[1].first.y));
    });

    test('diagonal kreslí čiary pod 45°', () {
      final result = ImageStrokeGenerator.toStrokes(
        _image(40, 40, (x, y) => true),
        pattern: PlotPattern.diagonal,
        lineSpacingMm: 60,
        pointSpacingMm: 2.0,
      );

      expect(result.pattern, PlotPattern.diagonal);
      expect(result.strokes, isNotEmpty);

      for (final stroke in result.strokes) {
        if (stroke.length < 2) continue;
        final dir = _direction(stroke);
        expect(dir.dx.abs(), closeTo(dir.dy.abs(), 0.5));
      }
    });

    test('cross-hatch prejde obe diagonály', () {
      final image = _image(40, 40, (x, y) => true);

      final single = ImageStrokeGenerator.toStrokes(
        image,
        pattern: PlotPattern.diagonal,
        lineSpacingMm: 60,
        pointSpacingMm: 2.0,
      );
      final cross = ImageStrokeGenerator.toStrokes(
        image,
        pattern: PlotPattern.crossHatch,
        lineSpacingMm: 60,
        pointSpacingMm: 2.0,
      );

      expect(cross.pattern, PlotPattern.crossHatch);
      expect(cross.rowCount, single.rowCount * 2);
      expect(cross.strokes.length, greaterThan(single.strokes.length));
      expect(cross.pointCount, greaterThan(single.pointCount));

      // prvý priechod má dx a dy rovnakého znamienka, druhý opačného
      final firstPass = cross.strokes.any((s) {
        final dir = _direction(s);
        return dir.dx * dir.dy > 0;
      });
      final secondPass = cross.strokes.any((s) {
        final dir = _direction(s);
        return dir.dx * dir.dy < 0;
      });

      expect(firstPass, isTrue);
      expect(secondPass, isTrue);
    });

    test('dots vygeneruje krátke samostatné ťahy', () {
      final result = ImageStrokeGenerator.toStrokes(
        _image(40, 40, (x, y) => true),
        pattern: PlotPattern.dots,
        lineSpacingMm: 20,
        pointSpacingMm: 1.0,
      );

      expect(result.pattern, PlotPattern.dots);
      expect(result.strokes.length, greaterThan(50));
      expect(result.pointCount, result.strokes.length * 2);

      for (final stroke in result.strokes) {
        expect(stroke, hasLength(2)); // bodka = krátky ťah
      }

      final tickMm = _direction(result.strokes.first).dx.abs();
      expect(tickMm, greaterThan(0.0));
      expect(tickMm, lessThanOrEqualTo(0.8));

      // susedné bodky sú od seba ďalej, než je dlhá samotná bodka
      final gapMm = (result.strokes[1].first.x - result.strokes.first.first.x) *
          PaperFormat.a4.widthMm;
      expect(gapMm, greaterThan(tickMm * 2));
    });

    test('dots rešpektuje limit bodov', () {
      final result = ImageStrokeGenerator.toStrokes(
        _image(40, 40, (x, y) => true),
        pattern: PlotPattern.dots,
        lineSpacingMm: 5,
        pointSpacingMm: 1.0,
        maxPoints: 10,
      );

      expect(result.truncated, isTrue);
      expect(result.pointCount, lessThanOrEqualTo(10));
    });

    test('auto vyberie najlacnejší pattern (zvislé pruhy → vertical)', () {
      // 1 px široké zvislé pruhy: vodorovné riadky by mali oveľa viac ťahov
      final result = ImageStrokeGenerator.toStrokes(
        _image(40, 40, (x, y) => x % 8 == 4),
        pattern: PlotPattern.auto,
        lineSpacingMm: 5,
        pointSpacingMm: 1.0,
      );

      expect(result.pattern, isNot(PlotPattern.auto));
      expect(result.pattern, PlotPattern.vertical);
      expect(result.strokes, isNotEmpty);
      // zvislé ťahy = konštantné x
      final stroke = result.strokes.first;
      expect(stroke.first.x, closeTo(stroke.last.x, 1e-9));
    });

    test('auto na prázdnom obrázku nič nekreslí', () {
      final result = ImageStrokeGenerator.toStrokes(
        _image(40, 40, (x, y) => false),
        pattern: PlotPattern.auto,
      );

      expect(result.isEmpty, isTrue);
      expect(result.pattern, isNot(PlotPattern.auto));
    });

    test('zigzag (Wave) pospája riadky do jedného dlhého ťahu', () {
      final image = _image(40, 40, (x, y) => true);

      final rows = ImageStrokeGenerator.toStrokes(
        image,
        lineSpacingMm: 40,
        pointSpacingMm: 2.0,
      );
      final wave = ImageStrokeGenerator.toStrokes(
        image,
        pattern: PlotPattern.zigzag,
        lineSpacingMm: 40,
        pointSpacingMm: 2.0,
      );

      expect(wave.pattern, PlotPattern.zigzag);
      // rovnaké riadky ako pri horizontal…
      expect(wave.rowCount, rows.rowCount);
      expect(rows.strokes.length, greaterThan(1));
      // …ale pero zdvihne len raz: riadky sú spojené do jednej čiary
      expect(wave.strokes, hasLength(1));

      final stroke = wave.strokes.single;
      expect(stroke.length, greaterThan(rows.strokes.first.length));
      // ťah prejde viac riadkov (meniace sa y)
      expect(stroke.map((p) => p.y).toSet().length, greaterThan(1));
    });

    test('spiral kreslí dlhú čiaru a na prázdnom obrázku nič', () {
      final spiral = ImageStrokeGenerator.toStrokes(
        _image(40, 40, (x, y) => true),
        pattern: PlotPattern.spiral,
        lineSpacingMm: 20,
        pointSpacingMm: 1.0,
      );

      expect(spiral.pattern, PlotPattern.spiral);
      expect(spiral.strokes, isNotEmpty);
      expect(spiral.pointCount, greaterThan(100));
      expect(spiral.strokes.first.length, greaterThan(20));

      final empty = ImageStrokeGenerator.toStrokes(
        _image(40, 40, (x, y) => false),
        pattern: PlotPattern.spiral,
      );
      expect(empty.isEmpty, isTrue);
    });

    test('contour (Outline) obíde hrany tvaru jednou dlhou čiarou', () {
      // vyplnený štvorec 20 × 20 px v strede obrázka
      final image =
          _image(40, 40, (x, y) => x >= 10 && x < 30 && y >= 10 && y < 30);

      final outline = ImageStrokeGenerator.toStrokes(
        image,
        pattern: PlotPattern.contour,
        lineSpacingMm: 5,
        pointSpacingMm: 1.0,
      );

      expect(outline.pattern, PlotPattern.contour);
      // obvod = jedna súvislá čiara (štyri hrany zreťazené za sebou)
      expect(outline.strokes, hasLength(1));

      final stroke = outline.strokes.single;
      final xs = stroke.map((p) => p.x).toList();
      final ys = stroke.map((p) => p.y).toList();
      // čiara obíde celý štvorec, nielen jednu stranu
      expect(xs.reduce(math.min), lessThan(0.5));
      expect(xs.reduce(math.max), greaterThan(0.5));
      expect(ys.reduce(math.min), lessThan(0.5));
      expect(ys.reduce(math.max), greaterThan(0.5));

      // obrys kreslí len hrany – oveľa menej bodov ako výplň
      final filled = ImageStrokeGenerator.toStrokes(
        image,
        pattern: PlotPattern.horizontal,
        lineSpacingMm: 5,
        pointSpacingMm: 1.0,
      );
      expect(outline.pointCount, lessThan(filled.pointCount));

      // prázdny obrázok nemá žiadnu hranu
      expect(
        ImageStrokeGenerator.toStrokes(
          _image(40, 40, (x, y) => false),
          pattern: PlotPattern.contour,
        ).isEmpty,
        isTrue,
      );
    });
  });
}
