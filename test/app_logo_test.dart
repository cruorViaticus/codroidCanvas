import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:codroid_pen_plotter/widgets/app_logo.dart';

void main() {
  testWidgets('AppLogo sa vykreslí bez pozadia aj s pozadím', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppLogo(size: 30),
                AppLogo(size: 64, background: true, rounded: true),
                AppLogo(
                  size: 48,
                  background: true,
                  rounded: false,
                  contentScale: 0.7,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(AppLogo), findsNWidgets(3));
    expect(find.byType(CustomPaint), findsWidgets);
    // logo má mať veľkosť presne podľa parametra
    expect(tester.getSize(find.byType(AppLogo).first), const Size(30, 30));
  });

  test('AppLogo má prístupný popis', () {
    const logo = AppLogo(size: 24);
    expect(logo.semanticLabel, isNotEmpty);
    expect(logo.size, 24);
    expect(logo.background, isFalse);
  });

  testWidgets('AppBarTitle zobrazí logo aj text', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: AppBarTitle('Codroid S Pen Controller')),
        ),
      ),
    );

    expect(find.text('Codroid S Pen Controller'), findsOneWidget);
    expect(find.byType(AppLogo), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
