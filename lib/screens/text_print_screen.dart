import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/paper_format.dart';
import '../models/stroke_point.dart';
import '../providers/robot_provider.dart';
import '../services/plot_estimator.dart';
import '../services/plot_transform.dart';
import '../services/text_stroke_generator.dart';
import '../widgets/app_logo.dart';
import '../widgets/paper_format_selector.dart';
import '../widgets/plot_preview.dart';

/// Režim „Text“: napíš text a robot ho vykreslí jednoťahovým fontom.
class TextPrintScreen extends StatefulWidget {
  const TextPrintScreen({super.key});

  @override
  State<TextPrintScreen> createState() => _TextPrintScreenState();
}

class _TextPrintScreenState extends State<TextPrintScreen> {
  final TextEditingController _textController =
      TextEditingController(text: 'Codroid\nS Pen plotter');

  double _fontSizeMm = 12.0;
  double _lineSpacing = 1.6;
  double _marginMm = TextStrokeGenerator.defaultMarginMm;
  TextAlignment _alignment = TextAlignment.left;
  PlotTransform _transform = const PlotTransform();

  /// Formát papiera, pre ktorý je práve vygenerovaný náhľad.
  PaperFormat _paper = kDefaultPaperFormat;

  late TextPlotResult _result;

  @override
  void initState() {
    super.initState();
    _paper = Provider.of<RobotProvider>(context, listen: false).paperFormat;
    _result = _generate();
    _textController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    super.dispose();
  }

  void _onTextChanged() => setState(() => _result = _generate());

  TextPlotResult _generate() => TextStrokeGenerator.generate(
        text: _textController.text,
        fontSizeMm: _fontSizeMm,
        lineSpacing: _lineSpacing,
        alignment: _alignment,
        marginMm: _marginMm,
        paper: _paper,
      );

  /// Ťahy po prípadnom zrkadlení – presne toto ide do fronty aj do náhľadu.
  List<List<StrokePoint>> get _plotStrokes =>
      _transform.applyToStrokes(_result.strokes);

  /// Jemné rozlíšenie podľa veľkosti písma (veľké písmo = hrubšie filtrovanie).
  double get _pointSpacingMm => math.min(1.0, math.max(0.3, _fontSizeMm / 20));

