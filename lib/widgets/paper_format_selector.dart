import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/paper_format.dart';
import '../providers/robot_provider.dart';

/// Výber formátu papiera (A4 / A3 / A5 / fotopapier 10 × 15).
///
/// Voľba sa ukladá do [RobotProvider] (a do `SharedPreferences`), takže ju
/// zdieľajú všetky režimy – voľná kresba, text aj obrázok. Dlhšia strana
/// papiera leží vždy v smere osi **X** robota, preto sa papier neotáča a
/// canvas/náhľad sa vždy kreslia „na výšku“.
class PaperFormatSelector extends StatelessWidget {
  /// Zobrazí pod chipmi aj rozmery papiera v mm a smer osí.
  final bool showDimensions;

  const PaperFormatSelector({super.key, this.showDimensions = true});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<RobotProvider>(context);
    final selected = provider.paperFormat;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Paper format',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 8),
            Text(
              selected.sizeLabel,
              style: TextStyle(
                color: Colors.indigo.shade400,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final format in PaperFormat.values)
              ChoiceChip(
                label: Text(format.label),
                avatar: format.isPhotoPaper
                    ? const Icon(Icons.photo_size_select_actual_outlined,
                        size: 18)
                    : null,
                selected: selected == format,
                onSelected: (_) => provider.setPaperFormat(format),
              ),
          ],
        ),
        if (showDimensions) ...[
          const SizedBox(height: 6),
          Text(
            '${selected.widthMm.toStringAsFixed(0)} mm (Y) × '
            '${selected.heightMm.toStringAsFixed(0)} mm (X) • '
            'longer side = X axis',
            style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 12),
          ),
        ],
      ],
    );
  }
}
