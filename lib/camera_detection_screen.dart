import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:camera/camera.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:video_player/video_player.dart';
import 'package:hand_landmarker/hand_landmarker.dart'; // ← NEW: real-time hand landmark detection

// ─────────────────────────────────────────────────────────────────────────────
// pubspec.yaml dependencies needed:
//   camera: ^0.10.5+9
//   flutter_tts: ^3.8.5
//   speech_to_text: ^6.6.0
//   tflite_flutter: ^0.10.4
//   video_player: ^2.8.1
//   hand_landmarker: ^2.2.0   ← NEW (replaces the old `image` package pipeline)
//
// REMOVED: the `image` package + manual YUV->RGB + pixel-tensor conversion.
// The alphabet model is now the LANDMARK-BASED classifier we trained
// together (MediaPipe hand landmarks -> small NN), not the CNN pixel
// classifier the previous version of this screen used. This is a genuinely
// different model, so the whole classification path changes:
//
//   OLD: camera frame -> resize to 224x224 -> uint8 pixel tensor -> CNN -> 76 classes
//   NEW: camera frame -> hand_landmarker (MediaPipe) -> 21 landmarks ->
//        normalize (same math as training) -> 63-float tensor -> small NN
//
// ASSETS YOU NEED TO PLACE (from the Colab notebook output):
//   assets/model.tflite   <- replace with our trained sign_model.tflite
//   assets/labels.json    <- NEW, add this file (from the notebook output)
//
// Update pubspec.yaml's assets section to include both:
//   assets:
//     - assets/model.tflite
//     - assets/labels.json
//     - assets/videos/          (unchanged, for the word module)
//
// Requires JDK 17+ and minSdkVersion 24+ on the Android side (hand_landmarker
// requirement) — check android/app/build.gradle if you hit a build error.
// ─────────────────────────────────────────────────────────────────────────────

class CameraDetectionScreen extends StatefulWidget {
  @override
  State<CameraDetectionScreen> createState() => _CameraDetectionScreenState();
}

class _CameraDetectionScreenState extends State<CameraDetectionScreen> {

  CameraController? controller;
  Interpreter? interpreter;
  HandLandmarkerPlugin? handPlugin; // ← NEW: MediaPipe hand landmark detector

  FlutterTts tts = FlutterTts();
  stt.SpeechToText speech = stt.SpeechToText();

  bool isCameraOn = false;
  bool isStreamActive = false;
  bool isModelLoaded = false;
  bool isProcessingFrame = false; // throttle: only one frame in flight at a time
  bool isListening = false;

  String detectedText = "";
  String micStatus = "Mic off";
  String modelStatus = "Loading model...";

  // ── Debounce state for alphabet predictions ───────────────────────────────
  String? _lastRawPrediction;
  int _sameStreak = 0;
  String _lastSpokenLetter = "";
  DateTime _lastSpokenAt = DateTime.now();
  int _noHandFrames = 0; // consecutive frames with no hand detected

  static const int STABLE_FRAMES_NEEDED = 4;
  static const double CONFIDENCE_THRESHOLD = 0.6;
  static const Duration SPEAK_COOLDOWN = Duration(milliseconds: 1500);
  static const int NO_HAND_RESET_FRAMES = 15; // allow re-speaking same letter after hand is hidden this long

  final TextEditingController textController = TextEditingController();
  final FocusNode textFocusNode = FocusNode();

  // ── Word → video module (UNCHANGED — do not touch) ────────────────────────
  final Map<String, String> signMap = {
    "baap":      "assets/videos/father.mp4",
    "dost":      "assets/videos/friend.mp4",
    "ghar":      "assets/videos/home.mp4",
    "khandan":   "assets/videos/family.mp4",
    "kitaab":    "assets/videos/book.mp4",
    "likhna":    "assets/videos/write.mp4",
    "maa":       "assets/videos/mother.mp4",
    "parhna":    "assets/videos/read.mp4",
    "talibeilm": "assets/videos/student.mp4",
  };

