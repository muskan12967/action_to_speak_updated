import 'package:flutter/material.dart';
import 'splash.dart';
import 'package:camera/camera.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

late Interpreter interpreter;
CameraController? controller;

// MODEL
Future<void> loadModel() async {
  interpreter = await Interpreter.fromAsset('model.tflite');
  print("Model loaded");
}

// CAMERA
Future<void> startCamera() async {
  final cameras = await availableCameras();

  controller = CameraController(
    cameras[0],
    ResolutionPreset.medium,
  );

  await controller!.initialize();
  print("Camera started");
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(const ActionToSpeakApp());

  // background init (safe for performance)
  
    Future.microtask(() async {
      await loadModel();
      await startCamera();
    });
  }

class ActionToSpeakApp extends StatelessWidget {
  const ActionToSpeakApp({super.key});

  @override
  Widget build(BuildContext context) {
    return  MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Action to Speak',
      home: Splash(),
    );
  }
}
