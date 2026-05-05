
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:video_player/video_player.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

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
  bool isListening = false;

  final int SEQ_LEN = 20;

  // ✅ LABELS (MATCH TRAINING)
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

  // ---------------- MIC FIXED ----------------
  void startListening() async {

    bool available = await speech.initialize();

    if (available) {
      setState(() => isListening = true);

      speech.listen(
        localeId: "ur_PK",
        listenFor: Duration(seconds: 5),
        onResult: (res) {
          handleVoice(res.recognizedWords);
        },
      );
    }
  }

  void stopListening() {
    speech.stop();
    setState(() => isListening = false);
  }

  // ---------------- VOICE HANDLER ----------------
  void handleVoice(String text) async {

    for (var key in signMap.keys) {
      if (text.contains(key) || text.contains(signMap[key]!["urdu"]!)) {

        playVideo(signMap[key]!["video"]!);

        await tts.speak("آپ نے $key کا اشارہ دیا ہے");

        return;
      }
    }

    await tts.speak("سمجھ نہیں آیا");
  }

  // ---------------- VIDEO ----------------
  void playVideo(String path) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => VideoScreen(path)),
    );
  }

  // ---------------- PREDICT ----------------
  String predict(List<List<double>> seq) {

    var input = [seq];
    var output = List.generate(1, (_) => List.filled(labels.length, 0.0));

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

      // ⚠️ placeholder landmarks (replace with real MediaPipe later)
      List<double> frame = List.filled(45,20,63);

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

          Text(
            "Detected: $detectedText",
            style: TextStyle(fontSize: 20),
          ),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [

              // 🎤 MIC BUTTON FIXED
              IconButton(
                icon: Icon(
                  isListening ? Icons.mic : Icons.mic_none,
                  color: Colors.green,
                  size: 40,
                ),
                onPressed: () {
                  if (isListening) {
                    stopListening();
                  } else {
                    startListening();
                  }
                },
              ),
            ],
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
    speech.stop();
    super.dispose();
  }
}
