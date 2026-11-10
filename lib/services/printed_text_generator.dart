import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../models/outline_options.dart';
import '../models/paper_format.dart';
import '../models/plot_pattern.dart';
import '../models/stroke_point.dart';
import 'image_stroke_generator.dart';
import 'text_stroke_generator.dart';

/// Ako sa má tlačený (reálny) font na papieri vykresliť.
enum PrintedTextFill {
  /// Pero obíde hrany písmen – najvernejší tvar, ale obrys (nie výplň).
  outline('Outline'),

  /// Pero písmená vyplní vlnou riadkov – plná kresba, ale veľa bodov.
  solid('Solid');

  const PrintedTextFill(this.label);

  /// Krátky popis pre chip v UI.
  final String label;
}

/// Text vytlačený **reálnym fontom** (nie jednoťahovým `VectorFont`).
///
/// Postup je rovnaký ako pri obrázku: text sa vykreslí do bitmapy presne
/// veľkej ako tlačiteľná plocha papiera, bitmapa sa prevedie na odtiene šedej
/// a [ImageStrokeGenerator] z nej spraví ťahy – buď **obrys** písmen
/// ([PrintedTextFill.outline] = `PlotPattern.contour`), alebo **plnú výplň**
/// ([PrintedTextFill.solid] = `PlotPattern.zigzag`).
///
/// Prečo bitmapa a nie `ui.Path` z fontu? Flutter nevie spoľahlivo vrátiť
/// obrysy glyfov (fonty sú v engine), kým rasterizácia je jedno volanie
/// `TextPainter.paint` a výsledok je presne to, čo pero vie nakresliť.
///
/// Súradnice výsledku sú rovnaké ako pri [TextStrokeGenerator] – normalizované
/// 0..1, y rastie nadol, takže náhľad, zrkadlenie aj fronta fungujú bez zmeny.
class PrintedTextGenerator {
  PrintedTextGenerator._();

  /// Rozlíšenie rasterizácie v pixeloch na milimeter.
  ///
  /// 7 px/mm = čiara pera 0,2 mm je ~1,4 px široká – obrys sa ešte nerozpadá
  /// na schodíky a bitmapa A4 ostáva okolo 2,3 Mpx.
  static const double pxPerMm = 7.0;

  /// Strop rasterizácie; väčšie plátna sa zjemnia (A3 tak ostane ~4,8 px/mm).
  static const int maxBitmapPixels = 2500000;

  /// Pomer výšky veľkých písmen k veľkosti písma (Roboto: 1456/2048).
  ///
  /// Podľa neho sa „Letter height“ v režime *Printed* správa rovnako ako
  /// v jednoťahovom fonte – slider udáva výšku veľkých písmen v mm a veľkosť
  /// písma (`fontSize`) sa dopočíta.
  static const double capHeightRatio = 0.71;

  /// Predvolená hustota výplne (*Solid*) v mm.
  static const double defaultFillDensityMm = 0.6;

  /// Predvolená rodina písiem – Roboto je pribalené k Materialu, takže tvary
  /// písmen sú na každej platforme rovnaké.
  static const String defaultFontFamily = 'Roboto';

  /// Prázdny výsledok (prázdny text, samé biele znaky).
  static const TextPlotResult emptyResult = TextPlotResult(
    strokes: <List<StrokePoint>>[],
    lines: <String>[],
    pointCount: 0,
    unsupportedCharacters: <String>{},
    overflow: false,
    usedHeightMm: 0,
  );

