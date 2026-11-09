import '../models/stroke_point.dart';

/// Zrkadlenie / prevrátenie výkresu pred odoslaním robotovi.
///
/// Hodí sa, keď pero kreslí na papier položený z druhej strany alebo keď je
/// potrebné zrkadliť šablónu. Súradnice sú normalizované (0..1) ako všade
/// inde v appke, takže zrkadlenie stačí prepočítať na papieri.
class PlotTransform {
  final bool mirrorX;
  final bool mirrorY;

  const PlotTransform({this.mirrorX = false, this.mirrorY = false});

  bool get isIdentity => !mirrorX && !mirrorY;

  /// Preklopí jeden bod (v normalizovaných súradniciach).
  StrokePoint apply(StrokePoint point) {
    if (isIdentity) return point;
    return StrokePoint(
      x: mirrorX ? 1.0 - point.x : point.x,
      y: mirrorY ? 1.0 - point.y : point.y,
      pressure: point.pressure,
    );
  }

  List<StrokePoint> applyToStroke(List<StrokePoint> stroke) =>
      isIdentity ? stroke : stroke.map(apply).toList();

  List<List<StrokePoint>> applyToStrokes(List<List<StrokePoint>> strokes) =>
      isIdentity ? strokes : strokes.map(applyToStroke).toList();

  PlotTransform copyWith({bool? mirrorX, bool? mirrorY}) => PlotTransform(
        mirrorX: mirrorX ?? this.mirrorX,
        mirrorY: mirrorY ?? this.mirrorY,
      );

  String get label {
    if (isIdentity) return 'Bez zmeny';
    if (mirrorX && mirrorY) return 'Otočené o 180°';
    return mirrorX ? 'Zrkadlené vodorovne' : 'Zrkadlené zvislo';
  }
}
