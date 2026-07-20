import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:permission_handler/permission_handler.dart';
import 'demo_screen.dart';
import 'camera_detection_screen.dart';

class HomeScreen extends StatelessWidget {
  
  Future<void> requestPermissions(BuildContext context) async {
    // Request camera and microphone permissions
    Map<Permission, PermissionStatus> statuses = await [
      Permission.camera,
      Permission.microphone,
    ].request();

    // Check result
    if (statuses[Permission.camera]!.isGranted &&
        statuses[Permission.microphone]!.isGranted) {
      print("Permissions granted ✅");
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CameraDetectionScreen(),
        ),
      );
    } else {
      // Show a dialog if permissions are denied
      print("Permissions denied ❌");
      _showPermissionDialog(context);
    }
  }

  void _showPermissionDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
            SizedBox(width: 10),
            Text("Permissions Required"),
          ],
        ),
        content: Text(
          "This app needs camera and microphone permissions to detect sign language and convert speech. Please grant permissions in settings.",
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(0xFF2563EB),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text("Open Settings"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF1E3A8A), // Deep blue
              Color(0xFF3B82F6), // Blue
              Color(0xFF60A5FA), // Light blue
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header Section
                  Container(
                    margin: EdgeInsets.only(top: 20, bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Action to Speak",
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 1.2,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          "Bridging the gap between deaf and hearing communities",
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.white70,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: 20),

                  // Lottie Animation
                  Center(
                    child: Container(
                     padding: EdgeInsets.all(20),
                     decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(30),
    ),
    child: Image.asset(
      "assets/logo.png",
      height: 200,
      width: 200,
      fit: BoxFit.contain,
    ),
  ),
),

                  SizedBox(height: 20),

                  // NEW: Quick Tips Section
                  Container(
                    margin: EdgeInsets.symmetric(vertical: 10),
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: Colors.white.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.tips_and_updates, color: Colors.yellow.shade700, size: 20),
                            SizedBox(width: 8),
                            Text(
                              "Quick Tips",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _buildTipChip("🎯", "Stand 2-3 feet away"),
                            _buildTipChip("✋", "Good lighting"),
                            _buildTipChip("📱", "Keep hands in frame"),
                            _buildTipChip("⏱️", "Hold sign for 1-2 sec"),
                            _buildTipChip("👕", "Plain background"),
                            _buildTipChip("🖐️", "Clear hand gestures"),
                          ],
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: 20),

                  // Features Section
                  Container(
                    margin: EdgeInsets.only(bottom: 20),
                    child: Text(
                      "Features",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),

                  // Feature Cards Row
                  Row(
                    children: [
                      Expanded(
                        child: _buildFeatureCard(
                          icon: Icons.handshake,
                          title: "Sign Detection",
                          description: "Real-time gesture recognition",
                          color: Colors.green,
                        ),
                      ),
                      SizedBox(width: 15),
                      Expanded(
                        child: _buildFeatureCard(
                          icon: Icons.record_voice_over,
                          title: "Voice Output",
                          description: "Text-to-speech conversion",
                          color: Colors.orange,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 15),
                  Row(
                    children: [
                      Expanded(
                        child: _buildFeatureCard(
                          icon: Icons.mic,
                          title: "Speech Input",
                          description: "Voice to text conversion",
                          color: Colors.purple,
                        ),
                      ),
                      SizedBox(width: 15),
                      Expanded(
                        child: _buildFeatureCard(
                          icon: Icons.video_library,
                          title: "Video Library",
                          description: "Learn sign language",
                          color: Colors.red,
                        ),
                      ),
                    ],
                  ),

                  SizedBox(height: 40),

                  // Main Action Buttons
                  Container(
                    margin: EdgeInsets.only(bottom: 20),
                    child: Text(
                      "Get Started",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),

                  // Start Camera Button with Animation
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => requestPermissions(context),
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        width: double.infinity,
                        padding: EdgeInsets.symmetric(vertical: 18),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.white, Colors.white.withOpacity(0.9)],
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 10,
                              offset: Offset(0, 5),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.camera_alt,
                              color: Color(0xFF2563EB),
                              size: 28,
                            ),
                            SizedBox(width: 12),
                            Text(
                              "Start Camera Detection",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF2563EB),
                              ),
                            ),
                            SizedBox(width: 12),
                            Icon(
                              Icons.arrow_forward,
                              color: Color(0xFF2563EB),
                              size: 24,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  SizedBox(height: 15),

                  // Demo Button with Animation
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => DemoScreen(),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        width: double.infinity,
                        padding: EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.play_circle_filled,
                              color: Colors.white,
                              size: 26,
                            ),
                            SizedBox(width: 12),
                            Text(
                              "Watch Demo / How to Use",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  SizedBox(height: 15),

                  // Terms Button with Animation
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        _showTermsDialog(context);
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        width: double.infinity,
                        padding: EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.privacy_tip,
                              color: Colors.white70,
                              size: 20,
                            ),
                            SizedBox(width: 8),
                            Text(
                              "Terms & Conditions",
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  SizedBox(height: 20),

                  // Footer
                  Container(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: Column(
                        children: [
                          Text(
                            "Made with ❤️ for Deaf Community",
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                          SizedBox(height: 5),
                          Text(
                            "Version 1.0.0",
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureCard({
    required IconData icon,
    required String title,
    required String description,
    required Color color,
  }) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: Colors.white.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: 30,
            ),
          ),
          SizedBox(height: 10),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 4),
          Text(
            description,
            style: TextStyle(
              fontSize: 11,
              color: Colors.white70,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // NEW: Helper method for tip chips
  Widget _buildTipChip(String emoji, String text) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        "$emoji $text",
        style: TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }

  void _showTermsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Container(
          padding: EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.privacy_tip, color: Colors.blue, size: 28),
                  ),
                  SizedBox(width: 15),
                  Text(
                    "Terms & Conditions",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 20),
              Container(
                height: 300,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTermItem(
                        "1. Camera Access",
                        "This app uses your camera exclusively for sign language detection. All processing is done locally on your device. No images or videos are stored or uploaded.",
                      ),
                      SizedBox(height: 15),
                      _buildTermItem(
                        "2. Microphone Access",
                        "Microphone is used only for speech-to-text conversion when you choose to speak instead of type. Audio is processed in real-time and not saved.",
                      ),
                      SizedBox(height: 15),
                      _buildTermItem(
                        "3. Data Privacy",
                        "We do not collect, store, or share any personal data. All recognition happens locally on your device for your privacy and security.",
                      ),
                      SizedBox(height: 15),
                      _buildTermItem(
                        "4. Usage Guidelines",
                        "This app is intended for communication assistance only. Do not use it for illegal activities or harassment.",
                      ),
                      SizedBox(height: 15),
                      _buildTermItem(
                        "5. Limitations",
                        "While we strive for accuracy, the app may not recognize all signs perfectly. It is a tool to assist communication, not replace human interpreters.",
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text("Decline", style: TextStyle(color: Colors.red)),
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(0xFF2563EB),
                        padding: EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text("Accept"),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTermItem(String title, String description) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.blue,
          ),
        ),
        SizedBox(height: 5),
        Text(
          description,
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey.shade700,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}
