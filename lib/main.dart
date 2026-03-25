import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/scan_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const PresenceSensorApp());
}

class PresenceSensorApp extends StatelessWidget {
  const PresenceSensorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Presence Sensor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: const ColorScheme.dark(
          primary: Colors.lightBlueAccent,
          surface: Color(0xFF16213E),
        ),
        useMaterial3: true,
      ),
      home: const ScanScreen(),
    );
  }
}
