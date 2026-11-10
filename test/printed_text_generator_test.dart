import 'package:flutter_test/flutter_test.dart';

import 'package:codroid_pen_plotter/models/paper_format.dart';
import 'package:codroid_pen_plotter/services/printed_text_generator.dart';
import 'package:codroid_pen_plotter/services/text_stroke_generator.dart';

/// Tlačený text na A5 s menším okrajom – rýchlejšia rasterizácia v testoch.
Future<TextPlotResult> _generate(
  String text, {
  double fontSizeMm = 12,
  PrintedTextFill fill = PrintedTextFill.outline,
  double fillDensityMm = PrintedTextGenerator.defaultFillDensityMm,
}) =>
    PrintedTextGenerator.generate(
      text: text,
      fontSizeMm: fontSizeMm,
      marginMm: 10,
      paper: PaperFormat.a5,
      fill: fill,
      fillDensityMm: fillDensityMm,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PrintedTextGenerator', () {
    test('prázdny text nevytvorí ani jeden ťah', () async {
      final result = await _generate('   \n  ');

      expect(result.isEmpty, isTrue);
      expect(result.pointCount, 0);
      expect(result.lines, isEmpty);
      expect(result.overflow, isFalse);
      expect(result.truncated, isFalse);
    });

    test('text sa vytlačí reálnym fontom a body ostávajú na papieri', () async {
      final result = await _generate('Codroid');

      expect(result.strokes, isNotEmpty);
      expect(result.lines, isNotEmpty);
      expect(result.unsupportedCharacters, isEmpty);
      expect(result.overflow, isFalse);
      expect(result.truncated, isFalse);
      expect(result.usedHeightMm, greaterThan(0));

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

    test('Solid vyplní písmená, Outline len obíde hrany', () async {
      final outline = await _generate('O');
      final solid = await _generate('O', fill: PrintedTextFill.solid);

      expect(outline.strokes, isNotEmpty);
      expect(solid.strokes, isNotEmpty);
      expect(solid.pointCount, greaterThan(outline.pointCount));
    });

    test('hustejšia výplň má viac bodov', () async {
      final fine = await _generate(
        'O',
        fill: PrintedTextFill.solid,
        fillDensityMm: 0.4,
      );
      final coarse = await _generate(
        'O',
        fill: PrintedTextFill.solid,
        fillDensityMm: 1.6,
      );

      expect(fine.pointCount, greaterThan(coarse.pointCount));
    });

    test('diakritika sa vytlačí (reálny font pozná všetko)', () async {
      final result = await _generate('áčďé');

      expect(result.unsupportedCharacters, isEmpty);
      expect(result.strokes, isNotEmpty);
    });

    test('ručné zalomenie riadkov sa prejaví v počte riadkov', () async {
      final oneLine = await _generate('AB');
      final twoLines = await _generate('A\nB');

      expect(oneLine.lines, hasLength(1));
      expect(twoLines.lines, hasLength(2));
    });

    test('text mimo papiera označí overflow', () async {
      final fits = await _generate('X');
      final tooBig = await _generate('WWW', fontSizeMm: 60);

      expect(fits.overflow, isFalse);
      expect(tooBig.overflow, isTrue);
    });
  });
}
