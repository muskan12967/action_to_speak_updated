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
import 'dart:io';

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

  DateTime lastTrigger = DateTime.now();

  final int SEQ_LEN = 25;
  final int FEATURES_PER_FRAME = 60;

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
        modelStatus = "🔍 Checking for model file...";
      });
      
      // First check if file exists
      bool fileExists = false;
      try {
        final fileData = await rootBundle.load('assets/model.tflite');
        print("✅ File found! Size: ${fileData.lengthInBytes} bytes");
        fileExists = true;
        setState(() {
          modelStatus = "File found (${fileData.lengthInBytes} bytes)";
        });
      } catch (e) {
        print("❌ File NOT found at assets/model.tflite");
        setState(() {
          modelStatus = "❌ model.tflite not found in assets/";
        });
        _showModelErrorDialog();
        return;
      }
      
      if (!fileExists) return;
      
      // Load the model
      interpreter = await Interpreter.fromAsset("assets/model.tflite");
      
      setState(() {
        isModelLoaded = true;
        modelStatus = "✅ Model ready! Camera ready";
      });
      
      print("✅ Model loaded successfully!");
      
      // Get model details
      var inputShape = interpreter!.getInputTensor(0).shape;
      var outputShape = interpreter!.getOutputTensor(0).shape;
      print("Model input shape: $inputShape");
      print("Model output shape: $outputShape");
      
      // Test model with dummy data
      _testModelWithDummyData();
      
    } catch (e) {
      setState(() {
        isModelLoaded = false;
        modelStatus = "❌ Error: ${e.toString().substring(0, 35)}";
      });
      print("❌ Error loading model: $e");
      _showModelErrorDialog();
    }
  }

  void _testModelWithDummyData() {
    print("="*50);
    print("TESTING MODEL WITH DUMMY DATA");
    print("="*50);
    
    if (interpreter == null) {
      print("❌ Model not loaded!");
      return;
    }
    
    // Get input shape
    var inputShape = interpreter!.getInputTensor(0).shape;
    print("Model expects input shape: $inputShape");
    
    try {
      dynamic input;
      var output = List.generate(1, (_) => List.filled(labels.length, 0.0));
      
      // Check what shape the model expects
      if (inputShape.length == 2 && inputShape[1] == 1500) {
        // Flattened input (1, 1500)
        List<double> flattened = List.generate(1500, (i) => Random().nextDouble());
        input = [flattened];
        print("Using flattened input shape (1, 1500)");
      } 
      else if (inputShape.length == 3 && inputShape[1] == 25) {
        // Sequence input (1, 25, 60)
        List<List<double>> dummySeq = List.generate(
          25,
          (i) => List.generate(60, (j) => Random().nextDouble() * 0.5)
        );
        input = [dummySeq];
        print("Using sequence input shape (1, 25, 60)");
      }
      else if (inputShape.length == 3 && inputShape[1] == 60) {
        // Transposed input (1, 60, 25)
        List<List<double>> dummySeq = List.generate(
          60,
          (i) => List.generate(25, (j) => Random().nextDouble() * 0.5)
        );
        input = [dummySeq];
        print("Using transposed input shape (1, 60, 25)");
      }
      else {
        print("⚠️ Unknown input shape: $inputShape");
        return;
      }
      
      interpreter!.run(input, output);
      print("✅ Model inference successful!");
      print("Output shape: ${output[0].length}");
      
      int idx = 0;
      double maxVal = output[0][0];
      for (int i = 0; i < labels.length; i++) {
        if (output[0][i] > maxVal) {
          maxVal = output[0][i];
          idx = i;
        }
      }
      print("🎯 Test prediction: ${labels[idx]} (confidence: ${maxVal.toStringAsFixed(4)})");
      
    } catch (e) {
      print("❌ Model test failed: $e");
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
              Text("2. Update pubspec.yaml:"),
              Container(
                margin: EdgeInsets.all(8),
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  "flutter:\n  assets:\n    - assets/model.tflite",
                  style: TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
              Text("3. Run: flutter clean && flutter pub get"),
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

  Future<List<double>> extractLandmarks(InputImage image) async {
    final poses = await poseDetector.processImage(image);
    if (poses.isEmpty) return List.filled(FEATURES_PER_FRAME, 0.0);

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

    if (data.length > FEATURES_PER_FRAME) {
      data = data.sublist(0, FEATURES_PER_FRAME);
    } else if (data.length < FEATURES_PER_FRAME) {
      data.addAll(List.filled(FEATURES_PER_FRAME - data.length, 0.0));
    }

    return data;
  }

  String predict(List<List<double>> seq) {
    if (interpreter == null || !isModelLoaded) {
      return "unknown";
    }
    
    try {
      // Get model input shape
      var inputShape = interpreter!.getInputTensor(0).shape;
      
      // Prepare input based on model's expected shape
      dynamic input;
      
      // Case 1: Flattened input (1, 1500)
      if (inputShape.length == 2 && inputShape[1] == 1500) {
        List<double> flattened = [];
        for (var frame in seq) {
          flattened.addAll(frame);
        }
        input = [flattened];
        print("📊 Using flattened input");
      }
      // Case 2: Sequence input (1, 25, 60)
      else if (inputShape.length == 3 && inputShape[1] == 25) {
        input = [seq];
        print("📊 Using sequence input (25, 60)");
      }
      // Case 3: Transposed input (1, 60, 25)
      else if (inputShape.length == 3 && inputShape[2] == 25) {
        List<List<double>> transposed = List.generate(60, (i) => 
          List.generate(25, (j) => seq[j][i])
        );
        input = [transposed];
        print("📊 Using transposed input (60, 25)");
      }
      else {
        print("⚠️ Unknown input shape: $inputShape, trying default");
        input = [seq];
      }
      
      // Create output array
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
      
      print("🎯 Prediction: ${labels[idx]} (${maxVal.toStringAsFixed(3)})");
      
      // Lower threshold for better detection
      if (maxVal > 0.3) {
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
                now.difference(lastTrigger).inMilliseconds > 1500 &&
                stability > 0.3) {

              lastResult = result;
              lastTrigger = now;

              setState(() {
                detectedText = result;
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
            Text("1. 📷 Turn ON camera to detect signs"),
            Text("2. ✍️ Type words in Roman Urdu"),
            Text("3. 🎤 Click mic to speak"),
            Text("4. Available words:"),
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
    poseDetector.close();
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
