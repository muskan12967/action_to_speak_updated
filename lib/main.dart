import 'package:flutter/material.dart';
import 'splash.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ActionToSpeakApp());
}

class ActionToSpeakApp extends StatelessWidget {
  const ActionToSpeakApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Action to Speak',
      home: Splash(),
    );
  }
}
