import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:video_player/video_player.dart';
import 'package:hand_landmarker/hand_landmarker.dart';

import 'dart:math';
import 'package:flutter/services.dart' show rootBundle;

class CameraDetectionScreen extends StatefulWidget {
  @override
  State<CameraDetectionScreen> createState() => _CameraDetectionScreenState();
}

class _CameraDetectionScreenState extends State<CameraDetectionScreen> {

  CameraController? controller;
  Interpreter? interpreter;
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
  final int FEATURES_PER_FRAME = 126; // 2 hands × 21 landmarks × 3

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
    "baap","dost","ghar","khandan",
    "kitaab","likhna","maa","parhna","talibeilm"
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

  final Set<String> twoHandSigns = {"likhna", "dost", "khandan", "parhna", "ghar", "kitaab"};
  final Set<String> oneHandSigns = {"baap", "maa", "talibeilm"};

  @override
  void initState() {
    super.initState();

    // Initialize Hand Landmarker
    final options = HandLandmarkerOptions(
      runningMode: RunningMode.liveStream,
      numHands: 2,
      minDetectionConfidence: 0.5,
      minTrackingConfidence: 0.5,
    );
    handLandmarker = HandLandmarker(options: options);

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
      if (available) {
        print("Speech recognition available");
      } else {
        print("Speech recognition not available");
      }
    } catch (e) {
      print("Speech initialization error: $e");
    }
  }

  Future loadModel() async {
    try {
      setState(() {
        modelStatus = "Loading model...";
      });
      
      // Load model from assets
      interpreter = await Interpreter.fromAsset("assets/model.tflite");
      
      setState(() {
        isModelLoaded = true;
        modelStatus = "✅ Model ready!";
      });
      
      print("✅ Model loaded successfully!");
      
      // Get model details
      var inputShape = interpreter!.getInputTensor(0).shape;
      var outputShape = interpreter!.getOutputTensor(0).shape;
      print("Model input shape: $inputShape");
      print("Model output shape: $outputShape");
      
    } catch (e) {
      setState(() {
        isModelLoaded = false;
        modelStatus = "❌ Error: ${e.toString().substring(0, 35)}";
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
          title: Text("Model File Missing"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("model.tflite file not found!", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
              SizedBox(height: 10),
              Text("Please ensure:", style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 5),
              Text("1. Copy 'model.tflite' to 'assets/' folder"),
              Text("2. Update pubspec.yaml with assets/model.tflite"),
              Text("3. Run: flutter clean && flutter pub get"),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("OK"),
            ),
          ],
        ),
      );
    });
  }

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
  
  InputImage inputImageFromCamera(
    CameraImage image, CameraDescription camera) { 
    final plane = image.planes[0]; 
    final inputImage = InputImage.fromBytes(
      bytes: plane.bytes, 
      metadata: InputImageMetadata( 
        size: Size(image.width.toDouble(), image.height.toDouble()), 
        rotation: InputImageRotationValue.fromRawValue(camera.sensorOrientation) ?? 
        InputImageRotation.rotation0deg, 
        format: InputImageFormatValue.fromRawValue(image.format.raw) ?? 
        InputImageFormat.nv21, 
        bytesPerRow: plane.bytesPerRow,
      ), 
    );
    return inputImage;
  }

  // Extract hand landmarks (21 points per hand, 2 hands = 126 features)
  Future<List<double>> extractLandmarks(InputImage image) async {
    try {
      final results = await handLandmarker.processImage(image);
      List<double> landmarks = [];
      
      if (results.handLandmarks.isNotEmpty) {
        // Process up to 2 hands
        for (int handIdx = 0; handIdx < min(2, results.handLandmarks.length); handIdx++) {
          final hand = results.handLandmarks[handIdx];
          for (final landmark in hand) {
            landmarks.add(landmark.x);
            landmarks.add(landmark.y);
            landmarks.add(landmark.z ?? 0.0);
          }
        }
        
        // If only one hand detected, pad with zeros for second hand
        if (results.handLandmarks.length == 1) {
          landmarks.addAll(List.filled(63, 0.0));
        }
      } else {
        // No hands detected
        landmarks = List.filled(FEATURES_PER_FRAME, 0.0);
      }
      
      // Ensure exactly 126 features
      if (landmarks.length < FEATURES_PER_FRAME) {
        landmarks.addAll(List.filled(FEATURES_PER_FRAME - landmarks.length, 0.0));
      } else if (landmarks.length > FEATURES_PER_FRAME) {
        landmarks = landmarks.sublist(0, FEATURES_PER_FRAME);
      }
      
      return landmarks;
      
    } catch (e) {
      print("Landmark extraction error: $e");
      return List.filled(FEATURES_PER_FRAME, 0.0);
    }
  }

  // Real model prediction - NO DEMO MODE
  String predict(List<List<double>> seq) {
    if (interpreter == null || !isModelLoaded) {
      print("❌ Model not loaded!");
      return "unknown";
    }
    
    try {
      // Prepare input shape [1, 25, 126]
      List<List<List<double>>> input = [seq];
      var output = List.generate(1, (_) => List.filled(labels.length, 0.0));
      
      // Run inference
      interpreter!.run(input, output);
      
      // Find highest probability
      int idx = 0;
      double maxVal = output[0][0];
      
      for (int i = 0; i < labels.length; i++) {
        if (output[0][i] > maxVal) {
          maxVal = output[0][i];
          idx = i;
        }
      }
      
      print("🎯 Prediction: ${labels[idx]} (confidence: ${maxVal.toStringAsFixed(3)})");
      
      // Confidence threshold
      if (maxVal > 0.5) {
        return labels[idx];
      }
      return "unknown";
      
    } catch (e) {
      print("❌ Prediction error: $e");
      return "unknown";
    }
  }

  double checkSequenceStability(List<List<double>> seq) {
    if (seq.length < 5) return 0.0;
    
    double totalVariance = 0.0;
    int comparisons = 0;
    
    for (int i = seq.length - 10; i < seq.length - 1; i++) {
      if (i < 0) continue;
      double variance = 0.0;
      for (int j = 0; j < seq[i].length; j++) {
        variance += pow(seq[i+1][j] - seq[i][j], 2);
      }
      totalVariance += sqrt(variance / seq[i].length);
      comparisons++;
    }
    
    if (comparisons == 0) return 0.0;
    double avgVariance = totalVariance / comparisons;
    return 1.0 - avgVariance.clamp(0.0, 0.8) / 0.8;
  }

  void startStream() {
    if (controller == null || isStreamActive || !isModelLoaded) return;

    controller!.startImageStream((image) async {
      if (isProcessing) return;
      isProcessing = true;

      try {
        final inputImage = inputImageFromCamera(image, controller!.description);
        final frame = await extractLandmarks(inputImage);

        sequence.add(frame);

        if (sequence.length > SEQ_LEN) {
          sequence.removeAt(0);
        }

        if (sequence.length == SEQ_LEN && isModelLoaded) {
          String result = predict(sequence);
          final now = DateTime.now();

          if (result != "unknown") {
            double stability = checkSequenceStability(sequence);
            
            if (result != lastResult &&
                now.difference(lastTrigger).inMilliseconds > 1500 &&
                stability > 0.3) {

              lastResult = result;
              lastTrigger = now;

              setState(() {
                detectedText = result;
              });

              print("✅ SIGN DETECTED: $result");
              await tts.speak(result);
              _showVideo(result);
            }
          }
        }
      } catch (e) {
        print("Stream error: $e");
      }

      isProcessing = false;
    });

    isStreamActive = true;
  }

  void handleTextInput(String text) {
    String input = text.toLowerCase().trim();
    if (input.isEmpty) {
      _showSnackBar("Please enter some text");
      return;
    }

    print("Searching for: $input");
    textController.clear();
    
    String? matchedKey = _findMatch(input);
    
    if (matchedKey != null) {
      setState(() => detectedText = matchedKey);
      tts.speak("یہ $matchedKey کا اشارہ ہے");
      _showVideo(matchedKey);
    } else {
      setState(() {
        detectedText = "No match found for: $input";
      });
      tts.speak("معاف کیجئے، یہ لفظ نہیں ملا");
      _showSnackBar("'$input' not found in vocabulary");
    }
  }

  String? _findMatch(String input) {
    if (signMap.containsKey(input)) {
      return input;
    }
    
    for (var entry in urduSynonyms.entries) {
      if (entry.value.contains(input)) {
        return entry.key;
      }
    }
    
    for (var key in signMap.keys) {
      if (input.contains(key) || key.contains(input)) {
        return key;
      }
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
      _showSnackBar("Microphone stopped");
    } else {
      bool available = await speech.initialize();
      if (available) {
        setState(() {
          isListening = true;
          micStatus = "🎤 Listening...";
          detectedText = "Listening...";
        });
        
        speech.listen(
          onResult: (result) {
            String spokenText = result.recognizedWords;
            print("Heard: $spokenText");
            
            setState(() {
              detectedText = "Heard: $spokenText";
            });
            
            speech.stop();
            setState(() {
              isListening = false;
              micStatus = "Mic off";
            });
            
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
    if (!signMap.containsKey(key)) {
      _showSnackBar("Video not found for: $key");
      return;
    }
    
    String videoPath = signMap[key]!;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoScreen(videoPath, key),
      ),
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void clearText() {
    textController.clear();
    setState(() {
      detectedText = "";
    });
    _showSnackBar("Text cleared");
  }

  void _showInfoDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("How to Use"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("1. 📷 Turn ON camera"),
            Text("2. 🤚 Perform hand sign in front of camera"),
            Text("3. 📢 App will speak the sign name"),
            Text("4. ✍️ Type Roman Urdu words directly"),
            Text("5. 🎤 Click mic to speak words"),
            SizedBox(height: 10),
            Text("Available signs:", style: TextStyle(fontWeight: FontWeight.bold)),
            Wrap(
              spacing: 8,
              children: signMap.keys.map((key) => Chip(label: Text(key))).toList(),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("OK"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Action to Speak - Sign Detection"),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(30),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            alignment: Alignment.centerLeft,
            child: Text(
              modelStatus,
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            flex: 2,
            child: Container(
              margin: EdgeInsets.all(8),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.blue, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: isCameraOn && controller != null && controller!.value.isInitialized
                    ? CameraPreview(controller!)
                    : Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.videocam_off, size: 64, color: Colors.grey),
                            SizedBox(height: 10),
                            Text("Camera is OFF", style: TextStyle(fontSize: 16)),
                            SizedBox(height: 10),
                            ElevatedButton(
                              onPressed: toggleCamera,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                              ),
                              child: Text("Turn ON Camera"),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          ),
          
          Container(
            margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.visibility, color: Colors.blue),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    detectedText.isEmpty ? "No sign detected yet" : detectedText,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: detectedText.isEmpty ? Colors.grey : Colors.black,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: textController,
                    focusNode: textFocusNode,
                    decoration: InputDecoration(
                      hintText: "Type Roman Urdu (e.g., baap, dost, ghar)",
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      prefixIcon: Icon(Icons.keyboard),
                      suffixIcon: textController.text.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.clear),
                              onPressed: clearText,
                            )
                          : null,
                    ),
                    onSubmitted: (value) {
                      textFocusNode.unfocus();
                      handleTextInput(value);
                    },
                  ),
                ),
                SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    textFocusNode.unfocus();
                    handleTextInput(textController.text);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  ),
                  child: Icon(Icons.send, color: Colors.white),
                ),
              ],
            ),
          ),
          
          Container(
            height: 50,
            margin: EdgeInsets.symmetric(horizontal: 16),
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: signMap.keys.map((key) {
                return Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
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
            padding: EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Column(
                  children: [
                    IconButton(
                      icon: Icon(
                        isCameraOn ? Icons.videocam : Icons.videocam_off,
                        color: Colors.blue,
                        size: 40,
                      ),
                      onPressed: toggleCamera,
                    ),
                    Text(isCameraOn ? "Camera ON" : "Camera OFF"),
                  ],
                ),
                
                Column(
                  children: [
                    Stack(
                      children: [
                        IconButton(
                          icon: Icon(
                            isListening ? Icons.mic : Icons.mic_none,
                            color: isListening ? Colors.red : Colors.grey,
                            size: 40,
                          ),
                          onPressed: toggleMic,
                        ),
                        if (isListening)
                          Positioned(
                            right: 0,
                            top: 0,
                            child: Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                      ],
                    ),
                    Text(micStatus, style: TextStyle(fontSize: 12)),
                  ],
                ),
                
                Column(
                  children: [
                    IconButton(
                      icon: Icon(Icons.info, color: Colors.orange, size: 40),
                      onPressed: _showInfoDialog,
                    ),
                    Text("Help"),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    controller?.dispose();
    handLandmarker.close();
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
  
  VideoScreen(this.path, this.signName);

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
      setState(() {
        isVideoLoading = false;
      });
      controller.play();
      controller.setLooping(true);
    } catch (e) {
      print("Error loading video: $e");
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
      ),
      backgroundColor: Colors.black,
      body: Center(
        child: isVideoLoading
            ? Column(
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
                      Icon(Icons.error_outline, color: Colors.red, size: 60),
                      SizedBox(height: 20),
                      Text("Video not found!", style: TextStyle(color: Colors.white)),
                      SizedBox(height: 10),
                      Text("Sign: ${widget.signName}", style: TextStyle(color: Colors.white70)),
                      SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text("Go Back"),
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
                      SizedBox(height: 20),
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
                                controller.value.isPlaying
                                    ? controller.pause()
                                    : controller.play();
                              });
                            },
                          ),
                          IconButton(
                            icon: Icon(Icons.replay, color: Colors.white, size: 40),
                            onPressed: () {
                              controller.seekTo(Duration.zero);
                              controller.play();
                            },
                          ),
                          IconButton(
                            icon: Icon(Icons.close, color: Colors.white, size: 40),
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
