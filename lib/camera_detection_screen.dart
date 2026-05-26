import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:video_player/video_player.dart';
import 'package:hand_landmarker/hand_landmarker.dart';
import 'dart:math';
import 'dart:typed_data';

class CameraDetectionScreen extends StatefulWidget {
  @override
  State<CameraDetectionScreen> createState() => _CameraDetectionScreenState();
}

class _CameraDetectionScreenState extends State<CameraDetectionScreen> {

  CameraController?     controller;
  Interpreter?          interpreter;
  HandLandmarkerPlugin? _plugin;

  FlutterTts       tts    = FlutterTts();
  stt.SpeechToText speech = stt.SpeechToText();

  bool isCameraOn     = false;
  bool isProcessing   = false;
  bool isStreamActive = false;
  bool isModelLoaded  = false;
  bool isListening    = false;

  List<List<double>> sequence = [];

  String detectedText  = "";
  String lastResult    = "";
  String modelStatus   = "Loading model...";
  String micStatus     = "Mic off";
  String debugStatus   = "No hands yet";

  DateTime lastTrigger = DateTime.now();

  final int SEQ_LEN            = 25;
  final int FEATURES_PER_FRAME = 126;

  int _rotation   = 90;
  int _frameCount = 0;

  final TextEditingController textController = TextEditingController();
  final FocusNode             textFocusNode  = FocusNode();

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
    "baap","dost","ghar","khandan",
    "kitaab","likhna","maa","parhna","talibeilm",
  ];

  final Map<String, List<String>> urduSynonyms = {
    "baap":      ["baap","father","dad","papa","walid","aba","bap"],
    "dost":      ["dost","friend","yaar","companion","saathi","dosta"],
    "ghar":      ["ghar","home","house","makan","residence"],
    "khandan":   ["khandan","family","gharana","rishtedaar","khandaan"],
    "kitaab":    ["kitaab","book","kitab","pustak"],
    "likhna":    ["likhna","write","likhai","likaai","likho"],
    "maa":       ["maa","mother","mom","amma","walida","mama"],
    "parhna":    ["parhna","read","study","padhai","mutalia","parho"],
    "talibeilm": ["talibeilm","student","talib-e-ilam","shagird"],
  };

  @override
  void initState() {
    super.initState();
    _initPlugin();
    loadModel();
    initTTS();
    initSpeech();
  }

  void _initPlugin() {
    try {
      _plugin = HandLandmarkerPlugin.create(
        numHands: 2,
        minHandDetectionConfidence: 0.5,
        delegate: HandLandmarkerDelegate.cpu,
      );
      print("HandLandmarkerPlugin ready");
    } catch (e) {
      print("HandLandmarkerPlugin error: $e");
      _plugin = null;
    }
  }

  Future<void> initTTS() async {
    await tts.setLanguage("ur-PK");
    await tts.setSpeechRate(0.5);
    await tts.setPitch(1.0);
  }

  Future<void> initSpeech() async {
    try {
      bool ok = await speech.initialize();
      print(ok ? "Speech available" : "Speech not available");
    } catch (e) {
      print("Speech init error: $e");
    }
  }

  Future<void> loadModel() async {
    try {
      setState(() => modelStatus = "Loading model...");

      // tflite_flutter 0.10.4 — load with options
      final options = InterpreterOptions()..threads = 2;
      interpreter = await Interpreter.fromAsset(
        "assets/model.tflite",
        options: options,
      );

      // Resize input tensor to exactly [1, 25, 126]
      interpreter!.resizeInputTensor(0, [1, SEQ_LEN, FEATURES_PER_FRAME]);
      interpreter!.allocateTensors();

      final inShape  = interpreter!.getInputTensor(0).shape;
      final outShape = interpreter!.getOutputTensor(0).shape;

      print("Input  shape: $inShape");
      print("Output shape: $outShape");

      setState(() {
        isModelLoaded = true;
        modelStatus   = "Model ready! $inShape → $outShape";
      });

    } catch (e) {
      setState(() {
        isModelLoaded = false;
        modelStatus   = "Model error: ${e.toString().substring(0, min(80, e.toString().length))}";
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
        isCameraOn     = false;
        isStreamActive = false;
        debugStatus    = "No hands yet";
      });
    } else {
      if (!isModelLoaded) {
        _showSnackBar("Model not loaded: $modelStatus");
        return;
      }
      setState(() => isCameraOn = true);
      await _initCamera();
    }
  }

  Future<void> _initCamera() async {
    try {
      final cams = await availableCameras();
      final cam  = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cams.first,
      );
      controller = CameraController(
        cam,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await controller!.initialize();
      if (mounted) setState(() {});
      if (!isStreamActive && isModelLoaded && _plugin != null) {
        _startStream();
      }
    } catch (e) {
      print("Camera error: $e");
      _showSnackBar("Camera error: $e");
      setState(() => isCameraOn = false);
    }
  }

  void _startStream() {
    if (controller == null || isStreamActive || !isModelLoaded || _plugin == null) return;
    isStreamActive = true;

    controller!.startImageStream((CameraImage image) async {
      if (isProcessing) return;
      isProcessing = true;
      try {
        final List<Hand> hands = await Future.microtask(
          () => _plugin!.detect(image, _rotation),
        );

        _frameCount++;
        if (_frameCount % 30 == 0) {
          print("Frame $_frameCount | Hands: ${hands.length} | Rot: $_rotation");
          if (mounted) {
            setState(() {
              debugStatus = "Hands: ${hands.length} | Rot: $_rotation° | F:$_frameCount";
            });
          }
        }

        if (mounted) _processHands(hands);
      } catch (e) {
        print("Stream error: $e");
      }
      isProcessing = false;
    });
  }

  void _processHands(List<Hand> hands) {
    List<double> hand0 = List.filled(63, 0.0);
    List<double> hand1 = List.filled(63, 0.0);

    if (hands.isNotEmpty)  hand0 = _toFeatures(hands[0]);
    if (hands.length >= 2) hand1 = _toFeatures(hands[1]);

    final frame = [...hand0, ...hand1];
    sequence.add(frame);
    if (sequence.length > SEQ_LEN) sequence.removeAt(0);

    if (sequence.length == SEQ_LEN) {
      final pred = predict(sequence);
      final now  = DateTime.now();

      if (pred != "unknown" &&
          pred != lastResult &&
          now.difference(lastTrigger).inMilliseconds > 1500) {
        lastResult  = pred;
        lastTrigger = now;
        if (mounted) setState(() => detectedText = pred);
        print("SIGN DETECTED: $pred");
        tts.speak(pred);
        _showVideo(pred);
      }
    }
  }

  List<double> _toFeatures(Hand hand) {
    final wx = hand.landmarks[0].x;
    final wy = hand.landmarks[0].y;
    final wz = hand.landmarks[0].z;
    final out = <double>[];
    for (final lm in hand.landmarks) {
      out.add(lm.x - wx);
      out.add(lm.y - wy);
      out.add(lm.z - wz);
    }
    return out;
  }

  String predict(List<List<double>> seq) {
    if (interpreter == null || !isModelLoaded) return "unknown";
    try {
      // tflite_flutter 0.10.4 correct format:
      // Input must be typed as List<List<List<double>>> with exact shape [1, 25, 126]
      // Use Float32List internally to ensure correct dtype

      // Build flat Float32List
      final flat = Float32List(SEQ_LEN * FEATURES_PER_FRAME);
      for (int i = 0; i < SEQ_LEN; i++) {
        for (int j = 0; j < FEATURES_PER_FRAME; j++) {
          flat[i * FEATURES_PER_FRAME + j] = seq[i][j];
        }
      }

      // Reshape into [1, 25, 126] as List structure
      final input = [
        List.generate(SEQ_LEN, (i) =>
          List.generate(FEATURES_PER_FRAME, (j) =>
            flat[i * FEATURES_PER_FRAME + j].toDouble()
          )
        )
      ];

      // Output [1, 9]
      final output = [List<double>.filled(labels.length, 0.0)];

      interpreter!.run(input, output);

      int    best  = 0;
      double score = output[0][0];
      for (int i = 1; i < labels.length; i++) {
        if (output[0][i] > score) {
          score = output[0][i];
          best  = i;
        }
      }

      if (_frameCount % 30 == 0) {
        print("Scores: ${output[0].asMap().entries.map((e) => '${labels[e.key]}:${e.value.toStringAsFixed(2)}').join(', ')}");
      }

      print("Best: ${labels[best]} (${score.toStringAsFixed(3)})");
      return score > 0.4 ? labels[best] : "unknown";

    } catch (e) {
      print("Prediction error: $e");
      return "unknown";
    }
  }

  void handleTextInput(String text) {
    final input = text.toLowerCase().trim();
    if (input.isEmpty) { _showSnackBar("Please enter some text"); return; }
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
    for (final e in urduSynonyms.entries) {
      if (e.value.contains(input)) return e.key;
    }
    for (final k in signMap.keys) {
      if (input.contains(k) || k.contains(input)) return k;
    }
    return null;
  }

  void toggleMic() async {
    if (isListening) {
      await speech.stop();
      setState(() { isListening = false; micStatus = "Mic off"; });
    } else {
      if (await speech.initialize()) {
        setState(() {
          isListening  = true;
          micStatus    = "Listening...";
          detectedText = "Listening...";
        });
        speech.listen(
          onResult: (r) {
            final spoken = r.recognizedWords;
            setState(() => detectedText = "Heard: $spoken");
            speech.stop();
            setState(() { isListening = false; micStatus = "Mic off"; });
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
    if (!signMap.containsKey(key)) { _showSnackBar("Video not found: $key"); return; }
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => VideoScreen(signMap[key]!, key)));
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 3)));
  }

  void clearText() { textController.clear(); setState(() => detectedText = ""); }

  void _showModelErrorDialog() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text("Model Error"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(modelStatus,
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
              const SizedBox(height: 8),
              const Text("Make sure model.tflite is in assets/ folder"),
              const Text("and listed in pubspec.yaml under assets:"),
            ],
          ),
          actions: [TextButton(
              onPressed: () => Navigator.pop(context), child: const Text("OK"))],
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
            const Text("2. Show your hand sign to camera"),
            const Text("3. App speaks the detected sign"),
            const Text("4. Type or speak Roman Urdu words"),
            const Text("5. If no detection, try rotation buttons"),
            const SizedBox(height: 10),
            const Text("Signs:", style: TextStyle(fontWeight: FontWeight.bold)),
            Wrap(spacing: 8,
                children: signMap.keys.map((k) => Chip(label: Text(k))).toList()),
          ],
        ),
        actions: [TextButton(
            onPressed: () => Navigator.pop(context), child: const Text("OK"))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Action to Speak"),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            alignment: Alignment.centerLeft,
            child: Text(modelStatus,
                style: const TextStyle(fontSize: 11, color: Colors.white70)),
          ),
        ),
      ),
      body: Column(children: [

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
              child: isCameraOn && controller != null && controller!.value.isInitialized
                  ? CameraPreview(controller!)
                  : Center(child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.videocam_off, size: 64, color: Colors.grey),
                        const SizedBox(height: 10),
                        const Text("Camera is OFF", style: TextStyle(fontSize: 16)),
                        const SizedBox(height: 10),
                        ElevatedButton(
                          onPressed: toggleCamera,
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                          child: const Text("Turn ON Camera",
                              style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    )),
            ),
          ),
        ),

        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue.shade200),
          ),
          child: Row(children: [
            const Icon(Icons.visibility, color: Colors.blue),
            const SizedBox(width: 10),
            Expanded(child: Text(
              detectedText.isEmpty ? "No sign detected yet" : detectedText,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: detectedText.isEmpty ? Colors.grey : Colors.black,
              ),
            )),
          ]),
        ),

        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(children: [
            const Icon(Icons.bug_report, size: 14, color: Colors.grey),
            const SizedBox(width: 6),
            Expanded(child: Text(debugStatus,
                style: const TextStyle(fontSize: 11, color: Colors.grey))),
          ]),
        ),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          child: Row(children: [
            const Text("Rotation: ", style: TextStyle(fontSize: 11)),
            ...[0, 90, 180, 270].map((r) => Padding(
              padding: const EdgeInsets.only(right: 4),
              child: GestureDetector(
                onTap: () {
                  setState(() => _rotation = r);
                  sequence.clear();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _rotation == r ? Colors.blue : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text("$r°", style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: _rotation == r ? Colors.white : Colors.black54,
                  )),
                ),
              ),
            )).toList(),
          ]),
        ),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: textController,
                focusNode: textFocusNode,
                decoration: InputDecoration(
                  hintText: "Type Roman Urdu (e.g., baap, dost, ghar)",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  prefixIcon: const Icon(Icons.keyboard),
                  suffixIcon: textController.text.isNotEmpty
                      ? IconButton(icon: const Icon(Icons.clear), onPressed: clearText)
                      : null,
                ),
                onSubmitted: (v) { textFocusNode.unfocus(); handleTextInput(v); },
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () { textFocusNode.unfocus(); handleTextInput(textController.text); },
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16)),
              child: const Icon(Icons.send, color: Colors.white),
            ),
          ]),
        ),

        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: signMap.keys.map((key) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ActionChip(
                label: Text(key),
                onPressed: () => handleTextInput(key),
                backgroundColor: Colors.blue.shade100,
              ),
            )).toList(),
          ),
        ),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _btn(
                icon: isCameraOn ? Icons.videocam : Icons.videocam_off,
                color: Colors.blue,
                label: isCameraOn ? "Camera ON" : "Camera OFF",
                onTap: toggleCamera,
              ),
              Stack(
                alignment: Alignment.topRight,
                children: [
                  _btn(
                    icon: isListening ? Icons.mic : Icons.mic_none,
                    color: isListening ? Colors.red : Colors.grey,
                    label: micStatus,
                    onTap: toggleMic,
                  ),
                  if (isListening)
                    Positioned(right: 4, top: 4,
                      child: Container(
                        width: 10, height: 10,
                        decoration: const BoxDecoration(
                            color: Colors.red, shape: BoxShape.circle),
                      )),
                ],
              ),
              _btn(icon: Icons.info, color: Colors.orange,
                   label: "Help", onTap: _showInfoDialog),
            ],
          ),
        ),

      ]),
    );
  }

  Widget _btn({
    required IconData icon, required Color color,
    required String label,  required VoidCallback onTap,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(icon: Icon(icon, color: color, size: 40), onPressed: onTap),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  @override
  void dispose() {
    controller?.dispose();
    _plugin?.dispose();
    interpreter?.close();
    tts.stop();
    speech.stop();
    textController.dispose();
    textFocusNode.dispose();
    super.dispose();
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
  bool hasError       = false;

  @override
  void initState() { super.initState(); _loadVideo(); }

  void _loadVideo() async {
    try {
      controller = VideoPlayerController.asset(widget.path);
      await controller.initialize();
      setState(() => isVideoLoading = false);
      controller.play();
      controller.setLooping(true);
    } catch (e) {
      print("Video error: $e");
      setState(() { isVideoLoading = false; hasError = true; });
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
            ? const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                CircularProgressIndicator(color: Colors.blue),
                SizedBox(height: 20),
                Text("Loading video...", style: TextStyle(color: Colors.white)),
              ])
            : hasError
                ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 60),
                    const SizedBox(height: 20),
                    const Text("Video not found!", style: TextStyle(color: Colors.white)),
                    Text("Sign: ${widget.signName}",
                        style: const TextStyle(color: Colors.white70)),
                    const SizedBox(height: 20),
                    ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text("Go Back")),
                  ])
                : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    AspectRatio(
                      aspectRatio: controller.value.aspectRatio,
                      child: VideoPlayer(controller),
                    ),
                    const SizedBox(height: 20),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      IconButton(
                        icon: Icon(
                          controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
                          color: Colors.white, size: 40),
                        onPressed: () => setState(() {
                          controller.value.isPlaying
                              ? controller.pause() : controller.play();
                        }),
                      ),
                      IconButton(
                        icon: const Icon(Icons.replay, color: Colors.white, size: 40),
                        onPressed: () {
                          controller.seekTo(Duration.zero); controller.play();
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white, size: 40),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ]),
                  ]),
      ),
    );
  }

  @override
  void dispose() { controller.dispose(); super.dispose(); }
}
