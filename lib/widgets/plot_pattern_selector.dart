import 'package:flutter/material.dart';

import '../models/plot_pattern.dart';

/// Výber patternu plotra (Auto / Horizontal / Vertical / Diagonal /
/// Diagonal 2 / Cross-hatch / Triple hatch / Dots / Wave / Spiral / Rings /
/// Outline / Sketch).
///
/// Pattern sa neukladá do `SharedPreferences` – je to parameter konkrétnej
/// kresby (rovnako ako hustota riadkov), takže si ho každá obrazovka drží
/// sama. Pod chipmi je vždy vysvetlenie zvoleného patternu a pri `auto` aj
/// pattern, ktorý generátor pre tento obrázok naozaj vybral.
class PlotPatternSelector extends StatelessWidget {
  /// Aktuálne zvolený pattern (môže byť [PlotPattern.auto]).
  final PlotPattern selected;

  /// Pattern, ktorý `auto` vybral pre aktuálny obrázok
  /// (`null` = náhľad ešte neexistuje).
  final PlotPattern? resolved;

  /// Volané po kliknutí na chip.
  final ValueChanged<PlotPattern> onChanged;

  const PlotPatternSelector({
    super.key,
    required this.selected,
    required this.onChanged,
    this.resolved,
  });

  /// Ikona pre jednotlivé patterny (chip v UI).
  static IconData iconFor(PlotPattern pattern) {
    switch (pattern) {
      case PlotPattern.auto:
        return Icons.auto_awesome;
      case PlotPattern.horizontal:
        return Icons.reorder;
      case PlotPattern.vertical:
        return Icons.view_week_outlined;
      case PlotPattern.diagonal:
        return Icons.show_chart;
      case PlotPattern.antiDiagonal:
        return Icons.multiline_chart;
      case PlotPattern.crossHatch:
        return Icons.grid_on;
      case PlotPattern.tripleHatch:
        return Icons.dashboard;
      case PlotPattern.dots:
        return Icons.blur_on;
      case PlotPattern.zigzag:
        return Icons.ssid_chart;
      case PlotPattern.spiral:
        return Icons.rotate_right;
      case PlotPattern.contour:
        return Icons.gesture;
      case PlotPattern.sketch:
        return Icons.draw;
      case PlotPattern.rings:
        return Icons.trip_origin;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Pri `auto` ukážeme, čo generátor pre tento obrázok naozaj vybral.
    final hint = selected.isAutomatic && resolved != null
        ? 'Auto → ${resolved!.label} for this image'
        : selected.description;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Plot pattern',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                hint,
                style: TextStyle(color: Colors.indigo.shade400, fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final pattern in PlotPattern.values)
              ChoiceChip(
                label: Text(pattern.label),
                avatar: Icon(iconFor(pattern), size: 18),
                selected: selected == pattern,
                onSelected: (_) => onChanged(pattern),
              ),
          ],
        ),
      ],
    );
  }
}
