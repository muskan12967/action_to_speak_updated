import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:video_player/video_player.dart';
import 'dart:math';
import 'dart:typed_data';
import 'package:image/image.dart' as img; // For image processing

class CameraDetectionScreen extends StatefulWidget {
  @override
  State<CameraDetectionScreen> createState() => _CameraDetectionScreenState();
}

class _CameraDetectionScreenState extends State<CameraDetectionScreen> {
  CameraController? controller;
  Interpreter? interpreter;

  FlutterTts tts = FlutterTts();
  stt.SpeechToText speech = stt.SpeechToText();

  bool isCameraOn = false;
  bool isProcessing = false;
  bool isStreamActive = false;
  bool isModelLoaded = false;
  bool isListening = false;

  List<List<double>> sequence = [];
  String detectedText = "";
  String lastResult = "";
  String modelStatus = "Loading model...";
  String micStatus = "Mic off";
  DateTime lastTrigger = DateTime.now();

  final int SEQ_LEN = 25;

  final TextEditingController textController = TextEditingController();
  final FocusNode textFocusNode = FocusNode();

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
    "baap", "dost", "ghar", "khandan",
    "kitaab", "likhna", "maa", "parhna", "talibeilm",
  ];

  final Map<String, List<String>> urduSynonyms = {
    "baap": ["baap", "father", "dad", "papa", "walid", "aba", "bap"],
    "dost": ["dost", "friend", "yaar", "companion", "saathi", "dosta"],
    "ghar": ["ghar", "home", "house", "makan", "residence"],
    "khandan": ["khandan", "family", "gharana", "rishtedaar", "khandaan"],
    "kitaab": ["kitaab", "book", "kitab", "pustak"],
    "likhna": ["likhna", "write", "likhai", "likaai", "likho"],
    "maa": ["maa", "mother", "mom", "amma", "walida", "mama"],
    "parhna": ["parhna", "read", "study", "padhai", "mutalia", "parho"],
    "talibeilm": ["talibeilm", "student", "talib-e-ilam", "shagird"],
  };

  @override
  void initState() {
    super.initState();
    initTTS();
    initSpeech();
    loadModel();
  }

  Future<void> initTTS() async {
    await tts.setLanguage("ur-PK");
    await tts.setSpeechRate(0.5);
    await tts.setPitch(1.0);
  }

  Future<void> initSpeech() async {
    try {
      bool ok = await speech.initialize(
        onError: (error) => print("Speech error: $error"),
      );
      print(ok ? "Speech available" : "Speech not available");
    } catch (e) {
      print("Speech init error: $e");
    }
  }

  Future<void> loadModel() async {
    try {
      setState(() => modelStatus = "Loading model...");
      interpreter = await Interpreter.fromAsset(
        "assets/model.tflite",
        options: InterpreterOptions()..threads = 2,
      );
      setState(() {
        isModelLoaded = true;
        modelStatus = "Model ready!";
      });
      print("Model loaded successfully!");
    } catch (e) {
      setState(() {
        isModelLoaded = false;
        modelStatus =
            "Model error: ${e.toString().substring(0, min(40, e.toString().length))}";
      });
      print("Error loading model: $e");
      _showModelErrorDialog();
    }
  }

  Future<void> toggleCamera() async {
    if (isCameraOn) {
      await controller?.stopImageStream();
      await controller?.dispose();
      controller = null;
      setState(() {
        isCameraOn = false;
        isStreamActive = false;
      });
    } else {
      if (!isModelLoaded) {
        _showSnackBar("Model not loaded yet.");
        return;
      }
      setState(() => isCameraOn = true);
      await _initCamera();
    }
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await controller!.initialize();
      if (mounted) setState(() {});
      if (!isStreamActive && isModelLoaded) {
        _startStream();
      }
    } catch (e) {
      print("Camera error: $e");
      _showSnackBar("Camera error: $e");
      setState(() => isCameraOn = false);
    }
  }

  void _startStream() {
    if (controller == null || isStreamActive || !isModelLoaded) return;
    isStreamActive = true;
    controller!.startImageStream((CameraImage image) async {
      if (isProcessing) return;
      isProcessing = true;

      try {
        final input = preprocessCameraImage(image);
        final output = List.filled(1 * labels.length, 0.0).reshape([1, labels.length]);

        interpreter!.run([input], output);

        int maxIdx = 0;
        double maxScore = output[0][0];
        for (int i = 1; i < labels.length; i++) {
          if (output[0][i] > maxScore) {
            maxScore = output[0][i];
            maxIdx = i;
          }
        }

        final prediction = maxScore > 0.6 ? labels[maxIdx] : "unknown";

        if (prediction != "unknown") {
          final now = DateTime.now();
          if (prediction != lastResult && now.difference(lastTrigger).inMilliseconds > 1500) {
            lastResult = prediction;
            lastTrigger = now;
            if (mounted) {
              setState(() => detectedText = prediction);
              tts.speak(prediction);
              _showVideo(prediction);
              print("SIGN DETECTED: $prediction");
            }
          }
        }
      } catch (e) {
        print("Inference error: $e");
      }
      isProcessing = false;
    });
  }

  Float32List preprocessCameraImage(CameraImage image) {
    final convertedImage = _convertYUV420toImage(image);
    final resizedImg = img.copyResize(convertedImage, width: 224, height: 224);
    final floatList = Float32List(224 * 224 * 3);
    int index = 0;
    for (var y = 0; y < 224; y++) {
      for (var x = 0; x < 224; x++) {
        final pixelColor = resizedImg.getPixel(x, y);
        final color = img.getColor((r * 255).toInt(), (g * 255).toInt(), (b * 255).toInt());
        floatList[index++] = r;
        floatList[index++] = g;
        floatList[index++] = b;
      }
    }
    return floatList;
  }

 import 'package:image/image.dart' as img;

