import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:codroid_pen_plotter/models/paper_format.dart';
import 'package:codroid_pen_plotter/models/plot_pattern.dart';
import 'package:codroid_pen_plotter/models/stroke_point.dart';
import 'package:codroid_pen_plotter/providers/robot_provider.dart';
import 'package:codroid_pen_plotter/services/image_stroke_generator.dart';
import 'package:codroid_pen_plotter/widgets/plot_preview.dart';

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

/// Dĺžka bodky (krátkeho ťahu) v milimetroch papiera A4.
double _tickMm(List<List<StrokePoint>> strokes) {
  final stroke = strokes.first;
  return ((stroke.last.x - stroke.first.x) * PaperFormat.a4.widthMm).abs();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('RobotProvider – šírka stopy pera', () {
    test('predvolená šírka je 0,2 mm', () async {
      final provider = RobotProvider();
      await provider.initialized;

      expect(provider.penWidthMm, RobotProvider.defaultPenWidthMm);
      expect(provider.penWidthMm, 0.2);
      expect(RobotProvider.minPenWidthMm, 0.05);
      expect(RobotProvider.maxPenWidthMm, 2.0);
    });

    test('šírka je orezaná na 0,05 – 2 mm', () async {
      final provider = RobotProvider();
      await provider.initialized;

      // tenšie pero by pero kreslilo „nič“ – pod 0,05 mm nemá zmysel
      provider.penWidthMm = 0.0;
      expect(provider.penWidthMm, RobotProvider.minPenWidthMm);

      provider.penWidthMm = 8.0;
      expect(provider.penWidthMm, RobotProvider.maxPenWidthMm);

      provider.penWidthMm = 0.35;
      expect(provider.penWidthMm, 0.35);
    });

    test('uložená šírka sa zapíše do SharedPreferences', () async {
      final provider = RobotProvider();
      await provider.initialized;

      await provider.setPenWidth(0.45);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('pen_width_mm'), 0.45);
      expect(provider.penWidthMm, 0.45);
    });

    test('uložená šírka sa pri štarte načíta', () async {
      SharedPreferences.setMockInitialValues({'pen_width_mm': 0.8});

      final provider = RobotProvider();
      await provider.initialized;

      expect(provider.penWidthMm, 0.8);
    });
  });

  group('ImageStrokeGenerator – šírka pera', () {
    test('hrubšie pero zväčší minimálny rozostup línií', () {
      final image = _image(40, 40, (x, y) => true);

      final thin = ImageStrokeGenerator.toStrokes(
        image,
        lineSpacingMm: 0.5,
        pointSpacingMm: 1.0,
        penWidthMm: 0.2,
      );
      final thick = ImageStrokeGenerator.toStrokes(
        image,
        lineSpacingMm: 0.5,
        pointSpacingMm: 1.0,
        penWidthMm: 1.0,
      );

      // 1 mm pero nerozdelí línie bližšie ako 1 mm – riadkov je menej
      expect(thick.rowCount, lessThan(thin.rowCount));
      expect(thick.strokes.length, lessThan(thin.strokes.length));
    });

    test('bodky sú aspoň dvojnásobok šírky pera dlhé', () {
      final image = _image(40, 40, (x, y) => true);

      final thin = ImageStrokeGenerator.toStrokes(
        image,
        pattern: PlotPattern.dots,
        lineSpacingMm: 10,
        pointSpacingMm: 1.0,
        penWidthMm: 0.2,
      );
      final thick = ImageStrokeGenerator.toStrokes(
        image,
        pattern: PlotPattern.dots,
        lineSpacingMm: 10,
        pointSpacingMm: 1.0,
        penWidthMm: 0.5,
      );

      expect(_tickMm(thin.strokes), closeTo(0.8, 0.01));
      // 0,5 mm pero = bodka aspoň 1 mm (inak by ju ani nebolo vidieť)
      expect(_tickMm(thick.strokes), greaterThanOrEqualTo(0.99));
    });

    test('predvolená šírka pera v generátore je 0,2 mm', () {
      expect(ImageStrokeGenerator.defaultPenWidthMm, 0.2);
      expect(ImageStrokeGenerator.defaultPenWidthMm,
          RobotProvider.defaultPenWidthMm);
    });
  });

  group('PlotPreview – hrúbka čiary', () {
    Future<void> pumpPreview(WidgetTester tester, double penWidthMm) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                height: 400,
                child: PlotPreview(
                  strokes: [
                    [
                      StrokePoint(x: 0.1, y: 0.1, pressure: 1.0),
                      StrokePoint(x: 0.9, y: 0.5, pressure: 1.0),
                    ],
                  ],
                  paper: PaperFormat.a4,
                  penWidthMm: penWidthMm,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('náhľad sa vykreslí pre tenké aj hrubé pero', (tester) async {
      await pumpPreview(tester, 0.2);
      expect(find.byType(CustomPaint), findsWidgets);

      await pumpPreview(tester, 2.0);
      expect(find.byType(CustomPaint), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('prázdny náhľad ukáže popis', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PlotPreview(strokes: [], emptyLabel: 'Nic tu nie je'),
          ),
        ),
      );

      expect(find.text('Nic tu nie je'), findsOneWidget);
    });
  });
}