  final Map<String, List<String>> urduSynonyms = {
    "baap":      ["baap", "father", "dad", "papa", "walid", "aba", "bap"],
    "dost":      ["dost", "friend", "yaar", "companion", "saathi", "dosta"],
    "ghar":      ["ghar", "home", "house", "makan", "residence"],
    "khandan":   ["khandan", "family", "gharana", "rishtedaar", "khandaan"],
    "kitaab":    ["kitaab", "book", "kitab", "pustak"],
    "likhna":    ["likhna", "write", "likhai", "likaai", "likho"],
    "maa":       ["maa", "mother", "mom", "amma", "walida", "mama"],
    "parhna":    ["parhna", "read", "study", "padhai", "mutalia", "parho"],
    "talibeilm": ["talibeilm", "student", "talib-e-ilam", "shagird"],
  };

  // ── Alphabet module: labels now loaded from assets/labels.json ───────────
  // (This replaces the old hardcoded 76-entry list. Whatever classes your
  // trained model actually has will be loaded automatically at runtime.)
  List<String> alphabetLabels = [];

  // Harmless if your labels don't have these suffixes — only cleans them if present.
  String _cleanLabel(String raw) {
    return raw.replaceAll("-Augmented", "").replaceAll("-Original", "");
  }

  @override
  void initState() {
    super.initState();
    loadLabelsAndModel();
    initHandLandmarker();
    initTTS();
    initSpeech();
  }

  Future initTTS() async {
    await tts.setLanguage("ur-PK");
    await tts.setSpeechRate(0.5);
    await tts.setPitch(1.0);
  }

  Future initSpeech() async {
    try {
      bool available = await speech.initialize();
      print(available
          ? "Speech recognition available"
          : "Speech recognition not available");
    } catch (e) {
      print("Speech initialization error: $e");
    }
  }

  // ── NEW: initialize the MediaPipe hand landmark detector ──────────────────
  Future<void> initHandLandmarker() async {
    try {
      handPlugin = HandLandmarkerPlugin.create(
        numHands: 1,
        minHandDetectionConfidence: 0.6,
        delegate: HandLandmarkerDelegate.gpu, // falls back to cpu if unsupported on device
      );
      print("✅ Hand landmarker ready");
    } catch (e) {
      print("❌ Error initializing hand landmarker: $e");
      _showSnackBar("Hand tracker init failed: $e");
    }
  }

  // ── CHANGED: loads labels.json + the landmark-based model.tflite ─────────
  Future loadLabelsAndModel() async {
    try {
      setState(() => modelStatus = "Loading model...");

      final labelsJsonStr = await rootBundle.loadString('assets/labels.json');
      final List<dynamic> decoded = json.decode(labelsJsonStr);
      alphabetLabels = decoded.map((e) => e.toString()).toList();

      interpreter = await Interpreter.fromAsset("assets/sign_model.tflite");

      final inputShape = interpreter!.getInputTensor(0).shape;
      final outputShape = interpreter!.getOutputTensor(0).shape;

      setState(() {
        isModelLoaded = true;
        modelStatus = "✅ Model ready! (${alphabetLabels.length} classes)";
      });

      print("✅ Model + labels loaded successfully!");
      print("Input  shape: $inputShape"); // expect [1, 63]
      print("Output shape: $outputShape"); // expect [1, alphabetLabels.length]

      if (outputShape.isNotEmpty && outputShape.last != alphabetLabels.length) {
        print("⚠️ WARNING: model outputs ${outputShape.last} classes but "
            "labels.json has ${alphabetLabels.length} entries — check they match.");
      }
    } catch (e) {
      setState(() {
        isModelLoaded = false;
        modelStatus = "❌ Error: ${e.toString().substring(0, min(150, e.toString().length))}";
      });
      print("❌ Error loading model/labels: $e");
      _showModelErrorDialog();
    }
  }