img.Image _convertYUV420toImage(CameraImage image) {
  final int width = image.width;
  final int height = image.height;
  final img.Image imgImage = img.Image(width: width, height: height); // Correct constructor

  final yBuffer = image.planes[0].bytes;
  final uBuffer = image.planes[1].bytes;
  final vBuffer = image.planes[2].bytes;

  int uvRowStride = image.planes[1].bytesPerRow;
  int uvPixelStride = image.planes[1].bytesPerPixel ?? 1;

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final int yIndex = y * image.planes[0].bytesPerRow + x;
      final int uvRow = y ~/ 2;
      final int uvCol = x ~/ 2;
      final int uIndex = uvRow * uvRowStride + uvCol * uvPixelStride;
      final int vIndex = uIndex;

      final int yValue = yBuffer[yIndex];
      final int uValue = uBuffer[uIndex];
      final int vValue = vBuffer[vIndex];

      final rVal = (yValue + 1.370705 * (vValue - 128)).clamp(0, 255).toInt();
      final gVal = (yValue - 0.337633 * (uValue - 128) - 0.698001 * (vValue - 128))
          .clamp(0, 255)
          .toInt();
      final bVal = (yValue + 1.732446 * (uValue - 128)).clamp(0, 255).toInt();

      final color = img.getColor(rVal, gVal, bVal);
      imgImage.setPixel(x, y, color);
    }
  }
  return imgImage;
}

  void handleTextInput(String text) {
    final input = text.toLowerCase().trim();
    if (input.isEmpty) {
      _showSnackBar("Please enter some text");
      return;
    }
    textController.clear();
    final matched = _findMatch(input);
    if (matched != null) {
      setState(() => detectedText = matched);
      tts.speak("یہ $matched کا اشارہ ہے");
      _showVideo(matched);
    } else {
      setState(() => detectedText = "No match: $input");
      tts.speak("معاف کیجئے، یہ لفظ نہیں ملا");
      _showSnackBar("'$input' not found");
    }
  }

  String? _findMatch(String input) {
    if (signMap.containsKey(input)) return input;
    for (final entry in urduSynonyms.entries) {
      if (entry.value.contains(input)) return entry.key;
    }
    for (final key in signMap.keys) {
      if (input.contains(key) || key.contains(input)) return key;
    }
    return null;
  }

  void toggleMic() async {
    if (isListening) {
      await speech.stop();
      setState(() {
        isListening = false;
        micStatus = "Mic off";
      });
    } else {
      if (await speech.initialize()) {
        setState(() {
          isListening = true;
          micStatus = "Listening...";
          detectedText = "Listening...";
        });
        speech.listen(
          onResult: (result) {
            final spoken = result.recognizedWords;
            setState(() => detectedText = "Heard: $spoken");
            speech.stop();
            setState(() {
              isListening = false;
              micStatus = "Mic off";
            });
            handleTextInput(spoken);
          },
        );
        _showSnackBar("Listening... Speak now");
      } else {
        _showSnackBar("Speech recognition not available");
      }
    }
  }

  void _showVideo(String key) {
    if (!signMap.containsKey(key)) {
      _showSnackBar("Video not found: $key");
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoScreen(signMap[key]!, key),
      ),
    );
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void clearText() {
    textController.clear();
    setState(() => detectedText = "");
  }

  void _showModelErrorDialog() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text("Model File Missing"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                "model.tflite not found!",
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
              ),
              SizedBox(height: 8),
              Text("1. Copy model.tflite to assets/"),
              Text("2. Add it in pubspec.yaml assets"),
              Text("3. Run: flutter clean && flutter pub get"),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("OK"),
            ),
          ],
        ),
      );
    });
  }

  void _showInfoDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("How to Use"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("1. Turn ON camera"),
            const Text("2. Show your hand sign"),
            const Text("3. App detects and speaks the sign"),
            const Text("4. Type or speak Roman Urdu words"),
            const SizedBox(height: 10),
            const Text("Signs:", style: TextStyle(fontWeight: FontWeight.bold)),
            Wrap(
              spacing: 8,
              children: signMap.keys.map((k) => Chip(label: Text(k))).toList(),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  Widget _btn({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(icon, color: color, size: 40),
          onPressed: onTap,
        ),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  @override
  void dispose() {
    controller?.dispose();
    interpreter?.close();
    tts.stop();
    speech.stop();
    textController.dispose();
    textFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Your widget tree here, for example:
    return Scaffold(
      appBar: AppBar(
        title: const Text("Action to Speak"),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: _showInfoDialog,
          ),
        ],
      ),
      body: Center(
        child: Column(
          children: [
            // Add your buttons and display here
            ElevatedButton(
              onPressed: toggleCamera,
              child: Text(isCameraOn ? "Stop Camera" : "Start Camera"),
            ),
            // Display detected text
            Text("Detected: $detectedText"),
            // Mic button
            ElevatedButton(
              onPressed: toggleMic,
              child: Text(micStatus),
            ),
            // Text input field
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: TextField(
                controller: textController,
                focusNode: textFocusNode,
                decoration: InputDecoration(
                  labelText: "Type word",
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: () => handleTextInput(textController.text),
                  ),
                ),
              ),
            ),
            // Add more buttons or UI as needed
          ],
        ),
      ),
    );
  }
}

