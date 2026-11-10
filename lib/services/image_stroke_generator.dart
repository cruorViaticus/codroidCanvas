import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../models/outline_options.dart';
import '../models/paper_format.dart';
import '../models/plot_pattern.dart';
import '../models/plot_start_side.dart';
import '../models/stroke_point.dart';

/// Odtiene šedej obrázka – 1 bajt na pixel (0 = čierna, 255 = biela).
class GrayImage {
  final int width;
  final int height;
  final Uint8List gray;

  const GrayImage({
    required this.width,
    required this.height,
    required this.gray,
  });

  /// Jas pixelu na súradniciach [x], [y] (0 = čierna, 255 = biela).
  int luminanceAt(int x, int y) => gray[y * width + x];
}

/// Výsledok prevodu obrázka na ťahy.
class ImagePlotResult {
  /// Ťahy v normalizovaných súradniciach papiera (0..1, y rastie nadol).
  final List<List<StrokePoint>> strokes;

  /// Počet bodov celkovo.
  final int pointCount;

  /// `true`, ak sa prekročil limit [ImageStrokeGenerator.defaultMaxPoints].
  final bool truncated;

  /// Rozmer výsledku na papieri v mm.
  final double drawWidthMm;
  final double drawHeightMm;

  /// Počet línií (riadkov / stĺpcov) zvoleného patternu.
  final int rowCount;

  /// Pattern, ktorým sa kresba naozaj vyplnila.
  ///
  /// Nikdy nie je [PlotPattern.auto] – pri `auto` je tu už konkrétny pattern,
  /// ktorý generátor pre tento obrázok vybral ako najlacnejší.
  final PlotPattern pattern;

  /// Odkiaľ pero kresbu začalo ([PlotStartSide.top] = zhora nadol).
  final PlotStartSide startSide;

  const ImagePlotResult({
    required this.strokes,
    required this.pointCount,
    required this.truncated,
    required this.drawWidthMm,
    required this.drawHeightMm,
    required this.rowCount,
    this.pattern = kDefaultPlotPattern,
    this.startSide = kDefaultPlotStartSide,
  });

  bool get isEmpty => strokes.isEmpty;
}

/// Prevod čierno-bieleho obrázka na ťahy pre pero.
///
/// Pero kreslí čiary, nie pixely, takže obrázok prechádzame po riadkoch
/// (ako stará ihličková tlačiareň): každý súvislý úsek tmavých pixelov
/// v riadku sa zmení na jeden vodorovný ťah. Čím menší `lineSpacingMm`,
/// tým hustejšia (a pomalšia) kresba. Striedavé riadky sa kreslia
/// obrátene (serpentína), aby pero prechádzalo menšie vzdialenosti.
class ImageStrokeGenerator {
  ImageStrokeGenerator._();

  /// Maximálny rozmer pri dekódovaní – väčšie obrázky sa zmenšia.
  static const int maxDecodeDimension = 900;

  /// Poistka, aby sa do fronty nedostali státisíce bodov.
  static const int defaultMaxPoints = 60000;

  /// Maximálna medzera (v pixeloch), ktorá sa ešte „premostí“ v rámci ťahu.
  ///
  /// Skutočná medzera sa počíta z [penWidthMm] (`joinGapMm`), aby pero
  /// nezdvíhalo pri medzerách, ktoré aj tak prekryje svojou šírkou. Táto
  /// hodnota je spodná hranica (dva pixely premostí vždy).
  static const int mergeGapPx = 2;

  /// Predvolená šírka stopy pera v mm (tenká linka 0,2 mm).
  ///
  /// Šírka pera určuje, aké jemné detaily má zmysel kresliť: dva ťahy bližšie
  /// ako šírka pera sa zlejú, preto generátor podľa nej nastaví minimálny
  /// rozostup línií a dĺžku premostenia medzier.
  static const double defaultPenWidthMm = 0.2;

  /// Najmenší krok dvoch bodov, ktorý robot ešte zvládne (mm).
  ///
  /// Dva body bližšie ako ~0,8 mm sú pre controller „stoj na mieste“: pohyb
  /// sa nestihne rozbehnúť, blending nemá čo vyhladiť a prechod na ďalší
  /// úsek sa často odmietne (*Cannot transition!*). Režim
  /// [PlotPattern.sketch] preto nikdy nevyskladá body bližšie – a detaily
  /// menšie ako tento krok rovno vyhodí.
  static const double minSketchStepMm = 0.8;

  /// Krok bodov v režime [PlotPattern.sketch] – ako blízko smú byť dva body.
  ///
  /// Rešpektuje zvolený rozostup bodov, ale nikdy nejde pod
  /// [minSketchStepMm] (ani pod štvornásobok šírky pera – body by zanikli
  /// v stope pera).
  static double sketchStepMmFor({
    required double pointSpacingMm,
    double penWidthMm = defaultPenWidthMm,
  }) {
    final pen = penWidthMm.clamp(0.05, 3.0).toDouble();
    final spacing = math.max(0.05, pointSpacingMm);
    return math.max(spacing, math.max(pen * 4, minSketchStepMm));
  }

  /// Dekóduje obrázok a vráti jeho odtiene šedej.
  ///
  /// Používa `dart:ui` (nie `package:image`), takže funguje rovnako na webe
  /// (CanvasKit) aj na mobile bez ďalších závislostí.
  static Future<GrayImage> decode(
    Uint8List bytes, {
    int maxDimension = maxDecodeDimension,
  }) async {
    // 1) Zisti rozmery (bez držania veľkého bufferu v pamäti).
    var width = 0;
    var height = 0;
    final probe = await ui.instantiateImageCodec(bytes);
    try {
      final frame = await probe.getNextFrame();
      width = frame.image.width;
      height = frame.image.height;
      frame.image.dispose();
    } finally {
      probe.dispose();
    }

    // 2) Dekóduj s rozumným rozlíšením.
    final longest = math.max(width, height);
    final ui.Codec codec;
    if (longest <= maxDimension) {
      codec = await ui.instantiateImageCodec(bytes);
    } else {
      final scale = maxDimension / longest;
      codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: math.max(1, (width * scale).round()),
        targetHeight: math.max(1, (height * scale).round()),
      );
    }

    final ui.Image image;
    try {
      image = (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }

    try {
      return await grayFromImage(image);
    } finally {
      image.dispose();
    }
  }

  /// Prevedie už vykreslený `ui.Image` na odtiene šedej.
  ///
  /// Hodí sa všade, kde obrázok nevzniká dekódovaním súboru – napr. text
  /// vytlačený reálnym fontom cez `TextPainter`: vykreslí sa do `ui.Picture`,
  /// z neho sa spraví `ui.Image` a ten sa pošle sem. Obrázok sa tu **neuvoľňuje**
  /// (patrí volajúcemu).
  static Future<GrayImage> grayFromImage(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) {
      throw StateError('Obrázok sa nepodarilo previesť na pixely.');
    }
    final rgba =
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    final gray = Uint8List(image.width * image.height);

    for (var i = 0; i < gray.length; i++) {
      final r = rgba[i * 4];
      final g = rgba[i * 4 + 1];
      final b = rgba[i * 4 + 2];
      final a = rgba[i * 4 + 3];
      final luminance = 0.299 * r + 0.587 * g + 0.114 * b;
      // Priehľadné pozadie berieme ako biely papier.
      final alpha = a / 255.0;
      gray[i] =
          (luminance * alpha + 255 * (1 - alpha)).round().clamp(0, 255).toInt();
    }

