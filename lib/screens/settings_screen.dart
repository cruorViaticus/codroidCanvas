import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/robot_provider.dart';
import '../widgets/app_logo.dart';
import '../widgets/paper_format_selector.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _ipController;
  late TextEditingController _speedController;
  late TextEditingController _offsetController;

  // Lokálne (neuložené) hodnoty – slider ich drží v zhode s textovým poľom.
  double _speed = RobotProvider.defaultLinearSpeed;
  double _zOffset = 0.0;
  double _penUp = RobotProvider.defaultPenUpHeightMm;
  double _blend = RobotProvider.defaultBlendDistanceMm;

  @override
  void initState() {
    super.initState();
    final provider = Provider.of<RobotProvider>(context, listen: false);
    _ipController = TextEditingController(text: provider.ipAddress);
    _speed = provider.linearSpeed;
    _zOffset = provider.zOffsetMm;
    _penUp = provider.penUpNominalZ;
    _blend = provider.blendDistanceMm;
    _speedController = TextEditingController(text: _speed.toStringAsFixed(0));
    _offsetController = TextEditingController(text: _formatOffset(_zOffset));
  }

  @override
  void dispose() {
    _ipController.dispose();
    _speedController.dispose();
    _offsetController.dispose();
    super.dispose();
  }

  /// Znáša desatinnú čiarku aj bodku.
  static double? _parseNumber(String? raw) =>
      double.tryParse((raw ?? '').trim().replaceAll(',', '.'));

  static String _formatOffset(double value) =>
      '${value >= 0 ? '+' : ''}${value.toStringAsFixed(1)}';

  void _onSpeedSlider(double value) {
    setState(() {
      _speed = value;
      _speedController.text = value.toStringAsFixed(0);
    });
  }

  void _onSpeedText(String value) {
    final parsed = _parseNumber(value);
    if (parsed != null) {
      setState(() => _speed = parsed
          .clamp(RobotProvider.minLinearSpeed, RobotProvider.maxLinearSpeed)
          .toDouble());
    }
  }

  void _onOffsetSlider(double value) {
    setState(() {
      _zOffset = value;
      _offsetController.text = _formatOffset(value);
    });
  }

  void _onOffsetText(String value) {
    final parsed = _parseNumber(value);
    if (parsed != null) {
      setState(() => _zOffset = parsed
          .clamp(-RobotProvider.maxZOffsetMm, RobotProvider.maxZOffsetMm)
          .toDouble());
    }
  }

  void _nudgeOffset(double delta) {
    final next = (_zOffset + delta)
        .clamp(-RobotProvider.maxZOffsetMm, RobotProvider.maxZOffsetMm)
        .toDouble();
    setState(() {
      _zOffset = next;
      _offsetController.text = _formatOffset(next);
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final provider = Provider.of<RobotProvider>(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final speed = _parseNumber(_speedController.text)!;
    final offset = _parseNumber(_offsetController.text)!;

    await provider.setIpAddress(_ipController.text.trim());
    await provider.setLinearSpeed(speed);
    await provider.setZOffset(offset);
    await provider.setPenUpHeight(_penUp);
    await provider.setBlendDistance(_blend);

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Saved • Speed ${provider.linearSpeed.toStringAsFixed(0)} mm/s • '
          'Z offset ${_formatOffset(provider.zOffsetMm)} mm '
          '(pen up ${provider.penUpZ.toStringAsFixed(1)} / '
          'down ${provider.penDownZ.toStringAsFixed(1)}) • '
          'lift ${provider.penUpNominalZ.toStringAsFixed(1)} mm • '
          'blend ${provider.blendDistanceMm.toStringAsFixed(1)} mm',
        ),
      ),
    );
    navigator.pop();
  }

  /// Skúšobný pohyb pera nahor/nadol s práve nastavenou korekciou.
  Future<void> _testPenHeight(bool down) async {
    final provider = Provider.of<RobotProvider>(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);

    // Aby test odpovedal tomu, čo je na slidery, najprv korekciu uložíme.
    await provider.setZOffset(_zOffset);
    final ok = await provider.movePenToHeight(down: down);

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Moving pen ${down ? 'DOWN' : 'UP'} to Z = '
                  '${(down ? provider.penDownZ : provider.penUpZ).toStringAsFixed(1)} mm'
              : 'Test skipped – connect the robot and wait until it is idle',
        ),
        backgroundColor: ok ? Colors.indigo : Colors.orange,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<RobotProvider>(context);
    final bool canTest = provider.status.isConnected;

    final double effectiveUpZ = _penUp + _zOffset;
    final double effectiveDownZ = provider.penDownNominalZ + _zOffset;

    // Praktický rozsah slidera (uložiť sa dá aj viac, ale 20 mm je dosť).
    const double maxLiftSlider = 20.0;

    return Scaffold(
      appBar: AppBar(
        title: const AppBarTitle('Robot Calibration Settings'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              // ---------- CONNECTION ----------
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Connection',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _ipController,
                        decoration: const InputDecoration(
                          labelText: 'Robot IP Address',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.network_check),
                        ),
                        validator: (val) => val == null || val.isEmpty
                            ? 'Enter valid IP'
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ---------- PAPER FORMAT ----------
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const PaperFormatSelector(),
                      const SizedBox(height: 10),
                      Text(
                        'Saved immediately and used by every plot mode. '
                        'The longer side of the sheet always lies along the '
                        'robot X axis, so the paper never has to be rotated.',
                        style: TextStyle(
                          color: Colors.blueGrey.shade400,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ---------- SPEED ----------
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Drawing Speed (TCP)',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(
                        'Robot limit is '
                        '${RobotProvider.maxLinearSpeed.toStringAsFixed(0)} mm/s. '
                        'Applied to every movl / movMulti point.',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade700),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.speed, color: Colors.indigo),
                          Expanded(
                            child: Slider(
                              value: _speed.clamp(RobotProvider.minLinearSpeed,
                                  RobotProvider.maxLinearSpeed),
                              min: RobotProvider.minLinearSpeed,
                              max: RobotProvider.maxLinearSpeed,
                              divisions: 98, // kroky po 5 mm/s
                              label: '${_speed.toStringAsFixed(0)} mm/s',
                              onChanged: _onSpeedSlider,
                            ),
                          ),
                        ],
                      ),
                      TextFormField(
                        controller: _speedController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Linear TCP Speed',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.speed),
                          suffixText: 'mm/s',
                        ),
                        onChanged: _onSpeedText,
                        validator: (val) {
                          final parsed = _parseNumber(val);
                          if (parsed == null) return 'Enter number';
                          if (parsed < RobotProvider.minLinearSpeed ||
                              parsed > RobotProvider.maxLinearSpeed) {
                            return 'Range ${RobotProvider.minLinearSpeed.toStringAsFixed(0)}'
                                ' – ${RobotProvider.maxLinearSpeed.toStringAsFixed(0)} mm/s';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ---------- Z OFFSET (PAPER HEIGHT) ----------
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Paper Height / Z Offset',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(
                        'Shifts the whole pen path up or down by up to '
                        '${RobotProvider.maxZOffsetMm.toStringAsFixed(0)} mm '
                        'when the paper or table is higher / lower.',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade700),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.height, color: Colors.indigo),
                          Expanded(
                            child: Slider(
                              value: _zOffset.clamp(-RobotProvider.maxZOffsetMm,
                                  RobotProvider.maxZOffsetMm),
                              min: -RobotProvider.maxZOffsetMm,
                              max: RobotProvider.maxZOffsetMm,
                              divisions: 120, // kroky po 0.5 mm
                              label: '${_formatOffset(_zOffset)} mm',
                              onChanged: _onOffsetSlider,
                            ),
                          ),
                        ],
                      ),
                      TextFormField(
                        controller: _offsetController,
                        keyboardType: const TextInputType.numberWithOptions(
                            signed: true, decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Z Offset',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.height),
                          suffixText: 'mm',
                          helperText:
                              'Positive = pen path higher, negative = lower',
                        ),
                        onChanged: _onOffsetText,
                        validator: (val) {
                          final parsed = _parseNumber(val);
                          if (parsed == null) return 'Enter number';
                          if (parsed.abs() > RobotProvider.maxZOffsetMm) {
                            return 'Range ±${RobotProvider.maxZOffsetMm.toStringAsFixed(0)} mm';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final step in const [-10.0, -1.0, 1.0, 10.0])
                            OutlinedButton(
                              onPressed: () => _nudgeOffset(step),
                              child: Text('${_formatOffset(step)} mm'),
                            ),
                        ],
                      ),
                      const Divider(height: 24),
                      Text(
                        'Pen up Z: ${effectiveUpZ.toStringAsFixed(1)} mm   •   '
                        'Pen down Z: ${effectiveDownZ.toStringAsFixed(1)} mm',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed:
                                  canTest ? () => _testPenHeight(false) : null,
                              icon: const Icon(Icons.arrow_upward),
                              label: const Text('Test Pen UP'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed:
                                  canTest ? () => _testPenHeight(true) : null,
                              icon: const Icon(Icons.arrow_downward),
                              label: const Text('Test Pen DOWN'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        canTest
                            ? 'Tip: jog the pen near the paper, then use '
                                'Test Pen DOWN and adjust the offset by ±1 mm.'
                            : 'Connect the robot to enable the pen height test.',
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ---------- PEN LIFT & BLENDING ----------
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Pen Lift & Blending (speed)',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(
                        'Lower lift + blending = much faster plotting: the arm '
                        'no longer stops at every point or raises the pen high '
                        'between strokes.',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade700),
                      ),
                      const SizedBox(height: 12),

                      // --- Pen lift ---
                      Row(
                        children: [
                          const Icon(Icons.vertical_align_top,
                              color: Colors.indigo),
                          Expanded(
                            child: Slider(
                              value: _penUp.clamp(
                                  RobotProvider.minPenUpHeightMm, maxLiftSlider),
                              min: RobotProvider.minPenUpHeightMm,
                              max: maxLiftSlider,
                              divisions: 19, // kroky po 1 mm
                              label: '${_penUp.toStringAsFixed(1)} mm',
                              onChanged: (value) =>
                                  setState(() => _penUp = value),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        'Pen lift between strokes: '
                        '${_penUp.toStringAsFixed(1)} mm '
                        '(recommended 3 mm – pen only leaves the paper)',
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 12),

                      // --- Blending ---
                      Row(
                        children: [
                          const Icon(Icons.gesture, color: Colors.indigo),
                          Expanded(
                            child: Slider(
                              value: _blend.clamp(
                                  0.0, RobotProvider.maxBlendDistanceMm),
                              min: 0.0,
                              max: RobotProvider.maxBlendDistanceMm,
                              divisions: 20, // kroky po 1 mm
                              label: '${_blend.toStringAsFixed(0)} mm',
                              onChanged: (value) =>
                                  setState(() => _blend = value),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        'Corner blending radius: '
                        '${_blend.toStringAsFixed(1)} mm '
                        '(0 = exact corners / slowest, '
                        '${RobotProvider.maxBlendDistanceMm.toStringAsFixed(0)}'
                        ' mm = smoothest)',
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Blending is sent as zone RELATIVE (zdis) on every '
                        'path point; only the pen-down contact point and the '
                        'end of each packet stay FINE.',
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              ElevatedButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save),
                label: const Text('Save Parameters'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
