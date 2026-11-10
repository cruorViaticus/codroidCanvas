import 'dart:math' as math;

import '../models/paper_format.dart';
import '../models/stroke_point.dart';
import 'vector_font.dart';

/// Zarovnanie riadkov textu.
enum TextAlignment { left, center, right }

/// Výsledok prekladu textu na ťahy.
class TextPlotResult {
  /// Ťahy v normalizovaných súradniciach papiera (0..1, y rastie nadol).
  final List<List<StrokePoint>> strokes;

  /// Riadky po zalomení.
  final List<String> lines;

  /// Počet bodov, ktoré sa pošlú robotovi.
  final int pointCount;

  /// Znaky, ktoré font nepozná (typicky emoji).
  final Set<String> unsupportedCharacters;

  /// `true`, ak text presiahol okraje papiera.
  final bool overflow;

  /// Výška použitého textu v mm.
  final double usedHeightMm;

  /// `true`, ak sa vyčerpal limit bodov (`maxPoints`).
  ///
  /// Týka sa len *Printed (real font)* režimu – jednoťahový font má bodov
  /// málo, kým plná výplň vytlačeného textu sa do limitu nemusí zmestiť.
  final bool truncated;

  const TextPlotResult({
    required this.strokes,
    required this.lines,
    required this.pointCount,
    required this.unsupportedCharacters,
    required this.overflow,
    required this.usedHeightMm,
    this.truncated = false,
  });

  bool get isEmpty => strokes.isEmpty;
}

/// Preloží text na zoznam ťahov pre [VectorFont] (jednoťahový font).
///
/// Postup: text sa rozdelí na riadky (rešpektuje `\n` aj automatické
/// zalomenie podľa šírky papiera), každý znak sa nahradí čiarami z fontu
/// a tie sa pretransformujú do normalizovaných súradníc papiera – presne
/// v rovnakom tvare, aký posiela voľná kresba z S Pen canvasu.
class TextStrokeGenerator {
  TextStrokeGenerator._();

  /// Predvolený okraj papiera v mm.
  static const double defaultMarginMm = 15.0;

  static TextPlotResult generate({
    required String text,
    double fontSizeMm = 12.0,
    double lineSpacing = 1.6,
    TextAlignment alignment = TextAlignment.left,
    double marginMm = defaultMarginMm,
    PaperFormat paper = kDefaultPaperFormat,
  }) {
    const empty = TextPlotResult(
      strokes: [],
      lines: [],
      pointCount: 0,
      unsupportedCharacters: <String>{},
      overflow: false,
      usedHeightMm: 0,
    );
    if (text.trim().isEmpty) return empty;

    final paperWidthMm = paper.widthMm;
    final paperHeightMm = paper.heightMm;
    final scale = fontSizeMm / VectorFont.capHeight;
    final letterSpacingMm = VectorFont.letterSpacing * scale;
    final spaceAdvanceMm = VectorFont.spaceAdvance * scale;
    final lineHeightMm = fontSizeMm * lineSpacing;
    final maxLineWidthMm = math.max(
      fontSizeMm,
      paperWidthMm - 2 * marginMm,
    );

    final lines = _wrap(
      text,
      maxLineWidthMm: maxLineWidthMm,
      scale: scale,
      letterSpacingMm: letterSpacingMm,
      spaceAdvanceMm: spaceAdvanceMm,
    );

    final strokes = <List<StrokePoint>>[];
    final unsupported = <String>{};
    var pointCount = 0;
    var minX = double.infinity, maxX = -double.infinity;
    var minY = double.infinity, maxY = -double.infinity;

    // Základná línia prvého riadku = horný okraj + výška veľkých písmen.
    var baselineMm = marginMm + fontSizeMm;

    for (final line in lines) {
      final lineWidthMm =
          _lineWidth(line, scale, letterSpacingMm, spaceAdvanceMm);
      var penXMm = switch (alignment) {
        TextAlignment.left => marginMm,
        TextAlignment.center => (paperWidthMm - lineWidthMm) / 2,
        TextAlignment.right => paperWidthMm - marginMm - lineWidthMm,
      };

      for (final rune in line.runes) {
        final char = String.fromCharCode(rune);
        if (char == ' ' || char == '\t') {
          penXMm += spaceAdvanceMm;
          continue;
        }

        final glyph = VectorFont.glyph(VectorFont.normalizeChar(char));
        if (glyph == null) {
          unsupported.add(char);
          penXMm += spaceAdvanceMm;
          continue;
        }

        for (final path in glyph.paths) {
          final points = <StrokePoint>[];
          for (var i = 0; i + 1 < path.length; i += 2) {
            final xMm = penXMm + path[i] * scale;
            final yMm = baselineMm - path[i + 1] * scale;
            minX = math.min(minX, xMm);
            maxX = math.max(maxX, xMm);
            minY = math.min(minY, yMm);
            maxY = math.max(maxY, yMm);
            points.add(StrokePoint(
              x: xMm / paperWidthMm,
              y: yMm / paperHeightMm,
              pressure: 1.0,
            ));
          }
          if (points.length >= 2) {
            strokes.add(points);
            pointCount += points.length;
          }
        }

        penXMm += glyph.width * scale + letterSpacingMm;
      }

      baselineMm += lineHeightMm;
    }

    final overflow = strokes.isNotEmpty &&
        (minX < 0 || minY < 0 || maxX > paperWidthMm || maxY > paperHeightMm);

    return TextPlotResult(
      strokes: strokes,
      lines: lines,
      pointCount: pointCount,
      unsupportedCharacters: unsupported,
      overflow: overflow,
      usedHeightMm: strokes.isEmpty ? 0 : maxY - minY,
    );
  }

  /// Rozdelí text na riadky tak, aby sa každý zmestil do [maxLineWidthMm].
  static List<String> _wrap(
    String text, {
    required double maxLineWidthMm,
    required double scale,
    required double letterSpacingMm,
    required double spaceAdvanceMm,
  }) {
    final lines = <String>[];

    for (final paragraph in text.replaceAll('\r\n', '\n').split('\n')) {
      final words = paragraph.split(RegExp(r'[ \t]+'));
      var current = '';
      var currentWidth = 0.0;

      for (final word in words) {
        if (word.isEmpty) continue;
        final wordWidth =
            _lineWidth(word, scale, letterSpacingMm, spaceAdvanceMm);

        if (current.isEmpty) {
          current = word;
          currentWidth = wordWidth;
          continue;
        }

        final needed = currentWidth + spaceAdvanceMm + wordWidth;
        if (needed <= maxLineWidthMm) {
          current = '$current $word';
          currentWidth = needed;
        } else {
          lines.add(current);
          current = word;
          currentWidth = wordWidth;
        }
      }

      lines.add(current);
    }

    return lines;
  }

  /// Šírka riadku v mm (medzera a neznámy znak = šírka medzery).
  static double _lineWidth(
    String line,
    double scale,
    double letterSpacingMm,
    double spaceAdvanceMm,
  ) {
    var width = 0.0;
    for (final rune in line.runes) {
      final char = String.fromCharCode(rune);
      if (char == ' ') {
        width += spaceAdvanceMm;
        continue;
      }
      final glyph = VectorFont.glyph(VectorFont.normalizeChar(char));
      width += glyph == null
          ? spaceAdvanceMm
          : glyph.width * scale + letterSpacingMm;
    }
    return width;
  }
}