    return GrayImage(width: image.width, height: image.height, gray: gray);
  }

  /// Prevedie odtiene šedej na ťahy pre robota.
  ///
  /// [pattern] – akým smerom pero obrázok vyplní (viď [PlotPattern]);
  /// [PlotPattern.auto] nechá voľbu na generátore (vyberie najlacnejší).
  /// [threshold] – 0 = kreslí len úplne čierne pixely, 1 = kreslí všetko
  /// (polotóny sa tak menia na plnú kresbu).
  /// [invert] – kreslí svetlé časti namiesto tmavých (negatív).
  /// [penWidthMm] – šírka stopy pera; podľa nej sa premostia malé medzery
  /// (`joinGapMm`) a oreže sa zbytočne jemné rozlíšenie.
  /// [startSide] – odkiaľ pero kresbu začne (`top` = horná línia, `bottom` =
  /// dolná); mení len poradie ťahov, nie výsledný obrázok.
  /// [outline] – nastavenia obrysov (`contour` / `sketch`): poradie ťahov,
  /// vyhladenie, krok bodov a najmenší kreslený detail.
  static ImagePlotResult toStrokes(
    GrayImage image, {
    PlotPattern pattern = kDefaultPlotPattern,
    double lineSpacingMm = 1.2,
    double pointSpacingMm = 0.6,
    double threshold = 0.5,
    bool invert = false,
    double marginMm = 10.0,
    double penWidthMm = defaultPenWidthMm,
    PaperFormat paper = kDefaultPaperFormat,
    PlotStartSide startSide = kDefaultPlotStartSide,
    OutlineOptions outline = const OutlineOptions(),
    int maxPoints = defaultMaxPoints,
  }) {
    final paperWidthMm = paper.widthMm;
    final paperHeightMm = paper.heightMm;
    final availableWidthMm = math.max(1.0, paperWidthMm - 2 * marginMm);
    final availableHeightMm = math.max(1.0, paperHeightMm - 2 * marginMm);
    final mmPerPixel = math.min(
      availableWidthMm / image.width,
      availableHeightMm / image.height,
    );

    final drawWidthMm = image.width * mmPerPixel;
    final drawHeightMm = image.height * mmPerPixel;

    // Pero užšie ako 0,05 mm sa nedá nakresliť; hrubšie ako 3 mm je fixka.
    final pen = penWidthMm.clamp(0.05, 3.0).toDouble();

    final geometry = _PlotGeometry(
      image: image,
      paperWidthMm: paperWidthMm,
      paperHeightMm: paperHeightMm,
      mmPerPixel: mmPerPixel,
      leftMm: marginMm + (availableWidthMm - drawWidthMm) / 2,
      topMm: marginMm + (availableHeightMm - drawHeightMm) / 2,
      drawWidthMm: drawWidthMm,
      drawHeightMm: drawHeightMm,
      // Dva ťahy bližšie ako šírka pera sa zlejú – lineSpacingMm je zároveň
      // minimálny rozostup, ktorý pero ešte rozlíši.
      lineSpacingMm: math.max(pen, lineSpacingMm),
      pointSpacingMm: math.max(0.05, pointSpacingMm),
      penWidthMm: pen,
      thresholdByte: (threshold.clamp(0.0, 1.0) * 255).round(),
      invert: invert,
      outline: outline,
      maxPoints: maxPoints,
    );

    // `auto` = generátor najprv ohodnotí všetkých kandidátov a vyberie
    // najlacnejšieho (najkratšia dráha + najmenší počet zdvihov pera).
    final resolved = pattern.isAutomatic ? geometry.optimalPattern() : pattern;
    final fill = geometry.fill(resolved);

    // „Začať odspodu“ = rovnaká kresba, ale pero prejde ťahy v opačnom
    // poradí. Otáča sa aj poradie bodov v každom ťahu, takže nadväznosť
    // koniec → začiatok (serpentína) ostáva zachovaná a pero nezdvíha viac.
    final strokes =
        startSide.isBottom ? _reverseStrokes(fill.strokes) : fill.strokes;

    return ImagePlotResult(
      strokes: strokes,
      pointCount: fill.pointCount,
      truncated: fill.truncated,
      drawWidthMm: drawWidthMm,
      drawHeightMm: drawHeightMm,
      rowCount: fill.lineCount,
      pattern: resolved,
      startSide: startSide,
    );
  }

  /// Otočí poradie ťahov aj bodov v nich (kresba „odspodu“).
  static List<List<StrokePoint>> _reverseStrokes(
          List<List<StrokePoint>> strokes) =>
      [
        for (final stroke in strokes.reversed)
          if (stroke.length < 2)
            stroke
          else
            stroke.reversed.toList(growable: false),
      ];

  /// `true`, ak pixel [x], [y] patrí atramentu (podľa prahu a invertu).
  static bool _isInkAt(
      GrayImage image, int x, int y, int thresholdByte, bool invert) {
    if (x < 0 || y < 0 || x >= image.width || y >= image.height) return false;
    return _isInk(image.luminanceAt(x, y), thresholdByte, invert);
  }

  static bool _isInk(int luminance, int thresholdByte, bool invert) =>
      invert ? luminance > 255 - thresholdByte : luminance < thresholdByte;
}

/// Výsledok jedného priechodu patternom.
class _Fill {
  /// Ťahy v normalizovaných súradniciach papiera (0..1, y rastie nadol).
  final List<List<StrokePoint>> strokes;

  /// Počet bodov vo všetkých ťahoch.
  final int pointCount;

  /// `true`, ak sa prekročil bodový limit.
  final bool truncated;

  /// Počet línií (riadkov / stĺpcov), ktoré pattern prešiel.
  final int lineCount;

  const _Fill({
    required this.strokes,
    required this.pointCount,
    required this.truncated,
    required this.lineCount,
  });
}

/// Geometria kresby na papieri + prevod pixelov na milimetre.
///
/// Jeden raster sa dá prejsť rôznymi smermi, preto tu nie je „vodorovný
/// scanline“, ale smer ťahu `d = (dirX, dirY)` a naň kolmá os `n`. Línie
/// patternu sú priamky `v = konšt.` a pero po nich ide v smere `d`
/// (striedavo tam a späť = serpentína).
class _PlotGeometry {
  _PlotGeometry({
    required this.image,
    required this.paperWidthMm,
    required this.paperHeightMm,
    required this.mmPerPixel,
    required this.leftMm,
    required this.topMm,
    required this.drawWidthMm,
    required this.drawHeightMm,
    required this.lineSpacingMm,
    required this.pointSpacingMm,
    required this.penWidthMm,
    required this.thresholdByte,
    required this.invert,
    required this.outline,
    required this.maxPoints,
  });

  final GrayImage image;
  final double paperWidthMm;
  final double paperHeightMm;

  /// Koľko milimetrov papiera pripadá na jeden pixel obrázka.
  final double mmPerPixel;

  /// Ľavý horný roh kresby v mm papiera.
  final double leftMm;
  final double topMm;

  /// Rozmer kresby na papieri v mm.
  final double drawWidthMm;
  final double drawHeightMm;

  final double lineSpacingMm;
  final double pointSpacingMm;

  /// Šírka stopy pera v mm (0,2 mm = tenká linka).
  final double penWidthMm;

  final int thresholdByte;
  final bool invert;

  /// Nastavenia obrysov (`contour` / `sketch`) z `toStrokes`.
  final OutlineOptions outline;

  final int maxPoints;

  /// Medzera v mm, ktorú pero prejde po papieri bez zdvihnutia („premostenie“).
  ///
  /// Štyri šírky pera: takú medzeru pero aj tak takmer prekryje, takže nemá
  /// zmysel zdvíhať pero, čakať na zdvih a znovu klesať. Zároveň to zaručí,
  /// že prejazd nie je kratší ako šírka pera (controller takéto „spiatočné“
  /// prejazdy odmieta – *Cannot transition!*).
  ///
  /// Nikdy to nie je viac ako polovica rozostupu línií – inak by pero
  /// vyplnilo aj prázdne miesto medzi dvoma líniami patternu.
  double get joinGapMm =>
      math.min(lineSpacingMm * 0.5, math.max(penWidthMm * 4, 0.5));

  /// [joinGapMm] prepočítané na vzorky (pixely) – aspoň
  /// [ImageStrokeGenerator.mergeGapPx], aby sa premostila aj 1 px diera.
  int get gapSamples => math.max(
      ImageStrokeGenerator.mergeGapPx, (joinGapMm / mmPerPixel).round());

  /// Krok bodov v režime [PlotPattern.sketch] (mm) – dva body nikdy bližšie.
  double get sketchStepMm => ImageStrokeGenerator.sketchStepMmFor(
        pointSpacingMm: pointSpacingMm,
        penWidthMm: penWidthMm,
      );

