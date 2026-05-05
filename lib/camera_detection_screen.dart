
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:video_player/video_player.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';

class CameraDetectionScreen extends StatefulWidget {
  @override
  State<CameraDetectionScreen> createState() => _CameraDetectionScreenState();
}

class _CameraDetectionScreenState extends State<CameraDetectionScreen> {

  CameraController? controller;
  late Interpreter interpreter;
  late PoseDetector poseDetector;

  FlutterTts tts = FlutterTts();
  stt.SpeechToText speech = stt.SpeechToText();

  bool isCameraOn = false;
  bool isProcessing = false;
  bool isStreamActive = false;

  List<List<double>> sequence = [];

  String detectedText = "";
  String lastResult = "";

  DateTime lastTrigger = DateTime.now();

  final int SEQ_LEN = 20;

  final TextEditingController textController = TextEditingController();

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

  final List<String> labels = [
    "baap","dost","ghar","khandan",
    "kitaab","likhna","maa","parhna","talibeilm"
  ];

  @override
  void initState() {
    super.initState();

    poseDetector = PoseDetector(
      options: PoseDetectorOptions(mode: PoseDetectionMode.stream),
    );

    loadModel();
    initTTS();
  }

  Future initTTS() async {
    await tts.setLanguage("ur-PK");
    await tts.setSpeechRate(0.5);
  }

  Future loadModel() async {
    interpreter = await Interpreter.fromAsset("model.tflite");
  }

  // ================= FRONT CAMERA =================
  Future initCamera() async {

    final cams = await availableCameras();

    final frontCam = cams.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
    );

    controller = CameraController(
      frontCam,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    await controller!.initialize();

    setState(() {});

    if (!isStreamActive) {
      startStream();
    }
  }

  Future toggleCamera() async {

    if (isCameraOn) {
      await controller?.stopImageStream();
      await controller?.dispose();
      controller = null;

      setState(() {
        isCameraOn = false;
        isStreamActive = false;
      });

    } else {
      setState(() => isCameraOn = true);
      await initCamera();
    }
  }

  // ================= FIXED INPUT IMAGE =================
 InputImage inputImageFromCamera(
   CameraImage image, CameraDescription camera) 
 { final plane = image.planes[0]; 
  final inputImage = InputImage.fromBytes
    ( bytes: plane.bytes, 
     metadata: InputImageMetadata( 
       size: Size(image.width.toDouble(),
                  image.height.toDouble()), 
       rotation: InputImageRotationValue.fromRawValue(camera.sensorOrientation)
       ?? 
       InputImageRotation.rotation0deg, 
       format: InputImageFormatValue.fromRawValue(image.format.raw) ?? 
       InputImageFormat.nv21, bytesPerRow: plane.bytesPerRow,
     ), 
    );
  return inputImage;
 }

  // ================= LANDMARKS =================
  Future<List<double>> extractLandmarks(InputImage image) async {

    final poses = await poseDetector.processImage(image);

    if (poses.isEmpty) return List.filled(63, 0.0);

    final pose = poses.first;

    List<double> data = [];

    for (final lm in pose.landmarks.values) {
      data.addAll([lm.x, lm.y, lm.z ?? 0.0]);
    }

    while (data.length < 63) {
      data.add(0.0);
    }

    return data;
  }

  // ================= MODEL =================
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

    if (maxVal < 0.6) return "unknown";

    return labels[idx];
  }

  // ================= STREAM =================
  void startStream() {

    if (controller == null || isStreamActive) return;

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

        final now = DateTime.now();

        if (result != "unknown" &&
            result != lastResult &&
            now.difference(lastTrigger).inMilliseconds > 1200) {

          lastResult = result;
          lastTrigger = now;

          setState(() {
            detectedText = result;
          });

          tts.speak(result);

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => VideoScreen(signMap[result]!),
            ),
          );
        }
      }

      isProcessing = false;
    });

    isStreamActive = true;
  }

  // ================= TEXT INPUT =================
  void handleInput(String text) {

    String input = text.toLowerCase();

    signMap.forEach((key, video) {
      if (input.contains(key)) {

        setState(() => detectedText = key);

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

  // ================= UI =================
  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(title: Text("Final AI Sign System")),

      body: Column(
        children: [

          Expanded(
            child: isCameraOn && controller != null
                ? CameraPreview(controller!)
                : Center(child: Text("Camera OFF")),
          ),

          Text("Detected: $detectedText"),

          Padding(
            padding: EdgeInsets.all(8),
            child: TextField(
              controller: textController,
              decoration: InputDecoration(
                hintText: "Type Roman Urdu",
                border: OutlineInputBorder(),
              ),
              onSubmitted: handleInput,
            ),
          ),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [

              IconButton(
                icon: Icon(
                  isCameraOn ? Icons.videocam : Icons.videocam_off,
                  color: Colors.blue,
                ),
                onPressed: toggleCamera,
              ),

              IconButton(
                icon: Icon(Icons.mic, color: Colors.red),
                onPressed: () async {
                  if (await speech.initialize()) {
                    speech.listen(
                      localeId: "ur_PK",
                      onResult: (res) {
                        handleInput(res.recognizedWords);
                      },
                    );
                  }
                },
              ),
            ],
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

// ================= VIDEO =================
class VideoScreen extends StatefulWidget {
  final String path;
  VideoScreen(this.path);

  @override
  State<VideoScreen> createState() => _VideoScreenState();
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
      backgroundColor: Colors.black,
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
