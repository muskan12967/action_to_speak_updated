import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:video_player/video_player.dart';
import 'package:google_mlkit_hand_landmark/google_mlkit_hand_landmark.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'dart:math';

// ─────────────────────────────────────────────────────────────────────────────
// pubspec.yaml dependencies needed:
//   camera: ^0.10.5+9
//   flutter_tts: ^3.8.5
//   speech_to_text: ^6.6.0
//   tflite_flutter: ^0.10.4
//   video_player: ^2.8.1
//   google_mlkit_hand_landmark: ^0.1.0        ← CHANGED from pose_detection
//   google_mlkit_commons: ^0.6.0
// ─────────────────────────────────────────────────────────────────────────────

class CameraDetectionScreen extends StatefulWidget {
  @override
  State<CameraDetectionScreen> createState() => _CameraDetectionScreenState();
}

class _CameraDetectionScreenState extends State<CameraDetectionScreen> {

  CameraController? controller;
  Interpreter? interpreter;

  // ── FIX 1: Use HandLandmarker instead of PoseDetector ──────────────────────
  late HandLandmarker handLandmarker;

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
  // 2 hands × 21 landmarks × 3 coords = 126  (unchanged — but now REAL data)
  final int FEATURES_PER_FRAME = 126;

  final TextEditingController textController = TextEditingController();
  final FocusNode textFocusNode = FocusNode();

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

  final List<String> labels = [
    "baap", "dost", "ghar", "khandan",
    "kitaab", "likhna", "maa", "parhna", "talibeilm"
  ];

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

  // ── FIX 2: initialise HandLandmarker ──────────────────────────────────────
  @override
  void initState() {
    super.initState();

    handLandmarker = HandLandmarker(
      options: HandLandmarkerOptions(
        baseOptions: BaseOptions(
          modelAssetPath: 'assets/hand_landmarker.task',
          // Download from:
          // https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/latest/hand_landmarker.task
          // and place in assets/ folder, add to pubspec.yaml assets list
        ),
        runningMode: RunningMode.liveStream,
        numHands: 2,                     // detect up to 2 hands
        minHandDetectionConfidence: 0.5,
        minHandPresenceConfidence: 0.5,
        minTrackingConfidence: 0.5,
        resultCallback: _onHandLandmarks, // async callback for liveStream mode
      ),
    );

    loadModel();
    initTTS();
    initSpeech();
  }