  /// Tolerance zjednodušenia čiary v režime [PlotPattern.sketch] (mm).
  ///
  /// Musí byť väčšia ako odchýlka pixelových schodíkov (asi polovica až
  /// jeden pixel), aby sa obrys vyhladil, ale menšia ako krok bodov – inak
  /// by zjednodušenie „prehltlo“ celý tvar.
  double get sketchToleranceMm =>
      math.min(sketchStepMm * 0.5, math.max(penWidthMm, mmPerPixel));

  /// Smernica 45° (`1 / √2`) – jednotkový vektor diagonálnych patternov.
  static const double _diagonal = math.sqrt1_2;

  /// Cena jedného zdvihu pera v mm ekvivalentu kreslenia.
  ///
  /// Používa ju len [optimalPattern]: zdvih + prejazd na ďalší ťah stojí
  /// približne toľko času ako 20 mm kreslenia.
  static const double penLiftPenaltyMm = 20.0;

  /// Vykreslí obrázok zvoleným patternom.
  _Fill fill(PlotPattern pattern) {
    switch (pattern) {
      case PlotPattern.auto:
      case PlotPattern.horizontal:
        return fillLines(1, 0);
      case PlotPattern.vertical:
        return fillLines(0, 1);
      case PlotPattern.diagonal:
        return fillLines(_diagonal, _diagonal);
      case PlotPattern.antiDiagonal:
        return fillLines(_diagonal, -_diagonal);
      case PlotPattern.crossHatch:
        // Dva priechody – každý dostane polovicu bodového rozpočtu.
        final budget = math.max(2, maxPoints ~/ 2);
        return _merge([
          fillLines(_diagonal, _diagonal, pointBudget: budget),
          fillLines(_diagonal, -_diagonal, pointBudget: budget),
        ]);
      case PlotPattern.tripleHatch:
        // Tri priechody (vodorovne, +45°, −45°) – tretina rozpočtu na každý.
        final budget = math.max(3, maxPoints ~/ 3);
        return _merge([
          fillLines(1, 0, pointBudget: budget),
          fillLines(_diagonal, _diagonal, pointBudget: budget),
          fillLines(_diagonal, -_diagonal, pointBudget: budget),
        ]);
      case PlotPattern.dots:
        return fillDots();
      case PlotPattern.zigzag:
        return fillZigzag();
      case PlotPattern.spiral:
        return fillSpiral();
      case PlotPattern.rings:
        return fillRings();
      case PlotPattern.contour:
        return fillContour();
      case PlotPattern.sketch:
        return fillSketch();
    }
  }

  /// Súvislé čiary v smere `d = (dirX, dirY)` – jadro všetkých patternov.
  ///
  /// Každá línia sa prejde po vzorkách veľkých jeden pixel; súvislý úsek
  /// atramentu sa zmení na jeden ťah (medzery do
  /// [ImageStrokeGenerator.mergeGapPx] pixelov sa premostia, aby pero
  /// zbytočne nezdvíhalo).
  _Fill fillLines(double dirX, double dirY, {int? pointBudget}) {
    final budget = pointBudget ?? maxPoints;
    final span = _span(dirX, dirY);
    final normalX = -dirY;
    final normalY = dirX;

    final lines =
        math.max(1, ((span.vMax - span.vMin) / lineSpacingMm).floor());
    final lineStepMm = (span.vMax - span.vMin) / lines;
    final samples = math.max(1, ((span.uMax - span.uMin) / mmPerPixel).floor());

    final strokes = <List<StrokePoint>>[];
    var pointCount = 0;
    var truncated = false;

    for (var line = 0; line < lines && !truncated; line++) {
      final v = span.vMin + lineStepMm * (line + 0.5);
      final reverse = line.isOdd;
      var runStart = -1;

      for (var k = 0; k <= samples; k++) {
        final u = span.uMin + k * mmPerPixel;
        final ink = _inkAt(u, v, dirX, dirY, normalX, normalY);

        if (ink && runStart < 0) {
          runStart = k;
          continue;
        }
        if (ink || runStart < 0) continue;

        // Medzera kratšia ako [gapSamples]: ak za ňou ešte atrament je,
        // pokračujeme – pero nezdvíha (dlhšie línie).
        if (k + gapSamples < samples &&
            _hasInkAhead(k, gapSamples, samples, v, span.uMin, dirX, dirY,
                normalX, normalY)) {
          continue;
        }

        final start = _mmPoint(
            span.uMin + runStart * mmPerPixel, v, dirX, dirY, normalX, normalY);
        final end = _mmPoint(u, v, dirX, dirY, normalX, normalY);
        runStart = -1;

        final lengthMm = (end - start).distance;
        final segments = math.max(1, (lengthMm / pointSpacingMm).ceil());
        if (pointCount + segments + 1 > budget) {
          truncated = true;
          break;
        }

        final points = <StrokePoint>[];
        for (var i = 0; i <= segments; i++) {
          final t = i / segments;
          points.add(_strokePoint(
            start.dx + (end.dx - start.dx) * t,
            start.dy + (end.dy - start.dy) * t,
          ));
        }
        if (reverse) {
          strokes.add(points.reversed.toList(growable: false));
        } else {
          strokes.add(points);
        }
        pointCount += points.length;
      }
    }

    return _Fill(
      strokes: strokes,
      pointCount: pointCount,
      truncated: truncated,
      lineCount: lines,
    );
  }

  /// Bodková matica – v každom atramentovom bode krátky ťah („bodka“).
  ///
  /// Pero pri každej bodke klesne a hneď sa zdvihne, preto sa tu hodí nastaviť
  /// vlastnú výšku zdvihu (`penLiftMm` v `QueuedStroke`) – pri bodkách je
  /// zdvih najčastejší pohyb celej kresby.
  _Fill fillDots() {
    final rows = math.max(1, (drawHeightMm / lineSpacingMm).floor());
    final rowStepMm = drawHeightMm / rows;
    final columns = math.max(1, (drawWidthMm / lineSpacingMm).floor());
    final columnStepMm = drawWidthMm / columns;
    final tickMm = _dotLengthMm(columnStepMm);

    final strokes = <List<StrokePoint>>[];
    var pointCount = 0;
    var truncated = false;

    for (var row = 0; row < rows && !truncated; row++) {
      final yMm = topMm + rowStepMm * (row + 0.5);
      final reverse = row.isOdd;
      for (var column = 0; column < columns; column++) {
        final xMm = leftMm + columnStepMm * (column + 0.5);
        if (!_isInkAtPixel(xMm, yMm)) continue;
        if (pointCount + 2 > maxPoints) {
          truncated = true;
          break;
        }
        final points = [
          _strokePoint(xMm - tickMm / 2, yMm),
          _strokePoint(xMm + tickMm / 2, yMm),
        ];
        strokes.add(reverse ? points.reversed.toList(growable: false) : points);
        pointCount += 2;
      }
    }

    return _Fill(
      strokes: strokes,
      pointCount: pointCount,
      truncated: truncated,
      lineCount: rows,
    );
  }

  /// Dĺžka jednej bodky v mm – kratšia ako rozostup bodov, aby sa bodky
  /// nezlievali do čiary (a aby controller krátky pohyb vôbec prijal).
  ///
  /// Nikdy nie je kratšia ako dvojnásobok šírky pera – tenšia bodka by sa
  /// vôbec neprejavila.
  double _dotLengthMm(double columnStepMm) => math.max(
        penWidthMm * 2,
        math.min(0.8, math.min(lineSpacingMm * 0.6, columnStepMm * 0.8)),
      );

