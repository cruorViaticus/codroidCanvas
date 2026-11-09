import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:codroid_pen_plotter/services/text_stroke_generator.dart';
import 'package:codroid_pen_plotter/services/vector_font.dart';

/// Najmenšia a najväčšia súradnica X spomedzi všetkých bodov.
({double min, double max}) _xRange(TextPlotResult result) {
  var min = double.infinity;
  var max = -double.infinity;
  for (final stroke in result.strokes) {
    for (final point in stroke) {
      min = math.min(min, point.x);
      max = math.max(max, point.x);
    }
  }
  return (min: min, max: max);
}

void main() {
  group('VectorFont', () {
    test('obsahuje veľké, malé písmená, číslice aj symboly', () {
      for (final char in [
        'A', 'Z', 'a', 'z', '0', '9', '.', '-', '!', '?', '@', '#' //
      ]) {
        expect(VectorFont.glyph(char), isNotNull, reason: 'chýba znak "$char"');
      }
    });

    test('každý glyf má párne súradnice a aspoň jednu čiaru', () {
      for (final char in VectorFont.supportedCharacters) {
        final glyph = VectorFont.glyph(char)!;
        expect(glyph.width, greaterThan(0), reason: 'znak "$char"');
        expect(glyph.paths, isNotEmpty, reason: 'znak "$char"');
        for (final path in glyph.paths) {
          expect(path.length.isEven, isTrue, reason: 'znak "$char"');
          expect(path.length, greaterThanOrEqualTo(4), reason: 'znak "$char"');
        }
      }
    });

    test('diakritika sa normalizuje na základný znak', () {
      expect(VectorFont.normalizeChar('á'), 'a');
      expect(VectorFont.normalizeChar('Č'), 'C');
      expect(VectorFont.normalizeChar('ž'), 'z');
      // neznámy znak ostáva nezmenený
      expect(VectorFont.normalizeChar('Q'), 'Q');
    });
  });

  group('TextStrokeGenerator', () {
    test('prázdny text nevytvorí ani jeden ťah', () {
      final result = TextStrokeGenerator.generate(text: '   \n  ');

      expect(result.isEmpty, isTrue);
      expect(result.pointCount, 0);
      expect(result.lines, isEmpty);
      expect(result.overflow, isFalse);
      expect(result.unsupportedCharacters, isEmpty);
    });

    test('text sa prevedie na ťahy s bodmi v rozsahu 0..1', () {
      final result =
          TextStrokeGenerator.generate(text: 'HELLO', fontSizeMm: 12);

      expect(result.strokes, isNotEmpty);

      var counted = 0;
      for (final stroke in result.strokes) {
        expect(stroke.length, greaterThanOrEqualTo(2));
        counted += stroke.length;
        for (final point in stroke) {
          expect(point.x, inInclusiveRange(0.0, 1.0));
          expect(point.y, inInclusiveRange(0.0, 1.0));
          expect(point.pressure, 1.0);
        }
      }
      // pointCount musí sedieť s tým, čo sa pošle do fronty
      expect(counted, result.pointCount);
    });

    test('výška textu zodpovedá zvolenej veľkosti písma', () {
      final result = TextStrokeGenerator.generate(text: 'H', fontSizeMm: 20);

      // 'H' siaha od základnej línie po výšku veľkých písmen
      expect(result.usedHeightMm, closeTo(20.0, 0.001));
    });

    test('väčšie písmo zaberie na papieri viac miesta', () {
      final small = TextStrokeGenerator.generate(text: 'ABC', fontSizeMm: 8);
      final large = TextStrokeGenerator.generate(text: 'ABC', fontSizeMm: 24);

      expect(small.usedHeightMm, lessThan(large.usedHeightMm));
    });

    test('dlhý text sa zalomí do viacerých riadkov', () {
      final text = List.filled(20, 'PLOTTER').join(' ');
      final result = TextStrokeGenerator.generate(text: text, fontSizeMm: 14);

      expect(result.lines.length, greaterThan(1));
      for (final line in result.lines) {
        expect(line, isNotEmpty);
        expect(line.length, lessThan(text.length));
      }
    });

    test('ručné zalomenie cez \\n sa rešpektuje', () {
      final result = TextStrokeGenerator.generate(text: 'PRVY\nDRUHY');

      expect(result.lines, ['PRVY', 'DRUHY']);
    });

    test('zarovnanie posúva text zľava doprava', () {
      final left = TextStrokeGenerator.generate(
        text: 'AB',
        alignment: TextAlignment.left,
      );
      final center = TextStrokeGenerator.generate(
        text: 'AB',
        alignment: TextAlignment.center,
      );
      final right = TextStrokeGenerator.generate(
        text: 'AB',
        alignment: TextAlignment.right,
      );

      final leftRange = _xRange(left);
      final centerRange = _xRange(center);
      final rightRange = _xRange(right);

      expect(centerRange.min, greaterThan(leftRange.min));
      expect(centerRange.max, greaterThan(leftRange.max));
      expect(rightRange.min, greaterThan(centerRange.min));
      expect(rightRange.max, greaterThan(centerRange.max));
      // text zostáva na papieri
      expect(rightRange.max, lessThanOrEqualTo(1.0));
    });

    test('diakritika sa vykreslí ako základný znak', () {
      final accented =
          TextStrokeGenerator.generate(text: 'ČŠŽ', fontSizeMm: 12);
      final plain = TextStrokeGenerator.generate(text: 'CSZ', fontSizeMm: 12);

      expect(accented.unsupportedCharacters, isEmpty);
      expect(accented.strokes.length, plain.strokes.length);
      expect(accented.pointCount, plain.pointCount);
    });

    test('nepodporovaný znak sa nahlási, ale generovanie pokračuje', () {
      final result = TextStrokeGenerator.generate(text: 'A😀B');

      expect(result.unsupportedCharacters, contains('😀'));
      expect(result.strokes, isNotEmpty);
      expect(result.pointCount, greaterThan(0));
    });

    test('text mimo papiera označí overflow', () {
      final fits = TextStrokeGenerator.generate(text: 'X', fontSizeMm: 12);
      final tooBig = TextStrokeGenerator.generate(text: 'X', fontSizeMm: 300);

      expect(fits.overflow, isFalse);
      expect(tooBig.overflow, isTrue);
    });

    test('väčší okraj papiera posúva text dovnútra', () {
      final small = TextStrokeGenerator.generate(text: 'I', marginMm: 10);
      final large = TextStrokeGenerator.generate(text: 'I', marginMm: 40);

      expect(_xRange(large).min, greaterThan(_xRange(small).min));
    });
  });
}
