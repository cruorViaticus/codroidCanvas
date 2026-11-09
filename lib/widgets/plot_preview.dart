import 'package:flutter/material.dart';

import '../models/paper_format.dart';
import '../models/stroke_point.dart';

/// Náhľad papiera s vykreslenými ťahmi.
///
/// Vzhľad zámerne kopíruje `DrawingCanvas` (rovnaká farba, hrúbka a rám),
/// aby text/obrázok vyzerali rovnako ako voľná kresba z S Pen. Pomer strán
/// určuje zvolený [PaperFormat], takže A3/A5/10 × 15 vyzerajú na obrazovke
/// rovnako ako papier na stole.
class PlotPreview extends StatelessWidget {
  /// Ťahy v normalizovaných súradniciach (0..1).
  final List<List<StrokePoint>> strokes;

  /// Text zobrazený, keď nie je čo kresliť.
  final String emptyLabel;

  /// Počas generovania sa zobrazí indikátor.
  final bool busy;

  /// Formát papiera – podľa neho sa nastaví pomer strán náhľadu.
  final PaperFormat paper;

  const PlotPreview({
    super.key,
    required this.strokes,
    this.emptyLabel = 'Zatiaľ nič na kreslenie',
    this.busy = false,
    this.paper = kDefaultPaperFormat,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: paper.aspectRatio,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.blueGrey, width: 2),
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (strokes.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    emptyLabel,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.blueGrey.shade300),
                  ),
                ),
              ),
            CustomPaint(painter: _PlotPreviewPainter(strokes)),
            if (busy)
              const ColoredBox(
                color: Colors.white70,
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }
}

class _PlotPreviewPainter extends CustomPainter {
  final List<List<StrokePoint>> strokes;

  _PlotPreviewPainter(this.strokes);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.blue.shade900
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    for (final stroke in strokes) {
      if (stroke.length < 2) continue;
      final path = Path();
      path.moveTo(stroke.first.x * size.width, stroke.first.y * size.height);
      for (var i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].x * size.width, stroke[i].y * size.height);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PlotPreviewPainter oldDelegate) =>
      oldDelegate.strokes != strokes;
}
