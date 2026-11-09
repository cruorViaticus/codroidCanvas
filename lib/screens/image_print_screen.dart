import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/paper_format.dart';
import '../models/stroke_point.dart';
import '../providers/robot_provider.dart';
import '../services/image_stroke_generator.dart';
import '../services/plot_estimator.dart';
import '../services/plot_transform.dart';
import '../widgets/app_logo.dart';
import '../widgets/paper_format_selector.dart';
import '../widgets/plot_preview.dart';

/// Režim „Black & White Image“: vyber obrázok, prahová hodnota ho zmení na
/// čiernobiele riadky (ako ihličková tlačiareň) a robot ich vykreslí.
///
/// Súbor sa vyberá cez `file_picker`, ktorý funguje na webe (dialóg
/// prehliadača) aj na Androide/iOS. Dekódovanie ide cez `dart:ui`, takže
/// nepotrebujeme žiadnu platformovo špecifickú knižnicu.
class ImagePrintScreen extends StatefulWidget {
  const ImagePrintScreen({super.key});

  @override
  State<ImagePrintScreen> createState() => _ImagePrintScreenState();
}

class _ImagePrintScreenState extends State<ImagePrintScreen> {
  Uint8List? _lastBytes;
  String? _fileName;
  GrayImage? _gray;
  ImagePlotResult? _plot;

  bool _loading = false;
  String? _error;

  double _lineSpacingMm = 1.2;
  double _pointSpacingMm = 0.6;
  double _threshold = 0.5;
  double _marginMm = 10.0;
  bool _invert = false;
  PlotTransform _transform = const PlotTransform();

  /// Formát papiera, pre ktorý sú práve prepočítané riadky.
  PaperFormat _paper = kDefaultPaperFormat;

  @override
  void initState() {
    super.initState();
    _paper = Provider.of<RobotProvider>(context, listen: false).paperFormat;
  }

  /// Ťahy pripravené na odoslanie (po prípadnom zrkadlení).
  List<List<StrokePoint>> get _plotStrokes =>
      _transform.applyToStrokes(_plot?.strokes ?? const []);

  /// Prepočíta riadky z už dekódovaného obrázka (bez opätovného načítania).
  ImagePlotResult? _buildPlot() {
    final gray = _gray;
    if (gray == null) return null;
    return ImageStrokeGenerator.toStrokes(
      gray,
      lineSpacingMm: _lineSpacingMm,
      pointSpacingMm: _pointSpacingMm,
      threshold: _threshold,
      invert: _invert,
      marginMm: _marginMm,
      paper: _paper,
    );
  }

