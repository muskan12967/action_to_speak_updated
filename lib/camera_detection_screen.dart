import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

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
  late Interpreter interpreter;
List sequence = [];

 @override
void initState() {
  super.initState();
  loadModel();   
  initCamera();
  setupTTS();   
}
  Future processImage(CameraImage image) async {

  int width = image.width;
  int height = image.height;

  img.Image converted = img.Image(width: width, height: height);

  final plane = image.planes[0];

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      int pixel = plane.bytes[y * width + x];
      converted.setPixelRgba(x, y, pixel, pixel, pixel, 255);    }
  }

  img.Image resized = img.copyResize(converted, width: 64, height: 64);

  List frame = List.generate(64, (y) =>
    List.generate(64, (x) {
      final p = resized.getPixel(x, y);
      return [
      
  p.r / 255.0,
  p.g / 255.0,
  p.b / 255.0,
];
    })
  );

  return frame;
}
  String runModel(List sequence) {

  var input = [sequence];

  var output = List.generate(1, (_) => List.filled(46, 0.0));

  interpreter.run(input, output);

  int index = output[0].indexOf(
    output[0].reduce((a, b) => a > b ? a : b),
  );

  List<String> labels = [
    "کتاب","دوست","باپ","خاندان","طالب علم",
    "لکھنا","ماں","پڑھنا","گھر"
  ];

  return labels[index];
}
  Future setupTTS() async {
  await flutterTts.setLanguage("ur-PK");   // Urdu
  await flutterTts.setPitch(1.0);
  await flutterTts.setSpeechRate(0.5);
}
  Future loadModel() async {
  interpreter = await Interpreter.fromAsset('model.tflite');
  print("Model Loaded");
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

    controller!.startImageStream((CameraImage image) async{

      

 if (sequence.length >= 20) return;

    var frame = await processImage(image);

    sequence.add(frame);

    if (sequence.length == 20) {
      String result = runModel(sequence);
      sequence.clear();

      if (result != detectedText && mounted) {
        setState(() {
          detectedText = result;
        });
        await flutterTts.speak(result);   
      }
    }
  });
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
