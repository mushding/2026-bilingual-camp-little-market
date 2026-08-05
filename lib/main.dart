import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'services/settings.dart';
import 'theme.dart';

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
      title: '2026 雙語營',
      debugShowCheckedModeBanner: false,
      theme: buildIslandTheme(),
      home: const HomeScreen(),
    );
  }
}
