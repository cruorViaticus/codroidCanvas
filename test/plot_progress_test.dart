import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:codroid_pen_plotter/models/stroke_point.dart';
import 'package:codroid_pen_plotter/providers/robot_provider.dart';
import 'package:codroid_pen_plotter/widgets/plot_progress_bar.dart';

/// Krátky dvojbodový ťah (stačí na zaradenie do fronty).
List<StrokePoint> _stroke(int index) => [
      StrokePoint(x: 0.10 + index * 0.01, y: 0.10, pressure: 1.0),
      StrokePoint(x: 0.20 + index * 0.01, y: 0.20, pressure: 1.0),
    ];

List<List<StrokePoint>> _strokes(int count) =>
    [for (var i = 0; i < count; i++) _stroke(i)];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Priebeh kreslenia v RobotProvider', () {
    test('pred kresbou nie je čo zobrazovať', () async {
      final provider = RobotProvider();
      await provider.initialized;

      expect(provider.hasPlotJob, isFalse);
      expect(provider.plotTotalStrokes, 0);
      expect(provider.plotProgress, 0.0);
      expect(provider.isPlotFinished, isFalse);
      expect(provider.plotRemainingTime, isNull);
    });

    test('nová úloha začína od nuly, prebytok sa oreže na 100 %', () async {
      final provider = RobotProvider();
      await provider.initialized;

      provider.addStrokes(_strokes(4));

      expect(provider.plotTotalStrokes, 4);
      expect(provider.plotDoneStrokes, 0);
      expect(provider.plotRemainingStrokes, 4);
      expect(provider.plotProgress, 0.0);
      expect(provider.hasPlotJob, isTrue);
      expect(provider.isPlotFinished, isFalse);

      provider.markStrokesPlotted(1);
      expect(provider.plotDoneStrokes, 1);
      expect(provider.plotProgress, closeTo(0.25, 0.0001));
      expect(provider.isPlotFinished, isFalse);

      // controller môže hlásiť viac dokončených balíkov – nad 100 % to nejde
      provider.markStrokesPlotted(10);
      expect(provider.plotDoneStrokes, 4);
      expect(provider.plotProgress, 1.0);
      expect(provider.isPlotFinished, isTrue);
      expect(provider.plotRemainingStrokes, 0);
    });

    test('prázdne ťahy sa do priebehu nepočítajú', () async {
      final provider = RobotProvider();
      await provider.initialized;

      provider.addStrokes([const <StrokePoint>[], _stroke(0)]);

      expect(provider.plotTotalStrokes, 1);
    });

    test('Clear Canvas vynuluje priebeh', () async {
      final provider = RobotProvider();
      await provider.initialized;
      provider.addStrokes(_strokes(2));
      provider.markStrokesPlotted(1);

      provider.clearCanvas();

      expect(provider.hasPlotJob, isFalse);
      expect(provider.plotProgress, 0.0);
      expect(provider.plotElapsed, isNull);
    });

    test('STOP (stopMovement) vynuluje priebeh aj frontu', () async {
      final provider = RobotProvider();
      await provider.initialized;
      provider.addStrokes(_strokes(3));
      provider.markStrokesPlotted(1);

      provider.stopMovement();

      expect(provider.pendingStrokes, 0);
      expect(provider.hasPlotJob, isFalse);
      expect(provider.isPlotting, isFalse);
    });
  });

  group('Widget PlotProgressBar', () {
    Future<RobotProvider> pumpBar(WidgetTester tester) async {
      final provider = RobotProvider();
      await provider.initialized;

      await tester.pumpWidget(
        ChangeNotifierProvider<RobotProvider>.value(
          value: provider,
          child: const MaterialApp(
            home: Scaffold(body: PlotProgressBar()),
          ),
        ),
      );
      await tester.pump();

      return provider;
    }

    testWidgets('kým sa nič nekreslí, pás nie je vidieť', (tester) async {
      await pumpBar(tester);

      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.textContaining('Plotting'), findsNothing);
      expect(find.text('STOP'), findsNothing);
    });

    testWidgets('počas kreslenia ukáže počet ťahov, percentá aj STOP',
        (tester) async {
      final provider = await pumpBar(tester);

      provider.addStrokes(_strokes(2));
      await tester.pump();

      expect(find.text('Plotting • 0 / 2 strokes'), findsOneWidget);
      expect(find.text('0 %'), findsOneWidget);
      expect(find.text('2 strokes to go'), findsOneWidget);
      expect(find.text('STOP'), findsOneWidget);

      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, 0.0);

      provider.markStrokesPlotted(1);
      await tester.pump();

      expect(find.text('Plotting • 1 / 2 strokes'), findsOneWidget);
      expect(find.text('50 %'), findsOneWidget);
      expect(find.textContaining('1 stroke to go'), findsOneWidget);
    });

    testWidgets('po dojazdení ukáže hotovo a ponúkne presun na bod B',
        (tester) async {
      final provider = await pumpBar(tester);

      provider.addStrokes(_strokes(1));
      await tester.pump();
      provider.markStrokesPlotted(1);
      await tester.pump();

      expect(find.text('Plot finished • 1 stroke'), findsOneWidget);
      expect(find.text('Move to B'), findsOneWidget);
      expect(find.text('STOP'), findsNothing);

      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, 1.0);
    });

    testWidgets('STOP v páse vyčistí frontu a pás zmizne', (tester) async {
      final provider = await pumpBar(tester);

      provider.addStrokes(_strokes(2));
      await tester.pump();

      await tester.tap(find.text('STOP'));
      await tester.pump();

      expect(provider.pendingStrokes, 0);
      expect(provider.hasPlotJob, isFalse);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });
  });
}