  /// Vlna – riadky pospájané do jedného dlhého ťahu.
  ///
  /// Rovnaké riadky ako [fillLines], ale pero medzi nimi nezdvíha: koniec
  /// jedného riadku plynule prejde na začiatok druhého (serpentína). Pre
  /// súvislú kresbu tak vznikne **jeden** ťah cez celý obrázok – najdlhšie
  /// línie a najmenej zdvihov pera, aké sa dajú dosiahnuť.
  _Fill fillZigzag() {
    final span = _span(1, 0);
    final lines =
        math.max(1, ((span.vMax - span.vMin) / lineSpacingMm).floor());
    final lineStepMm = (span.vMax - span.vMin) / lines;
    final samples = math.max(1, ((span.uMax - span.uMin) / mmPerPixel).floor());

    // Ako ďaleko smie pero prejsť po papieri bez zdvihnutia (spojenie riadkov
    // je najviac dva rozostupy).
    final linkMm = math.max(joinGapMm, lineSpacingMm * 2);

    final strokes = <List<StrokePoint>>[];
    var current = <StrokePoint>[];
    var pointCount = 0;
    var truncated = false;
    double? lastX;
    double? lastY;

    void flush() {
      if (current.length >= 2) {
        strokes.add(current);
        pointCount += current.length;
      }
      current = <StrokePoint>[];
      lastX = null;
      lastY = null;
    }

    /// Prejde pero na `(x2, y2)` a pridá body do rozbehnutého ťahu.
    bool drawTo(double x2, double y2) {
      final x1 = lastX;
      final y1 = lastY;
      if (x1 == null || y1 == null) {
        if (pointCount >= maxPoints) {
          truncated = true;
          return false;
        }
        current.add(_strokePoint(x2, y2));
        lastX = x2;
        lastY = y2;
        return true;
      }

      final lengthMm = math.sqrt((x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1));
      final steps = math.max(1, (lengthMm / pointSpacingMm).ceil());
      if (pointCount + current.length + steps > maxPoints) {
        truncated = true;
        return false;
      }
      for (var i = 1; i <= steps; i++) {
        final t = i / steps;
        current.add(_strokePoint(x1 + (x2 - x1) * t, y1 + (y2 - y1) * t));
      }
      lastX = x2;
      lastY = y2;
      return true;
    }

    double gapTo(double x, double y) {
      final x1 = lastX;
      final y1 = lastY;
      if (x1 == null || y1 == null) return 0.0;
      return math.sqrt((x - x1) * (x - x1) + (y - y1) * (y - y1));
    }

    for (var line = 0; line < lines && !truncated; line++) {
      final y = span.vMin + lineStepMm * (line + 0.5);
      final runs = _inkRuns(y, span.uMin, samples);
      final ordered = line.isOdd ? runs.reversed.toList() : runs;

      for (final run in ordered) {
        final from = line.isOdd ? run.end : run.start;
        final to = line.isOdd ? run.start : run.end;
        // Príliš vzdialený začiatok = nový ťah (pero musí zdvihnúť).
        if (gapTo(from, y) > linkMm) flush();
        if (!drawTo(from, y)) break;
        if (!drawTo(to, y)) break;
      }
    }
    flush();

    return _Fill(
      strokes: strokes,
      pointCount: pointCount,
      truncated: truncated,
      lineCount: lines,
    );
  }

  /// Špirála – jedna čiara sa točí od okraja kresby do stredu.
  ///
  /// Pero ide po obvode zmenšujúceho sa obdĺžnika (krok = hustota riadkov) a
  /// kreslí len tam, kde je atrament. Vznikne „kotúč“ s minimom zdvihov –
  /// veľké prázdne plochy pero prejde bez kreslenia.
  _Fill fillSpiral() {
    final step = lineSpacingMm;
    var l = leftMm;
    var t = topMm;
    var r = leftMm + drawWidthMm;
    var b = topMm + drawHeightMm;

    // Obvod špirály ako polyline v mm papiera.
    final path = <ui.Offset>[];
    while (r - l > step && b - t > step) {
      path
        ..add(ui.Offset(l, t))
        ..add(ui.Offset(r, t))
        ..add(ui.Offset(r, b))
        ..add(ui.Offset(l + step, b))
        ..add(ui.Offset(l + step, t + step));
      l += step;
      t += step;
      r -= step;
      b -= step;
    }

    final strokes = <List<StrokePoint>>[];
    var current = <StrokePoint>[];
    var pointCount = 0;
    var truncated = false;
    var blank = 0;

    void flush() {
      if (current.length >= 2) {
        strokes.add(current);
        pointCount += current.length;
      }
      current = <StrokePoint>[];
      blank = 0;
    }

    final sampleStep = math.max(penWidthMm, math.min(pointSpacingMm, 0.5));
    for (var i = 0; i < path.length - 1 && !truncated; i++) {
      final a = path[i];
      final next = path[i + 1];
      final lengthMm = (next - a).distance;
      final steps = math.max(1, (lengthMm / sampleStep).ceil());

      for (var s = 0; s < steps && !truncated; s++) {
        final ratio = s / steps;
        final x = a.dx + (next.dx - a.dx) * ratio;
        final y = a.dy + (next.dy - a.dy) * ratio;

        if (!_isInkAtPixel(x, y)) {
          // Krátku dieru v atramenti pero prejde bez zdvihnutia.
          if (++blank > gapSamples) flush();
          continue;
        }
        blank = 0;

        if (pointCount + current.length >= maxPoints) {
          truncated = true;
          break;
        }
        current.add(_strokePoint(x, y));
      }
    }
    flush();

    return _Fill(
      strokes: strokes,
      pointCount: pointCount,
      truncated: truncated,
      lineCount: math.max(1, (drawHeightMm / lineSpacingMm).floor()),
    );
  }

  /// Sústredné kružnice – pero krúži od stredu kresby k okraju.
  ///
  /// Každý kruh je uzavretá čiara vo vzdialenosti [lineSpacingMm] od
  /// predchádzajúceho, takže výplň je rovnako hustá ako pri riadkoch. Pero
  /// kreslí len tam, kde je atrament – prázdne miesta len prejde (kruh sa
  /// tým nerozdelí, ak je diera kratšia ako [gapSamples]). Kruhy na seba
  /// nenadväzujú, preto medzi nimi pero zdvihne.
  _Fill fillRings() {
    final centreX = leftMm + drawWidthMm / 2;
    final centreY = topMm + drawHeightMm / 2;

    // Krok kruhov = hustota riadkov (aspoň dva priemery pera, aby boli
    // susedné kruhy rozlíšiteľné).
    final step = math.max(lineSpacingMm, penWidthMm * 2);
    // Najväčší kruh musí dosiahnuť aj rohy kresby (polovica uhlopriečky).
    final maxRadius =
        math.sqrt(drawWidthMm * drawWidthMm + drawHeightMm * drawHeightMm) / 2;
    final rings = math.max(1, (maxRadius / step).ceil());

    final sampleStep = math.max(penWidthMm, math.min(pointSpacingMm, 0.5));

    final strokes = <List<StrokePoint>>[];
    var current = <StrokePoint>[];
    var pointCount = 0;
    var truncated = false;
    var blank = 0;

    void flush() {
      if (current.length >= 2) {
        strokes.add(current);
        pointCount += current.length;
      }
      current = <StrokePoint>[];
      blank = 0;
    }

    for (var ring = 1; ring <= rings && !truncated; ring++) {
      final radius = step * ring;
      final steps = math.max(8, (2 * math.pi * radius / sampleStep).ceil());

      for (var s = 0; s <= steps && !truncated; s++) {
        final angle = 2 * math.pi * s / steps;
        final x = centreX + radius * math.cos(angle);
        final y = centreY + radius * math.sin(angle);

        if (!_isInkAtPixel(x, y)) {
          // Krátku dieru v atramenti pero prejde bez zdvihnutia.
          if (++blank > gapSamples) flush();
          continue;
        }
        blank = 0;

        if (pointCount + current.length >= maxPoints) {
          truncated = true;
          break;
        }
        current.add(_strokePoint(x, y));
      }
      // Kruhy sú samostatné ťahy – pero medzi nimi zdvihne.
      flush();
    }
    flush();

    return _Fill(
      strokes: strokes,
      pointCount: pointCount,
      truncated: truncated,
      lineCount: rings,
    );
  }

