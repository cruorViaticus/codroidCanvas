import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:codroid_pen_plotter/models/paper_format.dart';
import 'package:codroid_pen_plotter/models/stroke_point.dart';
import 'package:codroid_pen_plotter/providers/robot_provider.dart';
import 'package:codroid_pen_plotter/services/image_stroke_generator.dart';
import 'package:codroid_pen_plotter/services/plot_estimator.dart';
import 'package:codroid_pen_plotter/services/stroke_motion_processor.dart';
import 'package:codroid_pen_plotter/services/text_stroke_generator.dart';
import 'package:codroid_pen_plotter/widgets/paper_format_selector.dart';
import 'package:codroid_pen_plotter/widgets/plot_preview.dart';

/// Jednofarebný obrázok (celý čierny alebo biely) pre testy mierky.
GrayImage _image(int width, int height, {bool ink = true}) {
  final gray = Uint8List(width * height);
  for (var i = 0; i < gray.length; i++) {
    gray[i] = ink ? 0 : 255;
  }
  return GrayImage(width: width, height: height, gray: gray);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('PaperFormat', () {
    test('dlhšia strana je výška (os X), kratšia šírka (os Y)', () {
      expect(PaperFormat.a4.shortSideMm, 210);
      expect(PaperFormat.a4.longSideMm, 297);
      expect(PaperFormat.a3.shortSideMm, 297);
      expect(PaperFormat.a3.longSideMm, 420);
      expect(PaperFormat.a5.shortSideMm, 148);
      expect(PaperFormat.a5.longSideMm, 210);
      expect(PaperFormat.photo10x15.shortSideMm, 100);
      expect(PaperFormat.photo10x15.longSideMm, 150);

      for (final format in PaperFormat.values) {
        expect(format.widthMm, format.shortSideMm);
        expect(format.heightMm, format.longSideMm);
        expect(format.heightMm, greaterThan(format.widthMm));
        expect(
          format.aspectRatio,
          closeTo(format.widthMm / format.heightMm, 1e-12),
        );
      }
    });

    test('popis rozmerov a rozlíšenie fotopapiera', () {
      expect(PaperFormat.a4.label, 'A4');
      expect(PaperFormat.a4.sizeLabel, '210 × 297 mm');
      expect(PaperFormat.photo10x15.label, '10 × 15');
      expect(PaperFormat.photo10x15.sizeLabel, '100 × 150 mm');
      expect(PaperFormat.photo10x15.isPhotoPaper, isTrue);
      expect(PaperFormat.a4.isPhotoPaper, isFalse);
      expect(PaperFormat.a4.aspectRatio, closeTo(210 / 297, 1e-12));
    });

    test('fromName padne na A4 pri neznámom alebo chýbajúcom vstupe', () {
      expect(PaperFormat.fromName('a3'), PaperFormat.a3);
      expect(PaperFormat.fromName('photo10x15'), PaperFormat.photo10x15);
      expect(PaperFormat.fromName(null), PaperFormat.a4);
      expect(PaperFormat.fromName('A2'), PaperFormat.a4);
      expect(kDefaultPaperFormat, PaperFormat.a4);
    });
  });

  group('RobotProvider – formát papiera', () {
    test('predvolene kreslí na A4', () async {
      final provider = RobotProvider();
      await provider.initialized;

      expect(provider.paperFormat, PaperFormat.a4);
      expect(provider.paperWidthMm, 210.0);
      expect(provider.paperHeightMm, 297.0);
      expect(provider.paperAspectRatio, closeTo(210 / 297, 1e-12));
    });

    test('zmena formátu sa uloží a načíta v novom providerovi', () async {
      final provider = RobotProvider();
      await provider.initialized;

      await provider.setPaperFormat(PaperFormat.photo10x15);

      expect(provider.paperFormat, PaperFormat.photo10x15);
      expect(provider.paperWidthMm, 100.0);
      expect(provider.paperHeightMm, 150.0);
      expect(provider.paperAspectRatio, closeTo(100 / 150, 1e-12));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('paper_format'), 'photo10x15');

      final reloaded = RobotProvider();
      await reloaded.initialized;
      expect(reloaded.paperFormat, PaperFormat.photo10x15);
    });

    test('neznámy uložený formát sa berie ako A4', () async {
      SharedPreferences.setMockInitialValues({'paper_format': 'neznámy'});

      final provider = RobotProvider();
      await provider.initialized;

      expect(provider.paperFormat, PaperFormat.a4);
    });
  });

  group('StrokeMotionProcessor – milimetre podľa papiera', () {
    test('A4: 297 mm v X a 210 mm v Y (ako doteraz)', () {
      final processor = StrokeMotionProcessor(RobotProvider());

      expect(
        processor.toMillimetres(StrokePoint(x: 0, y: 0, pressure: 1)),
        const Offset(297, 210),
      );
      expect(
        processor.toMillimetres(StrokePoint(x: 1, y: 1, pressure: 1)),
        Offset.zero,
      );
    });

    test('A3: dlhšia strana (420 mm) ide na os X', () async {
      final provider = RobotProvider();
      await provider.initialized;
      await provider.setPaperFormat(PaperFormat.a3);
      final processor = StrokeMotionProcessor(provider);

      expect(
        processor.toMillimetres(StrokePoint(x: 0, y: 0, pressure: 1)),
        const Offset(420, 297),
      );
      expect(
        processor.toMillimetres(StrokePoint(x: 1, y: 1, pressure: 1)),
        Offset.zero,
      );
    });

    test('10 × 15: dlhšia strana (150 mm) ide na os X', () async {
      final provider = RobotProvider();
      await provider.initialized;
      await provider.setPaperFormat(PaperFormat.photo10x15);
      final processor = StrokeMotionProcessor(provider);

      expect(
        processor.toMillimetres(StrokePoint(x: 0, y: 0, pressure: 1)),
        const Offset(150, 100),
      );
      expect(
        processor.toMillimetres(StrokePoint(x: 0.5, y: 0.5, pressure: 1)),
        const Offset(75, 50),
      );
    });
  });

  group('TextStrokeGenerator – formát papiera', () {
    test('menší papier zalomí ten istý text do viac riadkov', () {
      const text = 'Codroid S Pen plotter writing a long sentence on paper';

      final a3 =
          TextStrokeGenerator.generate(text: text, paper: PaperFormat.a3);
      final a5 =
          TextStrokeGenerator.generate(text: text, paper: PaperFormat.a5);

      expect(a3.isEmpty, isFalse);
      expect(a5.lines.length, greaterThan(a3.lines.length));
    });

    test('veľký text sa na fotopapier nezmestí, na A3 áno', () {
      // 6 riadkov po 30 mm = 285 mm na výšku: na 150 mm fotopapier sa to
      // nezmestí, na 420 mm A3 áno.
      const text = 'a\na\na\na\na\na';

      final photo = TextStrokeGenerator.generate(
        text: text,
        fontSizeMm: 30,
        lineSpacing: 1.6,
        paper: PaperFormat.photo10x15,
      );
      final a3 = TextStrokeGenerator.generate(
        text: text,
        fontSizeMm: 30,
        lineSpacing: 1.6,
        paper: PaperFormat.a3,
      );

      expect(photo.lines.length, a3.lines.length);
      expect(photo.overflow, isTrue);
      expect(a3.overflow, isFalse);
    });

    test('súradnice ostávajú normalizované 0..1 pre každý formát', () {
      for (final format in PaperFormat.values) {
        final result =
            TextStrokeGenerator.generate(text: 'Codroid', paper: format);

        expect(result.isEmpty, isFalse, reason: format.label);
        for (final stroke in result.strokes) {
          for (final point in stroke) {
            expect(point.x, inInclusiveRange(0.0, 1.0));
            expect(point.y, inInclusiveRange(0.0, 1.0));
          }
        }
      }
    });
  });

  group('ImageStrokeGenerator – formát papiera', () {
    test('kresba sa zmenší na fotopapier a zväčší na A3', () {
      final image = _image(40, 40);

      final photo = ImageStrokeGenerator.toStrokes(
        image,
        paper: PaperFormat.photo10x15,
        marginMm: 10,
        lineSpacingMm: 5,
      );
      final a3 = ImageStrokeGenerator.toStrokes(
        image,
        paper: PaperFormat.a3,
        marginMm: 10,
        lineSpacingMm: 5,
      );

      // 100 × 150 mm mínus 2 × 10 mm okraj
      expect(photo.drawWidthMm, lessThanOrEqualTo(80.0 + 1e-9));
      expect(photo.drawHeightMm, lessThanOrEqualTo(130.0 + 1e-9));
      expect(a3.drawWidthMm, greaterThan(photo.drawWidthMm));
      expect(a3.drawHeightMm, greaterThan(photo.drawHeightMm));
      expect(photo.isEmpty, isFalse);
    });
  });

  group('PlotEstimator – dĺžka dráhy podľa papiera', () {
    test('zvislý ťah po celej výške = výška papiera', () {
      final line = [
        [
          StrokePoint(x: 0.5, y: 0, pressure: 1),
          StrokePoint(x: 0.5, y: 1, pressure: 1),
        ],
      ];

      expect(PlotEstimator.pathLengthMm(line), closeTo(297, 1e-9));
      expect(
        PlotEstimator.pathLengthMm(line, paper: PaperFormat.a3),
        closeTo(420, 1e-9),
      );
      expect(
        PlotEstimator.pathLengthMm(line, paper: PaperFormat.photo10x15),
        closeTo(150, 1e-9),
      );
    });
  });

  group('UI', () {
    testWidgets('PlotPreview používa pomer strán zvoleného papiera',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: SizedBox(
              width: 100,
              child: PlotPreview(strokes: [], paper: PaperFormat.a5),
            ),
          ),
        ),
      );

      final ratio = tester.widget<AspectRatio>(
        find.descendant(
          of: find.byType(PlotPreview),
          matching: find.byType(AspectRatio),
        ),
      );
      expect(ratio.aspectRatio, closeTo(148 / 210, 1e-12));
    });

    testWidgets('PaperFormatSelector uloží vybraný formát do providera',
        (tester) async {
      final provider = RobotProvider();
      await provider.initialized;

      await tester.pumpWidget(
        ChangeNotifierProvider<RobotProvider>.value(
          value: provider,
          child: const MaterialApp(
            home: Scaffold(body: PaperFormatSelector()),
          ),
        ),
      );

      expect(find.text('Paper format'), findsOneWidget);
      expect(find.textContaining('210 mm (Y)'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'A3'));
      await tester.pumpAndSettle();

      expect(provider.paperFormat, PaperFormat.a3);
      expect(find.textContaining('297 mm (Y)'), findsOneWidget);

      final a3Chip =
          tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'A3'));
      expect(a3Chip.selected, isTrue);
    });
  });
}
