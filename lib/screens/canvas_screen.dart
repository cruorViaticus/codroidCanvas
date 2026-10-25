import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/stroke_point.dart';
import '../providers/robot_provider.dart';

class CanvasScreen extends StatefulWidget {
  const CanvasScreen({super.key});

  @override
  State<CanvasScreen> createState() => _CanvasScreenState();
}

class _CanvasScreenState extends State<CanvasScreen> {
  final GlobalKey _paperKey = GlobalKey();
  List<StrokePoint> _currentStroke = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final robotProvider = Provider.of<RobotProvider>(context, listen: false);
      if (robotProvider.status.isConnected) {
        robotProvider.moveToCanvasHome();
      }
    });
  }

  StrokePoint? _getNormalizedPoint(Offset globalPosition, double pressure) {
    final RenderBox? renderBox =
        _paperKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return null;

    final localPos = renderBox.globalToLocal(globalPosition);

    if (localPos.dx < 0 ||
        localPos.dy < 0 ||
        localPos.dx > renderBox.size.width ||
        localPos.dy > renderBox.size.height) {
      return null;
    }

    final normX = (localPos.dx / renderBox.size.width).clamp(0.0, 1.0);
    final normY = (localPos.dy / renderBox.size.height).clamp(0.0, 1.0);

    return StrokePoint(
      x: normX,
      y: normY,
      pressure: pressure > 0 ? pressure : 0.5,
    );
  }

  @override
  Widget build(BuildContext context) {
    final robotProvider = Provider.of<RobotProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('S Pen Drawing Canvas'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Clear Canvas',
            onPressed: () {
              robotProvider.clearCanvas();
              setState(() {
                _currentStroke.clear();
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Status bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.grey.shade200,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      'Strokes: ${robotProvider.strokes.length}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    if (robotProvider.isProcessingQueue) ...[
                      const SizedBox(width: 8),
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ],
                  ],
                ),
                Text(
                  robotProvider.status.isConnected
                      ? 'Connected (${robotProvider.status.robotMode})'
                      : 'Disconnected',
                  style: TextStyle(
                    color: robotProvider.status.isConnected
                        ? Colors.green.shade800
                        : Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          // Canvas A4 paper
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: AspectRatio(
                  aspectRatio: 210 / 297,
                  child: Container(
                    key: _paperKey,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.indigo, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.15),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: (event) {
                        final point = _getNormalizedPoint(
                            event.position, event.pressure);
                        if (point != null) {
                          setState(() {
                            _currentStroke = [point];
                          });
                        }
                      },
                      onPointerMove: (event) {
                        final point = _getNormalizedPoint(
                            event.position, event.pressure);
                        if (point != null) {
                          setState(() {
                            _currentStroke.add(point);
                          });
                        }
                      },
                      onPointerUp: (_) {
                        if (_currentStroke.isNotEmpty) {
                          robotProvider.addStroke(List.from(_currentStroke));
                          setState(() {
                            _currentStroke.clear();
                          });
                        }
                      },
                      child: CustomPaint(
                        painter: CanvasPainter(
                          strokes: robotProvider.strokes,
                          currentStroke: _currentStroke,
                        ),
                        child: Container(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Test API Move Buttons A & B
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: robotProvider.status.isConnected
                        ? () => robotProvider.moveToPoint(50.0, 100.0, 200.0,
                            a: -180.0, b: 0.0, c: 90.0)
                        : null,
                    icon: const Icon(Icons.navigation),
                    label: const Text('Move to A\n(50, 100, 200)',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: robotProvider.status.isConnected
                        ? () => robotProvider.moveToPoint(100.0, 100.0, 200.0,
                            a: -180.0, b: 0.0, c: 90.0)
                        : null,
                    icon: const Icon(Icons.navigation),
                    label: const Text('Move to B\n(100, 100, 200)',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepOrange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Emergency Stop Button
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  robotProvider.stopMovement();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('🛑 Emergency Stop Odoslaný & Fronta vyčistená!'),
                      backgroundColor: Colors.red,
                    ),
                  );
                },
                icon: const Icon(Icons.warning_amber),
                label: const Text('E-STOP / STOP MOVEMENT'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CanvasPainter extends CustomPainter {
  final List<List<StrokePoint>> strokes;
  final List<StrokePoint> currentStroke;

  CanvasPainter({required this.strokes, required this.currentStroke});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.indigo.shade900
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (var stroke in strokes) {
      if (stroke.length < 2) {
        if (stroke.length == 1) {
          canvas.drawCircle(
            Offset(stroke.first.x * size.width, stroke.first.y * size.height),
            3.0,
            paint..style = PaintingStyle.fill,
          );
          paint.style = PaintingStyle.stroke;
        }
        continue;
      }
      for (int i = 0; i < stroke.length - 1; i++) {
        final p1 = Offset(stroke[i].x * size.width, stroke[i].y * size.height);
        final p2 =
            Offset(stroke[i + 1].x * size.width, stroke[i + 1].y * size.height);

        paint.strokeWidth = (stroke[i].pressure * 5.0).clamp(2.0, 8.0);
        canvas.drawLine(p1, p2, paint);
      }
    }

    if (currentStroke.length >= 2) {
      for (int i = 0; i < currentStroke.length - 1; i++) {
        final p1 = Offset(
            currentStroke[i].x * size.width, currentStroke[i].y * size.height);
        final p2 = Offset(currentStroke[i + 1].x * size.width,
            currentStroke[i + 1].y * size.height);

        paint.strokeWidth = (currentStroke[i].pressure * 5.0).clamp(2.0, 8.0);
        canvas.drawLine(p1, p2, paint);
      }
    } else if (currentStroke.length == 1) {
      canvas.drawCircle(
        Offset(currentStroke.first.x * size.width,
            currentStroke.first.y * size.height),
        3.0,
        paint..style = PaintingStyle.fill,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CanvasPainter oldDelegate) => true;
}