  /// Obrys – pero obíde hrany tvarov, takže obrázok naozaj „nakreslí“.
  ///
  /// Hrany sa hľadajú na úrovni pixelov (zmena atramentu medzi susednými
  /// stĺpcami = zvislá hrana, medzi riadkami = vodorovná). Nadväzujúce hrany
  /// sa zreťazia do jednej čiary, takže pero kreslí dlhé línie po obvode –
  /// presne to, čo robí kresliaci robot (skica namiesto výplne).
  ///
  /// Správanie sa dá doladiť cez [OutlineOptions] (poradie ťahov, vyhladenie,
  /// krok bodov, najmenší detail) – viď [_fillOutlines].
  _Fill fillContour() => _fillOutlines(sketch: false);

  /// Skica pre drobné detaily – obrys, ktorý robot naozaj zvládne prejsť.
  ///
  /// Rovnaké hrany ako [fillContour], ale oveľa „robotickejšie“:
  /// * čiara sa najprv zjednoduší ([_simplifyPolyline]), takže zmiznú
  ///   pixelové schodíky a s nimi aj stovky odbočení o 90°,
  /// * body sa ukladajú tak, že **vzdušná** vzdialenosť dvoch susedných bodov
  ///   je vždy aspoň [sketchStepMm] ([_resamplePolyline]) – controller
  ///   nevie plynulo prejsť kratší úsek a prechod na ďalší často odmietne,
  /// * útvary kratšie ako jeden krok sa vyhodia – z bodky pod rozlíšením
  ///   pera by vznikol len „štuch“ do papiera.
  ///
  /// Hodí sa na obrázky s textom a jemnými líniami, kde `Outline` vyrobí
  /// tisíce bodov tesne pri sebe.
  _Fill fillSketch() => _fillOutlines(sketch: true);

  /// Spoločná cesta pre `contour` aj `sketch`.
  ///
  /// Rozdiel medzi patternmi je len v predvolených hodnotách – *Sketch* je
  /// „robot-safe“ (tetiva aspoň [sketchStepMm], vyhladenie, žiadne detaily pod
  /// jeden krok), *Outline* ide presne po pixelových hranách. Čo z toho platí,
  /// prepisuje [OutlineOptions]:
  ///
  /// * [OutlineOptions.order] a [OutlineOptions.rotateStart] – poradie ťahov
  ///   a začiatok uzavretého obrysu (najkratšie prejazdy, žiadne „tam a hneď
  ///   späť“, ktoré controller odmieta),
  /// * [OutlineOptions.smoothing] – Douglas–Peucker pred bodovaním,
  /// * [OutlineOptions.stepMm] – vlastný krok; prepne aj *Outline* na
  ///   robot-safe bodovanie po tetivách,
  /// * [OutlineOptions.minDetailMm] – najmenší detail, ktorý sa ešte kreslí.
  _Fill _fillOutlines({required bool sketch}) {
    final options = outline;

    // Krok bodov: vlastný (nikdy pod robot-safe minimum), inak podľa patternu.
    final stepMm = options.hasCustomStep
        ? math.max(
            options.stepMm,
            sketch ? ImageStrokeGenerator.minSketchStepMm : 0.05,
          )
        : (sketch ? sketchStepMm : pointSpacingMm);

    // Sketch boduje po tetivách; vlastný krok prepne na tetivy aj Outline.
    final chordStepping = sketch || options.hasCustomStep;
    final toleranceMm = _smoothingToleranceMm(sketch: sketch);

    // Detail menší ako stopa pera (alebo vlastný limit) sa nekreslí vôbec.
    final minDetailMm = math.max(options.minDetailMm, sketch ? stepMm : 0.0);

    final polylines = _orderOutlines([
      for (final line in _chainEdges(_edgeSegments()))
        if (_polylineLengthMm(line) >= minDetailMm) line,
    ]);

    final strokes = <List<StrokePoint>>[];
    var pointCount = 0;
    var truncated = false;

    for (final line in polylines) {
      final simplified =
          toleranceMm > 0 ? _simplifyPolyline(line, toleranceMm) : line;
      final points = chordStepping
          ? _resamplePolyline(simplified, stepMm)
          : _subdividePolyline(simplified, pointSpacingMm);
      // Kratšie ako jeden krok = detail, ktorý pero (ani robot) nezachytí.
      if (points.length < 2) continue;
      if (pointCount + points.length > maxPoints) {
        truncated = true;
        break;
      }
      pointCount += points.length;
      strokes.add(points);
    }

    return _Fill(
      strokes: strokes,
      pointCount: pointCount,
      truncated: truncated,
      lineCount: strokes.length,
    );
  }

  /// Tolerancia vyhladenia obrysu v mm podľa [OutlineOptions.smoothing].
  ///
  /// `auto` necháva rozhodnutie na patterne: *Sketch* vyhladzuje
  /// ([sketchToleranceMm]), *Outline* ostáva verný pixelom.
  double _smoothingToleranceMm({required bool sketch}) {
    switch (outline.smoothing) {
      case OutlineSmoothing.off:
        return 0;
      case OutlineSmoothing.auto:
        return sketch ? sketchToleranceMm : 0;
      case OutlineSmoothing.strong:
        return math.max(penWidthMm, mmPerPixel * 2);
    }
  }

  /// Orientované hrany tvarov v mm papiera (atrament po ľavej ruke).
  ///
  /// Zmena atramentu medzi susednými riadkami = vodorovná hrana, medzi
  /// stĺpcami = zvislá. Hrany sú orientované tak, že nadväzujúce úseky
  /// obrysu na seba presne sedia, takže sa dajú zreťaziť do dlhých čiar
  /// ([_chainEdges]).
  List<({ui.Offset a, ui.Offset b})> _edgeSegments() {
    final width = image.width;
    final height = image.height;

    bool ink(int x, int y) =>
        x >= 0 &&
        y >= 0 &&
        x < width &&
        y < height &&
        ImageStrokeGenerator._isInk(
            image.luminanceAt(x, y), thresholdByte, invert);

    double xMm(int column) => leftMm + column * mmPerPixel;
    double yMm(int row) => topMm + row * mmPerPixel;

    final segments = <({ui.Offset a, ui.Offset b})>[];

    // Vodorovné hrany: riadok [row] oddeľuje atrament zhora a zdola.
    //
    // Hrany sa ukladajú **orientované** (atrament po ľavej ruke), takže
    // nadväzujúce úseky obrysu na seba presne nadväzujú a dajú sa zreťaziť.
    for (var row = 0; row <= height; row++) {
      var runStart = -1;
      var runSign = 0;
      for (var column = 0; column <= width; column++) {
        final below = column < width && ink(column, row);
        final above = column < width && ink(column, row - 1);
        final sign = below == above ? 0 : (below ? 1 : -1);

        if (sign != runSign) {
          if (runSign != 0 && runStart >= 0 && column > runStart) {
            // Atrament dole (sign +1) = horná hrana, ide zľava doprava.
            // Atrament hore (sign −1) = dolná hrana, ide sprava doľava.
            final from = runSign > 0 ? runStart : column;
            final to = runSign > 0 ? column : runStart;
            segments.add((
              a: ui.Offset(xMm(from), yMm(row)),
              b: ui.Offset(xMm(to), yMm(row)),
            ));
          }
          runSign = sign;
          runStart = column;
        }
      }
    }

    // Zvislé hrany: stĺpec [column] oddeľuje atrament zľava a sprava.
    for (var column = 0; column <= width; column++) {
      var runStart = -1;
      var runSign = 0;
      for (var row = 0; row <= height; row++) {
        final right = row < height && ink(column, row);
        final left = row < height && ink(column - 1, row);
        final sign = right == left ? 0 : (right ? 1 : -1);

        if (sign != runSign) {
          if (runSign != 0 && runStart >= 0 && row > runStart) {
            // Atrament vpravo (sign +1) = ľavá hrana, ide zdola nahor.
            // Atrament vľavo (sign −1) = pravá hrana, ide zhora nadol.
            final from = runSign > 0 ? row : runStart;
            final to = runSign > 0 ? runStart : row;
            segments.add((
              a: ui.Offset(xMm(column), yMm(from)),
              b: ui.Offset(xMm(column), yMm(to)),
            ));
          }
          runSign = sign;
          runStart = row;
        }
      }
    }

    return segments;
  }

