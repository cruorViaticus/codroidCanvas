import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/robot_provider.dart';
import '../services/plot_estimator.dart';

/// Pás s priebehom kreslenia – koľko ťahov z koľkých už robot vykreslil.
///
/// Zdroj pravdy je [RobotProvider] (`plotTotalStrokes`, `plotDoneStrokes`),
/// ktorý plní `StrokeMotionProcessor` po každom dojazdenom balíku `movMulti`.
/// Kým nie je čo kresliť, widget sa vôbec nezobrazí, takže sa dá vložiť
/// doprostred obrazovky bez podmienok.
///
/// Po dojazdení sa pás zmení na „Plot finished“ a ponúkne presun do
/// parkovacej polohy **B** (`RobotProvider.moveToPointB`).
class PlotProgressBar extends StatelessWidget {
  const PlotProgressBar({super.key, this.showParkButton = true});

  /// Po dokončení ponúkni tlačidlo „Move to B“ (parkovacia poloha).
  final bool showParkButton;

  /// `1 stroke` / `5 strokes` – aby text nevyzeral ako strojový preklad.
  String _strokeCount(int count) => count == 1 ? '1 stroke' : '$count strokes';

  /// Doplnkový riadok pod pásom: „2 min left • 136 strokes to go“.
  String _detailText(RobotProvider provider, bool finished) {
    final parts = <String>[];

    final elapsed = provider.plotElapsed;
    final remaining = provider.plotRemainingTime;
    if (finished) {
      if (elapsed != null) {
        parts.add('in ${PlotEstimator.formatDuration(elapsed)}');
      }
    } else if (remaining != null) {
      parts.add('${PlotEstimator.formatDuration(remaining)} left');
    }

    if (!finished && provider.plotRemainingStrokes > 0) {
      parts.add('${_strokeCount(provider.plotRemainingStrokes)} to go');
    }

    return parts.join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<RobotProvider>(context);

    // Žiadna kresba → žiadny pás (0 px, nie prázdny rámik).
    if (!provider.hasPlotJob) return const SizedBox.shrink();

    final total = provider.plotTotalStrokes;
    final done = provider.plotDoneStrokes;
    final finished = provider.isPlotFinished;
    final progress = provider.plotProgress;
    final color = finished ? Colors.green.shade700 : Colors.indigo;

    final detail = _detailText(provider, finished);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                finished ? Icons.check_circle_outline : Icons.draw_outlined,
                color: color,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  finished
                      ? 'Plot finished • ${_strokeCount(total)}'
                      : 'Plotting • $done / ${_strokeCount(total)}',
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (!finished)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(
                    '${(progress * 100).round()} %',
                    style: TextStyle(
                      color: color,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              if (finished && showParkButton)
                TextButton.icon(
                  onPressed: provider.status.isConnected
                      ? () => provider.moveToPointB()
                      : null,
                  icon: const Icon(Icons.flight_land, size: 16),
                  label: const Text('Move to B'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                )
              else if (!finished)
                TextButton(
                  onPressed: () => provider.stopMovement(),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('STOP'),
                ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: color.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          if (detail.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                detail,
                style: TextStyle(
                  color: Colors.blueGrey.shade600,
                  fontSize: 11,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
