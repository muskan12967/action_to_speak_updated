import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:video_player/video_player.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'dart:math';

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
  bool isListening = false; // Track mic status

  List<List<double>> sequence = [];

  String detectedText = "";
  String lastResult = "";
  String modelStatus = "Loading model...";
  String micStatus = "Mic off"; // Show mic status

  DateTime lastTrigger = DateTime.now();

  final int SEQ_LEN = 25;

  final TextEditingController textController = TextEditingController();
  final FocusNode textFocusNode = FocusNode(); // For keyboard management

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

  // Urdu synonyms for better recognition
  final Map<String, List<String>> urduSynonyms = {
    "baap": ["baap", "father", "dad", "papa", "walid", "aba"],
    "dost": ["dost", "friend", "yaar", "companion", "saathi"],
    "ghar": ["ghar", "home", "house", "makan", "residence"],
    "khandan": ["khandan", "family", "gharana", "rishtedaar"],
    "kitaab": ["kitaab", "book", "kitab", "pustak"],
    "likhna": ["likhna", "write", "likhai", "likaai"],
    "maa": ["maa", "mother", "mom", "amma", "walida"],
    "parhna": ["parhna", "read", "study", "padhai", "mutalia"],
    "talibeilm": ["talibeilm", "student", "talib-e-ilam", "student", "shagird"],
  };

  // Multi-hand specific sets
  final Set<String> twoHandSigns = {"kitaab", "ghar", "khandan", "parhna","likhna","dost"};
  final Set<String> oneHandSigns = {"maa", "baap","talibeilm"};

  @override
  void initState() {
    super.initState();

    poseDetector = PoseDetector(
      options: PoseDetectorOptions(
        mode: PoseDetectionMode.stream,
        multiPose: true,
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
    bool available = await speech.initialize(
      onStatus: (status) {
        print("Speech status: $status");
        setState(() {
          if (status == "notListening") {
            isListening = false;
            micStatus = "Mic off";
          }
        });
      },
      onError: (error) {
        print("Speech error: $error");
        setState(() {
          isListening = false;
          micStatus = "Mic error";
        });
      },
    );
    
    if (available) {
      print("Speech recognition available");
    } else {
      print("Speech recognition not available");
    }
  }

  Future loadModel() async {
    try {
      setState(() {
        modelStatus = "Loading model...";
      });
      
      interpreter = await Interpreter.fromAsset("assets/model.tflite");
      
      setState(() {
        isModelLoaded = true;
        modelStatus = "✅ Model ready";
      });
      
      print("✅ Model loaded successfully");
      
      if (interpreter != null) {
        var inputShape = interpreter!.getInputTensor(0).shape;
        var outputShape = interpreter!.getOutputTensor(0).shape;
        print("Model input shape: $inputShape");
        print("Model output shape: $outputShape");
      }
      
    } catch (e) {
      setState(() {
        isModelLoaded = false;
        modelStatus = "❌ Model load failed";
      });
      print("❌ Error loading model: $e");
    }
  }

  // ================= FRONT CAMERA =================
  Future initCamera() async {
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
        _showSnackBar("Model is loading, please wait...");
        return;
      }
      setState(() => isCameraOn = true);
      await initCamera();
    }
  }

  // ================= INPUT IMAGE =================
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

  // ================= MULTI-HAND LANDMARKS =================
  Future<List<double>> extractLandmarks(InputImage image) async {
    final poses = await poseDetector.processImage(image);
    if (poses.isEmpty) return List.filled(60, 0.0);

    final primaryPose = poses.first;
    
    // Get shoulder center for normalization
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

  // ================= MODEL PREDICTION =================
  String predict(List<List<double>> seq) {
    if (interpreter == null || !isModelLoaded) {
      return "unknown";
    }
    
    try {
      List<List<List<double>>> input = [seq];
      
      var output = List.generate(
        1,
        (_) => List.filled(labels.length, 0.0),
      );

      interpreter!.run(input, output);

      int idx = 0;
      double maxVal = output[0][0];

      for (int i = 0; i < output[0].length; i++) {
        if (output[0][i] > maxVal) {
          maxVal = output[0][i];
          idx = i;
        }
      }

      if (maxVal < 0.6) return "unknown";
      return labels[idx];

    } catch (e) {
      print("Prediction error: $e");
      return "unknown";
    }
  }

  // ================= CHECK GESTURE STABILITY =================
  double checkSequenceStability(List<List<double>> seq) {
    if (seq.length < 5) return 0.0;
    
    double totalVariance = 0.0;
    int comparisons = 0;
    
    for (int i = 1; i < seq.length; i++) {
      double variance = 0.0;
      for (int j = 0; j < seq[i].length; j++) {
        variance += pow(seq[i][j] - seq[i-1][j], 2);
      }
      totalVariance += sqrt(variance / seq[i].length);
      comparisons++;
    }
    
    double avgVariance = totalVariance / comparisons;
    return 1.0 - avgVariance.clamp(0.0, 0.5) / 0.5;
  }

  // ================= COUNT HANDS =================
  Future<int> countHands(InputImage image) async {
    final poses = await poseDetector.processImage(image);
    int handCount = 0;
    
    for (var pose in poses) {
      if (pose.landmarks[PoseLandmarkType.leftWrist] != null) handCount++;
      if (pose.landmarks[PoseLandmarkType.rightWrist] != null) handCount++;
    }
    return handCount;
  }

  // ================= STREAM =================
  void startStream() {
    if (controller == null || isStreamActive || interpreter == null) return;

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
                stability > 0.5) {

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

  // ================= ENHANCED TEXT INPUT WITH SYNONYMS =================
  void handleTextInput(String text) {
    String input = text.toLowerCase().trim();
    if (input.isEmpty) {
      _showSnackBar("Please enter some text");
      return;
    }

    print("Searching for: $input");
    
    // Clear text field after submission
    textController.clear();
    
    // Search using synonyms
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

  // Helper method to find matching word using synonyms
  String? _findMatch(String input) {
    // First check direct match
    if (signMap.containsKey(input)) {
      return input;
    }
    
    // Check synonyms
    for (var entry in urduSynonyms.entries) {
      if (entry.value.contains(input)) {
        return entry.key;
      }
    }
    
    // Check partial matches
    for (var key in signMap.keys) {
      if (input.contains(key) || key.contains(input)) {
        return key;
      }
    }
    
    return null;
  }

  // ================= ENHANCED MIC INPUT =================
  void toggleMic() async {
    if (isListening) {
      // Stop listening
      await speech.stop();
      setState(() {
        isListening = false;
        micStatus = "Mic off";
      });
      _showSnackBar("Microphone stopped");
    } else {
      // Start listening
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
            
            // Auto stop after getting result
            speech.stop();
            setState(() {
              isListening = false;
              micStatus = "Mic off";
            });
            
            // Process the spoken text
            handleTextInput(spokenText);
          },
          onError: (error) {
            print("Speech error: $error");
            setState(() {
              isListening = false;
              micStatus = "Mic error";
            });
            _showSnackBar("Error: $error");
          },
          listenOptions: stt.ListenOptions(
            listenMode: stt.ListenMode.dictation,
            partialResults: false,
          ),
          localeId: "ur_PK", // Urdu
          pauseFor: Duration(seconds: 2),
        );
        
        _showSnackBar("Listening... Speak now");
      } else {
        _showSnackBar("Speech recognition not available");
      }
    }
  }

  // ================= SHOW VIDEO =================
  void _showVideo(String key) {
    if (signMap.containsKey(key)) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VideoScreen(signMap[key]!),
        ),
      );
    }
  }

  // ================= SHOW SNACKBAR =================
  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: Duration(seconds: 2),
      ),
    );
  }

  // ================= CLEAR TEXT =================
  void clearText() {
    textController.clear();
    setState(() {
      detectedText = "";
    });
    _showSnackBar("Text cleared");
  }

  // ================= UI =================
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
          // Camera Preview
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
                child: isCameraOn && controller != null
                    ? CameraPreview(controller!)
                    : Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.videocam_off, size: 64, color: Colors.grey),
                            SizedBox(height: 10),
                            Text("Camera is OFF", style: TextStyle(fontSize: 16)),
                            if (!isModelLoaded)
                              Padding(
                                padding: EdgeInsets.all(16),
                                child: CircularProgressIndicator(),
                              ),
                          ],
                        ),
                      ),
              ),
            ),
          ),
          
          // Detected Text Display
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
          
          // Text Input Section
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: textController,
                    focusNode: textFocusNode,
                    decoration: InputDecoration(
                      hintText: "Type in Roman Urdu (e.g., baap, dost, ghar)",
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
                      textFocusNode.unfocus(); // Hide keyboard
                      handleTextInput(value);
                    },
                  ),
                ),
                SizedBox(width: 8),
                // Send Button
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
          
          // Suggested words chips
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
                // Camera Toggle Button
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
                
                // Mic Button with Status
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
                
                // Info Button
                Column(
                  children: [
                    IconButton(
                      icon: Icon(Icons.info, color: Colors.orange, size: 40),
                      onPressed: () {
                        _showInfoDialog();
                      },
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
            Text("3. 🎤 Click mic to speak"),
            SizedBox(height: 8),
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

// ================= VIDEO SCREEN =================
class VideoScreen extends StatefulWidget {
  final String path;
  VideoScreen(this.path);

  @override
  State<VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends State<VideoScreen> {
  late VideoPlayerController controller;

  @override
  void initState() {
    super.initState();
    controller = VideoPlayerController.asset(widget.path)
      ..initialize().then((_) {
        setState(() {});
        controller.play();
      })
      ..setLooping(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Sign Video"),
        backgroundColor: Colors.black,
      ),
      backgroundColor: Colors.black,
      body: Center(
        child: controller.value.isInitialized
            ? Column(
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
                    ],
                  ),
                ],
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
