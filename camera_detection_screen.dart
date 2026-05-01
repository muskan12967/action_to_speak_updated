import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_tts/flutter_tts.dart';

class CameraDetectionScreen extends StatefulWidget {
  @override
  _CameraDetectionScreenState createState() => _CameraDetectionScreenState();
}

class _CameraDetectionScreenState extends State<CameraDetectionScreen> {

  CameraController? controller;
  List<CameraDescription>? cameras;

  String detectedText = "";
  List<String> chatMessages = [];

  FlutterTts flutterTts = FlutterTts();

  @override
  void initState() {
    super.initState();
    initCamera();
  }

  Future<void> initCamera() async {

    cameras = await availableCameras();

    final frontCamera = cameras!.firstWhere(
            (camera) => camera.lensDirection == CameraLensDirection.front);

    controller = CameraController(
      frontCamera,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    await controller!.initialize();

    startDetection();

    if (mounted) {
      setState(() {});
    }
  }

  /// Simulated AI detection (replace with real model)
  bool isDetecting = false;

  void startDetection() {
    if (isDetecting) return;

    isDetecting = true;

    controller!.startImageStream((CameraImage image) {
      String result = detectSign(image);

      if (result != detectedText && mounted) {
        setState(() {
          detectedText = result;
        });
      }
    });
  }

  /// Placeholder for AI model
  String detectSign(CameraImage image) {

    // Later connect TFLite model here

    return "Hello";
  }

  void sendMessage() async {

    if (detectedText.isNotEmpty) {

      setState(() {
        chatMessages.add(detectedText);
      });

      await flutterTts.speak(detectedText);

      detectedText = "";
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {

    if (controller == null || !controller!.value.isInitialized) {
      return Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(

      appBar: AppBar(
        title: Text("Live Sign Detection"),
        backgroundColor: Color(0xFF2563EB),
      ),

      body: Column(
        children: [

          /// CAMERA PREVIEW
          Container(
            height: 300,
            child: CameraPreview(controller!),
          ),

          /// DETECTED TEXT
          Container(
            padding: EdgeInsets.all(10),
            child: Text(
              "Detected: $detectedText",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),

          /// CHAT AREA
          Expanded(
            child: ListView.builder(
              itemCount: chatMessages.length,
              itemBuilder: (context, index) {

                return Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    margin: EdgeInsets.all(10),
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Text(
                      chatMessages[index],
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                );
              },
            ),
          ),

          /// CONTROL BAR
          Container(
            color: Colors.grey[200],
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [

                /// CAMERA ICON
                IconButton(
                  icon: Icon(Icons.camera_alt, color: Colors.blue),
                  onPressed: () {},
                ),

                /// MIC ICON
                IconButton(
                  icon: Icon(Icons.mic, color: Colors.green),
                  onPressed: () {
                    // speech to text can go here
                  },
                ),

                Spacer(),

                /// SEND BUTTON
                IconButton(
                  icon: Icon(Icons.send, color: Colors.blue),
                  onPressed: sendMessage,
                ),

              ],
            ),
          )

        ],
      ),
    );
  }
}