  /// Zreťazí nadväzujúce hrany (schodíky obrysu) do dlhých polyliniek.
  ///
  /// Hrany na seba nadväzujú koncom a začiatkom, preto sa z nich dá poskladať
  /// celý obvod tvaru jednou čiarou (menej zdvihov pera).
  List<List<ui.Offset>> _chainEdges(
      List<({ui.Offset a, ui.Offset b})> segments) {
    String key(ui.Offset point) =>
        '${(point.dx * 100).round()}:${(point.dy * 100).round()}';
    final byStart = <String, List<int>>{};
    for (var i = 0; i < segments.length; i++) {
      byStart.putIfAbsent(key(segments[i].a), () => <int>[]).add(i);
    }

    final used = List<bool>.filled(segments.length, false);
    final polylines = <List<ui.Offset>>[];

    for (var i = 0; i < segments.length; i++) {
      if (used[i]) continue;
      used[i] = true;
      final polyline = <ui.Offset>[segments[i].a, segments[i].b];

      while (true) {
        final candidates = byStart[key(polyline.last)];
        if (candidates == null) break;
        int? next;
        for (final index in candidates) {
          if (!used[index]) {
            next = index;
            break;
          }
        }
        if (next == null) break;
        used[next] = true;
        polyline.add(segments[next].b);
      }

      polylines.add(polyline);
    }
    return polylines;
  }

  /// Veľkosť bunky mriežky (mm), v ktorej sa hľadá najbližší obrys.
  ///
  /// Malá bunka = viac buniek a pomalšie hľadanie, veľká = viac kandidátov
  /// v jednej bunke. 20 mm je pri obrázkoch s textom dobrý kompromis.
  static const double _outlineCellMm = 20.0;

  /// Zoradí obrysy tak, aby prejazdy medzi nimi boli čo najkratšie.
  ///
  /// Pero kreslí obrysy v poradí, v akom sú v zozname – po každom obryse sa
  /// zdvihne a prejde na začiatok ďalšieho. Poradie „zhora dole“ tak pri
  /// obrázkoch s textom znamená dlhé prejazdy cez celú kresbu a často presne
  /// **späť po čiare, ktorú pero práve nakreslilo** – presne to hlási
  /// `Cannot transition! ... collinear and in opposite directions`.
  ///
  /// * [OutlineOrder.nearest] / [OutlineOrder.nearestFlipped] – chamtivé
  ///   hľadanie najbližšieho obrysu (v mriežke buniek, aby to pri tisíckach
  ///   obrysov netrvalo sekundy),
  /// * [OutlineOptions.rotateStart] – uzavretý obrys sa začne v bode
  ///   najbližšom k miestu, kde pero práve stojí; pero tak do obrysu „vstúpi“
  ///   z boku namiesto prejazdu na jeho začiatok a späť.
  List<List<ui.Offset>> _orderOutlines(List<List<ui.Offset>> polylines) {
    if (polylines.isEmpty) return polylines;

    final ordered = <List<ui.Offset>>[];
    var cursor = ui.Offset(leftMm, topMm);

    List<ui.Offset> startAt(List<ui.Offset> line) =>
        outline.rotateStart ? _rotateClosedOutline(line, cursor) : line;

    // Pôvodné poradie – mení sa len začiatok uzavretých obrysov.
    if (polylines.length < 2 || outline.order == OutlineOrder.asFound) {
      for (final line in polylines) {
        final stroke = startAt(line);
        ordered.add(stroke);
        cursor = stroke.last;
      }
      return ordered;
    }

    final allowFlip = outline.order == OutlineOrder.nearestFlipped;
    (int, int) cellOf(ui.Offset point) => (
          (point.dx / _outlineCellMm).floor(),
          (point.dy / _outlineCellMm).floor(),
        );

    final cells = <(int, int), List<int>>{};
    void addEntry(ui.Offset point, int index) =>
        cells.putIfAbsent(cellOf(point), () => <int>[]).add(index);
    for (var i = 0; i < polylines.length; i++) {
      addEntry(polylines[i].first, i);
      if (allowFlip && _isOpenOutline(polylines[i])) {
        addEntry(polylines[i].last, i);
      }
    }

    final maxRing =
        (math.max(paperWidthMm, paperHeightMm) / _outlineCellMm).ceil() + 1;
    final used = List<bool>.filled(polylines.length, false);

    for (var drawn = 0; drawn < polylines.length; drawn++) {
      var index = -1;
      var flip = false;
      var best = double.infinity;
      final centre = cellOf(cursor);

      // Prstence buniek okolo pera – najbližší obrys sa hľadá len v okolí.
      for (var ring = 0; ring <= maxRing; ring++) {
        for (var x = centre.$1 - ring; x <= centre.$1 + ring; x++) {
          for (var y = centre.$2 - ring; y <= centre.$2 + ring; y++) {
            final onRing = x == centre.$1 - ring ||
                x == centre.$1 + ring ||
                y == centre.$2 - ring ||
                y == centre.$2 + ring;
            if (ring > 0 && !onRing) continue; // vnútro prešli menšie prstence
            for (final candidate in cells[(x, y)] ?? const <int>[]) {
              if (used[candidate]) continue;
              final line = polylines[candidate];
              final canFlip = allowFlip && _isOpenOutline(line);
              for (final candidateFlip
                  in canFlip ? const [false, true] : const [false]) {
                final point = candidateFlip ? line.last : line.first;
                final distance = (point - cursor).distance;
                if (distance < best) {
                  best = distance;
                  index = candidate;
                  flip = candidateFlip;
                }
              }
            }
          }
        }
        // Bod v ďalšom prstenci je od pera aspoň `ring × bunka` ďaleko.
        if (index >= 0 && best <= ring * _outlineCellMm) break;
      }

      // Nič v dosahu mriežky (prázdne miesto na papieri) – prejdi všetko.
      if (index < 0) {
        for (var i = 0; i < polylines.length; i++) {
          if (used[i]) continue;
          final line = polylines[i];
          final canFlip = allowFlip && _isOpenOutline(line);
          for (final candidateFlip
              in canFlip ? const [false, true] : const [false]) {
            final point = candidateFlip ? line.last : line.first;
            final distance = (point - cursor).distance;
            if (distance < best) {
              best = distance;
              index = i;
              flip = candidateFlip;
            }
          }
        }
      }
      if (index < 0) break;

      used[index] = true;
      final line = flip
          ? polylines[index].reversed.toList(growable: false)
          : polylines[index];
      final stroke = startAt(line);
      ordered.add(stroke);
      cursor = stroke.last;
    }

    return ordered;
  }

  /// Je obrys otvorený (prvý a posledný bod nie sú totožné)?
  bool _isOpenOutline(List<ui.Offset> polyline) =>
      polyline.length < 2 || (polyline.last - polyline.first).distance > 1e-6;

  /// Otočí uzavretý obrys tak, aby začínal v bode najbližšom k [from].
  ///
  /// Uzavretý obrys sa kreslí celý, takže je jedno, ktorým bodom začne – ale
  /// prejazd k začiatku áno. Keď pero pokračuje v bode, ktorý je mu najbližší,
  /// prejazd je krátky a (hlavne) nevedie späť po čiare, ktorú práve nakreslil.
  List<ui.Offset> _rotateClosedOutline(
      List<ui.Offset> polyline, ui.Offset from) {
    if (polyline.length < 4 || _isOpenOutline(polyline)) return polyline;

    var bestIndex = 0;
    var bestDistance = double.infinity;
    for (var i = 0; i < polyline.length - 1; i++) {
      final distance = (polyline[i] - from).distance;
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = i;
      }
    }
    if (bestIndex == 0) return polyline;

