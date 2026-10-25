import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/robot_provider.dart';

class JoggingScreen extends StatelessWidget {
  const JoggingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final robotProvider = Provider.of<RobotProvider>(context);
    
    // Jogging je povolený, keď je robot pripojený cez API
    final bool isReadyForJog = robotProvider.status.isConnected;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Jogging Control (Tool 1)'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Banner so stavom pripojenia
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isReadyForJog ? Colors.green.shade100 : Colors.orange.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: isReadyForJog ? Colors.green : Colors.orange),
              ),
              child: Row(
                children: [
                  Icon(
                    isReadyForJog ? Icons.check_circle : Icons.warning,
                    color: isReadyForJog ? Colors.green.shade800 : Colors.orange.shade800,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isReadyForJog
                          ? 'Robot Ready (${robotProvider.status.robotMode}) — Hold buttons to Jog Tool 1'
                          : 'Jogging Disabled — Connect to Robot API first!',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isReadyForJog ? Colors.green.shade900 : Colors.orange.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Karta so živými súradnicami
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    const Text(
                      'Current Frame Position (POSCFG Mode 7)',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _coordTile('X', robotProvider.status.x),
                        _coordTile('Y', robotProvider.status.y),
                        _coordTile('Z', robotProvider.status.z),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Mriežka s tlačidlami pre joggovanie
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Y+ Button
                    _jogButton(
                      context: context,
                      label: 'Y+ (Forward)',
                      icon: Icons.keyboard_arrow_up,
                      enabled: isReadyForJog,
                      onPressedStart: () => robotProvider.startTcpJog(2, 1),
                      onPressedEnd: () => robotProvider.stopTcpJog(),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // X- Button
                        _jogButton(
                          context: context,
                          label: 'X-',
                          icon: Icons.keyboard_arrow_left,
                          enabled: isReadyForJog,
                          onPressedStart: () => robotProvider.startTcpJog(1, -1),
                          onPressedEnd: () => robotProvider.stopTcpJog(),
                        ),
                        const SizedBox(width: 20),
                        // Emergency Stop Tlačidlo
                        ElevatedButton(
                          onPressed: () => robotProvider.stopMovement(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            shape: const CircleBorder(),
                            padding: const EdgeInsets.all(24),
                          ),
                          child: const Text('STOP', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 20),
                        // X+ Button
                        _jogButton(
                          context: context,
                          label: 'X+',
                          icon: Icons.keyboard_arrow_right,
                          enabled: isReadyForJog,
                          onPressedStart: () => robotProvider.startTcpJog(1, 1),
                          onPressedEnd: () => robotProvider.stopTcpJog(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Y- Button
                    _jogButton(
                      context: context,
                      label: 'Y- (Backward)',
                      icon: Icons.keyboard_arrow_down,
                      enabled: isReadyForJog,
                      onPressedStart: () => robotProvider.startTcpJog(2, -1),
                      onPressedEnd: () => robotProvider.stopTcpJog(),
                    ),
                    const SizedBox(height: 32),

                    // Ovládanie Z osi (Hore / Dole)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _jogButton(
                          context: context,
                          label: 'Z+ (Up)',
                          icon: Icons.arrow_upward,
                          enabled: isReadyForJog,
                          onPressedStart: () => robotProvider.startTcpJog(3, 1),
                          onPressedEnd: () => robotProvider.stopTcpJog(),
                        ),
                        _jogButton(
                          context: context,
                          label: 'Z- (Down)',
                          icon: Icons.arrow_downward,
                          enabled: isReadyForJog,
                          onPressedStart: () => robotProvider.startTcpJog(3, -1),
                          onPressedEnd: () => robotProvider.stopTcpJog(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _coordTile(String axis, double val) {
    return Column(
      children: [
        Text(axis, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
        Text(val.toStringAsFixed(2), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _jogButton({
    required BuildContext context,
    required String label,
    required IconData icon,
    required bool enabled,
    required VoidCallback onPressedStart,
    required VoidCallback onPressedEnd,
  }) {
    return GestureDetector(
      onTapDown: enabled ? (_) => onPressedStart() : null,
      onTapUp: enabled ? (_) => onPressedEnd() : null,
      onTapCancel: enabled ? () => onPressedEnd() : null,
      child: ElevatedButton.icon(
        onPressed: enabled ? () {} : null, // Reakciu na stlačenie/podržanie rieši GestureDetector
        icon: Icon(icon),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
    );
  }
}