  Future<void> _send() async {
    final provider = Provider.of<RobotProvider>(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);

    if (_plotStrokes.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('⚠️ Nie je čo kresliť – zadaj text.')),
      );
      return;
    }
    if (!provider.status.isConnected) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('🔌 Najprv sa pripoj k robotovi (Connect API).'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    await provider.prepareForPlotting();
    provider.addStrokes(_plotStrokes, minPointSpacingMm: _pointSpacingMm);

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '🖊️ Do fronty pridaných ${_plotStrokes.length} ťahov '
          '(${_result.pointCount} bodov, spacing '
          '${_pointSpacingMm.toStringAsFixed(2)} mm).',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final robotProvider = Provider.of<RobotProvider>(context);

    // Formát papiera sa dá zmeniť aj tu (alebo v Settings) - náhľad sa musí
    // prepočítať, inak by ukazoval staré rozmery papiera.
    if (robotProvider.paperFormat != _paper) {
      _paper = robotProvider.paperFormat;
      _result = _generate();
    }

    final duration =
        PlotEstimator.estimateDuration(_plotStrokes, paper: _paper);

    return Scaffold(
      appBar: AppBar(
        title: const AppBarTitle('Text Plotter'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Clear Canvas',
            onPressed: () {
              robotProvider.clearCanvas();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('🗑️ Canvas vyčistený.')),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _textController,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Text to plot',
                helperText: 'Enter = new line, long lines wrap automatically',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            const Divider(height: 24),
            const PaperFormatSelector(),
            const Divider(height: 24),
            _sliderRow(
              label: 'Letter height',
              value: '${_fontSizeMm.toStringAsFixed(1)} mm',
            ),
            Slider(
              value: _fontSizeMm,
              min: 3,
              max: 40,
              divisions: 74,
              label: '${_fontSizeMm.toStringAsFixed(1)} mm',
              onChanged: (v) => setState(() {
                _fontSizeMm = v;
                _result = _generate();
              }),
            ),
            _sliderRow(
              label: 'Line spacing',
              value: '${_lineSpacing.toStringAsFixed(2)} ×',
            ),
            Slider(
              value: _lineSpacing,
              min: 1.0,
              max: 3.0,
              divisions: 20,
              label: '${_lineSpacing.toStringAsFixed(2)} ×',
              onChanged: (v) => setState(() {
                _lineSpacing = v;
                _result = _generate();
              }),
            ),
            _sliderRow(
              label: 'Paper margin',
              value: '${_marginMm.toStringAsFixed(0)} mm',
            ),
            Slider(
              value: _marginMm,
              min: 0,
              max: 60,
              divisions: 60,
              label: '${_marginMm.toStringAsFixed(0)} mm',
              onChanged: (v) => setState(() {
                _marginMm = v;
                _result = _generate();
              }),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [
                for (final entry in const {
                  TextAlignment.left: 'Left',
                  TextAlignment.center: 'Center',
                  TextAlignment.right: 'Right',
                }.entries)
                  ChoiceChip(
                    label: Text(entry.value),
                    selected: _alignment == entry.key,
                    onSelected: (_) => setState(() {
                      _alignment = entry.key;
                      _result = _generate();
                    }),
                  ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Mirror horizontally'),
              subtitle: const Text('For plotting on the back of the paper'),
              value: _transform.mirrorX,
              onChanged: (v) =>
                  setState(() => _transform = _transform.copyWith(mirrorX: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Mirror vertically'),
              value: _transform.mirrorY,
              onChanged: (v) =>
                  setState(() => _transform = _transform.copyWith(mirrorY: v)),
            ),
            if (_result.overflow)
              _notice(
                icon: Icons.warning_amber,
                color: Colors.orange.shade800,
                text: 'Text je väčší ako papier – zmenši písmo alebo okraje.',
              ),
            if (_result.unsupportedCharacters.isNotEmpty)
              _notice(
                icon: Icons.info_outline,
                color: Colors.blueGrey,
                text: 'Font nepozná znaky: '
                    '${_result.unsupportedCharacters.join(' ')}',
              ),
            const SizedBox(height: 8),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: PlotPreview(
                  strokes: _plotStrokes,
                  paper: _paper,
                  emptyLabel: 'Zadaj text pre náhľad',
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 18,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _stat('Lines', '${_result.lines.length}'),
                _stat('Strokes', '${_plotStrokes.length}'),
                _stat('Points', '${_result.pointCount}'),
                _stat(
                  'Length',
                  '${PlotEstimator.pathLengthMm(_plotStrokes, paper: _paper).toStringAsFixed(0)} mm',
                ),
                _stat('Est. time', PlotEstimator.formatDuration(duration)),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _send,
              icon: const Icon(Icons.play_arrow),
              label: Text(
                robotProvider.status.isConnected
                    ? 'Add to Plot Queue (${_plotStrokes.length} strokes)'
                    : 'Connect to the robot first',
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => setState(() => _result = _generate()),
              icon: const Icon(Icons.refresh),
              label: const Text('Regenerate Preview'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Popisok + hodnota nad sliderom.
  Widget _sliderRow({required String label, required String value}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        Text(value, style: TextStyle(color: Colors.indigo.shade400)),
      ],
    );
  }

  /// Malá štatistika pod náhľadom.
  Widget _stat(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.grey,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
        Text(
          value,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  /// Výstražný pásik (prekročenie papiera, neznáme znaky…).
  Widget _notice({
    required IconData icon,
    required Color color,
    required String text,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(color: color, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
