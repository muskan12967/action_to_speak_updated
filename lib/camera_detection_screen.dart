import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:tflite/tflite.dart';
import 'package:flutter_tts/flutter_tts.dart';

class DetectionScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const DetectionScreen({Key? key, required this.cameras}) : super(key: key);

  @override
  State<DetectionScreen> createState() => _DetectionScreenState();
}

class _DetectionScreenState extends State<DetectionScreen> {
  CameraController? _controller;
  bool _isDetecting = false;

  String detectedText = "";
  FlutterTts tts = FlutterTts();

  @override
  void initState() {
    super.initState();
    initCamera();
    loadModel();
  }

  // 📷 Initialize Camera
  void initCamera() async {
    _controller = CameraController(
      widget.cameras[0],
      ResolutionPreset.medium,
    );

    await _controller!.initialize();

    _controller!.startImageStream((image) {
      if (!_isDetecting) {
        _isDetecting = true;
        runModel(image);
      }
    });

    setState(() {});
  }

  // 🧠 Load TFLite Model
  Future loadModel() async {
    await Tflite.close();

    await Tflite.loadModel(
      model: "assets/model.tflite",
      labels: "assets/labels.txt",
    );
  }

  // 🔍 Run Model on Camera Frame
  void runModel(CameraImage image) async {
    try {
      var recognitions = await Tflite.runModelOnFrame(
        bytesList: image.planes.map((e) => e.bytes).toList(),
        imageHeight: image.height,
        imageWidth: image.width,
        numResults: 1,
        threshold: 0.7,
      );

      if (recognitions != null && recognitions.isNotEmpty) {
        String label = recognitions[0]['label'];

        if (label != detectedText) {
          setState(() {
            detectedText = label;
          });

          speak(label); // 🔊 Voice Output
        }
      }
    } catch (e) {
      print("Error: $e");
    }

    _isDetecting = false;
  }

  // 🔊 Text to Speech
  void speak(String text) async {
    await tts.setLanguage("ur-PK"); // ya "en-US"
    await tts.speak("Ye $text ka sign hai");
  }

  @override
  void dispose() {
    _controller?.dispose();
    Tflite.close();
    tts.stop();
    super.dispose();
  }

  // 🎨 UI
  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text("Sign Detection")),

      body: Stack(
        children: [
          CameraPreview(_controller!),

          // 📝 Text Output
          Positioned(
            bottom: 50,
            left: 20,
            right: 20,
            child: Container(
              padding: EdgeInsets.all(12),
              color: Colors.black54,
              child: Text(
                detectedText.isEmpty
                    ? "Detecting..."
                    : "Detected: $detectedText",
                style: TextStyle(color: Colors.white, fontSize: 20),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
