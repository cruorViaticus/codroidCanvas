import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:codroid_pen_plotter/providers/robot_provider.dart';
import 'package:codroid_pen_plotter/screens/settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  /// Zobrazí [SettingsScreen] cez push, aby `Navigator.pop` po uložení fungoval.
  Future<RobotProvider> pumpSettings(WidgetTester tester) async {
    // Dostatočne vysoký viewport, aby boli všetky polia viditeľné.
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final provider = RobotProvider();
    await provider.initialized;

    await tester.pumpWidget(
      ChangeNotifierProvider<RobotProvider>.value(
        value: provider,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  ),
                  child: const Text('open settings'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open settings'));
    await tester.pumpAndSettle();

    return provider;
  }

  testWidgets('SettingsScreen zobrazí rýchlosť aj Z korekciu', (tester) async {
    final provider = await pumpSettings(tester);

    expect(find.text('Drawing Speed (TCP)'), findsOneWidget);
    expect(find.text('Paper Height / Z Offset'), findsOneWidget);
    // dva slidery: rýchlosť + Z korekcia
    expect(find.byType(Slider), findsNWidgets(2));
    // náhľad výsledných Z výšok bez korekcie
    expect(
      find.textContaining('Pen up Z: ${provider.penUpNominalZ.toStringAsFixed(1)}'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Pen down Z: ${provider.penDownNominalZ.toStringAsFixed(1)}'),
      findsOneWidget,
    );
  });

  testWidgets('rýchlosť nad 500 mm/s neprejde validáciou', (tester) async {
    final provider = await pumpSettings(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Linear TCP Speed'),
      '900',
    );
    await tester.tap(find.text('Save Parameters'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Range 10'), findsOneWidget);
    expect(provider.linearSpeed, RobotProvider.defaultLinearSpeed);
    // zostávame na obrazovke nastavení
    expect(find.text('Save Parameters'), findsOneWidget);
  });

  testWidgets('uloženie prenesie rýchlosť a Z korekciu do providera',
      (tester) async {
    final provider = await pumpSettings(tester);

    // +10 mm korekcia papiera tlačidlom
    await tester.tap(find.widgetWithText(OutlinedButton, '+10.0 mm'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Pen up Z: 25.0'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Linear TCP Speed'),
      '480',
    );
    await tester.tap(find.text('Save Parameters'));
    await tester.pumpAndSettle();

    expect(provider.linearSpeed, 480.0);
    expect(provider.zOffsetMm, 10.0);
    expect(provider.penUpZ, closeTo(provider.penUpNominalZ + 10.0, 0.001));
    expect(provider.penDownZ, closeTo(provider.penDownNominalZ + 10.0, 0.001));

    // po uložení sa obrazovka zavrie
    expect(find.text('open settings'), findsOneWidget);
  });

  testWidgets('Z korekcia mimo ±30 mm neprejde validáciou', (tester) async {
    final provider = await pumpSettings(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Z Offset'),
      '45',
    );
    await tester.tap(find.text('Save Parameters'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Range ±30'), findsOneWidget);
    expect(provider.zOffsetMm, 0.0);
  });
}
