import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:codroid_pen_plotter/models/stroke_point.dart';
import 'package:codroid_pen_plotter/providers/robot_provider.dart';
import 'package:codroid_pen_plotter/screens/text_print_screen.dart';
import 'package:codroid_pen_plotter/widgets/plot_preview.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  /// Zobrazí [TextPrintScreen] s čistým [RobotProvider] (nepripojený robot).
  Future<RobotProvider> pumpTextPrint(WidgetTester tester) async {
    // Vysoký viewport, aby boli viditeľné všetky ovládače aj tlačidlá.
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final provider = RobotProvider();
    await provider.initialized;

    await tester.pumpWidget(
      ChangeNotifierProvider<RobotProvider>.value(
        value: provider,
        child: const MaterialApp(home: TextPrintScreen()),
      ),
    );
    await tester.pumpAndSettle();

    return provider;
  }

  /// Ťahy, ktoré sú práve v náhľade (po zrkadlení).
  List<List<StrokePoint>> previewStrokes(WidgetTester tester) =>
      tester.widget<PlotPreview>(find.byType(PlotPreview)).strokes;

  testWidgets('TextPrintScreen zobrazí ovládače, náhľad a štatistiky',
      (tester) async {
    await pumpTextPrint(tester);

    expect(find.text('Text to plot'), findsOneWidget);
    expect(find.text('Letter height'), findsOneWidget);
    expect(find.text('Line spacing'), findsOneWidget);
    expect(find.text('Paper margin'), findsOneWidget);
    expect(find.text('Left'), findsOneWidget);
    expect(find.text('Center'), findsOneWidget);
    expect(find.text('Right'), findsOneWidget);
    expect(find.text('Mirror horizontally'), findsOneWidget);
    expect(find.text('Mirror vertically'), findsOneWidget);
    expect(find.text('Strokes'), findsOneWidget);
    expect(find.text('Points'), findsOneWidget);
    expect(find.text('Est. time'), findsOneWidget);
    expect(find.text('Regenerate Preview'), findsOneWidget);

    // predvolený text "Codroid\nS Pen plotter" sa hneď vygeneruje
    expect(previewStrokes(tester), isNotEmpty);
  });

  testWidgets('TextPrintScreen bez textu nemá čo kresliť', (tester) async {
    await pumpTextPrint(tester);

    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();

    expect(previewStrokes(tester), isEmpty);
  });

  testWidgets('TextPrintScreen zrkadlenie preklopí ťahy vodorovne',
      (tester) async {
    await pumpTextPrint(tester);

    final before = previewStrokes(tester).first.first;

    await tester.tap(find.text('Mirror horizontally'));
    await tester.pumpAndSettle();

    final after = previewStrokes(tester).first.first;
    expect(after.x, closeTo(1.0 - before.x, 1e-9));
    expect(after.y, closeTo(before.y, 1e-9));
  });

  testWidgets('TextPrintScreen prepína zarovnanie textu', (tester) async {
    await pumpTextPrint(tester);

    await tester.tap(find.text('Center'));
    await tester.pumpAndSettle();

    final center = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'Center'),
    );
    final left = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'Left'),
    );

    expect(center.selected, isTrue);
    expect(left.selected, isFalse);
    expect(previewStrokes(tester), isNotEmpty);
  });

  testWidgets('TextPrintScreen bez pripojenia neodošle ťahy do fronty',
      (tester) async {
    final provider = await pumpTextPrint(tester);

    await tester.tap(find.text('Connect to the robot first'));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(provider.pendingStrokes, 0);
  });

  testWidgets('TextPrintScreen veľký text ohlási prekročenie papiera',
      (tester) async {
    await pumpTextPrint(tester);

    await tester.enterText(find.byType(TextField), 'WWWWWWWWWWWWWWWWWWWW');
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.warning_amber), findsOneWidget);
  });

  /// Počká, kým sa tlačený text dorasterizuje.
  ///
  /// Rasterizácia reálneho fontu beží mimo testovacieho „fake“ času, preto sa
  /// čaká cez [WidgetTester.runAsync] a frame sa pumpuje mimo neho.
  Future<void> waitForPreview(WidgetTester tester) async {
    for (var i = 0; i < 60; i++) {
      if (!tester.widget<PlotPreview>(find.byType(PlotPreview)).busy) return;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
    fail('Tlačený text sa nevygeneroval včas.');
  }

  testWidgets('TextPrintScreen vie prepnúť na tlačený reálny font',
      (tester) async {
    await pumpTextPrint(tester);

    await tester.tap(find.text('Printed (real font)'));
    await tester.pump();
    await waitForPreview(tester);

    expect(find.text('Outline'), findsOneWidget);
    expect(find.text('Solid'), findsOneWidget);
    expect(find.text('Pen line width'), findsOneWidget);
    // hustota výplne sa nastavuje až pri plnej výplni
    expect(find.text('Fill density'), findsNothing);
    expect(previewStrokes(tester), isNotEmpty);
  });

  testWidgets('TextPrintScreen Solid ukáže hustotu výplne', (tester) async {
    await pumpTextPrint(tester);

    await tester.tap(find.text('Printed (real font)'));
    await tester.pump();
    await waitForPreview(tester);

    await tester.tap(find.text('Solid'));
    await tester.pump();
    await waitForPreview(tester);

    expect(find.text('Fill density'), findsOneWidget);
    expect(previewStrokes(tester), isNotEmpty);
  });

  testWidgets('TextPrintScreen sa vráti z tlačeného fontu späť',
      (tester) async {
    await pumpTextPrint(tester);

    final penFont = previewStrokes(tester).length;

    await tester.tap(find.text('Printed (real font)'));
    await tester.pump();
    await waitForPreview(tester);

    await tester.tap(find.text('Pen font'));
    await tester.pump();

    expect(find.text('Outline'), findsNothing);
    expect(previewStrokes(tester), hasLength(penFont));
  });
}
