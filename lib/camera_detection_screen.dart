import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:video_player/video_player.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';

class CameraDetectionScreen extends StatefulWidget {
  @override
  _CameraDetectionScreenState createState() => _CameraDetectionScreenState();
}

class _CameraDetectionScreenState extends State<CameraDetectionScreen> {

  CameraController? controller;

  late PoseDetector poseDetector;
  late Interpreter interpreter;

  FlutterTts tts = FlutterTts();
  stt.SpeechToText speech = stt.SpeechToText();

  bool isProcessing = false;
  bool isListening = false;

  String detectedText = "";
  String lastResult = "";

  List<List<double>> sequence = [];
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

  final Map<String, String> signMap = {
    "baap": "assets/videos/father.mp4",
    "dost": "assets/videos/friend.mp4",
    "ghar": "assets/videos/home.mp4",
    "khandan": "assets/videos/family.mp4",
    "kitaab": "assets/videos/book.mp4",
    "likhna": "assets/videos/write.mp4",
    "maa": "assets/videos/mother.mp4",
    "parhna": "assets/videos/read.mp4",
    "talibeilm": "assets/videos/student.mp4",
  };

  @override
  void initState() {
    super.initState();
    initTTS();
    loadModel();
    initPose();
    initCamera();
  }

  // ---------------- MODEL ----------------
  Future loadModel() async {
    interpreter = await Interpreter.fromAsset('model.tflite');
  }

  // ---------------- POSE (MEDIAPIPE FIX) ----------------
  void initPose() {
    poseDetector = PoseDetector(
      options: PoseDetectorOptions(
        mode: PoseDetectionMode.stream,
      ),
    );
  }

  // ---------------- TTS ----------------
  Future initTTS() async {
    await tts.setLanguage("ur-PK");
    await tts.setSpeechRate(0.5);
  }

  // ---------------- CAMERA ----------------
  Future initCamera() async {

    final cams = await availableCameras();

    controller = CameraController(
      cams.first,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    await controller!.initialize();
    setState(() {});

    startStream();
  }

  // ---------------- INPUT IMAGE FIX ----------------
  InputImage inputImageFromCamera(CameraImage image) {

    final WriteBuffer allBytes = WriteBuffer();

    for (final plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }

    final bytes = allBytes.done().buffer.asUint8List();

    final Size imageSize =
        Size(image.width.toDouble(), image.height.toDouble());

    final imageRotation = InputImageRotation.rotation0deg;

    final inputImageFormat =
        InputImageFormatValue.fromRawValue(image.format.raw) ??
            InputImageFormat.nv21;

    final planeData = image.planes.map(
      (plane) {
        return InputImagePlaneMetadata(
          bytesPerRow: plane.bytesPerRow,
          height: plane.height,
          width: plane.width,
        );
      },
    ).toList();

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: imageSize,
        rotation: imageRotation,
        format: inputImageFormat,
        bytesPerRow: image.planes[0].bytesPerRow,
      ),
    );
  }

  // ---------------- LANDMARK EXTRACTION ----------------
  Future<List<double>> extractLandmarks(InputImage image) async {

    final poses = await poseDetector.processImage(image);

    if (poses.isEmpty) {
      return List.filled(63, 0.0);
    }

    final pose = poses.first;

    List<double> data = [];

    pose.landmarks.forEach((type, landmark) {
      data.add(landmark.x);
      data.add(landmark.y);
      data.add(landmark.z ?? 0.0);
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

  // ---------------- REAL TIME STREAM ----------------
  void startStream() {

    controller!.startImageStream((CameraImage image) async {

      if (isProcessing) return;
      isProcessing = true;

      final inputImage = inputImageFromCamera(image);

      final frame = await extractLandmarks(inputImage);

      sequence.add(frame);

      if (sequence.length > SEQ_LEN) {
        sequence.removeAt(0);
      }

      if (sequence.length == SEQ_LEN) {

        String result = predict(sequence);

        if (result != "unknown" && result != lastResult) {

          lastResult = result;

          setState(() {
            detectedText = result;
          });

          await tts.speak(result);

          if (signMap.containsKey(result)) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => VideoScreen(signMap[result]!),
              ),
            );
          }
        }
      }

      isProcessing = false;
    });
  }

  // ---------------- MIC ----------------
  void toggleMic() async {

    if (!isListening) {

      bool ok = await speech.initialize();

      if (ok) {
        setState(() => isListening = true);

        speech.listen(
          localeId: "ur_PK",
          onResult: (res) {
            handleVoice(res.recognizedWords.toLowerCase());
          },
        );
      }

    } else {
      speech.stop();
      setState(() => isListening = false);
    }
  }

  // ---------------- VOICE ----------------
  void handleVoice(String text) {

    signMap.forEach((key, video) {

      if (text.contains(key)) {

        tts.speak("یہ $key کا اشارہ ہے");

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => VideoScreen(video),
          ),
        );
      }
    });
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {

    if (controller == null || !controller!.value.isInitialized) {
      return Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: Text("MediaPipe Sign Detection")),

      body: Column(
        children: [

          Expanded(child: CameraPreview(controller!)),

          Text(
            "Detected: $detectedText",
            style: TextStyle(fontSize: 20),
          ),

          IconButton(
            icon: Icon(
              isListening ? Icons.mic : Icons.mic_none,
              color: isListening ? Colors.red : Colors.green,
              size: 40,
            ),
            onPressed: toggleMic,
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    controller?.dispose();
    poseDetector.close();
    interpreter.close();
    speech.stop();
    tts.stop();
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
        setState(() {});
        controller.play();
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