  void _showModelErrorDialog() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text("Model or Labels File Missing"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text("model.tflite or labels.json not found!",
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
              SizedBox(height: 10),
              Text("Please ensure:", style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 5),
              Text("1. Copy both files into the 'assets/' folder"),
              Text("2. Add both to pubspec.yaml's assets list"),
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

  // ── Camera helpers ─────────────────────────────────────────────────────────

  Future initCamera() async {
    if (!isModelLoaded) {
      _showSnackBar("Model not loaded. Please fix model file.");
      return;
    }
    try {
      final cams = await availableCameras();
      final frontCam = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cams.first,
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
    } catch (e) {
      print("Camera error: $e");
      _showSnackBar("Camera error: $e");
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
      if (!isModelLoaded) {
        _showSnackBar("Model not loaded yet. Please wait.");
        return;
      }
      setState(() => isCameraOn = true);
      await initCamera();
    }
  }

  // ── CHANGED: per-frame landmark detection + classification ───────────────
  void startStream() {
    if (controller == null || isStreamActive || !isModelLoaded) return;
    isStreamActive = true;

    controller!.startImageStream((CameraImage image) {
      if (isProcessingFrame) return;
      isProcessingFrame = true;

      _classifyFrame(image, controller!.description).whenComplete(() {
        isProcessingFrame = false;
      });
    });
  }

  Future<void> _classifyFrame(
      CameraImage cameraImage, CameraDescription camera) async {
    try {
      if (handPlugin == null) return;

      // MediaPipe hand landmark detection (synchronous, on native thread)
      final hands = handPlugin!.detect(cameraImage, camera.sensorOrientation);

      if (hands.isEmpty) {
        _handleNoHand();
        return;
      }

      _noHandFrames = 0;
      final landmarks = hands.first.landmarks; // 21 points, normalized x/y/z
      final features = _normalizeLandmarks(landmarks); // length-63 Float32List

      final input = [features];
      final output = List.generate(1, (_) => List.filled(alphabetLabels.length, 0.0));

      interpreter!.run(input, output);

      int idx = 0;
      double maxProb = output[0][0];
      for (int i = 1; i < alphabetLabels.length; i++) {
        if (output[0][i] > maxProb) {
          maxProb = output[0][i];
          idx = i;
        }
      }

      _handlePrediction(alphabetLabels[idx], maxProb);
    } catch (e) {
      print("❌ Frame classification error: $e");
    }
  }

  // Must exactly match normalize_landmarks() from the Python training script:
  // translate so wrist (landmark 0) is the origin, then scale so the
  // wrist -> middle-finger-MCP (landmark 9) distance is 1.0.
  Float32List _normalizeLandmarks(List<Landmark> landmarks) {
    final wrist = landmarks[0];
    final coords = landmarks
        .map((l) => [l.x - wrist.x, l.y - wrist.y, l.z - wrist.z])
        .toList();

    final mid = coords[9];
    double scaleRef = sqrt(mid[0] * mid[0] + mid[1] * mid[1] + mid[2] * mid[2]);
    if (scaleRef < 1e-6) scaleRef = 1e-6;

    final flat = Float32List(63);
    for (int i = 0; i < 21; i++) {
      flat[i * 3 + 0] = coords[i][0] / scaleRef;
      flat[i * 3 + 1] = coords[i][1] / scaleRef;
      flat[i * 3 + 2] = coords[i][2] / scaleRef;
    }
    return flat;
  }

  void _handleNoHand() {
    _sameStreak = 0;
    _lastRawPrediction = null;
    _noHandFrames++;
    // After the hand's been away a while, allow the same letter to be spoken
    // again the next time it's shown (mirrors the webcam test script logic).
    if (_noHandFrames > NO_HAND_RESET_FRAMES) {
      _lastSpokenLetter = "";
    }
  }

  // Debounce: require several consecutive frames to agree before speaking,
  // so a fleeting misread doesn't get announced.
  void _handlePrediction(String rawLabel, double confidence) {
    if (confidence < CONFIDENCE_THRESHOLD) {
      _sameStreak = 0;
      _lastRawPrediction = null;
      return;
    }

    if (rawLabel == _lastRawPrediction) {
      _sameStreak++;
    } else {
      _lastRawPrediction = rawLabel;
      _sameStreak = 1;
    }

    if (_sameStreak < STABLE_FRAMES_NEEDED) return;

    final cleanLetter = _cleanLabel(rawLabel);
    final now = DateTime.now();
    final cooledDown = now.difference(_lastSpokenAt) > SPEAK_COOLDOWN;

    if (cleanLetter != _lastSpokenLetter || cooledDown) {
      _lastSpokenLetter = cleanLetter;
      _lastSpokenAt = now;

      if (mounted) {
        setState(() => detectedText = cleanLetter);
      }

      print("✅ ALPHABET DETECTED: $cleanLetter (confidence: ${confidence.toStringAsFixed(3)})");
      tts.speak(cleanLetter);
      // NOTE: no _showVideo() call here on purpose — alphabets don't have
      // per-letter videos; only the word module below plays videos.
    }
  }

  // ── Text / voice input — UNCHANGED, still drives the word→video module ────

  void handleTextInput(String text) {
    final input = text.toLowerCase().trim();
    if (input.isEmpty) { _showSnackBar("Please enter some text"); return; }

    print("Searching for: $input");
    textController.clear();

    final matched = _findMatch(input);
    if (matched != null) {
      setState(() => detectedText = matched);
      tts.speak("یہ $matched کا اشارہ ہے");
      _showVideo(matched);
    } else {
      setState(() => detectedText = "No match found for: $input");
      tts.speak("معاف کیجئے، یہ لفظ نہیں ملا");
      _showSnackBar("'$input' not found in vocabulary");
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
      setState(() { isListening = false; micStatus = "Mic off"; });
      _showSnackBar("Microphone stopped");
    } else {
      final available = await speech.initialize();
      if (available) {
        setState(() {
          isListening = true;
          micStatus = "🎤 Listening...";
          detectedText = "Listening...";
        });
        speech.listen(
          onResult: (result) {
            final spokenText = result.recognizedWords;
            print("Heard: $spokenText");
            setState(() => detectedText = "Heard: $spokenText");
            speech.stop();
            setState(() { isListening = false; micStatus = "Mic off"; });
            handleTextInput(spokenText);
          },
        );
        _showSnackBar("Listening... Speak now");
      } else {
        _showSnackBar("Speech recognition not available");
      }
    }
  }

  void _showVideo(String key) {
    if (!signMap.containsKey(key)) { _showSnackBar("Video not found for: $key"); return; }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => VideoScreen(signMap[key]!, key)),
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  void clearText() {
    textController.clear();
    setState(() => detectedText = "");
    _showSnackBar("Text cleared");
  }

  void _showInfoDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("How to Use"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("1. 📷 Turn ON camera and hold an alphabet sign steady"),
            const Text("2. 📢 App will speak + show the detected letter"),
            const Text("3. ✍️ Type Roman Urdu words directly for word signs"),
            const Text("4. 🎤 Click mic to speak a word instead"),
            const SizedBox(height: 10),
            const Text("Available word signs:", style: TextStyle(fontWeight: FontWeight.bold)),
            Wrap(
              spacing: 8,
              children: signMap.keys.map((k) => Chip(label: Text(k))).toList(),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("OK")),
        ],
      ),
    );
  }

  // ── UI — UNCHANGED ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Action to Speak - Sign Detection"),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(30),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            alignment: Alignment.centerLeft,
            child: Text(
              modelStatus,
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            flex: 2,
            child: Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.blue, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: isCameraOn &&
                        controller != null &&
                        controller!.value.isInitialized
                    ? CameraPreview(controller!)
                    : Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.videocam_off,
                                size: 64, color: Colors.grey),
                            const SizedBox(height: 10),
                            const Text("Camera is OFF",
                                style: TextStyle(fontSize: 16)),
                            const SizedBox(height: 10),
                            ElevatedButton(
                              onPressed: toggleCamera,
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue),
                              child: const Text("Turn ON Camera"),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Row(
              children: [
                const Icon(Icons.visibility, color: Colors.blue),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    detectedText.isEmpty ? "No sign detected yet" : detectedText,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color:
                          detectedText.isEmpty ? Colors.grey : Colors.black,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: textController,
                    focusNode: textFocusNode,
                    decoration: InputDecoration(
                      hintText:
                          "Type Roman Urdu (e.g., baap, dost, ghar)",
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      prefixIcon: const Icon(Icons.keyboard),
                      suffixIcon: textController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: clearText,
                            )
                          : null,
                    ),
                    onSubmitted: (v) {
                      textFocusNode.unfocus();
                      handleTextInput(v);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    textFocusNode.unfocus();
                    handleTextInput(textController.text);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 16),
                  ),
                  child: const Icon(Icons.send, color: Colors.white),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 50,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: signMap.keys.map((key) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ActionChip(
                    label: Text(key),
                    onPressed: () {
                      textController.text = key;
                      handleTextInput(key);
                    },
                    backgroundColor: Colors.blue.shade100,
                  ),
                );
              }).toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _controlButton(
                  icon: isCameraOn ? Icons.videocam : Icons.videocam_off,
                  color: Colors.blue,
                  label: isCameraOn ? "Camera ON" : "Camera OFF",
                  onTap: toggleCamera,
                ),
                Stack(
                  alignment: Alignment.topRight,
                  children: [
                    _controlButton(
                      icon: isListening ? Icons.mic : Icons.mic_none,
                      color: isListening ? Colors.red : Colors.grey,
                      label: micStatus,
                      onTap: toggleMic,
                    ),
                    if (isListening)
                      Positioned(
                        right: 4,
                        top: 4,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
                _controlButton(
                  icon: Icons.info,
                  color: Colors.orange,
                  label: "Help",
                  onTap: _showInfoDialog,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _controlButton({
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

  // ── Dispose ────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    controller?.dispose();
    interpreter?.close();
    handPlugin?.dispose(); // ← NEW: release native hand landmarker resources
    tts.stop();
    speech.stop();
    textController.dispose();
    textFocusNode.dispose();
    super.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// VideoScreen — UNCHANGED (word → video module, do not touch)
// ─────────────────────────────────────────────────────────────────────────────

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
      print("Error loading video: $e");
      setState(() { isVideoLoading = false; hasError = true; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Sign: ${widget.signName.toUpperCase()}"),
        backgroundColor: Colors.black,
      ),
      backgroundColor: Colors.black,
      body: Center(
        child: isVideoLoading
            ? const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.blue),
                  SizedBox(height: 20),
                  Text("Loading video...",
                      style: TextStyle(color: Colors.white)),
                ],
              )
            : hasError
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline,
                          color: Colors.red, size: 60),
                      const SizedBox(height: 20),
                      const Text("Video not found!",
                          style: TextStyle(color: Colors.white)),
                      const SizedBox(height: 10),
                      Text("Sign: ${widget.signName}",
                          style: const TextStyle(color: Colors.white70)),
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
                              controller.value.isPlaying
                                  ? Icons.pause
                                  : Icons.play_arrow,
                              color: Colors.white,
                              size: 40,
                            ),
                            onPressed: () {
                              setState(() {
                                controller.value.isPlaying
                                    ? controller.pause()
                                    : controller.play();
                              });
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.replay,
                                color: Colors.white, size: 40),
                            onPressed: () {
                              controller.seekTo(Duration.zero);
                              controller.play();
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.close,
                                color: Colors.white, size: 40),
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
