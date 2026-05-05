import 'dart:typed_data';
import 'dart:ui'; // ✅ FIX HERE
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:tflite_flutter/tflite_flutter.dart';
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
  stt.SpeechToText speech = stt.SpeechToText();

  late PoseDetector poseDetector;

  List<List<double>> sequence = [];
  bool isProcessing = false;

  String detectedText = "";
  String lastSpoken = "";

  final int SEQ_LEN = 20;

  final List<String> labels = [
    "baap","dost","ghar","khandan","kitaab",
    "likhna","maa","parhna","talibeilm"
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

    poseDetector = PoseDetector(
      options: PoseDetectorOptions(mode: PoseDetectionMode.stream),
    );

    initCamera();
    loadModel();
    initTTS();
  }

  Future initTTS() async {
    await tts.setLanguage("ur-PK");
  }

  Future loadModel() async {
    interpreter = await Interpreter.fromAsset("model.tflite");
  }

  Future initCamera() async {
    final cams = await availableCameras();

    controller = CameraController(
      cams.first,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    await controller!.initialize();
    startStream();

    setState(() {});
  }

  // ✅ FIXED INPUT IMAGE (NO ERRORS)
  InputImage inputImageFromCamera(CameraImage image, CameraDescription camera) {

    final WriteBuffer allBytes = WriteBuffer();

    for (final plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }

    final bytes = allBytes.done().buffer.asUint8List();

    final rotation =
        InputImageRotationValue.fromRawValue(camera.sensorOrientation) ??
            InputImageRotation.rotation0deg;

    final format = InputImageFormatValue.fromRawValue(image.format.raw) ??
        InputImageFormat.nv21;

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes.first.bytesPerRow,
      ),
    );
  }

  Future<List<double>> extractLandmarks(InputImage inputImage) async {

    final poses = await poseDetector.processImage(inputImage);

    if (poses.isEmpty) {
      return List.filled(63, 0.0);
    }

    final pose = poses.first;

    List<double> data = [];

    pose.landmarks.forEach((_, lm) {
      data.addAll([lm.x, lm.y, lm.z ?? 0.0]);
    });

    while (data.length < 63) {
      data.add(0.0);
    }

    return data;
  }

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

  void startStream() {
    controller!.startImageStream((image) async {

      if (isProcessing) return;
      isProcessing = true;

      final inputImage =
          inputImageFromCamera(image, controller!.description);

      final frame = await extractLandmarks(inputImage);

      sequence.add(frame);

      if (sequence.length > SEQ_LEN) {
        sequence.removeAt(0);
      }

      if (sequence.length == SEQ_LEN) {

        String result = predict(sequence);

        if (result != "unknown") {

          setState(() {
            detectedText = result;
          });

          if (result != lastSpoken) {
            await tts.speak(result);
            lastSpoken = result;

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
            icon: Icon(Icons.mic, size: 40),
            onPressed: () async {

              if (await speech.initialize()) {
                speech.listen(
                  localeId: "ur_PK",
                  onResult: (res) {
                    String text = res.recognizedWords.toLowerCase();

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
                  },
                );
              }
            },
          )
        ],
      ),
    );
  }

  @override
  void dispose() {
    controller?.dispose();
    poseDetector.close();
    interpreter.close();
    tts.stop();
    speech.stop();
    super.dispose();
  }
}

// ---------------- VIDEO ----------------
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
            ? VideoPlayer(controller)
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
