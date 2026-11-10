import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:codroid_pen_plotter/models/paper_format.dart';
import 'package:codroid_pen_plotter/models/plot_pattern.dart';
import 'package:codroid_pen_plotter/models/plot_start_side.dart';
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
      expect(PlotPattern.values, hasLength(13));
    });

    test('ďalšie patterny: druhá diagonála, trojité šrafovanie, kruhy', () {
      expect(PlotPattern.antiDiagonal.label, 'Diagonal 2');
      expect(PlotPattern.tripleHatch.label, 'Triple hatch');
      expect(PlotPattern.rings.label, 'Rings');
      expect(PlotPattern.fromName('antiDiagonal'), PlotPattern.antiDiagonal);
      expect(PlotPattern.fromName('tripleHatch'), PlotPattern.tripleHatch);
      expect(PlotPattern.fromName('rings'), PlotPattern.rings);

      // kruhy aj trojité šrafovanie sú výplne s dlhými čiarami / veľa bodmi
      expect(PlotPattern.rings.usesLongLines, isTrue);
      expect(PlotPattern.tripleHatch.usesLongLines, isFalse);
      expect(PlotPattern.antiDiagonal.isDotPattern, isFalse);

      // auto vyberá výplne, kruhy (umelecký priechod) nie
      expect(PlotPattern.antiDiagonal.isAutoCandidate, isTrue);
      expect(PlotPattern.tripleHatch.isAutoCandidate, isTrue);
      expect(PlotPattern.rings.isAutoCandidate, isFalse);
      expect(PlotPattern.auto.isAutoCandidate, isFalse);
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

    test('sketch: obrys s krokom bodov, ktorý robot zvládne', () {
      expect(PlotPattern.sketch.label, 'Sketch');
      expect(PlotPattern.fromName('sketch'), PlotPattern.sketch);

      // kreslí hrany (ako obrys), ale nie je výplň → `auto` ho nevyberá
      expect(PlotPattern.sketch.isOutline, isTrue);
      expect(PlotPattern.sketch.isAutoCandidate, isFalse);
      expect(PlotPattern.sketch.isDotPattern, isFalse);

      // minimálny krok rešpektuje rozostup bodov…
      expect(
        ImageStrokeGenerator.sketchStepMmFor(pointSpacingMm: 3.0),
        closeTo(3.0, 1e-9),
      );
      // …ale nikdy nejde pod hranicu, ktorú controller zvládne
      expect(
        ImageStrokeGenerator.sketchStepMmFor(pointSpacingMm: 0.2),
        ImageStrokeGenerator.minSketchStepMm,
      );
      // hrubé pero potrebuje väčší krok (body by zanikli v stope pera)
      expect(
        ImageStrokeGenerator.sketchStepMmFor(
          pointSpacingMm: 0.2,
          penWidthMm: 0.5,
        ),
        closeTo(2.0, 1e-9),
      );
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

    test('sketch drží body ďalej od seba než Outline (text a detail)', () {
      // kruh s jemnou hranou – Outline ho prejde pixel po pixeli
      final image = _image(
        800,
        800,
        (x, y) => (x - 400) * (x - 400) + (y - 400) * (y - 400) <= 200 * 200,
      );

      /// Najmenšia vzdialenosť dvoch susedných bodov v mm papiera.
      double minStepMm(List<List<StrokePoint>> strokes) {
        const paper = PaperFormat.a4;
        var minStep = double.infinity;
        for (final stroke in strokes) {
          for (var i = 1; i < stroke.length; i++) {
            final dx = (stroke[i].x - stroke[i - 1].x) * paper.widthMm;
            final dy = (stroke[i].y - stroke[i - 1].y) * paper.heightMm;
            minStep = math.min(minStep, math.sqrt(dx * dx + dy * dy));
          }
        }
        return minStep;
      }

      final outline = ImageStrokeGenerator.toStrokes(
        image,
        pattern: PlotPattern.contour,
        pointSpacingMm: 0.6,
      );
      final sketch = ImageStrokeGenerator.toStrokes(
        image,
        pattern: PlotPattern.sketch,
        pointSpacingMm: 0.6,
      );

      expect(sketch.pattern, PlotPattern.sketch);
      expect(sketch.strokes, isNotEmpty);
      // každý ťah má aspoň dva body (inak by to bola len bodka)
      expect(sketch.strokes.every((stroke) => stroke.length >= 2), isTrue);

      final step = ImageStrokeGenerator.sketchStepMmFor(pointSpacingMm: 0.6);
      expect(minStepMm(sketch.strokes), greaterThanOrEqualTo(step - 1e-6));

      // Outline ide po pixelových hranách – tam sú body oveľa bližšie…
      expect(minStepMm(outline.strokes), lessThan(step / 2));
      // …a preto ich má výrazne viac
      expect(sketch.pointCount, lessThan(outline.pointCount ~/ 2));
    });

    test('sketch vyhodí detaily menšie ako jeden krok', () {
      // 1 px bodka na veľkom obrázku má obvod ~0,5 mm – menej ako krok
      final speck = _image(1600, 1600, (x, y) => x == 800 && y == 800);

      expect(
        ImageStrokeGenerator.toStrokes(speck, pattern: PlotPattern.contour)
            .strokes,
        isNotEmpty,
      );
      expect(
        ImageStrokeGenerator.toStrokes(speck, pattern: PlotPattern.sketch)
            .isEmpty,
        isTrue,
      );

      // prázdny obrázok nemá žiadnu hranu
      expect(
        ImageStrokeGenerator.toStrokes(
          _image(40, 40, (x, y) => false),
          pattern: PlotPattern.sketch,
        ).isEmpty,
        isTrue,
      );
    });

    test('sketch obíde aj dieru v tvare (napr. písmeno O)', () {
      final image = _image(600, 600, (x, y) {
        final outer = x >= 100 && x < 500 && y >= 100 && y < 500;
        final hole = x >= 250 && x < 350 && y >= 250 && y < 350;
        return outer && !hole;
      });

      final sketch = ImageStrokeGenerator.toStrokes(
        image,
        pattern: PlotPattern.sketch,
        pointSpacingMm: 0.6,
      );

      // vonkajší obvod + vnútorná diera = dva samostatné ťahy
      expect(sketch.strokes, hasLength(2));
      for (final stroke in sketch.strokes) {
        expect(stroke.length, greaterThan(2));
        expect(stroke.first.x, closeTo(stroke.last.x, 1e-6));
        expect(stroke.first.y, closeTo(stroke.last.y, 1e-6));
      }
    });

    test('antiDiagonal (Diagonal 2) kreslí čiary zrkadlovo k diagonal', () {
      final image = _image(40, 40, (x, y) => true);

      final diagonal = ImageStrokeGenerator.toStrokes(
        image,
        pattern: PlotPattern.diagonal,
        lineSpacingMm: 60,
        pointSpacingMm: 2.0,
      );
      final anti = ImageStrokeGenerator.toStrokes(
        image,
        pattern: PlotPattern.antiDiagonal,
        lineSpacingMm: 60,
        pointSpacingMm: 2.0,
      );

      expect(anti.pattern, PlotPattern.antiDiagonal);
      expect(anti.strokes, isNotEmpty);
      expect(anti.rowCount, diagonal.rowCount);
      expect(anti.pointCount, greaterThan(0));

      // prvý pattern má dx a dy rovnakého znamienka…
      for (final stroke in diagonal.strokes.where((s) => s.length > 1)) {
        final dir = _direction(stroke);
        expect(dir.dx * dir.dy, greaterThan(0));
      }
      // …druhý presne opačného (čiary pod −45°)
      for (final stroke in anti.strokes.where((s) => s.length > 1)) {
        final dir = _direction(stroke);
        expect(dir.dx.abs(), closeTo(dir.dy.abs(), 0.5));
        expect(dir.dx * dir.dy, lessThan(0));
      }
    });

    test('tripleHatch prejde tri priechody (0°, +45°, −45°)', () {
      final image = _image(40, 40, (x, y) => true);

      final rows = ImageStrokeGenerator.toStrokes(
        image,
        pattern: PlotPattern.horizontal,
        lineSpacingMm: 60,
        pointSpacingMm: 2.0,
      );
      final cross = ImageStrokeGenerator.toStrokes(
        image,
        pattern: PlotPattern.crossHatch,
        lineSpacingMm: 60,
        pointSpacingMm: 2.0,
      );
      final triple = ImageStrokeGenerator.toStrokes(
        image,
        pattern: PlotPattern.tripleHatch,
        lineSpacingMm: 60,
        pointSpacingMm: 2.0,
      );

      expect(triple.pattern, PlotPattern.tripleHatch);
      // vodorovné riadky + krížové šrafovanie = tri priechody
      expect(triple.rowCount, rows.rowCount + cross.rowCount);
      expect(triple.strokes.length, greaterThan(cross.strokes.length));
      expect(triple.pointCount, greaterThan(cross.pointCount));

      final dirs = triple.strokes
          .where((s) => s.length > 1)
          .map((s) => _direction(s))
          .toList();
      expect(dirs.any((d) => d.dy.abs() < 0.5), isTrue); // vodorovný priechod
      expect(dirs.any((d) => d.dx * d.dy > 0), isTrue); // +45°
      expect(dirs.any((d) => d.dx * d.dy < 0), isTrue); // −45°
    });

    test('rings kreslia sústredné kružnice od stredu', () {
      final rings = ImageStrokeGenerator.toStrokes(
        _image(40, 40, (x, y) => true),
        pattern: PlotPattern.rings,
        lineSpacingMm: 20,
        pointSpacingMm: 1.0,
      );

      expect(rings.pattern, PlotPattern.rings);
      expect(rings.strokes.length, greaterThan(1));

      double radiusOf(StrokePoint p) {
        final dx = (p.x - 0.5) * PaperFormat.a4.widthMm;
        final dy = (p.y - 0.5) * PaperFormat.a4.heightMm;
        return math.sqrt(dx * dx + dy * dy);
      }

      final first = rings.strokes.first;
      // prvý kruh je vo vzdialenosti jednej hustoty riadkov od stredu
      expect(radiusOf(first.first), closeTo(20, 1.5));
      // kruh je uzavretý – koniec je tam, kde začiatok
      expect(radiusOf(first.last), closeTo(radiusOf(first.first), 1.5));
      // každý ďalší kruh je väčší
      expect(radiusOf(rings.strokes[1].first),
          greaterThan(radiusOf(first.first) + 10));

      // prázdny obrázok nemá čo kresliť
      expect(
        ImageStrokeGenerator.toStrokes(
          _image(40, 40, (x, y) => false),
          pattern: PlotPattern.rings,
        ).isEmpty,
        isTrue,
      );
    });

    test('startSide bottom otočí poradie ťahov (kresba ostáva rovnaká)', () {
      final image = _image(40, 40, (x, y) => true);

      final top = ImageStrokeGenerator.toStrokes(
        image,
        lineSpacingMm: 20,
        pointSpacingMm: 2.0,
      );
      final bottom = ImageStrokeGenerator.toStrokes(
        image,
        lineSpacingMm: 20,
        pointSpacingMm: 2.0,
        startSide: PlotStartSide.bottom,
      );

      expect(top.startSide, PlotStartSide.top);
      expect(bottom.startSide, PlotStartSide.bottom);
      // rovnaký počet ťahov aj bodov, len v opačnom poradí
      expect(bottom.strokes.length, top.strokes.length);
      expect(bottom.pointCount, top.pointCount);
      expect(bottom.rowCount, top.rowCount);

      // prvý ťah zdola je presne posledný ťah zhora (aj s opačnými bodmi)
      expect(bottom.strokes.first.first.y,
          closeTo(top.strokes.last.first.y, 1e-9));
      expect(
          bottom.strokes.first.first.x, closeTo(top.strokes.last.last.x, 1e-9));
      // pero začína nižšie na papieri (y rastie nadol)
      expect(
          bottom.strokes.first.first.y, greaterThan(top.strokes.first.first.y));
    });
  });

  group('PlotStartSide', () {
    test('predvolená aj neznáma hodnota je top', () {
      expect(kDefaultPlotStartSide, PlotStartSide.top);
      expect(PlotStartSide.fromName('bottom'), PlotStartSide.bottom);
      expect(PlotStartSide.fromName('nonsense'), PlotStartSide.top);
      expect(PlotStartSide.fromName(null), PlotStartSide.top);

      expect(PlotStartSide.bottom.isBottom, isTrue);
      expect(PlotStartSide.top.isBottom, isFalse);
      expect(PlotStartSide.top.label, 'Top');
      expect(PlotStartSide.bottom.label, 'Bottom');
      expect(PlotStartSide.values, hasLength(2));
    });
  });
}
