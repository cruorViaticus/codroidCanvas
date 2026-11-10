import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/outline_options.dart';
import '../models/paper_format.dart';
import '../models/plot_pattern.dart';
import '../models/plot_start_side.dart';
import '../models/stroke_point.dart';
import '../providers/robot_provider.dart';
import '../services/image_stroke_generator.dart';
import '../services/plot_estimator.dart';
import '../services/plot_transform.dart';
import '../widgets/app_logo.dart';
import '../widgets/paper_format_selector.dart';
import '../widgets/plot_pattern_selector.dart';
import '../widgets/plot_preview.dart';
import '../widgets/plot_progress_bar.dart';

/// Režim „Black & White Image“: vyber obrázok, prahová hodnota ho zmení na
/// čiernobiele ťahy a robot ich vykreslí.
///
/// Pattern (vodorovné riadky, stĺpce, 45° šrafovanie, krížové šrafovanie alebo
/// bodky) sa dá zvoliť; `Auto` nechá generátor vybrať najlacnejší pattern pre
/// konkrétny obrázok.
///
/// Súbor sa vyberá cez `file_picker`, ktorý funguje na webe (dialóg
/// prehliadača), na Androide a rovnako aj na Windows/Linux/macOS. Dekódovanie
/// ide cez `dart:ui`, takže nepotrebujeme žiadnu platformovo špecifickú
/// knižnicu.
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

  /// Šírka stopy pera v mm – tenká linka 0,2 mm (dá sa zmeniť pre túto kresbu).
  double _penWidthMm = RobotProvider.defaultPenWidthMm;

  /// Pattern, ktorým sa obrázok vyplní (`auto` = najlacnejší pre tento obrázok).
  PlotPattern _pattern = PlotPattern.auto;

  /// Nastavenia obrysov (*Outline* / *Sketch*): poradie ťahov, vyhladenie,
  /// krok bodov a najmenší detail. Ostatné patterny ich ignorujú.
  OutlineOptions _outline = const OutlineOptions();

  /// Odkiaľ pero kresbu začne (`top` = horná línia, `bottom` = dolná).
  PlotStartSide _startSide = kDefaultPlotStartSide;

  /// Výška zdvihu pera medzi líniami / bodkami (mm nad papierom).
  double _penLiftMm = RobotProvider.defaultPenUpHeightMm;

  /// Formát papiera, pre ktorý sú práve prepočítané riadky.
  PaperFormat _paper = kDefaultPaperFormat;

  @override
  void initState() {
    super.initState();
    final provider = Provider.of<RobotProvider>(context, listen: false);
    _paper = provider.paperFormat;
    // Zdvih začína na hodnote z nastavení – dá sa ale zmeniť len pre túto kresbu.
    _penLiftMm = provider.penUpNominalZ;
    // Šírka stopy pera (predvolene 0,2 mm) tiež začína v nastaveniach.
    _penWidthMm = provider.penWidthMm;
  }

  /// Ťahy pripravené na odoslanie (po prípadnom zrkadlení).
  List<List<StrokePoint>> get _plotStrokes =>
      _transform.applyToStrokes(_plot?.strokes ?? const []);

  /// Rozostup bodov, ktorý generátor naozaj použije (mm).
  ///
  /// Režim `sketch` má pevnú spodnú hranicu – body bližšie ako
  /// `ImageStrokeGenerator.minSketchStepMm` robot nevie prejsť, preto sa
  /// rozostup v tomto režime nikdy nezmenší pod ňu. Vlastný krok obrysov
  /// ([OutlineOptions.stepMm]) má prednosť pred sliderom „Point spacing“.
  double get _effectivePointSpacingMm {
    final stepMm = _outline.stepMm;
    if (stepMm > 0) {
      return _pattern == PlotPattern.sketch &&
              stepMm < ImageStrokeGenerator.minSketchStepMm
          ? ImageStrokeGenerator.minSketchStepMm
          : stepMm;
    }
    return _pattern == PlotPattern.sketch
        ? ImageStrokeGenerator.sketchStepMmFor(
            pointSpacingMm: _pointSpacingMm,
            penWidthMm: _penWidthMm,
          )
        : _pointSpacingMm;
  }

  /// Krok, ktorý by generátor použil bez vlastného nastavenia obrysov (mm).
  ///
  /// Ukazuje ho UI pri slidri „Outline step“ ako hodnotu `Auto`.
  double get _automaticStepMm => _pattern == PlotPattern.sketch
      ? ImageStrokeGenerator.sketchStepMmFor(
          pointSpacingMm: _pointSpacingMm,
          penWidthMm: _penWidthMm,
        )
      : _pointSpacingMm;

  /// Koľko bodov pripadne na 1 m línie pri aktuálnom rozstupe bodov.
  ///
  /// Je to len informatívny údaj pre UI („hustota“ kresby), samotný generátor
  /// boduje presne podľa `pointSpacingMm` (v režime `sketch` podľa
  /// [_effectivePointSpacingMm]).
  int get _pointsPerMetre => _effectivePointSpacingMm <= 0
      ? 0
      : (1000 / _effectivePointSpacingMm).round();

  /// Koľko bodov z limitu práve prepočítaná kresba spotrebuje.
  ///
  /// Robot má obmedzenú dĺžku fronty (`defaultMaxPoints`), preto sa hodí
  /// vidieť, ako ďaleko od limitu kresba je a či bola orezená.
  String _queuePointsText(ImagePlotResult? plot) {
    if (plot == null) return '';
    const limit = ImageStrokeGenerator.defaultMaxPoints;
    return plot.truncated
        ? ' – drawing cut off at the $limit point limit'
        : ' – ${plot.pointCount} of $limit points';
  }

  /// Prepočíta riadky z už dekódovaného obrázka (bez opätovného načítania).
  ImagePlotResult? _buildPlot() {
    final gray = _gray;
    if (gray == null) return null;
    return ImageStrokeGenerator.toStrokes(
      gray,
      pattern: _pattern,
      lineSpacingMm: _lineSpacingMm,
      pointSpacingMm: _pointSpacingMm,
      threshold: _threshold,
      invert: _invert,
      marginMm: _marginMm,
      penWidthMm: _penWidthMm,
      paper: _paper,
      startSide: _startSide,
      outline: _outline,
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

  /// Spustí kreslenie obrázka: pripraví robota (Auto + Power On), zhodí
  /// predchádzajúcu dokončenú kresbu a pošle ťahy do fronty.
  ///
  /// Priebeh sa zobrazuje v [PlotProgressBar] pod tlačidlami – netreba
  /// prechádzať na inú obrazovku.
  Future<void> _startPlot() async {
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

    // Keď nič nebeží, stará kresba už nemá čo robiť – vyčistíme ju, aby sa
    // ťahy nekopili a progress bar začínal od nuly.
    if (!provider.isPlotting) provider.clearCanvas();

    // Filter v motion procesore nesmie byť hrubší než krok, ktorým generátor
    // body naozaj umiestnil – inak by z obrysu ostali len každé druhé body.
    final spacingMm = _effectivePointSpacingMm < _pointSpacingMm
        ? _effectivePointSpacingMm
        : _pointSpacingMm;

    provider.addStrokes(
      strokes,
      minPointSpacingMm: spacingMm,
      penLiftMm: _penLiftMm,
    );

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '🖊️ Kreslím ${strokes.length} ťahov '
          '(${_plot?.pointCount ?? 0} bodov, '
          '${_plot?.pattern.label ?? _pattern.label}, '
          'zdvih ${_penLiftMm.toStringAsFixed(1)} mm).',
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
                '${plot?.pattern.label ?? _pattern.label} • '
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
            PlotPatternSelector(
              selected: _pattern,
              resolved: plot?.pattern,
              onChanged: (pattern) => setState(() {
                _pattern = pattern;
                _plot = _buildPlot();
              }),
            ),
            const SizedBox(height: 12),
            _startSideRow(),
            const Divider(height: 24),
            _sliderRow(
              'Pen lift between lines / dots',
              '${_penLiftMm.toStringAsFixed(1)} mm',
            ),
            Slider(
              value: _penLiftMm,
              min: RobotProvider.minPenUpHeightMm,
              max: 20,
              divisions: 38,
              label: '${_penLiftMm.toStringAsFixed(1)} mm',
              onChanged: (v) => setState(() => _penLiftMm = v),
            ),
            Text(
              'How high the pen rises above the paper between two lines or '
              'dots. Higher = safer, but every lift is a longer Z move '
              '(higher lifts pay off for the Dots pattern).',
              style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 12),
            ),
            _sliderRow(
              'Pen line width',
              '${_penWidthMm.toStringAsFixed(2)} mm',
            ),
            Slider(
              value: _penWidthMm.clamp(RobotProvider.minPenWidthMm, 1.0),
              min: RobotProvider.minPenWidthMm,
              max: 1.0,
              divisions: 19, // kroky po 0.05 mm
              label: '${_penWidthMm.toStringAsFixed(2)} mm',
              onChanged: (v) => setState(() {
                _penWidthMm = v;
                _plot = _buildPlot();
              }),
            ),
            Text(
              'How wide the pen draws (0.2 mm = thin liner). Lines closer than '
              'the pen width merge, so the density and the gap bridging follow '
              'this value – a thicker pen draws fewer, bolder lines.',
              style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 12),
            ),
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
            Text(
              'Distance between the points the robot receives – the arm draws a '
              'line from one point to the next, so this is also the smallest '
              'step it keeps between two commands. Smaller = curves stay '
              'faithful but the queue grows (limit '
              '${ImageStrokeGenerator.defaultMaxPoints} points); larger = fewer '
              'points, faster plotting and shorter lines.',
              style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 12),
            ),
            Text(
              'Now: ${_effectivePointSpacingMm.toStringAsFixed(2)} mm ≈ '
              '$_pointsPerMetre points per metre of line'
              '${_queuePointsText(plot)}.',
              style: TextStyle(color: Colors.indigo.shade300, fontSize: 12),
            ),
            if (_pattern == PlotPattern.sketch)
              Text(
                'Sketch keeps the points at least '
                '${_effectivePointSpacingMm.toStringAsFixed(2)} mm apart – the '
                'robot cannot follow shorter steps – and skips details smaller '
                'than that.',
                style: TextStyle(color: Colors.orange.shade800, fontSize: 12),
              ),
            if (_pattern.isOutline) _outlineOptions(),
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
                  penWidthMm: _penWidthMm,
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
                _stat('Pen', '${_penWidthMm.toStringAsFixed(2)} mm'),
                _stat(
                  'Length',
                  '${PlotEstimator.pathLengthMm(_plotStrokes, paper: _paper).toStringAsFixed(0)} mm',
                ),
                _stat('Est. time', PlotEstimator.formatDuration(duration)),
              ],
            ),
            const SizedBox(height: 16),
            const PlotProgressBar(),
            FilledButton.icon(
              onPressed: _startPlot,
              icon: const Icon(Icons.play_arrow),
              label: Text(
                robotProvider.status.isConnected
                    ? 'Plot (${_plotStrokes.length} strokes)'
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

  /// Prepínač „odkiaľ začať“ – horná alebo dolná línia kresby.
  ///
  /// Obrázok sa nemení (hore ostáva hore), mení sa len poradie ťahov, takže
  /// pero začne tam, kde práve stojí – pri spodnom okraji papiera je tak
  /// prvý prejazd kratší.
  Widget _startSideRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Start from',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _startSide.description,
                style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final side in PlotStartSide.values)
              ChoiceChip(
                avatar: Icon(
                  side.isBottom
                      ? Icons.vertical_align_bottom
                      : Icons.vertical_align_top,
                  size: 18,
                ),
                label: Text(side.label),
                selected: _startSide == side,
                onSelected: (_) => setState(() {
                  _startSide = side;
                  _plot = _buildPlot();
                }),
              ),
          ],
        ),
      ],
    );
  }

  /// Nastavenia obrysov – viditeľné len pri *Outline* / *Sketch*.
  ///
  /// Tie isté hrany sa dajú prejsť rôzne: poradie ťahov rozhoduje o dĺžke
  /// prejazdov (a práve tie controller odmieta), vyhladenie o počte bodov
  /// a „najmenší detail“ o tom, či pero vôbec klesne k bodke pod rozlíšením
  /// pera.
  Widget _outlineOptions() {
    final stepText = _outline.stepMm > 0
        ? '${_outline.stepMm.toStringAsFixed(2)} mm'
        : 'Auto (${_automaticStepMm.toStringAsFixed(2)} mm)';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        Row(
          children: [
            const Text(
              'Outline options',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Stroke order, smoothing, step and smallest detail',
                style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final order in OutlineOrder.values)
              ChoiceChip(
                label: Text(order.label),
                avatar: Icon(_outlineOrderIcon(order), size: 18),
                selected: _outline.order == order,
                onSelected: (_) => setState(() {
                  _outline = _outline.copyWith(order: order);
                  _plot = _buildPlot();
                }),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          _outline.order.description,
          style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 12),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Start each loop at the closest point'),
          subtitle: const Text('No traverse back along the line it just drew'),
          value: _outline.rotateStart,
          onChanged: (v) => setState(() {
            _outline = _outline.copyWith(rotateStart: v);
            _plot = _buildPlot();
          }),
        ),
        Row(
          children: [
            const Text(
              'Smoothing',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _outline.smoothing.description,
                style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final smoothing in OutlineSmoothing.values)
              ChoiceChip(
                label: Text(smoothing.label),
                selected: _outline.smoothing == smoothing,
                onSelected: (_) => setState(() {
                  _outline = _outline.copyWith(smoothing: smoothing);
                  _plot = _buildPlot();
                }),
              ),
          ],
        ),
        const SizedBox(height: 8),
        _sliderRow('Outline step', stepText),
        Slider(
          value: _outline.stepMm.clamp(0.0, 3.0),
          min: 0,
          max: 3,
          divisions: 30, // kroky po 0.1 mm, 0 = automaticky
          label: stepText,
          onChanged: (v) => setState(() {
            _outline = _outline.copyWith(stepMm: v);
            _plot = _buildPlot();
          }),
        ),
        Text(
          'Distance between the points of the outline. 0 = automatic '
          '(${_automaticStepMm.toStringAsFixed(2)} mm) – and never below '
          '${ImageStrokeGenerator.minSketchStepMm.toStringAsFixed(2)} mm, '
          'because the robot cannot follow shorter steps.',
          style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 12),
        ),
        _sliderRow(
          'Skip details under',
          _outline.minDetailMm > 0
              ? '${_outline.minDetailMm.toStringAsFixed(1)} mm'
              : 'Off',
        ),
        Slider(
          value: _outline.minDetailMm.clamp(0.0, 5.0),
          min: 0,
          max: 5,
          divisions: 50,
          label: '${_outline.minDetailMm.toStringAsFixed(1)} mm',
          onChanged: (v) => setState(() {
            _outline = _outline.copyWith(minDetailMm: v);
            _plot = _buildPlot();
          }),
        ),
        Text(
          'Off keeps every detail. A speck smaller than the pen line is only a '
          'poke into the paper – raising this drops it before it reaches the '
          'robot (fewer pen lifts, fewer warnings).',
          style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 12),
        ),
      ],
    );
  }

  /// Ikona poradia obrysov (chip v UI).
  IconData _outlineOrderIcon(OutlineOrder order) => switch (order) {
        OutlineOrder.asFound => Icons.format_list_numbered,
        OutlineOrder.nearest => Icons.near_me,
        OutlineOrder.nearestFlipped => Icons.swap_horiz,
      };

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
