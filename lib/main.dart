import 'package:flutter/material.dart';
import 'screens/scan_screen.dart';
import 'services/settings.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Settings.instance.load();
  runApp(const FlyyoungApp());
}

class FlyyoungApp extends StatelessWidget {
  const FlyyoungApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '小市集 · 攤主端',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1a4d2e),
          brightness: Brightness.dark,
        ),
      ),
      home: const ScanScreen(),
    );
  }
}
