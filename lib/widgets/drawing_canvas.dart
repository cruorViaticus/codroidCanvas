import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/stroke_point.dart';
import '../providers/robot_provider.dart';

class DrawingCanvas extends StatefulWidget {
  const DrawingCanvas({super.key});

  @override

  State<DrawingCanvas> createState() => _DrawingCanvasState();
}

class _DrawingCanvasState extends State<DrawingCanvas> {
  List<StrokePoint> _currentStroke = [];

  @override

  Widget build(BuildContext context) {
    final robotProvider = Provider.of<RobotProvider>(context);

    return AspectRatio(
      aspectRatio: 210 / 297, // A4 Aspect Ratio matching physical paper
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.blueGrey, width: 2),
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
        ),
        child: Listener(
          onPointerDown: (PointerDownEvent event) {
            final RenderBox box = context.findRenderObject() as RenderBox;
            final localPos = box.globalToLocal(event.position);
            final normalizedX = (localPos.dx / box.size.width).clamp(0.0, 1.0);
            final normalizedY = (localPos.dy / box.size.height).clamp(0.0, 1.0);

            setState(() {
              _currentStroke = [
                StrokePoint(x: normalizedX, y: normalizedY, pressure: event.pressure)
              ];
            });
          },
          onPointerMove: (PointerMoveEvent event) {
            final RenderBox box = context.findRenderObject() as RenderBox;
            final localPos = box.globalToLocal(event.position);
            final normalizedX = (localPos.dx / box.size.width).clamp(0.0, 1.0);
            final normalizedY = (localPos.dy / box.size.height).clamp(0.0, 1.0);

            setState(() {
              _currentStroke.add(
                StrokePoint(x: normalizedX, y: normalizedY, pressure: event.pressure),
              );
            });
          },
          onPointerUp: (_) {
            if (_currentStroke.isNotEmpty) {
              robotProvider.addStroke(List.from(_currentStroke));
              setState(() {
                _currentStroke = [];
              });
            }
          },
          child: CustomPaint(
            painter: _CanvasPainter(
              strokes: robotProvider.strokes,
              currentStroke: _currentStroke,
            ),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }
}

class _CanvasPainter extends CustomPainter {
  final List<List<StrokePoint>> strokes;
  final List<StrokePoint> currentStroke;

  _CanvasPainter({required this.strokes, required this.currentStroke});

  @override

  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.blue.shade900
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3.0;

    void drawPath(List<StrokePoint> points) {
      if (points.length < 2) return;
      for (int i = 0; i < points.length - 1; i++) {
        final p1 = Offset(points[i].x * size.width, points[i].y * size.height);
        final p2 = Offset(points[i + 1].x * size.width, points[i + 1].y * size.height);
        canvas.drawLine(p1, p2, paint);
      }
    }

    for (var stroke in strokes) {
      drawPath(stroke);
    }
    drawPath(currentStroke);
  }

  @override

  bool shouldRepaint(covariant _CanvasPainter oldDelegate) => true;
}