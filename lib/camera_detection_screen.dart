import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:video_player/video_player.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'dart:typed_data';
import 'package:flutter/foundation.dart'; // 🔥 IMPORTANT

class CameraDetectionScreen extends StatefulWidget {
  @override
  _CameraDetectionScreenState createState() => _CameraDetectionScreenState();
}

class _CameraDetectionScreenState extends State<CameraDetectionScreen> {

  CameraController? controller;
  late Interpreter interpreter;
  FlutterTts tts = FlutterTts();
  late stt.SpeechToText speech;

  late PoseDetector poseDetector;

  List<List<double>> sequence = [];

  String detectedText = "";
  String lastSpoken = "";

  bool isProcessing = false;

  final int SEQ_LEN = 20;

  // ✅ TRAINING LABEL ORDER
  final List<String> labels = [
    "baap",
    "dost",
    "ghar",
    "khandan",
    "kitaab",
    "likhna",
    "maa",
    "parhna",
    "talibeilm",
  ];

  // ✅ MAP
  final Map<String, Map<String, String>> signMap = {
    "baap": {"urdu": "باپ", "video": "assets/videos/father.mp4"},
    "dost": {"urdu": "دوست", "video": "assets/videos/friend.mp4"},
    "ghar": {"urdu": "گھر", "video": "assets/videos/home.mp4"},
    "khandan": {"urdu": "خاندان", "video": "assets/videos/family.mp4"},
    "kitaab": {"urdu": "کتاب", "video": "assets/videos/book.mp4"},
    "likhna": {"urdu": "لکھنا", "video": "assets/videos/write.mp4"},
    "maa": {"urdu": "ماں", "video": "assets/videos/mother.mp4"},
    "parhna": {"urdu": "پڑھنا", "video": "assets/videos/read.mp4"},
    "talibeilm": {"urdu": "طالبِ علم", "video": "assets/videos/student.mp4"},
  };

  @override
  void initState() {
    super.initState();

    speech = stt.SpeechToText();

    poseDetector = PoseDetector(options: PoseDetectorOptions());

    loadModel();
    initCamera();
    initTTS();
  }

  // ---------------- MODEL ----------------
  Future loadModel() async {
    interpreter = await Interpreter.fromAsset('model.tflite');
  }

  // ---------------- TTS ----------------
  Future initTTS() async {
    await tts.setLanguage("ur-PK");
    await tts.setSpeechRate(0.5);
  }

  // ---------------- CAMERA ----------------
  Future initCamera() async {
    final cameras = await availableCameras();

    final cam = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front
    );

    controller = CameraController(
      cam,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    await controller!.initialize();
    startStream();

    setState(() {});
  }
  // ---------------- IMAGE CONVERT ----------------
InputImage inputImageFromCamera(CameraImage image) {

  final bytes = image.planes[0].bytes;

  final inputImage = InputImage.fromBytes(
    bytes: bytes,
    metadata: InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: InputImageRotation.rotation0deg,
      format: InputImageFormat.yuv420,
      bytesPerRow: image.planes[0].bytesPerRow,
    ),
  );

  return inputImage;
}

  // ---------------- LANDMARKS ----------------
 Future<List<double>> extractLandmarks(CameraImage image) async {

  final inputImage = inputImageFromCamera(image); // ✅ USE HERE

  final poses = await poseDetector.processImage(inputImage);

  if (poses.isEmpty) {
    return List.filled(63, 0.0);
  }

  final pose = poses.first;

  final points = [
    pose.landmarks[PoseLandmarkType.leftWrist],
    pose.landmarks[PoseLandmarkType.leftElbow],
    pose.landmarks[PoseLandmarkType.leftShoulder],
  ];

  List<double> data = [];

  for (var p in points) {
    if (p != null) {
      data.addAll([p.x, p.y, 0.0]);
    } else {
      data.addAll([0.0, 0.0, 0.0]);
    }
  }

  while (data.length < 63) {
    data.add(0.0);
  }

  return data;
}
  // ---------------- PREDICT ----------------
  String predict(List<List<double>> seq) {

    var input = [seq];

    var output = List.generate(
      1,
      (_) => List.filled(labels.length, 0.0),
    );

    interpreter.run(input, output);

    int idx = 0;
    double maxVal = output[0][0];

    for (int i = 0; i < output[0].length; i++) {
      if (output[0][i] > maxVal) {
        maxVal = output[0][i];
        idx = i;
      }
    }

    if (maxVal < 0.5) return "unknown";

    return labels[idx];
  }

  // ---------------- STREAM ----------------
  void startStream() {
    controller!.startImageStream((image) async {

      if (isProcessing) return;
      isProcessing = true;

      var frame = await extractLandmarks(image);

      sequence.add(frame);

      if (sequence.length > SEQ_LEN) {
        sequence.removeAt(0);
      }

      if (sequence.length == SEQ_LEN) {

        String result = predict(sequence);

        if (result != "unknown" && signMap.containsKey(result)) {

          String urdu = signMap[result]!["urdu"]!;

          if (result != lastSpoken) {
            await tts.speak(urdu);
            lastSpoken = result;
          }

          setState(() {
            detectedText = urdu;
          });
        }
      }

      isProcessing = false;
    });
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {

    if (controller == null || !controller!.value.isInitialized) {
      return Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: Text("Sign AI Assistant")),
      body: Column(
        children: [

          Expanded(
            flex: 3,
            child: CameraPreview(controller!),
          ),

          Padding(
            padding: EdgeInsets.all(10),
            child: Text(
              "Detected: $detectedText",
              style: TextStyle(fontSize: 20),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    controller?.dispose();
    interpreter.close();
    tts.stop();
    poseDetector.close();
    super.dispose();
  }
}
