import 'dart:math' as math;

import '../models/paper_format.dart';
import '../models/stroke_point.dart';

/// Rýchle odhady pre UI: koľko má robot kresliť a ako dlho to potrvá.
///
/// Ide o hrubý odhad (nie simuláciu akcelerácií) – slúži len na to, aby
/// používateľ pred spustením videl, či ide o minútovú alebo hodinovú prácu.
class PlotEstimator {
  PlotEstimator._();

  /// Odhadovaná kresliaca rýchlosť v mm/s (rovnaká, akú používa jog).
  static const double defaultSpeedMmPerSecond = 60.0;

  /// Čas na zdvihnutie/pero a prejazd medzi dvoma ťahmi v sekundách.
  static const double defaultPenLiftSeconds = 0.8;

  /// Počet bodov vo všetkých ťahoch.
  static int pointCount(List<List<StrokePoint>> strokes) {
    var count = 0;
    for (final stroke in strokes) {
      count += stroke.length;
    }
    return count;
  }

  /// Dĺžka všetkých ťahov v mm (normalizované súradnice → mm papiera).
  ///
  /// [paper] určuje rozmery papiera – normalizované súradnice sa násobia
  /// skutočnou šírkou/výškou, takže odhad sedí pre A4, A3, A5 aj 10 × 15.
  static double pathLengthMm(
    List<List<StrokePoint>> strokes, {
    PaperFormat paper = kDefaultPaperFormat,
  }) {
    var total = 0.0;
    for (final stroke in strokes) {
      for (var i = 1; i < stroke.length; i++) {
        final dx = (stroke[i].x - stroke[i - 1].x) * paper.widthMm;
        final dy = (stroke[i].y - stroke[i - 1].y) * paper.heightMm;
        total += math.sqrt(dx * dx + dy * dy);
      }
    }
    return total;
  }

  /// Odhadovaný čas kreslenia.
  static Duration estimateDuration(
    List<List<StrokePoint>> strokes, {
    PaperFormat paper = kDefaultPaperFormat,
    double speedMmPerSecond = defaultSpeedMmPerSecond,
    double penLiftSeconds = defaultPenLiftSeconds,
  }) {
    if (strokes.isEmpty) return Duration.zero;
    final speed =
        speedMmPerSecond <= 0 ? defaultSpeedMmPerSecond : speedMmPerSecond;
    final seconds = pathLengthMm(strokes, paper: paper) / speed +
        strokes.length * penLiftSeconds;
    return Duration(milliseconds: (seconds * 1000).round());
  }

  /// Formátovanie `Duration` pre UI (`1 h 23 min`, `5 min 20 s`, `42 s`).
  static String formatDuration(Duration duration) {
    if (duration.inSeconds < 60) return '${duration.inSeconds} s';
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    if (minutes < 60) return '$minutes min $seconds s';
    final hours = duration.inHours;
    return '$hours h ${minutes % 60} min';
  }
}
