import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:codroid_pen_plotter/models/queued_stroke.dart';
import 'package:codroid_pen_plotter/models/stroke_point.dart';
import 'package:codroid_pen_plotter/providers/robot_provider.dart';
import 'package:codroid_pen_plotter/services/stroke_motion_processor.dart';

/// Procesor, ktorý balíky neposiela robotovi, len si ich zapamätá.
class _CapturingProcessor extends StrokeMotionProcessor {
  final List<List<Map<String, dynamic>>> packets = [];

  _CapturingProcessor(super.provider);

  @override
  Future<bool> sendPacket(List<Map<String, dynamic>> points) async {
    packets.add(List<Map<String, dynamic>>.from(points));
    return true;
  }
}

double _z(Map<String, dynamic> point) =>
    ((point['target']['cpos'] as Map)['z'] as num).toDouble();

List<StrokePoint> _stroke() => [
      StrokePoint(x: 0.10, y: 0.10, pressure: 1.0),
      StrokePoint(x: 0.20, y: 0.10, pressure: 1.0),
      StrokePoint(x: 0.20, y: 0.20, pressure: 1.0),
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('RobotProvider.penUpZFor', () {
    test('bez vlastného zdvihu platí hodnota z nastavení', () async {
      final provider = RobotProvider();
      await provider.initialized;
      provider.penUpNominalZ = 4.0;
      provider.zOffsetMm = 2.5;

      expect(provider.penUpZFor(null), closeTo(provider.penUpZ, 0.001));
      expect(provider.penUpZ, closeTo(6.5, 0.001));
    });

    test('vlastný zdvih sa meria od papiera (od penDownZ)', () async {
      final provider = RobotProvider();
      await provider.initialized;
      provider.zOffsetMm = 10.0;

      expect(provider.penDownZ, 10.0);
      expect(provider.penUpZFor(8.0), closeTo(provider.penDownZ + 8.0, 0.001));
    });

    test('zdvih je orezaný na 1 – 50 mm', () async {
      final provider = RobotProvider();
      await provider.initialized;

      expect(
        provider.penUpZFor(0.1),
        closeTo(provider.penDownZ + RobotProvider.minPenUpHeightMm, 0.001),
      );
      expect(
        provider.penUpZFor(500.0),
        closeTo(provider.penDownZ + RobotProvider.maxPenUpHeightMm, 0.001),
      );
    });
  });

  group('Zdvih pera v balíkoch movMulti', () {
    test('plotStroke(penLiftMm) dvíha pero na zadanú výšku', () async {
      final provider = RobotProvider();
      await provider.initialized;
      final processor = _CapturingProcessor(provider);

      await processor.plotStroke(_stroke(), penLiftMm: 8.0);

      final packet = processor.packets.single;
      // nájazd vo výške zdvihu, klesnutie na papier, zdvih na konci
      expect(_z(packet.first), closeTo(provider.penDownZ + 8.0, 0.001));
      expect(_z(packet[1]), closeTo(provider.penDownZ, 0.001));
      expect(_z(packet.last), closeTo(provider.penDownZ + 8.0, 0.001));
    });

    test('bez penLiftMm ostáva zdvih z nastavení', () async {
      final provider = RobotProvider();
      await provider.initialized;
      provider.penUpNominalZ = 6.0;
      final processor = _CapturingProcessor(provider);

      await processor.plotStroke(_stroke());

      expect(_z(processor.packets.single.first), closeTo(6.0, 0.001));
      expect(_z(processor.packets.single.last), closeTo(6.0, 0.001));
    });

    test('QueuedStroke si pamätá vlastný zdvih', () {
      final job = QueuedStroke(
        _stroke(),
        minPointSpacingMm: 0.4,
        penLiftMm: 12.0,
      );

      expect(job.penLiftMm, 12.0);
      expect(job.minPointSpacingMm, 0.4);
      expect(job.toString(), contains('12.0'));
      expect(QueuedStroke(_stroke()).penLiftMm, isNull);
    });

    test('addStrokes prenesie zdvih do fronty', () async {
      final provider = RobotProvider();
      await provider.initialized;

      provider.addStrokes(
        [_stroke(), _stroke()],
        minPointSpacingMm: 0.5,
        penLiftMm: 9.0,
      );

      expect(provider.pendingStrokes, 2);
      expect(provider.strokes, hasLength(2));
    });
  });
}
