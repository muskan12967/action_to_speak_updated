import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

class DemoScreen extends StatelessWidget {
  final List<Map<String, dynamic>> steps = [
    {
      "step": "1",
      "icon": Icons.camera_alt,
      "title": "Start Camera",
      "description": "Turn ON the camera by tapping the camera button",
      "color": Colors.blue,
    },
    {
      "step": "2",
      "icon": Icons.back_hand,
      "title": "Perform Sign",
      "description": "Show your hand sign clearly in front of the camera",
      "color": Colors.green,
    },
    {
      "step": "3",
      "icon": Icons.psychology,
      "title": "AI Detection",
      "description": "AI recognizes your gesture automatically",
      "color": Colors.purple,
    },
    {
      "step": "4",
      "icon": Icons.volume_up,
      "title": "Voice Output",
      "description": "App speaks out the detected sign",
      "color": Colors.orange,
    },
    {
      "step": "5",
      "icon": Icons.keyboard,
      "title": "Type or Speak",
      "description": "Hearing users can type or speak words",
      "color": Colors.red,
    },
    {
      "step": "6",
      "icon": Icons.school,
      "title": "Quick Tips",
      "description": "Maintain good lighting and keep hands in frame",
      "color": Colors.teal,
    },
  ];

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
          child: Column(
            children: [
              // Custom App Bar
              Container(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.arrow_back, color: Colors.white),
                      ),
                    ),
                    SizedBox(width: 15),
                    Expanded(
                      child: Text(
                        "How to Use",
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Lottie Animation
              Container(
                height: 180,
                margin: EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Center(
                  child: Lottie.network(
                    "https://assets2.lottiefiles.com/packages/lf20_jcikwtux.json",
                    height: 150,
                    fit: BoxFit.contain,
                  ),
                ),
              ),

              SizedBox(height: 20),

              // Steps Title
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  "Follow these simple steps:",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),

              SizedBox(height: 15),

              // Steps List
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(30),
                      topRight: Radius.circular(30),
                    ),
                  ),
                  child: ListView.builder(
                    padding: EdgeInsets.all(20),
                    itemCount: steps.length,
                    itemBuilder: (context, index) {
                      return _buildStepCard(steps[index]);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepCard(Map<String, dynamic> step) {
    return Container(
      margin: EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: Colors.grey.shade200,
          width: 1,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            // Step Number Circle
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    step["color"].withOpacity(0.2),
                    step["color"].withOpacity(0.1),
                  ],
                ),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  step["step"],
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: step["color"],
                  ),
                ),
              ),
            ),
            SizedBox(width: 15),
            
            // Icon
            Container(
              width: 45,
              height: 45,
              decoration: BoxDecoration(
                color: step["color"].withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                step["icon"],
                color: step["color"],
                size: 25,
              ),
            ),
            SizedBox(width: 15),
            
            // Text Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    step["title"],
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    step["description"],
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