  Future<void> _pickAndProcess() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) {
        setState(() => _error = 'Súbor sa nepodarilo načítať (prázdne dáta).');
        return;
      }
      await _decodeBytes(bytes, file.name);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Súbor sa nepodarilo načítať: $e');
      messenger.showSnackBar(
        SnackBar(
          content: Text('⚠️ Súbor sa nepodarilo načítať: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Dekóduje pixely a hneď z nich postaví riadky (scanline algoritmus).
  Future<void> _decodeBytes(Uint8List bytes, String name) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _lastBytes = bytes;
      _fileName = name;
      _loading = true;
      _error = null;
    });

    try {
      final gray = await ImageStrokeGenerator.decode(bytes);
      if (!mounted) return;
      setState(() {
        _gray = gray;
        _plot = _buildPlot();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Obrázok sa nepodarilo spracovať: $e';
      });
      messenger.showSnackBar(
        SnackBar(
          content: Text('⚠️ Obrázok sa nepodarilo spracovať: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Skúsi dekódovanie znova s naposledy načítanými dátami.
  Future<void> _retryDecode() async {
    final bytes = _lastBytes;
    if (bytes == null) return;
    await _decodeBytes(bytes, _fileName ?? 'image');
  }

  Future<void> _send() async {
    final provider = Provider.of<RobotProvider>(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final strokes = _plotStrokes;

    if (strokes.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('⚠️ Najprv vyber obrázok.')),
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
    provider.addStrokes(strokes, minPointSpacingMm: _pointSpacingMm);

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '🖊️ Do fronty pridaných ${strokes.length} ťahov '
          '(${_plot?.pointCount ?? 0} bodov).',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final robotProvider = Provider.of<RobotProvider>(context);

    // Formát papiera sa dá zmeniť aj tu (alebo v Settings) - riadky sa musia
    // prepočítať na nové rozmery, inak by kresba nesedela s papierom.
    if (robotProvider.paperFormat != _paper) {
      _paper = robotProvider.paperFormat;
      _plot = _buildPlot();
    }

    final plot = _plot;
    final duration =
        PlotEstimator.estimateDuration(_plotStrokes, paper: _paper);
    final gray = _gray;

    return Scaffold(
      appBar: AppBar(
        title: const AppBarTitle('B&W Image Plotter'),
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
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _loading ? null : _pickAndProcess,
                    icon: const Icon(Icons.image_outlined),
                    label: const Text('Pick Image'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Colors.indigo,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _fileName ?? 'PNG / JPG / BMP / GIF / WebP',
              style: TextStyle(color: Colors.blueGrey.shade600),
              textAlign: TextAlign.center,
            ),
            if (gray != null)
              Text(
                '${gray.width} × ${gray.height} px • '
                '${plot?.rowCount ?? 0} riadkov • '
                '${_invert ? 'negatív' : 'čierna = kreslí'}',
                style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  children: [
                    Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                    if (_lastBytes != null)
                      TextButton.icon(
                        onPressed: _loading ? null : _retryDecode,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Try again'),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            const Divider(height: 24),
            const PaperFormatSelector(),
            const Divider(height: 24),
            _sliderRow(
              'Line density',
              '${_lineSpacingMm.toStringAsFixed(1)} mm',
            ),
            Slider(
              value: _lineSpacingMm,
              min: 0.4,
              max: 4.0,
              divisions: 36,
              label: '${_lineSpacingMm.toStringAsFixed(1)} mm',
              onChanged: (v) => setState(() {
                _lineSpacingMm = v;
                _plot = _buildPlot();
              }),
            ),
            _sliderRow(
              'Point spacing',
              '${_pointSpacingMm.toStringAsFixed(2)} mm',
            ),
            Slider(
              value: _pointSpacingMm,
              min: 0.2,
              max: 2.0,
              divisions: 36,
              label: '${_pointSpacingMm.toStringAsFixed(2)} mm',
              onChanged: (v) => setState(() {
                _pointSpacingMm = v;
                _plot = _buildPlot();
              }),
            ),
            _sliderRow(
              'Threshold',
              '${(_threshold * 100).toStringAsFixed(0)} %',
            ),
            Slider(
              value: _threshold,
              min: 0.05,
              max: 0.95,
              divisions: 18,
              label: '${(_threshold * 100).toStringAsFixed(0)} %',
              onChanged: (v) => setState(() {
                _threshold = v;
                _plot = _buildPlot();
              }),
            ),
            _sliderRow('Paper margin', '${_marginMm.toStringAsFixed(0)} mm'),
            Slider(
              value: _marginMm,
              min: 0,
              max: 40,
              divisions: 40,
              label: '${_marginMm.toStringAsFixed(0)} mm',
              onChanged: (v) => setState(() {
                _marginMm = v;
                _plot = _buildPlot();
              }),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Invert (plot the light areas)'),
              subtitle: const Text('Useful for white drawings on black'),
              value: _invert,
              onChanged: (v) => setState(() {
                _invert = v;
                _plot = _buildPlot();
              }),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Mirror horizontally'),
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
            if (plot?.truncated ?? false)
              _notice(
                icon: Icons.warning_amber,
                color: Colors.orange.shade800,
                text: 'Obrázok je príliš detailný – kresba bola skrátená '
                    '(limit ${ImageStrokeGenerator.defaultMaxPoints} bodov). '
                    'Zväčši hustotu riadkov alebo bodov.',
              ),
            const SizedBox(height: 8),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: PlotPreview(
                  strokes: _plotStrokes,
                  paper: _paper,
                  busy: _loading,
                  emptyLabel: 'Vyber obrázok pre náhľad',
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 18,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _stat('Strokes', '${_plotStrokes.length}'),
                _stat('Points', '${plot?.pointCount ?? 0}'),
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
          ],
        ),
      ),
    );
  }

  /// Popisok + hodnota nad sliderom.
  Widget _sliderRow(String label, String value) {
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

  /// Výstražný pásik (skrátená kresba…).
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
