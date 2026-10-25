import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/robot_provider.dart';
import 'screens/dashboard_screen.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => RobotProvider(),
      child: const CodroidPlotterApp(),
    ),
  );
}

class CodroidPlotterApp extends StatelessWidget {
  const CodroidPlotterApp({super.key});

  @override

  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Codroid S Pen Plotter',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const DashboardScreen(),
    );
  }
}