import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/paper_format.dart';
import '../models/stroke_point.dart';
import '../providers/robot_provider.dart';
import '../services/plot_estimator.dart';
import '../services/plot_transform.dart';
import '../services/printed_text_generator.dart';
import '../services/text_stroke_generator.dart';
import '../widgets/app_logo.dart';
import '../widgets/paper_format_selector.dart';
import '../widgets/plot_preview.dart';
import '../widgets/plot_progress_bar.dart';

/// Režim „Text“: napíš text a robot ho vykreslí.
///
/// Dva štýly: *Pen font* (jednoťahový `VectorFont` – každé písmeno je jedna
/// čiara) a *Printed (real font)* ([PrintedTextGenerator] – reálny font
/// rasterizovaný na bitmapu, ktorý pero obkreslí ako obrys alebo vyplní).
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

  /// `true` = tlačí sa reálny font (obrys alebo plná výplň), `false` =
  /// jednoťahový font.
  bool _printed = false;

  /// Ako sa tlačený text kreslí – obrys písmen, alebo plná výplň.
  PrintedTextFill _printedFill = PrintedTextFill.outline;

  /// Hustota výplne (*Solid*) a šírka stopy pera pre tlačený text (mm).
  double _fillDensityMm = PrintedTextGenerator.defaultFillDensityMm;
  double _penWidthMm = RobotProvider.defaultPenWidthMm;

  /// `true`, kým sa rasterizuje tlačený text (počíta sa na pozadí).
  bool _generating = false;

  /// Poradové číslo požiadavky na prepočet – posledný stav vyhráva.
  int _requestId = 0;

  /// `true`, kým beží výpočet; nové požiadavky sa len zapíšu a dobehnú po ňom.
  bool _workerRunning = false;

  /// Doplnený, keď je prepočet hotový (čaká naň odoslanie do fronty).
  Completer<void>? _idle;

  /// Výška zdvihu pera medzi ťahmi (písmenami) v mm nad papierom.
  double _penLiftMm = RobotProvider.defaultPenUpHeightMm;

  /// Formát papiera, pre ktorý je práve vygenerovaný náhľad.
  PaperFormat _paper = kDefaultPaperFormat;

  late TextPlotResult _result;

  @override
  void initState() {
    super.initState();
    final provider = Provider.of<RobotProvider>(context, listen: false);
    _paper = provider.paperFormat;
    // Zdvih začína na hodnote z nastavení – dá sa ale zmeniť len pre tento text.
    _penLiftMm = provider.penUpNominalZ;
    _penWidthMm = provider.penWidthMm;
    _result = _generatePenFont();
    _textController.addListener(_onTextChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Formát papiera sa dá zmeniť aj v Settings – náhľad sa musí prepočítať,
    // inak by ukazoval staré rozmery papiera. Robí sa to až po tomto frame,
    // lebo tlačený text sa generuje asynchrónne a nesmie sa rozbehnúť počas
    // buildu.
    final format =
        Provider.of<RobotProvider>(context, listen: false).paperFormat;
    if (format == _paper) return;
    _paper = format;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _regenerate();
    });
  }

  @override
  void dispose() {
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    super.dispose();
  }

  void _onTextChanged() => _regenerate();

  /// Jednoťahový font – hotový hneď, bez rasterizácie.
  TextPlotResult _generatePenFont() => TextStrokeGenerator.generate(
        text: _textController.text,
        fontSizeMm: _fontSizeMm,
        lineSpacing: _lineSpacing,
        alignment: _alignment,
        marginMm: _marginMm,
        paper: _paper,
      );

  /// Tlačený text reálnym fontom – rasterizácia je asynchrónna.
  Future<TextPlotResult> _generatePrinted() => PrintedTextGenerator.generate(
        text: _textController.text,
        fontSizeMm: _fontSizeMm,
        lineSpacing: _lineSpacing,
        alignment: _alignment,
        marginMm: _marginMm,
        paper: _paper,
        fill: _printedFill,
        fillDensityMm: _fillDensityMm,
        penWidthMm: _penWidthMm,
        pointSpacingMm: _pointSpacingMm,
      );

  /// Prepočíta náhľad; pri tlačenom fonte sa počíta na pozadí.
  void _regenerate() {
    _requestId++;
    _pumpGeneration();
  }

  /// Prepočíta náhľad a **počká**, kým je hotový (pred odoslaním do fronty).
  Future<void> _regenerateAndWait() {
    _requestId++;
    final done = _idle ??= Completer<void>();
    _pumpGeneration();
    return done.future;
  }

  /// Spracuje požiadavky na prepočet – vždy beží len jeden výpočet naraz.
  ///
  /// Tlačený text sa rasterizuje desiatky milisekúnd, takže pri ťahaní
  /// slidera by sa inak rozbehlo niekoľko výpočtov súčasne; tu sa počas
  /// výpočtu zapíše len „treba prepočítať“ a hneď po ňom sa počíta znova
  /// s najnovšími hodnotami.
  Future<void> _pumpGeneration() async {
    if (_workerRunning) return;
    _workerRunning = true;
    try {
      while (true) {
        final requested = _requestId;
        if (!_printed) {
          final result = _generatePenFont();
          if (!mounted) return;
          setState(() {
            _result = result;
            _generating = false;
          });
        } else {
          if (!mounted) return;
          setState(() => _generating = true);
          final result = await _generatePrinted();
          if (!mounted) return;
          setState(() {
            _result = result;
            _generating = false;
          });
        }
        // Ovládače sa medzitým nezmenili → náhľad zodpovedá aktuálnemu stavu.
        if (requested == _requestId) break;
      }
    } finally {
      _workerRunning = false;
      final idle = _idle;
      _idle = null;
      if (idle != null && !idle.isCompleted) idle.complete();
    }
  }

  /// Ťahy po prípadnom zrkadlení – presne toto ide do fronty aj do náhľadu.
  List<List<StrokePoint>> get _plotStrokes =>
      _transform.applyToStrokes(_result.strokes);

  /// Jemné rozlíšenie podľa veľkosti písma (veľké písmo = hrubšie filtrovanie).
  double get _pointSpacingMm => math.min(1.0, math.max(0.3, _fontSizeMm / 20));

  /// Spustí kreslenie textu: pripraví robota (Auto + Power On), zhodí
  /// predchádzajúcu dokončenú kresbu a pošle ťahy do fronty.
  Future<void> _plot() async {
    final provider = Provider.of<RobotProvider>(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);

    // Tlačený text sa počíta na pozadí – do fronty musí ísť presne to, čo je
    // práve v náhľade, takže sa pred odoslaním dopočíta aktuálny stav.
    if (_printed) await _regenerateAndWait();
    if (!mounted) return;

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

    // Keď nič nebeží, stará kresba už nemá čo robiť – progress bar začína od nuly.
    if (!provider.isPlotting) provider.clearCanvas();

    provider.addStrokes(
      _plotStrokes,
      minPointSpacingMm: _pointSpacingMm,
      penLiftMm: _penLiftMm,
    );

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '🖊️ Kreslím ${_plotStrokes.length} ťahov '
          '(${_result.pointCount} bodov, spacing '
          '${_pointSpacingMm.toStringAsFixed(2)} mm, '
          'zdvih ${_penLiftMm.toStringAsFixed(1)} mm).',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final robotProvider = Provider.of<RobotProvider>(context);

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
              onChanged: (v) {
                _fontSizeMm = v;
                _regenerate();
              },
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
              onChanged: (v) {
                _lineSpacing = v;
                _regenerate();
              },
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
              onChanged: (v) {
                _marginMm = v;
                _regenerate();
              },
            ),
            _sliderRow(
              label: 'Pen lift between strokes',
              value: '${_penLiftMm.toStringAsFixed(1)} mm',
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
              'How high the pen rises above the paper between two strokes '
              '(letters). Higher = safer, but every lift is a longer Z move.',
              style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 12),
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
                    onSelected: (_) {
                      _alignment = entry.key;
                      _regenerate();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 4),
            const Divider(height: 24),
            Wrap(
              spacing: 8,
              children: [
                for (final entry in const {
                  false: 'Pen font',
                  true: 'Printed (real font)',
                }.entries)
                  ChoiceChip(
                    label: Text(entry.value),
                    selected: _printed == entry.key,
                    onSelected: (_) {
                      if (_printed == entry.key) return;
                      _printed = entry.key;
                      _regenerate();
                    },
                  ),
              ],
            ),
            Text(
              _printed
                  ? 'The real typeface is rasterised and plotted – either as '
                      'letter outlines or as a solid fill.'
                  : 'One-stroke font – one line per letter, the fastest option.',
              style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 12),
            ),
            if (_printed) ...[
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                children: [
                  for (final entry in const {
                    PrintedTextFill.outline: 'Outline',
                    PrintedTextFill.solid: 'Solid',
                  }.entries)
                    ChoiceChip(
                      label: Text(entry.value),
                      selected: _printedFill == entry.key,
                      onSelected: (_) {
                        if (_printedFill == entry.key) return;
                        _printedFill = entry.key;
                        _regenerate();
                      },
                    ),
                ],
              ),
              _sliderRow(
                label: 'Pen line width',
                value: '${_penWidthMm.toStringAsFixed(2)} mm',
              ),
              Slider(
                value: _penWidthMm.clamp(RobotProvider.minPenWidthMm, 1.0),
                min: RobotProvider.minPenWidthMm,
                max: 1.0,
                divisions: 19, // kroky po 0.05 mm
                label: '${_penWidthMm.toStringAsFixed(2)} mm',
                onChanged: (v) {
                  _penWidthMm = v;
                  _regenerate();
                },
              ),
              Text(
                'How wide the pen draws (0.2 mm = thin liner). Lines closer than '
                'the pen width merge, so the outline spacing follows this value.',
                style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 12),
              ),
              if (_printedFill == PrintedTextFill.solid) ...[
                _sliderRow(
                  label: 'Fill density',
                  value: '${_fillDensityMm.toStringAsFixed(2)} mm',
                ),
                Slider(
                  value: _fillDensityMm,
                  min: 0.4,
                  max: 2.0,
                  divisions: 32,
                  label: '${_fillDensityMm.toStringAsFixed(2)} mm',
                  onChanged: (v) {
                    _fillDensityMm = v;
                    _regenerate();
                  },
                ),
                Text(
                  'Solid letters are filled line by line – a denser fill means '
                  'more points and a slower plot.',
                  style: TextStyle(
                    color: Colors.blueGrey.shade400,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
            const SizedBox(height: 4),
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
            if (_result.truncated)
              _notice(
                icon: Icons.speed,
                color: Colors.deepOrange,
                text: 'Výplň je príliš hustá – zvyšok kresby sa vynechal '
                    '(zväčši Fill density alebo zmenši písmo).',
              ),
            if (_result.overflow)
              _notice(
                icon: Icons.warning_amber,
                color: Colors.orange.shade800,
                text: 'Text je väčší ako papier – zmenši písmo alebo okraje.',
              ),
            if (!_printed && _result.unsupportedCharacters.isNotEmpty)
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
                  penWidthMm: _penWidthMm,
                  busy: _generating,
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
            const PlotProgressBar(),
            FilledButton.icon(
              onPressed: _plot,
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
            OutlinedButton.icon(
              onPressed: _regenerate,
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
