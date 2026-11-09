import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:codroid_pen_plotter/models/plot_pattern.dart';
import 'package:codroid_pen_plotter/providers/robot_provider.dart';
import 'package:codroid_pen_plotter/screens/image_print_screen.dart';
import 'package:codroid_pen_plotter/widgets/plot_preview.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  /// Zobrazí [ImagePrintScreen] s čistým [RobotProvider] (nepripojený robot).
  Future<RobotProvider> pumpImagePrint(WidgetTester tester) async {
    // Vysoký viewport, aby boli viditeľné všetky ovládače aj tlačidlá.
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final provider = RobotProvider();
    await provider.initialized;

    await tester.pumpWidget(
      ChangeNotifierProvider<RobotProvider>.value(
        value: provider,
        child: const MaterialApp(home: ImagePrintScreen()),
      ),
    );
    await tester.pumpAndSettle();

    return provider;
  }

  testWidgets('ImagePrintScreen zobrazí ovládače a prázdny náhľad',
      (tester) async {
    await pumpImagePrint(tester);

    expect(find.text('Pick Image'), findsOneWidget);
    expect(find.text('PNG / JPG / BMP / GIF / WebP'), findsOneWidget);
    expect(find.text('Plot pattern'), findsOneWidget);
    expect(find.text('Pen lift between lines / dots'), findsOneWidget);
    expect(find.text('Line density'), findsOneWidget);
    expect(find.text('Point spacing'), findsOneWidget);
    expect(find.text('Threshold'), findsOneWidget);
    expect(find.text('Paper margin'), findsOneWidget);
    expect(find.text('Mirror horizontally'), findsOneWidget);
    expect(find.text('Mirror vertically'), findsOneWidget);
    expect(find.text('Strokes'), findsOneWidget);
    expect(find.text('Points'), findsOneWidget);
    expect(find.text('Connect to the robot first'), findsOneWidget);

    // bez obrázka nie je čo kresliť
    final preview = tester.widget<PlotPreview>(find.byType(PlotPreview));
    expect(preview.strokes, isEmpty);

    // `auto` je predvolený pattern a všetkých šesť volieb je na obrazovke
    for (final pattern in PlotPattern.values) {
      expect(find.widgetWithText(ChoiceChip, pattern.label), findsOneWidget);
    }
  });

  testWidgets('ImagePrintScreen – výber patternu a zdvihu pera',
      (tester) async {
    await pumpImagePrint(tester);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Diagonal'));
    await tester.pumpAndSettle();

    final diagonal = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'Diagonal'),
    );
    expect(diagonal.selected, isTrue);
    // popis zvoleného patternu sa zobrazí pod chipmi
    expect(find.text(PlotPattern.diagonal.description), findsOneWidget);

    // zdvih pera má vlastný slider (predvolene z nastavení = 3 mm)
    final liftSliders = tester
        .widgetList<Slider>(find.byType(Slider))
        .where((slider) => slider.min == RobotProvider.minPenUpHeightMm);
    expect(liftSliders, isNotEmpty);
    expect(liftSliders.first.value, RobotProvider.defaultPenUpHeightMm);
  });

  testWidgets('ImagePrintScreen bez obrázka neodošle nič do fronty',
      (tester) async {
    final provider = await pumpImagePrint(tester);

    await tester.tap(find.text('Connect to the robot first'));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(provider.pendingStrokes, 0);
  });

  testWidgets('ImagePrintScreen invert a zrkadlenie menia nastavenie',
      (tester) async {
    await pumpImagePrint(tester);

    await tester.tap(find.text('Invert (plot the light areas)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mirror vertically'));
    await tester.pumpAndSettle();

    final invert = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'Invert (plot the light areas)'),
    );
    final mirror = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'Mirror vertically'),
    );

    expect(invert.value, isTrue);
    expect(mirror.value, isTrue);
  });

  testWidgets('ImagePrintScreen clear canvas vyprázdni frontu', (tester) async {
    final provider = await pumpImagePrint(tester);

    await tester.tap(find.byTooltip('Clear Canvas'));
    await tester.pumpAndSettle();

    expect(provider.pendingStrokes, 0);
    expect(provider.strokes, isEmpty);
  });
}
