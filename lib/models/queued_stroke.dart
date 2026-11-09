import 'stroke_point.dart';

/// Jeden ťah čakajúci vo FIFO fronte na vykreslenie robotom.
///
/// Okrem samotných bodov si nesie aj vlastnú hustotu bodov: voľná kresba
/// z S Pen canvasu chce hrubé filtrovanie (rýchlosť), kým text a obrázok
/// potrebujú jemné rozlíšenie, inak sa detaily stratia.
///
/// [penLiftMm] je výška zdvihu pera medzi ťahmi pre tento konkrétny ťah –
/// bodkový pattern potrebuje iný zdvih ako súvislé riadky.
class QueuedStroke {
  /// Body ťahu v normalizovaných súradniciach canvasu (0..1).
  final List<StrokePoint> points;

  /// Minimálna vzdialenosť dvoch bodov dráhy v mm.
  ///
  /// `null` = predvolená hodnota `StrokeMotionProcessor.minPointSpacingMm`
  /// (5 mm – rovnaká ako doteraz pre voľnú kresbu).
  final double? minPointSpacingMm;

  /// Výška zdvihu pera medzi ťahmi v mm (meraná od papiera).
  ///
  /// `null` = predvolený zdvih z nastavení (`RobotProvider.penUpNominalZ`).
  final double? penLiftMm;

  const QueuedStroke(this.points, {this.minPointSpacingMm, this.penLiftMm});

  @override
  String toString() => 'QueuedStroke(${points.length} bodov, '
      'spacing: $minPointSpacingMm mm, lift: $penLiftMm mm)';
}
