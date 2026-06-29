// ✅ FINAL CLEAN VERSION

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:hand_landmarker/hand_landmarker.dart';
import 'dart:math';

class CameraDetectionScreen extends StatefulWidget {
  @override
  State<CameraDetectionScreen> createState() => _CameraDetectionScreenState();
}

class _CameraDetectionScreenState extends State<CameraDetectionScreen> {

  CameraController? controller;
  Interpreter? interpreter;
  HandLandmarkerPlugin? plugin;

  FlutterTts tts = FlutterTts();

  bool isCameraOn = false;
  bool isProcessing = false;
  bool isModelLoaded = false;

  String detectedText = "No sign detected";

  List<List<double>> sequence = [];

  final int SEQ_LEN = 25;
  final int FEATURES = 126;

  String lastResult = "";
  DateTime lastTrigger = DateTime.now();

  final labels = ["baap","dost","ghar","khandan","kitaab","likhna","maa","parhna","talibeilm"];

  @override
  void initState() {
    super.initState();
    loadModel();
    initTTS();
    initHand();
  }

  // ✅ INIT HAND LANDMARK
  void initHand() {
    plugin = HandLandmarkerPlugin.create(
      numHands: 2,
      minHandDetectionConfidence: 0.5,
    );
  }

  // ✅ TTS
  Future<void> initTTS() async {
    await tts.setLanguage("ur-PK");
    await tts.setSpeechRate(0.45);
    await tts.awaitSpeakCompletion(true);
  }

  // ✅ LOAD MODEL
  Future<void> loadModel() async {
    interpreter = await Interpreter.fromAsset("assets/model.tflite");

    interpreter!.resizeInputTensor(0, [1, SEQ_LEN, FEATURES]);
    interpreter!.allocateTensors();

    setState(() => isModelLoaded = true);
  }

  // ✅ CAMERA START
  Future<void> startCamera() async {
    final cameras = await availableCameras();
    controller = CameraController(
      cameras.first,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    await controller!.initialize();
    setState(() => isCameraOn = true);

    controller!.startImageStream((image) async {

      if (isProcessing || !isModelLoaded) return;
      isProcessing = true;

      final hands = await plugin!.detect(image, 90);

      processHands(hands);

      isProcessing = false;
    });
  }

  // ✅ PROCESS HANDS
  void processHands(List<Hand> hands) {

    List<double> h0 = List.filled(63, 0);
    List<double> h1 = List.filled(63, 0);

    if (hands.isNotEmpty) h0 = extract(hands[0]);
    if (hands.length > 1) h1 = extract(hands[1]);

    sequence.add([...h0, ...h1]);

    if (sequence.length > SEQ_LEN) sequence.removeAt(0);

    if (sequence.length == SEQ_LEN) {

      final pred = predict(sequence);
      final now = DateTime.now();

      if (pred != "unknown" &&
          pred != lastResult &&
          now.difference(lastTrigger).inMilliseconds > 2000) {

        lastResult = pred;
        lastTrigger = now;

        setState(() => detectedText = pred);

        String msg = "یہ ${pred} کا سائن ہے";

        tts.stop();
        tts.speak(msg);
      }
    }
  }

  // ✅ FEATURE EXTRACTION
  List<double> extract(Hand hand) {
    final baseX = hand.landmarks[0].x;
    final baseY = hand.landmarks[0].y;
    final baseZ = hand.landmarks[0].z;

    List<double> out = [];

    for (var lm in hand.landmarks) {
      out.add(lm.x - baseX);
      out.add(lm.y - baseY);
      out.add(lm.z - baseZ);
    }

    return out;
  }

  // ✅ PREDICTION
  String predict(List<List<double>> seq) {

    final input = [seq];

    final output = [List<double>.filled(labels.length, 0)];

    interpreter!.run(input, output);

    int best = 0;
    double score = output[0][0];

    for (int i = 1; i < labels.length; i++) {
      if (output[0][i] > score) {
        score = output[0][i];
        best = i;
      }
    }

    print("Prediction: ${labels[best]} score=$score");

    return score > 0.6 ? labels[best] : "unknown";
  }

  // ✅ UI
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Sign to Voice")),

      body: Column(
        children: [

          Expanded(
            child: controller != null
                ? CameraPreview(controller!)
                : Center(child: Text("Camera OFF")),
          ),

          Text(
            detectedText,
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),

          SizedBox(height: 10),

          ElevatedButton(
            onPressed: startCamera,
            child: Text("Start Camera"),
          ),

          SizedBox(height: 20),
        ],
      ),
    );
  }
}
