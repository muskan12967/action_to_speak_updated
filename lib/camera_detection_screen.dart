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

  final int SEQ_LEN = 20;

  /// 🔥 ALL SIGNS MAP (SCALABLE)
 final Map<String, Map<String, String>> signMap = {
  "father": {
    "urdu": "باپ",
    "video": "assets/videos/father.mp4"
  },
  "family": {
    "urdu": "خاندان",
    "video": "assets/videos/family.mp4"
  },
  "friend": {
    "urdu": "دوست",
    "video": "assets/videos/friend.mp4"
  },
  "student": {
    "urdu": "طالبِ علم",
    "video": "assets/videos/student.mp4"
  },
  "write": {
    "urdu": "لکھنا",
    "video": "assets/videos/write.mp4"
  },
  "mother": {
    "urdu": "ماں",
    "video": "assets/videos/mother.mp4"
  },
  "read": {
    "urdu": "پڑھنا",
    "video": "assets/videos/read.mp4"
  },
  "book": {
    "urdu": "کتاب",
    "video": "assets/videos/book.mp4"
  },
  "home": {
    "urdu": "گھر",
    "video": "assets/videos/home.mp4"
  },
};
  late List<String> labels;

  @override
  void initState() {
    super.initState();
    speech = stt.SpeechToText();
    labels = signMap.keys.toList();

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

  // ---------------- FRAME PROCESS ----------------
  Future<List> processFrame(CameraImage image) async {

    final plane = image.planes[0];

    img.Image frame = img.Image(width: 64, height: 64);

    for (int y = 0; y < 64; y++) {
      for (int x = 0; x < 64; x++) {
        int pixel = plane.bytes[y * plane.bytesPerRow + x];
        frame.setPixelRgba(x, y, pixel, pixel, pixel, 255);
      }
    }

    return List.generate(64, (y) =>
      List.generate(64, (x) {
        final p = frame.getPixel(x, y);
        return [p.r/255.0, p.g/255.0, p.b/255.0];
      })
    );
  }

  // ---------------- MODEL PREDICT ----------------
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

    return labels[idx];
  }

  // ---------------- CAMERA STREAM ----------------
  void startStream() {
    controller!.startImageStream((image) async {

      if (isProcessing) return;
      isProcessing = true;

      var frame = await processFrame(image);

      sequence.add(frame);
      if (sequence.length > SEQ_LEN) sequence.removeAt(0);

     if (sequence.length == SEQ_LEN) {

  String result = predict(sequence);

  if (signMap.containsKey(result)) {
    playVideo(signMap[result]!["video"]!);
  }
}
        if (result != detectedText) {
          setState(() => detectedText = result);

          /// 🔊 Voice
          if (result != lastSpoken) {
            await tts.speak(result);
            lastSpoken = result;
          }

          /// 🎥 Play video
          playVideo(signMap[result]!["video"]!);
          playVideo(signMap[key]!["video"]!);
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

          String text = res.recognizedWords;
          setState(() => detectedText = text);

          handleVoice(text);
        },
      );
    }
  }

  // ---------------- VOICE COMMAND ----------------
  void handleVoice(String text) {

    for (var key in signMap.keys) {
      if (text.contains(key)) {

        playVideo(signMap[key]!["video"]!);
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

          Expanded(flex: 3, child: CameraPreview(controller!)),

          Text("Detected: $detectedText", style: TextStyle(fontSize: 20)),

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
