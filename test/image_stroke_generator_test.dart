import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:codroid_pen_plotter/services/image_stroke_generator.dart';

/// Obrázok poskladaný z pixelov – čierne pásy na bielom pozadí.
GrayImage _image(
  int width,
  int height,
  bool Function(int x, int y) isInk, {
  bool inverted = false,
}) {
  final gray = Uint8List(width * height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final ink = isInk(x, y);
      gray[y * width + x] = inverted ? (ink ? 255 : 0) : (ink ? 0 : 255);
    }
  }
  return GrayImage(width: width, height: height, gray: gray);
}

/// Horizontálny pás v riadku [y] od [fromX] po [toX] (vrátane).
bool Function(int, int) _bar({
  required int y,
  int fromX = 5,
  int toX = 34,
  Set<int> gaps = const {},
}) {
  return (x, row) => row == y && x >= fromX && x <= toX && !gaps.contains(x);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ImageStrokeGenerator.toStrokes', () {
    test('biely obrázok nevygeneruje žiadny ťah', () {
      final image = _image(40, 40, (x, y) => false);

      final result = ImageStrokeGenerator.toStrokes(image);

      expect(result.isEmpty, isTrue);
      expect(result.pointCount, 0);
      expect(result.truncated, isFalse);
      // riadky sa počítajú aj pre prázdny obrázok
      expect(result.rowCount, greaterThan(0));
    });

    test('čierny pás sa zmení na jeden vodorovný ťah', () {
      final image = _image(40, 40, _bar(y: 20));

      final result = ImageStrokeGenerator.toStrokes(
        image,
        lineSpacingMm: 200, // jediný „scanline“ → deterministický výsledok
        pointSpacingMm: 1.0,
      );

      expect(result.strokes, hasLength(1));
      expect(result.rowCount, 1);

      final stroke = result.strokes.single;
      expect(stroke.first.x, lessThan(stroke.last.x)); // zľava doprava
      for (final point in stroke) {
        expect(point.x, inInclusiveRange(0.0, 1.0));
        expect(point.y, inInclusiveRange(0.0, 1.0));
        expect(point.pressure, 1.0);
      }
      // pás začína na 5. pixli, nie na kraji papiera
      expect(stroke.first.x, greaterThan(0.05));
    });

    test('bodová hustota mení počet bodov v ťahu', () {
      final image = _image(40, 40, _bar(y: 20));

      final dense = ImageStrokeGenerator.toStrokes(
        image,
        lineSpacingMm: 200,
        pointSpacingMm: 0.5,
      );
      final sparse = ImageStrokeGenerator.toStrokes(
        image,
        lineSpacingMm: 200,
        pointSpacingMm: 4.0,
      );

      expect(dense.strokes.length, sparse.strokes.length);
      expect(dense.pointCount, greaterThan(sparse.pointCount));
      // krajné body ostávajú rovnaké
      expect(
        dense.strokes.single.first.x,
        closeTo(sparse.strokes.single.first.x, 0.0001),
      );
    });

    test('hustejšie riadky znamenajú viac ťahov', () {
      final image = _image(40, 40, (x, y) => y > 5 && y < 35);

      final dense = ImageStrokeGenerator.toStrokes(image, lineSpacingMm: 2.0);
      final sparse = ImageStrokeGenerator.toStrokes(image, lineSpacingMm: 10.0);

      expect(dense.rowCount, greaterThan(sparse.rowCount));
      expect(dense.strokes.length, greaterThan(sparse.strokes.length));
    });

    test('malá medzera v páse ťah nerozdelí, veľká áno', () {
      final tiny = _image(40, 40, _bar(y: 20, gaps: {20}));
      final wide = _image(40, 40, _bar(y: 20, gaps: {18, 19, 20, 21, 22}));

      expect(
        ImageStrokeGenerator.toStrokes(
          tiny,
          lineSpacingMm: 200,
          pointSpacingMm: 1.0,
        ).strokes,
        hasLength(1),
      );
      expect(
        ImageStrokeGenerator.toStrokes(
          wide,
          lineSpacingMm: 200,
          pointSpacingMm: 1.0,
        ).strokes,
        hasLength(2),
      );
    });

    test('invert kreslí svetlé časti namiesto tmavých', () {
      // biely pás na čiernom pozadí
      final image = _image(40, 40, _bar(y: 20), inverted: true);

      final normal = ImageStrokeGenerator.toStrokes(
        image,
        lineSpacingMm: 200,
        pointSpacingMm: 1.0,
      );
      final inverted = ImageStrokeGenerator.toStrokes(
        image,
        lineSpacingMm: 200,
        pointSpacingMm: 1.0,
        invert: true,
      );

      // bez invertu sa kreslí čierne pozadie – biely pás ho rozdelí na dva ťahy
      expect(normal.strokes, hasLength(2));
      // s invertom sa kreslí iba biely pás
      expect(inverted.strokes, hasLength(1));
      expect(inverted.strokes.single.first.x,
          greaterThan(normal.strokes.first.first.x));
    });

    test('striedavé riadky sa kreslia opačným smerom (serpentína)', () {
      final image = _image(40, 40, (x, y) => true); // celý čierny

      final result = ImageStrokeGenerator.toStrokes(
        image,
        lineSpacingMm: 60, // 3 scanlines
        pointSpacingMm: 2.0,
      );

      expect(result.strokes, hasLength(3));
      expect(result.strokes[0].first.x, lessThan(result.strokes[0].last.x));
      expect(result.strokes[1].first.x, greaterThan(result.strokes[1].last.x));
      expect(result.strokes[2].first.x, lessThan(result.strokes[2].last.x));
    });

    test('limit bodov kresbu skráti a označí truncated', () {
      final image = _image(40, 40, _bar(y: 20));

      final result = ImageStrokeGenerator.toStrokes(
        image,
        lineSpacingMm: 200,
        pointSpacingMm: 0.5,
        maxPoints: 20,
      );

      expect(result.truncated, isTrue);
      expect(result.pointCount, lessThanOrEqualTo(20));
    });

    test('threshold rozhoduje, čo je ešte atrament', () {
      // stredne šedý pás (128) – pri prahu 20 % je už „biely“, pri 80 % je atrament
      final gray = Uint8List(40 * 40)..fillRange(0, 40 * 40, 255);
      for (var x = 5; x <= 34; x++) {
        gray[20 * 40 + x] = 128;
      }
      final image = GrayImage(width: 40, height: 40, gray: gray);

      final low = ImageStrokeGenerator.toStrokes(
        image,
        lineSpacingMm: 200,
        threshold: 0.2,
      );
      final high = ImageStrokeGenerator.toStrokes(
        image,
        lineSpacingMm: 200,
        threshold: 0.8,
      );

      expect(low.strokes, isEmpty);
      expect(high.strokes, hasLength(1));
    });
  });

  group('ImageStrokeGenerator.decode', () {
    test('dekóduje PNG a prevedie ho na odtiene šedej', () async {
      final black = await _pngBytes(4, 2, Colors.black);
      final gray = await ImageStrokeGenerator.decode(black);

      expect(gray.width, 4);
      expect(gray.height, 2);
      expect(gray.gray.length, 8);
      expect(gray.luminanceAt(0, 0), lessThan(10));
      expect(gray.luminanceAt(3, 1), lessThan(10));
    });

    test('veľký obrázok sa pri dekódovaní zmenší', () async {
      final big = await _pngBytes(64, 32, Colors.white);

      final gray = await ImageStrokeGenerator.decode(big, maxDimension: 16);

      expect(gray.width, 16);
      expect(gray.height, 8);
      expect(gray.luminanceAt(0, 0), greaterThan(245));
    });
  });
}

/// Vytvorí PNG s jednoliato farbou – aby test nepotreboval binárny fixture.
Future<Uint8List> _pngBytes(int width, int height, Color color) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = color,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}
