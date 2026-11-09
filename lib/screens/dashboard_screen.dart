import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/robot_provider.dart';
import '../widgets/app_logo.dart';
import '../widgets/plot_progress_bar.dart';
import 'canvas_screen.dart';
import 'image_print_screen.dart';
import 'jogging_screen.dart';
import 'settings_screen.dart';
import 'text_print_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final robotProvider = Provider.of<RobotProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const AppBarTitle('Codroid S Pen Controller'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Connection Card
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Status: ${robotProvider.status.robotMode}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Icon(
                          robotProvider.status.isConnected
                              ? Icons.check_circle
                              : Icons.error,
                          color: robotProvider.status.isConnected
                              ? Colors.green
                              : Colors.red,
                        )
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: robotProvider.isConnecting
                                ? null
                                : () {
                                    if (robotProvider.status.isConnected) {
                                      robotProvider.disconnect();
                                    } else {
                                      robotProvider.connect();
                                    }
                                  },
                            icon: Icon(
                              robotProvider.status.isConnected
                                  ? Icons.power_off
                                  : Icons.power,
                            ),
                            label: Text(
                              robotProvider.status.isConnected
                                  ? 'Disconnect'
                                  : 'Connect API',
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: robotProvider.status.isConnected
                                  ? Colors.red
                                  : Colors.green,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: () async {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    '📡 Testujem sieťové spojenie (TCP Ping)...'),
                                duration: Duration(milliseconds: 800),
                              ),
                            );

                            bool isOnline = await robotProvider.pingNetworkIP();

                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    isOnline
                                        ? '✅ Robot na ${robotProvider.ipAddress} odpovedá na sieti!'
                                        : '❌ Robot na ${robotProvider.ipAddress} je NEDOSTUPNÝ! Skontroluj Wi-Fi.',
                                  ),
                                  backgroundColor:
                                      isOnline ? Colors.green : Colors.red,
                                  duration: const Duration(seconds: 3),
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.network_ping),
                          label: const Text('Ping IP'),
                        )
                      ],
                    )
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Robot Controls Card (Motors & Mode)
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Robot Quick Controls',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const Divider(),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton.icon(
                          onPressed: robotProvider.status.isConnected
                              ? () => robotProvider.setMotorPower(true)
                              : null,
                          icon: const Icon(Icons.bolt, color: Colors.amber),
                          label: const Text('Motors ON'),
                        ),
                        ElevatedButton.icon(
                          onPressed: robotProvider.status.isConnected
                              ? () => robotProvider.setMotorPower(false)
                              : null,
                          icon: const Icon(Icons.power_off),
                          label: const Text('Motors OFF'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey.shade200,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        OutlinedButton(
                          onPressed: robotProvider.status.isConnected
                              ? () => robotProvider.setRobotMode(false)
                              : null,
                          child: const Text('Manual Mode'),
                        ),
                        ElevatedButton(
                          onPressed: robotProvider.status.isConnected
                              ? () => robotProvider.setRobotMode(true)
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Auto Mode'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Live Cartesian Telemetry Card
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Live Coordinates (User Frame 1)',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _coordChip('X', robotProvider.status.cartPosition.x),
                        _coordChip('Y', robotProvider.status.cartPosition.y),
                        _coordChip('Z', robotProvider.status.cartPosition.z),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Aktuálne nastavenie rýchlosti a Z korekcie papiera
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Plotter Settings',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const Divider(),
                    Wrap(
                      spacing: 24,
                      runSpacing: 8,
                      alignment: WrapAlignment.spaceAround,
                      children: [
                        _infoChip('Feed',
                            '${robotProvider.linearSpeed.toStringAsFixed(0)} mm/s'),
                        _infoChip(
                          'Z Offset',
                          '${robotProvider.zOffsetMm >= 0 ? '+' : ''}'
                              '${robotProvider.zOffsetMm.toStringAsFixed(1)} mm',
                        ),
                        _infoChip(
                          'Pen Z (up/down)',
                          '${robotProvider.penUpZ.toStringAsFixed(1)} / '
                              '${robotProvider.penDownZ.toStringAsFixed(1)}',
                        ),
                        _infoChip(
                          'Paper',
                          '${robotProvider.paperFormat.label} '
                              '(${robotProvider.paperFormat.sizeLabel})',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            // Priebeh kreslenia – ostáva viditeľný aj po návrate z inej obrazovky
            const PlotProgressBar(),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: robotProvider.status.isConnected
                        ? () => robotProvider.moveToPointA()
                        : null,
                    icon: const Icon(Icons.home_outlined),
                    label: Text(
                      'Move to A\n'
                      '(${RobotProvider.pointAX.toStringAsFixed(0)}, '
                      '${RobotProvider.pointAY.toStringAsFixed(0)}, pen up)',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: robotProvider.status.isConnected
                        ? () => robotProvider.moveToPointB()
                        : null,
                    icon: const Icon(Icons.flight_land),
                    label: Text(
                      'Move to B\n(${RobotProvider.pointBLabel})',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Navigation Buttons
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CanvasScreen()),
                );
              },
              icon: const Icon(Icons.gesture),
              label: const Text('Open S Pen Canvas'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
            const SizedBox(height: 12),

            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const TextPrintScreen()),
                );
              },
              icon: const Icon(Icons.text_fields),
              label: const Text('Plot Text'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.indigo.shade400,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 12),

            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ImagePrintScreen()),
                );
              },
              icon: const Icon(Icons.image),
              label: const Text('Plot Black & White Image'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.indigo.shade400,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 12),

            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const JoggingScreen()),
                );
              },
              icon: const Icon(Icons.open_with),
              label: const Text('Axis Jogging (X, Y, Z)'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.indigo.shade600,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 12),

            OutlinedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              },
              icon: const Icon(Icons.settings),
              label: const Text('Calibration & Settings'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _coordChip(String label, double val) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.grey,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          val.toStringAsFixed(2),
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  /// Malý textový "chip" pre nastavenia (rýchlosť, Z korekcia…).
  Widget _infoChip(String label, String value) {
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
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
