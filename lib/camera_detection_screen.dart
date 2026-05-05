import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:video_player/video_player.dart';
import 'package:google_mlkit_hands/google_mlkit_hands.dart';

class CameraDetectionScreen extends StatefulWidget {
  @override
  _CameraDetectionScreenState createState() => _CameraDetectionScreenState();
}

class _CameraDetectionScreenState extends State<CameraDetectionScreen> {

  CameraController? controller;
  late Interpreter interpreter;
  FlutterTts tts = FlutterTts();
  late stt.SpeechToText speech;

  late HandsDetector handsDetector;

  List<List<double>> sequence = [];

  bool isProcessing = false;
  bool isListening = false;

  String detectedText = "";
  String lastSpoken = "";

  final int SEQ_LEN = 20;

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

    handsDetector = HandsDetector(
      options: HandsDetectorOptions(
        mode: DetectionMode.stream,
        maxHands: 1,
      ),
    );

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
    await tts.setPitch(1.0);
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

  // ---------------- LANDMARKS ----------------
  Future<List<double>> extractLandmarks(InputImage image) async {

    final hands = await handsDetector.processImage(image);

    if (hands.isEmpty) {
      return List.filled(63, 0.0);
    }

    final hand = hands.first;

    List<double> data = [];

    hand.landmarks.forEach((lm) {
      data.addAll([lm.x, lm.y, lm.z ?? 0.0]);
    });

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

  // ---------------- STREAM (REAL TIME FIXED) ----------------
  void startStream() {
    controller!.startImageStream((CameraImage image) async {

      if (isProcessing) return;
      isProcessing = true;

      final inputImage = InputImage.fromBytes(
        bytes: image.planes[0].bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: InputImageRotation.rotation0deg,
          format: InputImageFormat.yuv420,
          bytesPerRow: image.planes[0].bytesPerRow,
        ),
      );

      final frame = await extractLandmarks(inputImage);

      sequence.add(frame);

      if (sequence.length > SEQ_LEN) {
        sequence.removeAt(0);
      }

      if (sequence.length == SEQ_LEN) {

        String result = predict(sequence);

        if (result != "unknown" && signMap.containsKey(result)) {

          String urdu = signMap[result]!["urdu"]!;
          String video = signMap[result]!["video"]!;

          if (result != lastSpoken) {

            await tts.stop();
            await tts.speak(urdu);

            lastSpoken = result;

            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => VideoScreen(video),
              ),
            );
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
      appBar: AppBar(title: Text("Real-Time Sign Detection")),

      body: Column(
        children: [

          Expanded(
            flex: 3,
            child: CameraPreview(controller!),
          ),

          SizedBox(height: 10),

          Text(
            "Detected: $detectedText",
            style: TextStyle(fontSize: 20),
          ),

          IconButton(
            icon: Icon(Icons.mic, color: Colors.green, size: 40),
            onPressed: () async {

              bool ok = await speech.initialize();

              if (ok) {
                speech.listen(
                  localeId: "ur_PK",
                  onResult: (res) {
                    handleVoice(res.recognizedWords);
                  },
                );
              }
            },
          ),
        ],
      ),
    );
  }

  // ---------------- VOICE ----------------
  void handleVoice(String text) {

    signMap.forEach((key, value) {

      if (text.contains(value["urdu"]!)) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => VideoScreen(value["video"]!),
          ),
        );

        tts.speak("یہ $key کا اشارہ ہے");
      }
    });
  }

  @override
  void dispose() {
    controller?.dispose();
    interpreter.close();
    tts.stop();
    handsDetector.close();
    speech.stop();
    super.dispose();
  }
}

// ---------------- VIDEO SCREEN ----------------
class VideoScreen extends StatefulWidget {
  final String path;
  VideoScreen(this.path);

  @override
  _VideoScreenState createState() => _VideoScreenState();
}

class _VideoScreenState extends State<VideoScreen> {

  late VideoPlayerController controller;

  @override
  void initState() {
    super.initState();

    controller = VideoPlayerController.asset(widget.path)
      ..initialize().then((_) {
        controller.play();
        setState(() {});
      });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: controller.value.isInitialized
            ? AspectRatio(
                aspectRatio: controller.value.aspectRatio,
                child: VideoPlayer(controller),
              )
            : CircularProgressIndicator(),
      ),
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}
