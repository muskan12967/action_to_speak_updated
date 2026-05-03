import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:video_player/video_player.dart';

class CameraDetectionScreen extends StatefulWidget {
  @override
  _CameraDetectionScreenState createState() => _CameraDetectionScreenState();
}

class _CameraDetectionScreenState extends State<CameraDetectionScreen> {

  CameraController? controller;
  List<CameraDescription>? cameras;

  late Interpreter interpreter;
  FlutterTts tts = FlutterTts();
  late stt.SpeechToText speech;

  List sequence = [];
  String detectedText = "";
  String lastSpoken = "";

  bool isProcessing = false;
  bool isVideoPlaying = false;

  int frameCount = 0;

  final int SEQ_LEN = 20;

  // ✅ URDU LABELS (MATCH TRAINING)
  final List<String> labels = [
    'باپ',
    'خاندان',
    'دوست',
    'طالبِ علم',
    'لکھنا',
    'ماں',
    'پڑھنا',
    'کتاب',
    'گھر'
  ];

  // ✅ URDU → VIDEO MAP
  final Map<String, String> signMap = {
    "باپ": "assets/videos/father.mp4",
    "خاندان": "assets/videos/family.mp4",
    "دوست": "assets/videos/friend.mp4",
    "طالبِ علم": "assets/videos/student.mp4",
    "لکھنا": "assets/videos/write.mp4",
    "ماں": "assets/videos/mother.mp4",
    "پڑھنا": "assets/videos/read.mp4",
    "کتاب": "assets/videos/book.mp4",
    "گھر": "assets/videos/home.mp4",
  };

  @override
  void initState() {
    super.initState();

    speech = stt.SpeechToText();

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
    cameras = await availableCameras();

    final cam = cameras!.firstWhere(
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

  // ---------------- FRAME PROCESSING (FIXED SIZE) ----------------
  Future<List> processFrame(CameraImage image) async {

    final plane = image.planes[0];
    int size = 160;

    img.Image frame = img.Image(width: size, height: size);

    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        int pixel = plane.bytes[y * plane.bytesPerRow + x];
        frame.setPixelRgba(x, y, pixel, pixel, pixel, 255);
      }
    }

    return List.generate(size, (y) =>
      List.generate(size, (x) {
        final p = frame.getPixel(x, y);
        return [p.r / 255.0, p.g / 255.0, p.b / 255.0];
      })
    );
  }

  // ---------------- PREDICT ----------------
  String predict(List seq) {

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

    if (maxVal < 0.4) return "unknown";

    return labels[idx];
  }

  // ---------------- STREAM ----------------
  void startStream() {
    controller!.startImageStream((image) async {

      if (isProcessing) return;
      isProcessing = true;

      var frame = await processFrame(image);

      sequence.add(frame);

      if (sequence.length > SEQ_LEN) {
        sequence.removeAt(0);
      }

      frameCount++;

      if (sequence.length == SEQ_LEN && frameCount % 10 == 0) {

        String result = predict(sequence);

        if (result != "unknown" && signMap.containsKey(result)) {

          String video = signMap[result]!;

          if (result != detectedText) {
            setState(() {
              detectedText = result;
            });
          }

          if (result != lastSpoken) {
            await tts.speak(result);
            lastSpoken = result;
          }

          if (!isVideoPlaying) {
            isVideoPlaying = true;

            playVideo(video);

            Future.delayed(Duration(seconds: 2), () {
              isVideoPlaying = false;
            });
          }
        }
      }

      isProcessing = false;
    });
  }

  // ---------------- MIC ----------------
  void startListening() async {

    bool available = await speech.initialize();

    if (available) {
      speech.listen(
        localeId: "ur_PK",
        onResult: (res) {

          setState(() {
            detectedText = res.recognizedWords;
          });

          handleVoice(res.recognizedWords);
        },
      );
    }
  }

  // ---------------- VOICE COMMAND ----------------
  void handleVoice(String text) {

    for (var key in signMap.keys) {

      if (text.contains(key)) {

        playVideo(signMap[key]!);
        tts.speak("یہ $key کا اشارہ ہے");
        return;
      }
    }

    tts.speak("سمجھ نہیں آیا");
  }

  // ---------------- VIDEO ----------------
  void playVideo(String path) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoScreen(path),
      ),
    );
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

          IconButton(
            icon: Icon(Icons.mic, size: 40, color: Colors.green),
            onPressed: startListening,
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