  /// Preloží [text] na ťahy pomocou reálneho fontu.
  ///
  /// [fillDensityMm] – rozostup výplňových línií (*Solid*; menšie = tmavšie
  /// a pomalšie), [penWidthMm] – šírka stopy pera (premostenie medzier),
  /// [pointSpacingMm] – najmenšia vzdušná vzdialenosť dvoch bodov obrysu
  /// (nikdy pod `ImageStrokeGenerator.minSketchStepMm`),
  /// [maxPoints] – poistka proti státisícom bodov ([TextPlotResult.truncated]).
  static Future<TextPlotResult> generate({
    required String text,
    double fontSizeMm = 12.0,
    double lineSpacing = 1.6,
    TextAlignment alignment = TextAlignment.left,
    double marginMm = TextStrokeGenerator.defaultMarginMm,
    PaperFormat paper = kDefaultPaperFormat,
    PrintedTextFill fill = PrintedTextFill.outline,
    double fillDensityMm = defaultFillDensityMm,
    double penWidthMm = ImageStrokeGenerator.defaultPenWidthMm,
    double pointSpacingMm = 0.6,
    String? fontFamily = defaultFontFamily,
    FontWeight? fontWeight,
    int maxPoints = ImageStrokeGenerator.defaultMaxPoints,
  }) async {
    final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    if (normalized.trim().isEmpty) return emptyResult;

    // 1) Plátno = tlačiteľná plocha papiera (okraje ostávajú okrajmi).
    final availableWidthMm = math.max(1.0, paper.widthMm - 2 * marginMm);
    final availableHeightMm = math.max(1.0, paper.heightMm - 2 * marginMm);
    final scale = _scaleFor(availableWidthMm, availableHeightMm);
    final imgWidth = math.max(1, (availableWidthMm * scale).round());
    final imgHeight = math.max(1, (availableHeightMm * scale).round());

    // 2) Vysádzačka – `height` je násobok veľkosti písma, takže riadkovanie
    //    ostáva v rovnakých jednotkách ako pri jednoťahovom fonte (mm).
    final painter = TextPainter(
      text: TextSpan(
        text: normalized,
        style: TextStyle(
          color: const Color(0xFF000000),
          fontSize: fontSizeMm * scale / capHeightRatio,
          height: lineSpacing * capHeightRatio,
          fontFamily: fontFamily,
          fontWeight: fontWeight,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: switch (alignment) {
        TextAlignment.left => TextAlign.left,
        TextAlignment.center => TextAlign.center,
        TextAlignment.right => TextAlign.right,
      },
    )..layout(maxWidth: imgWidth.toDouble());

    // 3) Rasterizácia: biely papier + čierny text.
    final gray = await _rasterize(painter, imgWidth, imgHeight);

    // 4) Bitmapa je presne tlačiteľná plocha, takže sa mapuje 1:1 – písmo
    //    ostane také veľké, aké ho používateľ nastavil.
    final plotted = ImageStrokeGenerator.toStrokes(
      gray,
      pattern: fill == PrintedTextFill.outline
          ? PlotPattern.contour
          : PlotPattern.zigzag,
      lineSpacingMm: fillDensityMm,
      pointSpacingMm: pointSpacingMm,
      marginMm: marginMm,
      penWidthMm: penWidthMm,
      paper: paper,
      outline: OutlineOptions(
        // Obrys z pixelovej hrany by mal tisíce bodov tesne pri sebe; krok
        // nikdy nejde pod `minSketchStepMm`, takže controller prejde všetko.
        stepMm: math.max(ImageStrokeGenerator.minSketchStepMm, pointSpacingMm),
        smoothing: OutlineSmoothing.off,
        order: OutlineOrder.nearest,
        rotateStart: true,
      ),
      maxPoints: maxPoints,
    );

    final usedHeightMm = painter.height / scale;

    return TextPlotResult(
      strokes: plotted.strokes,
      lines: List<String>.filled(
        painter.computeLineMetrics().length,
        '',
        growable: false,
      ),
      pointCount: plotted.pointCount,
      // Reálny font pozná aj diakritiku – neznáme znaky rieši font fallback.
      unsupportedCharacters: const <String>{},
      overflow: painter.width > imgWidth + 0.5 ||
          painter.height > imgHeight + 0.5 ||
          usedHeightMm > paper.heightMm,
      usedHeightMm: usedHeightMm,
      truncated: plotted.truncated,
    );
  }

  /// px/mm pre danú tlačiteľnú plochu – detailnejšie, ale v rámci pamäte.
  static double _scaleFor(double widthMm, double heightMm) {
    final areaMm2 = math.max(1.0, widthMm * heightMm);
    final memoryCap = math.sqrt(maxBitmapPixels / areaMm2);
    return math.max(1.0, math.min(pxPerMm, memoryCap));
  }

  /// Vykreslí [painter] na biele plátno a vráti odtiene šedej.
  static Future<GrayImage> _rasterize(
    TextPainter painter,
    int width,
    int height,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ui.Paint()..color = const Color(0xFFFFFFFF),
    );
    painter.paint(canvas, ui.Offset.zero);

    final picture = recorder.endRecording();
    final ui.Image image;
    try {
      image = await picture.toImage(width, height);
    } finally {
      picture.dispose();
    }

    try {
      return await ImageStrokeGenerator.grayFromImage(image);
    } finally {
      image.dispose();
    }
  }
}