  // ── FIX 3: liveStream result callback ────────────────────────────────────
  // In liveStream mode HandLandmarker calls this when results are ready.
  void _onHandLandmarks(
    HandLandmarkerResult result,
    InputImage inputImage,
    int timestamp,
  ) {
    if (!mounted) return;
    _processHandResult(result);
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

  Future loadModel() async {
    try {
      setState(() => modelStatus = "Loading model...");

      interpreter = await Interpreter.fromAsset("assets/model.tflite");

      setState(() {
        isModelLoaded = true;
        modelStatus = "✅ Model ready!";
      });

      print("✅ Model loaded successfully!");
      print("Input  shape: ${interpreter!.getInputTensor(0).shape}");
      print("Output shape: ${interpreter!.getOutputTensor(0).shape}");

    } catch (e) {
      setState(() {
        isModelLoaded = false;
        modelStatus = "❌ Error: ${e.toString().substring(0, min(35, e.toString().length))}";
      });
      print("❌ Error loading model: $e");
      _showModelErrorDialog();
    }
  }

  void _showModelErrorDialog() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text("Model File Missing"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text("model.tflite not found!",
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
              SizedBox(height: 10),
              Text("Please ensure:", style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 5),
              Text("1. Copy 'model.tflite' to 'assets/' folder"),
              Text("2. Copy 'hand_landmarker.task' to 'assets/' folder"),
              Text("3. Update pubspec.yaml with both assets"),
              Text("4. Run: flutter clean && flutter pub get"),
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
      );

      controller = CameraController(
        frontCam,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await controller!.initialize();
      setState(() {});

      if (!isStreamActive && isModelLoaded) {
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
        isStreamActive = false; // ← FIX 4: reset flag in setState
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

  InputImage _inputImageFromCamera(CameraImage image, CameraDescription camera) {
    final plane = image.planes[0];
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: InputImageRotationValue.fromRawValue(camera.sensorOrientation)
            ?? InputImageRotation.rotation0deg,
        format: InputImageFormatValue.fromRawValue(image.format.raw)
            ?? InputImageFormat.nv21,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  // ── FIX 5: Extract REAL hand landmarks (21 pts × 2 hands × 3 = 126) ───────
  List<double> _extractFeaturesFromResult(HandLandmarkerResult result) {
    // We always produce exactly 126 values: hand0 (63) + hand1 (63).
    // Missing hands are filled with zeros — same convention as training data.
    List<double> hand0 = List.filled(63, 0.0);
    List<double> hand1 = List.filled(63, 0.0);

    if (result.landmarks.isNotEmpty) {
      hand0 = _landmarkToFeatures(result.landmarks[0]);
    }
    if (result.landmarks.length >= 2) {
      hand1 = _landmarkToFeatures(result.landmarks[1]);
    }

    return [...hand0, ...hand1]; // 126 values total
  }

  List<double> _landmarkToFeatures(List<NormalizedLandmark> landmarks) {
    // Normalise relative to landmark 0 (wrist) so position-invariant
    final wristX = landmarks[0].x;
    final wristY = landmarks[0].y;
    final wristZ = landmarks[0].z;

    List<double> features = [];
    for (final lm in landmarks) {           // 21 landmarks
      features.add(lm.x - wristX);         // x relative to wrist
      features.add(lm.y - wristY);         // y relative to wrist
      features.add(lm.z - wristZ);         // z relative to wrist
    }
    return features; // 63 values
  }

  // ── FIX 6: Drive sequence + prediction from the liveStream callback ────────
  void _processHandResult(HandLandmarkerResult result) {
    if (!isModelLoaded) return;

    final frame = _extractFeaturesFromResult(result);
    sequence.add(frame);
    if (sequence.length > SEQ_LEN) sequence.removeAt(0);

    if (sequence.length == SEQ_LEN) {
      final prediction = predict(sequence);
      final now = DateTime.now();

      if (prediction != "unknown") {
        // FIX 7: lowered stability threshold to 0.1 so normal signing passes
        final stability = checkSequenceStability(sequence);

        if (prediction != lastResult &&
            now.difference(lastTrigger).inMilliseconds > 1500 &&
            stability > 0.1) {

          lastResult = prediction;
          lastTrigger = now;

          if (mounted) {
            setState(() => detectedText = prediction);
          }

          print("✅ SIGN DETECTED: $prediction");
          tts.speak(prediction);
          _showVideo(prediction);
        }
      }
    }
  }

  // ── FIX 8: stream now only sends frames to HandLandmarker (no processing here)
  void startStream() {
    if (controller == null || isStreamActive || !isModelLoaded) return;

    // Mark active BEFORE starting so re-entrant calls are blocked
    isStreamActive = true; // FIX 9: set before startImageStream

    int frameTimestamp = 0;

    controller!.startImageStream((image) {
      if (isProcessing) return;
      isProcessing = true;

      try {
        final inputImage = _inputImageFromCamera(image, controller!.description);
        frameTimestamp += 33; // ~30 fps in ms
        // liveStream mode: result arrives in _onHandLandmarks callback
        handLandmarker.detectAsync(inputImage, frameTimestamp);
      } catch (e) {
        print("Stream error: $e");
      }

      isProcessing = false;
    });
  }

  // ── Model inference (unchanged logic, same input shape) ────────────────────
  String predict(List<List<double>> seq) {
    if (interpreter == null || !isModelLoaded) return "unknown";

    try {
      // shape: [1, SEQ_LEN, FEATURES_PER_FRAME]
      final List<List<List<double>>> input = [seq];
      final output = List.generate(1, (_) => List.filled(labels.length, 0.0));

      interpreter!.run(input, output);

      int idx = 0;
      double maxVal = output[0][0];
      for (int i = 1; i < labels.length; i++) {
        if (output[0][i] > maxVal) {
          maxVal = output[0][i];
          idx = i;
        }
      }

      print("🎯 Prediction: ${labels[idx]} (confidence: ${maxVal.toStringAsFixed(3)})");
      return maxVal > 0.5 ? labels[idx] : "unknown";

    } catch (e) {
      print("❌ Prediction error: $e");
      return "unknown";
    }
  }

  double checkSequenceStability(List<List<double>> seq) {
    if (seq.length < 5) return 0.0;

    double totalVariance = 0.0;
    int comparisons = 0;

    for (int i = max(0, seq.length - 10); i < seq.length - 1; i++) {
      double variance = 0.0;
      for (int j = 0; j < seq[i].length; j++) {
        variance += pow(seq[i + 1][j] - seq[i][j], 2).toDouble();
      }
      totalVariance += sqrt(variance / seq[i].length);
      comparisons++;
    }

    if (comparisons == 0) return 0.0;
    final avgVariance = totalVariance / comparisons;
    return 1.0 - (avgVariance.clamp(0.0, 0.8) / 0.8);
  }

  // ── Text / voice input ─────────────────────────────────────────────────────

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
            const Text("1. 📷 Turn ON camera"),
            const Text("2. 🤚 Perform hand sign in front of camera"),
            const Text("3. 📢 App will speak the sign name"),
            const Text("4. ✍️ Type Roman Urdu words directly"),
            const Text("5. 🎤 Click mic to speak words"),
            const SizedBox(height: 10),
            const Text("Available signs:", style: TextStyle(fontWeight: FontWeight.bold)),
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

  // ── UI ─────────────────────────────────────────────────────────────────────

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
          // Camera preview
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

          // Detection result banner
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

          // Text input row
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

          // Quick-pick chips
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

          // Control buttons
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
    handLandmarker.close();   // ← was poseDetector.close()
    interpreter?.close();
    tts.stop();
    speech.stop();
    textController.dispose();
    textFocusNode.dispose();
    super.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// VideoScreen — unchanged
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
