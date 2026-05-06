import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:video_player/video_player.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'dart:math';
import 'package:flutter/services.dart' show rootBundle;

class CameraDetectionScreen extends StatefulWidget {
  @override
  State<CameraDetectionScreen> createState() => _CameraDetectionScreenState();
}

class _CameraDetectionScreenState extends State<CameraDetectionScreen> {

  CameraController? controller;
  Interpreter? interpreter;
  late PoseDetector poseDetector;

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
  String speechOutput = ""; // Option 3: Text Output
  String voiceInputText = ""; // Option 4: Voice Input

  DateTime lastTrigger = DateTime.now();

  final int SEQ_LEN = 25;

  final TextEditingController textController = TextEditingController();
  final FocusNode textFocusNode = FocusNode();

  // Option 3: Text output controller
  final TextEditingController textOutputController = TextEditingController();
  
  // Option 4: Voice input status
  bool isVoiceInputEnabled = false;

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
    "ghar": ["ghar", "home", "house", "makan", "residence", "ghar"],
    "khandan": ["khandan", "family", "gharana", "rishtedaar", "khandaan"],
    "kitaab": ["kitaab", "book", "kitab", "pustak", "book"],
    "likhna": ["likhna", "write", "likhai", "likaai", "likho"],
    "maa": ["maa", "mother", "mom", "amma", "walida", "mama"],
    "parhna": ["parhna", "read", "study", "padhai", "mutalia", "parho"],
    "talibeilm": ["talibeilm", "student", "talib-e-ilam", "shagird", "student"],
  };

  final Set<String> twoHandSigns = {"likhna", "dost", "khandan", "parhna", "ghar", "kitaab"};
  final Set<String> oneHandSigns = {"baap", "maa", "talibeilm"};

  @override
  void initState() {
    super.initState();

    poseDetector = PoseDetector(
      options: PoseDetectorOptions(
        mode: PoseDetectionMode.stream,
      ),
    );

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
        modelStatus = "Loading model from assets/model.tflite...";
      });
      
      // First check if file exists
      try {
        final fileData = await rootBundle.load('assets/model.tflite');
        print("✅ Model file found! Size: ${fileData.lengthInBytes} bytes");
      } catch (e) {
        print("❌ Model file not found: assets/model.tflite");
        setState(() {
          modelStatus = "❌ Model file not found in assets/";
        });
        _showModelErrorDialog();
        return;
      }
      
      // Load model from asset
      interpreter = await Interpreter.fromAsset("assets/model.tflite");
      
      setState(() {
        isModelLoaded = true;
        modelStatus = "✅ Model ready";
      });
      
      print("✅ Model loaded successfully from assets/model.tflite");
      
      // Get model details
      var inputShape = interpreter!.getInputTensor(0).shape;
      var outputShape = interpreter!.getOutputTensor(0).shape;
      print("Model input shape: $inputShape");
      print("Model output shape: $outputShape");
      
    } catch (e) {
      setState(() {
        isModelLoaded = false;
        modelStatus = "❌ Model load failed: ${e.toString().substring(0, 40)}";
      });
      print("❌ Error loading model: $e");
      _showModelErrorDialog();
    }
  }

  void _showModelErrorDialog() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text("Model File Missing"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("model.tflite file not found!", style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 10),
              Text("Please ensure:"),
              SizedBox(height: 5),
              Text("1. model.tflite is in assets/ folder"),
              Text("2. Path in pubspec.yaml is correct"),
              Text("3. Run 'flutter clean' and 'flutter pub get'"),
              Text("4. Restart the app"),
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
        _showSnackBar("Model not loaded yet. Please wait or restart app.");
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

  Future<List<double>> extractLandmarks(InputImage image) async {
    final poses = await poseDetector.processImage(image);
    if (poses.isEmpty) return List.filled(60, 0.0);

    final primaryPose = poses.first;
    
    final leftShoulder = primaryPose.landmarks[PoseLandmarkType.leftShoulder];
    final rightShoulder = primaryPose.landmarks[PoseLandmarkType.rightShoulder];
    
    double shoulderCenterX = 0.5;
    double shoulderCenterY = 0.5;
    double torsoLength = 0.5;
    
    if (leftShoulder != null && rightShoulder != null) {
      shoulderCenterX = (leftShoulder.x + rightShoulder.x) / 2;
      shoulderCenterY = (leftShoulder.y + rightShoulder.y) / 2;
      
      final leftHip = primaryPose.landmarks[PoseLandmarkType.leftHip];
      final rightHip = primaryPose.landmarks[PoseLandmarkType.rightHip];
      
      if (leftHip != null && rightHip != null) {
        double hipCenterY = (leftHip.y + rightHip.y) / 2;
        torsoLength = hipCenterY - shoulderCenterY;
        if (torsoLength < 0.1) torsoLength = 0.5;
      }
    }

    List<double> data = [];

    final points = [
      PoseLandmarkType.nose,
      PoseLandmarkType.leftEye,
      PoseLandmarkType.rightEye,
      PoseLandmarkType.leftShoulder,
      PoseLandmarkType.rightShoulder,
      PoseLandmarkType.leftElbow,
      PoseLandmarkType.rightElbow,
      PoseLandmarkType.leftWrist,
      PoseLandmarkType.rightWrist,
      PoseLandmarkType.leftHip,
      PoseLandmarkType.rightHip,
      PoseLandmarkType.leftKnee,
      PoseLandmarkType.rightKnee,
      PoseLandmarkType.leftAnkle,
      PoseLandmarkType.rightAnkle,
      PoseLandmarkType.leftPinky,
      PoseLandmarkType.rightPinky,
      PoseLandmarkType.leftIndex,
      PoseLandmarkType.rightIndex,
      PoseLandmarkType.leftThumb,
    ];

    for (final p in points) {
      final lm = primaryPose.landmarks[p];

      if (lm != null) {
        double normalizedX = (lm.x - shoulderCenterX) / torsoLength;
        double normalizedY = (lm.y - shoulderCenterY) / torsoLength;
        double normalizedZ = (lm.z ?? 0.0) / torsoLength;
        
        data.addAll([normalizedX, normalizedY, normalizedZ]);
      } else {
        data.addAll([0.0, 0.0, 0.0]);
      }
    }

    if (data.length > 60) {
      data = data.sublist(0, 60);
    } else if (data.length < 60) {
      data.addAll(List.filled(60 - data.length, 0.0));
    }

    return data;
  }

  String predict(List<List<double>> seq) {
    if (interpreter == null || !isModelLoaded) {
      print("❌ Model not loaded! Cannot predict.");
      return "unknown";
    }
    
    try {
      List<List<List<double>>> input = [seq];
      var output = List.generate(1, (_) => List.filled(labels.length, 0.0));
      
      interpreter!.run(input, output);
      
      int idx = 0;
      double maxVal = output[0][0];
      
      for (int i = 0; i < labels.length; i++) {
        if (output[0][i] > maxVal) {
          maxVal = output[0][i];
          idx = i;
        }
      }
      
      print("📊 Prediction: ${labels[idx]} with confidence: ${maxVal.toStringAsFixed(3)}");
      
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

  Future<int> countHands(InputImage image) async {
    final poses = await poseDetector.processImage(image);
    int handCount = 0;
    
    for (var pose in poses) {
      if (pose.landmarks[PoseLandmarkType.leftWrist] != null) handCount++;
      if (pose.landmarks[PoseLandmarkType.rightWrist] != null) handCount++;
    }
    return handCount;
  }

  void startStream() {
    if (controller == null || isStreamActive || !isModelLoaded) return;

    controller!.startImageStream((image) async {
      if (isProcessing) return;
      isProcessing = true;

      try {
        final inputImage = inputImageFromCamera(image, controller!.description);
        int handCount = await countHands(inputImage);
        final frame = await extractLandmarks(inputImage);

        sequence.add(frame);

        if (sequence.length > SEQ_LEN) {
          sequence.removeAt(0);
        }

        if (sequence.length == SEQ_LEN && isModelLoaded) {
          String result = predict(sequence);
          final now = DateTime.now();

          if (result != "unknown") {
            bool validHandCount = true;
            if (twoHandSigns.contains(result) && handCount < 2) {
              validHandCount = false;
            } else if (oneHandSigns.contains(result) && handCount == 0) {
              validHandCount = false;
            }
            
            double stability = checkSequenceStability(sequence);
            
            if (validHandCount && 
                result != lastResult &&
                now.difference(lastTrigger).inMilliseconds > 1800 &&
                stability > 0.3) {

              lastResult = result;
              lastTrigger = now;

              setState(() {
                detectedText = result;
                // Option 3: Update text output
                speechOutput = "Detected: $result";
                textOutputController.text = speechOutput;
              });

              print("✅ Sign Detected: $result");
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

  // Option 3: Manual text output
  void setTextOutput(String text) {
    setState(() {
      speechOutput = text;
      textOutputController.text = text;
    });
    tts.speak(text);
  }

  void clearTextOutput() {
    setState(() {
      speechOutput = "";
      textOutputController.clear();
    });
  }

  // Option 4: Voice to Text (for hearing people to speak)
  void startVoiceInput() async {
    bool available = await speech.initialize();
    if (available) {
      setState(() {
        isVoiceInputEnabled = true;
        voiceInputText = "Listening...";
      });
      
      speech.listen(
        onResult: (result) {
          setState(() {
            voiceInputText = result.recognizedWords;
          });
          print("Voice Input: ${result.recognizedWords}");
          
          // Process voice input
          handleTextInput(result.recognizedWords);
          
          speech.stop();
          setState(() {
            isVoiceInputEnabled = false;
          });
        },
        onDevice: true,
      );
      
      _showSnackBar("Speak now...");
    } else {
      _showSnackBar("Speech recognition not available");
    }
  }

  void stopVoiceInput() {
    speech.stop();
    setState(() {
      isVoiceInputEnabled = false;
      voiceInputText = "";
    });
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
      setState(() {
        detectedText = matchedKey;
        // Option 3: Update text output
        speechOutput = "Word: $matchedKey";
        textOutputController.text = speechOutput;
      });
      tts.speak("یہ $matchedKey کا اشارہ ہے");
      _showVideo(matchedKey);
    } else {
      setState(() {
        detectedText = "No match found for: $input";
        speechOutput = "No match found";
        textOutputController.text = speechOutput;
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
    print("Playing video for: $key at path: $videoPath");
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoScreen(videoPath, key),
      ),
    ).then((_) {
      Future.delayed(Duration(milliseconds: 500), () {
        lastResult = "";
        sequence.clear();
      });
    });
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
            Text("1. 📷 Turn ON camera to detect signs"),
            SizedBox(height: 8),
            Text("2. ✍️ Type words in Roman Urdu (e.g., 'baap', 'dost')"),
            SizedBox(height: 8),
            Text("3. 📝 Text Output shows detected word"),
            SizedBox(height: 8),
            Text("4. 🎤 Voice Input (Speak to convert to sign)"),
            SizedBox(height: 8),
            Text("5. 🔊 Mic button for voice commands"),
            SizedBox(height: 8),
            Text("6. Available words:"),
            SizedBox(height: 8),
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
        title: Text("Action to Speak - Deaf Communication"),
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
          // Camera Preview (Option 1)
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
          
          // Detected Sign Display (Option 2)
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
                    detectedText.isEmpty ? "No sign detected yet" : "Sign: $detectedText",
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

          // Option 3: Text Output Section
          Container(
            margin: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.text_fields, color: Colors.green),
                    SizedBox(width: 8),
                    Text(
                      "📝 Text Output (Option 3)",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade800,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: textOutputController,
                        decoration: InputDecoration(
                          hintText: "Detected text will appear here",
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        readOnly: true,
                      ),
                    ),
                    SizedBox(width: 8),
                    IconButton(
                      icon: Icon(Icons.volume_up, color: Colors.green),
                      onPressed: () {
                        if (speechOutput.isNotEmpty) {
                          tts.speak(speechOutput);
                        }
                      },
                    ),
                    IconButton(
                      icon: Icon(Icons.clear, color: Colors.red),
                      onPressed: clearTextOutput,
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Option 4: Voice Input Section
          Container(
            margin: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.purple.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.purple.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.mic, color: Colors.purple),
                    SizedBox(width: 8),
                    Text(
                      "🎤 Voice Input (Option 4) - Speak to convert to sign",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.purple.shade800,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          voiceInputText.isEmpty ? "Click mic button and speak" : voiceInputText,
                          style: TextStyle(
                            fontSize: 14,
                            color: voiceInputText.isEmpty ? Colors.grey : Colors.black,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 8),
                    if (!isVoiceInputEnabled)
                      IconButton(
                        icon: Icon(Icons.mic, color: Colors.purple, size: 30),
                        onPressed: startVoiceInput,
                      ),
                    if (isVoiceInputEnabled)
                      Stack(
                        children: [
                          IconButton(
                            icon: Icon(Icons.mic, color: Colors.red, size: 30),
                            onPressed: stopVoiceInput,
                          ),
                          Positioned(
                            right: 0,
                            top: 0,
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
          
          // Text Input Row (Roman Urdu)
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
          
          // Quick Action Chips
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
          
          // Control Buttons
          Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Camera Button
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
                
                // Mic Button for Voice Search
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
                
                // Help Button
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
    poseDetector.close();
    interpreter?.close();
    tts.stop();
    speech.stop();
    textController.dispose();
    textOutputController.dispose();
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
      print("Loading video from: ${widget.path}");
      
      controller = VideoPlayerController.asset(widget.path);
      
      await controller.initialize();
      
      print("Video loaded successfully!");
      
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
                  CircularProgressIndicator(
                    color: Colors.blue,
                  ),
                  SizedBox(height: 20),
                  Text(
                    "Loading video...",
                    style: TextStyle(color: Colors.white),
                  ),
                ],
              )
            : hasError
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: Colors.red,
                        size: 60,
                      ),
                      SizedBox(height: 20),
                      Text(
                        "Video not found!",
                        style: TextStyle(color: Colors.white, fontSize: 18),
                      ),
                      SizedBox(height: 10),
                      Text(
                        "Sign: ${widget.signName}",
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                      SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                        ),
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
                          SizedBox(width: 20),
                          IconButton(
                            icon: Icon(Icons.replay, color: Colors.white, size: 40),
                            onPressed: () {
                              controller.seekTo(Duration.zero);
                              controller.play();
                            },
                          ),
                          SizedBox(width: 20),
                          IconButton(
                            icon: Icon(Icons.close, color: Colors.white, size: 40),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                      SizedBox(height: 10),
                      Text(
                        "Showing: ${widget.signName}",
                        style: TextStyle(color: Colors.white70, fontSize: 14),
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