class VideoScreen extends StatefulWidget {
  final String path;
  final String signName;
  const VideoScreen(this.path, this.signName, {super.key});

  @override
  State<VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends State<VideoScreen> {
  late VideoPlayerController controller;
  bool isVideoLoading = true;
  bool hasError = false;

  @override
  void initState() {
    super.initState();
    _loadVideo();
  }

  void _loadVideo() async {
    try {
      controller = VideoPlayerController.asset(widget.path);
      await controller.initialize();
      setState(() => isVideoLoading = false);
      controller.play();
      controller.setLooping(true);
    } catch (e) {
      print("Video error: $e");
      setState(() {
        isVideoLoading = false;
        hasError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Sign: ${widget.signName.toUpperCase()}"),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      backgroundColor: Colors.black,
      body: Center(
        child: isVideoLoading
            ? const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.blue),
                  SizedBox(height: 20),
                  Text("Loading video...", style: TextStyle(color: Colors.white)),
                ],
              )
            : hasError
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red, size: 60),
                      const SizedBox(height: 20),
                      const Text("Video not found!", style: TextStyle(color: Colors.white)),
                      Text("Sign: ${widget.signName}", style: const TextStyle(color: Colors.white70)),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text("Go Back"),
                      ),
                    ],
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AspectRatio(
                        aspectRatio: controller.value.aspectRatio,
                        child: VideoPlayer(controller),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            icon: Icon(
                              controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
                              color: Colors.white,
                              size: 40,
                            ),
                            onPressed: () {
                              setState(() {
                                controller.value.isPlaying ? controller.pause() : controller.play();
                              });
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.replay, color: Colors.white, size: 40),
                            onPressed: () {
                              controller.seekTo(Duration.zero);
                              controller.play();
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white, size: 40),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ],
                  ),
      ),
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}