    // [vk … vn-1, v0 … vk-1, vk] – stále uzavretý obrys, len s iným začiatkom.
    return [
      ...polyline.sublist(bestIndex, polyline.length - 1),
      ...polyline.sublist(0, bestIndex),
      polyline[bestIndex],
    ];
  }

  /// Dĺžka obrysu pozdĺž čiary v mm.
  double _polylineLengthMm(List<ui.Offset> polyline) {
    var length = 0.0;
    for (var i = 1; i < polyline.length; i++) {
      length += (polyline[i] - polyline[i - 1]).distance;
    }
    return length;
  }

  /// Prevedie polylinu v mm na ťah s bodmi po [stepMm] (pôvodné *Outline*).
  ///
  /// Krok sa meria **pozdĺž čiary**: každá hrana sa rozdelí na toľko dielov,
  /// aby body neboli ďalej ako [stepMm] – vrátane pixelových schodíkov. Keď
  /// potrebuje pero skutočnú **tetivu** (krok, ktorý robot prejde), použije sa
  /// [_resamplePolyline].
  List<StrokePoint> _subdividePolyline(
      List<ui.Offset> polyline, double stepMm) {
    if (polyline.length < 2) return const [];

    final points = <StrokePoint>[
      _strokePoint(polyline.first.dx, polyline.first.dy),
    ];
    for (var i = 1; i < polyline.length; i++) {
      final a = polyline[i - 1];
      final b = polyline[i];
      final steps = math.max(1, ((b - a).distance / stepMm).ceil());
      for (var s = 1; s <= steps; s++) {
        final t = s / steps;
        points.add(_strokePoint(
          a.dx + (b.dx - a.dx) * t,
          a.dy + (b.dy - a.dy) * t,
        ));
      }
    }
    return points;
  }

  /// Douglas–Peucker: vyhodí body, ktoré sú bližšie k spojnici susedov ako
  /// [toleranceMm].
  ///
  /// Obrys z pixelových hrán je „schodisko“ – každý pixel pridá odbočenie
  /// o 90°. Zjednodušenie z neho spraví rovné úseky, takže robot nemá tisíce
  /// krátkych úsekov, na ktorých musí zastavovať.
  List<ui.Offset> _simplifyPolyline(
      List<ui.Offset> polyline, double toleranceMm) {
    if (polyline.length < 3) return polyline;

    final keep = List<bool>.filled(polyline.length, false);
    keep[0] = true;
    keep[polyline.length - 1] = true;

    // Zásobník namiesto rekurzie – dlhý obrys by inak mohol prekročiť stack.
    final stack = <(int, int)>[(0, polyline.length - 1)];
    while (stack.isNotEmpty) {
      final (first, last) = stack.removeLast();
      if (last <= first + 1) continue;

      final a = polyline[first];
      final b = polyline[last];
      var farthest = -1;
      var farthestDistance = toleranceMm;
      for (var i = first + 1; i < last; i++) {
        final distance = _distanceToSegment(polyline[i], a, b);
        if (distance > farthestDistance) {
          farthestDistance = distance;
          farthest = i;
        }
      }
      if (farthest < 0) continue;

      keep[farthest] = true;
      stack.add((first, farthest));
      stack.add((farthest, last));
    }

    return [
      for (var i = 0; i < polyline.length; i++)
        if (keep[i]) polyline[i],
    ];
  }

  /// Vzdialenosť bodu [point] od úsečky [a]–[b] v mm.
  double _distanceToSegment(ui.Offset point, ui.Offset a, ui.Offset b) {
    final ab = b - a;
    final lengthSquared = ab.dx * ab.dx + ab.dy * ab.dy;
    if (lengthSquared <= 0) return (point - a).distance;

    final ap = point - a;
    final t = ((ap.dx * ab.dx + ap.dy * ab.dy) / lengthSquared).clamp(0.0, 1.0);
    return (point - ui.Offset(a.dx + ab.dx * t, a.dy + ab.dy * t)).distance;
  }

  /// Prevedie polylinu na ťah s krokmi **aspoň** [stepMm].
  ///
  /// Krok sa meria **vzdušnou čiarou** (tetivou), nie po dĺžke obrysu: pero
  /// ide priamo z bodu do bodu, takže práve tetiva rozhoduje o tom, či sa
  /// pohyb stihne rozbehnúť. Dva susedné body sú preto vždy aspoň [stepMm]
  /// od seba – presne to, čo robot potrebuje, aby controller prechod prijal.
  ///
  /// Uzavretý obrys sa na konci dotiahne späť na začiatok (inak by v kresbe
  /// ostala medzera), otvorená čiara môže na konci stratiť zvyšok kratší ako
  /// jeden krok. Keď je celá čiara kratšia ako krok, vráti prázdny zoznam
  /// (detail sa nedá nakresliť).
  List<StrokePoint> _resamplePolyline(List<ui.Offset> polyline, double stepMm) {
    if (polyline.length < 2) return const [];

    // Body na čiare, z ktorých sa nakoniec poskladá ťah (v mm).
    final anchors = <ui.Offset>[polyline.first];
    var anchor = polyline.first;
    var walk = polyline.first;
    var nextIndex = 1;

    while (nextIndex < polyline.length) {
      final next = polyline[nextIndex];

      // Ešte sme od posledného bodu ďaleko menej ako jeden krok – ideme ďalej.
      if ((next - anchor).distance < stepMm) {
        walk = next;
        nextIndex++;
        continue;
      }

      // Bod na úseku walk–next, ktorý je od [anchor] presne [stepMm].
      final t = _stepCrossing(anchor, walk, next, stepMm);
      final point = ui.Offset(
        walk.dx + (next.dx - walk.dx) * t,
        walk.dy + (next.dy - walk.dy) * t,
      );
      anchors.add(point);
      anchor = point;
      walk = point;
    }

    if (anchors.length == 1) return const [];

    // Uzavretý obrys: dotiahnuť späť na začiatok. Ak by posledný bod bol od
    // začiatku bližšie ako krok, radšej sa zahodí, než by robot dostal dva
    // body tesne pri sebe.
    final closed = (polyline.last - polyline.first).distance < 1e-6;
    if (closed) {
      while (anchors.length > 1 &&
          (anchors.last - polyline.first).distance < stepMm) {
        anchors.removeLast();
      }
      if (anchors.length == 1) return const [];
      anchors.add(polyline.first);
    }

    return [for (final point in anchors) _strokePoint(point.dx, point.dy)];
  }

  /// Parameter `t` na úseku [from]–[to], kde je bod od [anchor] vzdialený
  /// presne [stepMm] (riešenie kvadratickej rovnice, nie odhad).
  ///
  /// Vráti najmenší koreň v rozsahu `(0, 1>`; keď úsek krok nepretne,
  /// vráti `1` (pokračuje sa jeho koncom).
  double _stepCrossing(
      ui.Offset anchor, ui.Offset from, ui.Offset to, double stepMm) {
    final directionX = to.dx - from.dx;
    final directionY = to.dy - from.dy;
    final offsetX = from.dx - anchor.dx;
    final offsetY = from.dy - anchor.dy;

    final qa = directionX * directionX + directionY * directionY;
    if (qa <= 0) return 1;

    final qb = 2 * (directionX * offsetX + directionY * offsetY);
    final qc = offsetX * offsetX + offsetY * offsetY - stepMm * stepMm;
    final discriminant = qb * qb - 4 * qa * qc;
    if (discriminant < 0) return 1;

    final root = math.sqrt(discriminant);
    final first = (-qb - root) / (2 * qa);
    final second = (-qb + root) / (2 * qa);
    for (final t in [first, second]) {
      if (t > 1e-9 && t <= 1 + 1e-9) return t.clamp(0.0, 1.0);
    }
    return 1;
  }

  /// Ohodnotí všetkých kandidátov a vráti najlacnejší pattern.
  ///
  /// Cena = dĺžka kresby v mm + [penLiftPenaltyMm] za každý samostatný ťah
  /// (t. j. za každý zdvih pera). Pre konkrétny obrázok tak `auto` vyberie
  /// smer, ktorý má najmenej zdvihov a najkratšiu dráhu.
  ///
  /// `Outline` ani `Spiral`/`Rings` sa nehodnotia – nie sú to výplne, ale
  /// spôsob kresby (obrys / kotúč), takže by `auto` vždy prevalcovali
  /// najnižšou cenou.
  PlotPattern optimalPattern() {
    final horizontal = _costLines(1, 0);
    final diagonal = _costLines(_diagonal, _diagonal);
    final antiDiagonal = _costLines(_diagonal, -_diagonal);

    final costs = <PlotPattern, double>{
      PlotPattern.horizontal: horizontal,
      PlotPattern.vertical: _costLines(0, 1),
      PlotPattern.diagonal: diagonal,
      PlotPattern.antiDiagonal: antiDiagonal,
      PlotPattern.crossHatch: diagonal + antiDiagonal,
      // Tri priechody = vodorovná výplň + obe šrafovania (najdrahšia výplň).
      PlotPattern.tripleHatch: horizontal + diagonal + antiDiagonal,
      PlotPattern.dots: _costDots(),
      PlotPattern.zigzag: _costZigzag(),
    };

    var best = PlotPattern.horizontal;
    var bestCost = costs[PlotPattern.horizontal]!;
    for (final entry in costs.entries) {
      if (entry.value < bestCost) {
        best = entry.key;
        bestCost = entry.value;
      }
    }
    return best;
  }

  /// Zmeria súvislé línie v danom smere (ťahy sa nestavajú, len počítajú).
  ///
  /// Vráti dĺžku atramentu v mm a počet samostatných úsekov (= zdvihov pera).
  ({double inkMm, int runs}) _measureLines(double dirX, double dirY) {
    final span = _span(dirX, dirY);
    final normalX = -dirY;
    final normalY = dirX;
    final lines =
        math.max(1, ((span.vMax - span.vMin) / lineSpacingMm).floor());
    final lineStepMm = (span.vMax - span.vMin) / lines;
    final samples = math.max(1, ((span.uMax - span.uMin) / mmPerPixel).floor());

    var runs = 0;
    var inkSamples = 0;
    for (var line = 0; line < lines; line++) {
      final v = span.vMin + lineStepMm * (line + 0.5);
      var inRun = false;
      for (var k = 0; k <= samples; k++) {
        final ink =
            _inkAt(span.uMin + k * mmPerPixel, v, dirX, dirY, normalX, normalY);
        if (!ink) {
          inRun = false;
          continue;
        }
        inkSamples++;
        if (!inRun) {
          runs++;
          inRun = true;
        }
      }
    }
    return (inkMm: inkSamples * mmPerPixel, runs: runs);
  }

  /// Cena súvislých línií v danom smere (ťahy sa nestavajú, len počítajú).
  double _costLines(double dirX, double dirY) {
    final measured = _measureLines(dirX, dirY);
    return measured.inkMm + measured.runs * penLiftPenaltyMm;
  }

  /// Cena vlny – riadky sú pospájané, preto sa platí len zlomok ceny zdvihov
  /// (pero prejde medzeru bez zdvihnutia a hneď kreslí ďalej).
  double _costZigzag() {
    final measured = _measureLines(1, 0);
    return measured.inkMm + measured.runs * penLiftPenaltyMm * 0.15;
  }

  /// Atramentové úseky v riadku `y` (vodorovný smer), v mm papiera.
  ///
  /// Medzery do [gapSamples] sa premostia – pero nemá dôvod zdvíhať pre dieru,
  /// ktorú aj tak prekryje svojou šírkou.
  List<({double start, double end})> _inkRuns(
      double y, double uMin, int samples) {
    const dirX = 1.0;
    const dirY = 0.0;
    const normalX = 0.0;
    const normalY = 1.0;

    final runs = <({double start, double end})>[];
    var runStart = -1;

    for (var k = 0; k <= samples; k++) {
      final ink =
          _inkAt(uMin + k * mmPerPixel, y, dirX, dirY, normalX, normalY);

      if (ink && runStart < 0) {
        runStart = k;
        continue;
      }
      if (ink || runStart < 0) continue;

      if (k + gapSamples < samples &&
          _hasInkAhead(
              k, gapSamples, samples, y, uMin, dirX, dirY, normalX, normalY)) {
        continue;
      }

      runs.add((
        start: uMin + runStart * mmPerPixel,
        end: uMin + k * mmPerPixel,
      ));
      runStart = -1;
    }

    return runs;
  }

  /// Cena bodkovej matice – každá bodka je samostatný ťah (zdvih pera).
  double _costDots() {
    final rows = math.max(1, (drawHeightMm / lineSpacingMm).floor());
    final rowStepMm = drawHeightMm / rows;
    final columns = math.max(1, (drawWidthMm / lineSpacingMm).floor());
    final columnStepMm = drawWidthMm / columns;
    final tickMm = _dotLengthMm(columnStepMm);

    var dots = 0;
    for (var row = 0; row < rows; row++) {
      final yMm = topMm + rowStepMm * (row + 0.5);
      for (var column = 0; column < columns; column++) {
        final xMm = leftMm + columnStepMm * (column + 0.5);
        if (_isInkAtPixel(xMm, yMm)) dots++;
      }
    }
    return dots * (tickMm + penLiftPenaltyMm);
  }

  /// Spojí výsledky dvoch priechodov (cross-hatch).
  _Fill _merge(List<_Fill> parts) {
    final strokes = <List<StrokePoint>>[];
    var pointCount = 0;
    var truncated = false;
    var lineCount = 0;
    for (final part in parts) {
      strokes.addAll(part.strokes);
      pointCount += part.pointCount;
      truncated = truncated || part.truncated;
      lineCount += part.lineCount;
    }
    return _Fill(
      strokes: strokes,
      pointCount: pointCount,
      truncated: truncated,
      lineCount: lineCount,
    );
  }

  /// Rozsah kresby v smere ťahu (`u`) a kolmo naň (`v`) v mm.
  ({double uMin, double uMax, double vMin, double vMax}) _span(
      double dirX, double dirY) {
    final normalX = -dirY;
    final normalY = dirX;
    var uMin = double.infinity;
    var uMax = -double.infinity;
    var vMin = double.infinity;
    var vMax = -double.infinity;
    for (final x in [leftMm, leftMm + drawWidthMm]) {
      for (final y in [topMm, topMm + drawHeightMm]) {
        final u = x * dirX + y * dirY;
        final v = x * normalX + y * normalY;
        uMin = math.min(uMin, u);
        uMax = math.max(uMax, u);
        vMin = math.min(vMin, v);
        vMax = math.max(vMax, v);
      }
    }
    return (uMin: uMin, uMax: uMax, vMin: vMin, vMax: vMax);
  }

  /// Bod v mm papiera pre súradnice `(u, v)` v priestore patternu.
  ui.Offset _mmPoint(double u, double v, double dirX, double dirY,
          double normalX, double normalY) =>
      ui.Offset(u * dirX + v * normalX, u * dirY + v * normalY);

  /// Je na pozícii `(u, v)` patternu atrament?
  bool _inkAt(double u, double v, double dirX, double dirY, double normalX,
      double normalY) {
    final px = ((u * dirX + v * normalX - leftMm) / mmPerPixel).round();
    final py = ((u * dirY + v * normalY - topMm) / mmPerPixel).round();
    return ImageStrokeGenerator._isInkAt(image, px, py, thresholdByte, invert);
  }

  /// Je atrament na milimetrovej pozícii `(xMm, yMm)`?
  bool _isInkAtPixel(double xMm, double yMm) {
    final px = ((xMm - leftMm) / mmPerPixel).round();
    final py = ((yMm - topMm) / mmPerPixel).round();
    return ImageStrokeGenerator._isInkAt(image, px, py, thresholdByte, invert);
  }

  /// Je v nasledujúcich [gap] vzorkách (od [from]) atrament?
  bool _hasInkAhead(int from, int gap, int samples, double v, double uMin,
      double dirX, double dirY, double normalX, double normalY) {
    final end = math.min(samples, from + gap);
    for (var k = from; k <= end; k++) {
      if (_inkAt(uMin + k * mmPerPixel, v, dirX, dirY, normalX, normalY)) {
        return true;
      }
    }
    return false;
  }

  /// Prevod milimetrov na normalizované súradnice papiera.
  StrokePoint _strokePoint(double xMm, double yMm) => StrokePoint(
        x: (xMm / paperWidthMm).clamp(0.0, 1.0).toDouble(),
        y: (yMm / paperHeightMm).clamp(0.0, 1.0).toDouble(),
        pressure: 1.0,
      );
}
