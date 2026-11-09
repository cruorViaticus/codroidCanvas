import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../models/paper_format.dart';
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

  /// Počet riadkov („scanlines“).
  final int rowCount;

  const ImagePlotResult({
    required this.strokes,
    required this.pointCount,
    required this.truncated,
    required this.drawWidthMm,
    required this.drawHeightMm,
    required this.rowCount,
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
  static const int mergeGapPx = 2;

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
        gray[i] = (luminance * alpha + 255 * (1 - alpha))
            .round()
            .clamp(0, 255)
            .toInt();
      }

      return GrayImage(width: image.width, height: image.height, gray: gray);
    } finally {
      image.dispose();
    }
  }

  /// Prevedie odtiene šedej na ťahy pre robota.
  ///
  /// [threshold] – 0 = kreslí len úplne čierne pixely, 1 = kreslí všetko
  /// (polotóny sa tak menia na plnú kresbu).
  /// [invert] – kreslí svetlé časti namiesto tmavých (negatív).
  static ImagePlotResult toStrokes(
    GrayImage image, {
    double lineSpacingMm = 1.2,
    double pointSpacingMm = 0.6,
    double threshold = 0.5,
    bool invert = false,
    double marginMm = 10.0,
    PaperFormat paper = kDefaultPaperFormat,
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
    final offsetXMm = marginMm + (availableWidthMm - drawWidthMm) / 2;
    final offsetYMm = marginMm + (availableHeightMm - drawHeightMm) / 2;

    final rows =
        math.max(1, (drawHeightMm / math.max(0.2, lineSpacingMm)).floor());
    final rowStepMm = drawHeightMm / rows;
    final thresholdByte = (threshold.clamp(0.0, 1.0) * 255).round();

    final strokes = <List<StrokePoint>>[];
    var pointCount = 0;
    var truncated = false;

    for (var row = 0; row < rows && !truncated; row++) {
      final yMm = offsetYMm + rowStepMm * (row + 0.5);
      final srcY = math.min(
        image.height - 1,
        math.max(0, ((row + 0.5) / rows * image.height).floor()),
      );
      final reverse = row.isOdd;

      var runStart = -1;
      for (var x = 0; x <= image.width; x++) {
        final ink = x < image.width &&
            _isInk(image.luminanceAt(x, srcY), thresholdByte, invert);

        if (ink && runStart < 0) {
          runStart = x;
          continue;
        }
        if (ink || runStart < 0) continue;

        // Koniec úseku – ak je medzera len 1–2 px a za ňou ešte atrament,
        // pokračujeme v tom istom ťahu (menej zdvihov pera).
        if (x + mergeGapPx < image.width &&
            _hasInkAhead(image, x, srcY, mergeGapPx, thresholdByte, invert)) {
          continue;
        }

        final xStartMm = offsetXMm + runStart * mmPerPixel;
        final xEndMm = offsetXMm + x * mmPerPixel;
        runStart = -1;

        final lengthMm = xEndMm - xStartMm;
        final segments =
            math.max(1, (lengthMm / math.max(0.05, pointSpacingMm)).ceil());
        if (pointCount + segments + 1 > maxPoints) {
          truncated = true;
          break;
        }

        final points = <StrokePoint>[];
        for (var i = 0; i <= segments; i++) {
          final xMm = xStartMm + lengthMm * i / segments;
          points.add(StrokePoint(
            x: xMm / paperWidthMm,
            y: yMm / paperHeightMm,
            pressure: 1.0,
          ));
        }
        if (reverse) {
          strokes.add(points.reversed.toList());
        } else {
          strokes.add(points);
        }
        pointCount += points.length;
      }
    }

    return ImagePlotResult(
      strokes: strokes,
      pointCount: pointCount,
      truncated: truncated,
      drawWidthMm: drawWidthMm,
      drawHeightMm: drawHeightMm,
      rowCount: rows,
    );
  }

  static bool _isInk(int luminance, int thresholdByte, bool invert) =>
      invert ? luminance > 255 - thresholdByte : luminance < thresholdByte;

  /// Je v okolí [x]..[x + gap] ešte atrament na riadku [y]?
  static bool _hasInkAhead(
    GrayImage image,
    int x,
    int y,
    int gap,
    int thresholdByte,
    bool invert,
  ) {
    final end = math.min(image.width - 1, x + gap);
    for (var probe = x; probe <= end; probe++) {
      if (_isInk(image.luminanceAt(probe, y), thresholdByte, invert)) {
        return true;
      }
    }
    return false;
  }
}
