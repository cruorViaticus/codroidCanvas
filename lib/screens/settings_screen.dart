import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/robot_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override

  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _ipController;
  late TextEditingController _speedController;

  @override

  void initState() {
    super.initState();
    final provider = Provider.of<RobotProvider>(context, listen: false);
    _ipController = TextEditingController(text: provider.ipAddress);
    _speedController = TextEditingController(text: provider.linearSpeed.toString());
  }

  @override

  void dispose() {
    _ipController.dispose();
    _speedController.dispose();
    super.dispose();
  }

  @override

  Widget build(BuildContext context) {
    final provider = Provider.of<RobotProvider>(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Robot Calibration Settings')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _ipController,
                decoration: const InputDecoration(
                  labelText: 'Robot IP Address',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.network_check),
                ),
                validator: (val) => val == null || val.isEmpty ? 'Enter valid IP' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _speedController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Linear TCP Speed (mm/s)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.speed),
                ),
                validator: (val) => val == null || double.tryParse(val) == null ? 'Enter number' : null,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {
                  if (_formKey.currentState!.validate()) {
                    provider.setIpAddress(_ipController.text);
                    provider.linearSpeed = double.parse(_speedController.text);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Settings Saved to SharedPreferences!')),
                    );
                    Navigator.pop(context);
                  }
                },
                icon: const Icon(Icons.save),
                label: const Text('Save Parameters'),
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              )
            ],
          ),
        ),
      ),
    );
  }
}