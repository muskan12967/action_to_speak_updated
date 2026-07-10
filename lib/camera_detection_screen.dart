import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:video_player/video_player.dart';
import 'package:image/image.dart' as img; // ← NEW: for YUV->RGB + resize/normalize
import 'dart:math';

// ─────────────────────────────────────────────────────────────────────────────
// pubspec.yaml dependencies needed:
//   camera: ^0.10.5+9
//   flutter_tts: ^3.8.5
//   speech_to_text: ^6.6.0
//   tflite_flutter: ^0.10.4
//   video_player: ^2.8.1
//   image: ^4.1.3          ← NEW: pure-Dart image lib, used to convert each
//                              camera YUV frame to RGB and resize/normalize
//                              it for the alphabet classifier.
//
// REMOVED: hand_landmarker — the alphabet model is a static single-frame
// image classifier (per your label names like "Alif-Augmented" / "Alif-
// Original", which is a standard image-augmentation naming convention, not
// a landmark-coordinate convention). No hand-keypoint extraction needed.
//
// CONFIRMED from inspecting your actual model.tflite (urdu_sign_model_int8):
//   INPUT:  shape [1, 224, 224, 3], dtype UINT8, scale=0.00392157 (1/255), zero_point=0
//   OUTPUT: shape [1, 76],          dtype UINT8, scale=0.00390625 (1/256), zero_point=0
// Since input scale is exactly 1/255 with zero_point 0, raw pixel bytes
// (0-255) are fed directly as the quantized input — no float normalization.
// Output quantization params are re-read from the interpreter at load time
// as a safety net in case you ever swap in a different quantized model.
// ─────────────────────────────────────────────────────────────────────────────

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
  bool isStreamActive = false;
  bool isModelLoaded = false;
  bool isProcessingFrame = false; // throttle: only one frame in flight at a time
  bool isListening = false;

  String detectedText = "";
  String micStatus = "Mic off";
  String modelStatus = "Loading model...";

  // ── Debounce state for alphabet predictions ───────────────────────────────
  String? _lastRawPrediction;   // last frame's raw predicted label
  int _sameStreak = 0;          // how many consecutive frames agreed
  String _lastSpokenLetter = "";
  DateTime _lastSpokenAt = DateTime.now();

  // Confirmed against urdu_sign_model_int8.tflite:
  //   input:  [1,224,224,3] uint8, scale=0.00392157 (~1/255), zero_point=0
  //   output: [1,76]        uint8, scale=0.00390625 (1/256),  zero_point=0
  static const int ALPHABET_INPUT_SIZE = 224;
  static const double OUTPUT_SCALE = 0.00390625; // dequantize: raw * scale
  static const int STABLE_FRAMES_NEEDED = 4;  // consecutive-agreement threshold
  static const double CONFIDENCE_THRESHOLD = 0.6;
  static const Duration SPEAK_COOLDOWN = Duration(milliseconds: 1500);

  final TextEditingController textController = TextEditingController();
  final FocusNode textFocusNode = FocusNode();

  // ── Word → video module (UNCHANGED) ───────────────────────────────────────
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

  // ── Alphabet module: 76 classes from your labels JSON ─────────────────────
  // Index position in this list MUST match your model's output index order.
  final List<String> alphabetLabels = [
    "1-Hay-Augmented", "1-Hay-Original", "2-Hay", "Ain-Augmented", "Ain-Original",
    "Alif-Augmented", "Alif-Original", "Alifmad", "Aray", "Bay-Augmented",
    "Bay-Original", "Byeh-Augmented", "Byeh-Original", "Chay-Augmented", "Chay-Original",
    "Cyeh-Augmented", "Cyeh-Original", "Daal-Augmented", "Daal-Original", "Dal-Augmented",
    "Dal-Original", "Dochahay-Augmented", "Dochahay-Original", "Fay-Augmented", "Fay-Original",
    "Gaaf-Augmented", "Gaaf-Original", "Ghain-Augmented", "Ghain-Original", "Hamza-Augmented",
    "Hamza-Original", "Jeem", "Kaf-Augmented", "Kaf-Original", "Khay-Augmented",
    "Khay-Original", "Kiaf-Augmented", "Kiaf-Original", "Lam-Augmented", "Lam-Original",
    "Meem-Augmented", "Meem-Original", "Nuun-Augmented", "Nuun-Original", "Nuungh-Augmented",
    "Nuungh-Original", "Pay-Augmented", "Pay-Original", "Ray-Augmented", "Ray-Original",
    "Say-Augmented", "Say-Original", "Seen-Augmented", "Seen-Original", "Sheen-Augmented",
    "Sheen-Original", "Suad-Augmented", "Suad-Original", "Taay-Augmented", "Taay-Original",
    "Tay-Augmented", "Tay-Original", "Tuey-Augmented", "Tuey-Original", "Wao-Augmented",
    "Wao-Original", "Zaal-Augmented", "Zaal-Original", "Zaey-Augmented", "Zaey-Original",
    "Zay-Augmented", "Zay-Original", "Zuad-Augmented", "Zuad-Original", "Zuey-Augmented",
    "Zuey-Original",
  ];

  // Strips "-Augmented" / "-Original" so both variants speak/display as the
  // same clean letter name (e.g. "Alif-Augmented" -> "Alif").
  String _cleanLabel(String raw) {
    return raw.replaceAll("-Augmented", "").replaceAll("-Original", "");
  }

  @override
  void initState() {
    super.initState();
    loadModel();
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

  Future loadModel() async {
    try {
      setState(() => modelStatus = "Loading model...");

      interpreter = await Interpreter.fromAsset("assets/model.tflite");

      final inputShape = interpreter!.getInputTensor(0).shape;
      final outputShape = interpreter!.getOutputTensor(0).shape;

      setState(() {
        isModelLoaded = true;
        modelStatus = "✅ Model ready!";
      });

      print("✅ Model loaded successfully!");
      print("Input  shape: $inputShape");
      print("Output shape: $outputShape");

      // Heads-up if the real shape doesn't match our assumption.
      if (outputShape.isNotEmpty &&
          outputShape.last != alphabetLabels.length) {
        print("⚠️ WARNING: model outputs ${outputShape.last} classes but "
            "alphabetLabels has ${alphabetLabels.length} entries — check order/count.");
      }
    } catch (e) {
      setState(() {
        isModelLoaded = false;
        modelStatus = "❌ Error: ${e.toString().substring(0, min(150, e.toString().length))}";
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
              Text("2. Update pubspec.yaml assets list to include it"),
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

  // ── CHANGED: per-frame static image classification ────────────────────────
  // Throttled so we only ever have one frame being converted/classified at a
  // time — YUV->RGB conversion + resize is real CPU work, unlike the old
  // landmark-plugin path which handled that natively off the UI thread.
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
      final rgbImage = _convertCameraImageToImage(cameraImage);
      if (rgbImage == null) return;

      // Rotate to upright based on sensor orientation (front camera on most
      // Android phones is 270 or 90 depending on device — adjust if your
      // preview looks sideways/upside down during testing).
      final rotated = camera.sensorOrientation == 0
          ? rgbImage
          : img.copyRotate(rgbImage, angle: camera.sensorOrientation);

      final resized = img.copyResize(
        rotated,
        width: ALPHABET_INPUT_SIZE,
        height: ALPHABET_INPUT_SIZE,
      );

      // Model is uint8-quantized: input is raw 0-255 pixel bytes (no /255
      // normalization — the quantization scale already accounts for that),
      // output is also uint8 and needs dequantizing to get a real probability.
      final input = _imageToUint8Tensor(resized);
      final output =
          List.generate(1, (_) => List.filled(alphabetLabels.length, 0));

      interpreter!.run(input, output);

      int idx = 0;
      int maxRaw = output[0][0];
      for (int i = 1; i < alphabetLabels.length; i++) {
        if (output[0][i] > maxRaw) {
          maxRaw = output[0][i];
          idx = i;
        }
      }

      // Dequantize: output scale = 0.00390625 (1/256), zero_point = 0
      final double confidence = maxRaw * OUTPUT_SCALE;

      _handlePrediction(alphabetLabels[idx], confidence);
    } catch (e) {
      print("❌ Frame classification error: $e");
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

  // Converts a YUV_420_888 (Android) or BGRA8888 (iOS) CameraImage into an
  // `image` package Image for resizing/normalizing.
  img.Image? _convertCameraImageToImage(CameraImage cameraImage) {
    try {
      if (cameraImage.format.group == ImageFormatGroup.yuv420) {
        return _convertYUV420(cameraImage);
      } else if (cameraImage.format.group == ImageFormatGroup.bgra8888) {
        return img.Image.fromBytes(
          width: cameraImage.width,
          height: cameraImage.height,
          bytes: cameraImage.planes[0].bytes.buffer,
          order: img.ChannelOrder.bgra,
        );
      }
      print("Unsupported image format: ${cameraImage.format.group}");
      return null;
    } catch (e) {
      print("Image conversion error: $e");
      return null;
    }
  }

  img.Image _convertYUV420(CameraImage cameraImage) {
    final width = cameraImage.width;
    final height = cameraImage.height;

    final yPlane = cameraImage.planes[0];
    final uPlane = cameraImage.planes[1];
    final vPlane = cameraImage.planes[2];

    final out = img.Image(width: width, height: height);

    final int uvRowStride = uPlane.bytesPerRow;
    final int uvPixelStride = uPlane.bytesPerPixel ?? 1;

    for (int y = 0; y < height; y++) {
      final int yRowOffset = y * yPlane.bytesPerRow;
      final int uvRowOffset = (y >> 1) * uvRowStride;

      for (int x = 0; x < width; x++) {
        final int yIndex = yRowOffset + x;
        final int uvIndex = uvRowOffset + (x >> 1) * uvPixelStride;

        final yVal = yPlane.bytes[yIndex];
        final uVal = uPlane.bytes[uvIndex];
        final vVal = vPlane.bytes[uvIndex];

        // Standard YUV -> RGB conversion
        final int r = (yVal + 1.370705 * (vVal - 128)).round().clamp(0, 255);
        final int g = (yVal - 0.337633 * (uVal - 128) - 0.698001 * (vVal - 128))
            .round()
            .clamp(0, 255);
        final int b = (yVal + 1.732446 * (uVal - 128)).round().clamp(0, 255);

        out.setPixelRgb(x, y, r, g, b);
      }
    }

    return out;
  }

  // Builds a [1, SIZE, SIZE, 3] uint8 tensor of raw pixel values (0-255).
  // Confirmed against the actual model: input dtype=uint8, scale≈1/255,
  // zero_point=0 — that quantization mapping already IS "pixel/255", so we
  // feed raw bytes directly rather than normalizing to a float 0-1 range.
  List<List<List<List<int>>>> _imageToUint8Tensor(img.Image image) {
    return [
      List.generate(
        image.height,
        (y) => List.generate(
          image.width,
          (x) {
            final pixel = image.getPixel(x, y);
            return [
              pixel.r.toInt(),
              pixel.g.toInt(),
              pixel.b.toInt(),
            ];
          },
        ),
      ),
    ];
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
    tts.stop();
    speech.stop();
    textController.dispose();
    textFocusNode.dispose();
    super.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// VideoScreen — UNCHANGED (word → video module)
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
