import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

class DemoScreen extends StatelessWidget {

  Widget buildStep(String title, String description, IconData icon) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.blue,
          child: Icon(icon, color: Colors.white),
        ),
        title: Text(title,
            style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(description),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(
        title: Text("How to Use"),
        backgroundColor: Color(0xFF2563EB),
      ),

      body: SingleChildScrollView(
        padding: EdgeInsets.all(20),

        child: Column(
          children: [

            Lottie.network(
              "https://assets2.lottiefiles.com/packages/lf20_jcikwtux.json",
              height: 200,
            ),

            SizedBox(height: 20),

            buildStep(
              "Step 1: Start Camera",
              "Click the Start Camera button to begin gesture detection.",
              Icons.camera_alt,
            ),

            SizedBox(height: 10),

            buildStep(
              "Step 2: Perform Hand Sign",
              "Show your hand sign clearly in front of the camera.",
              Icons.back_hand,
            ),

            SizedBox(height: 10),

            buildStep(
              "Step 3: AI Detection",
              "The AI model analyzes your gesture and recognizes the sign.",
              Icons.psychology,
            ),

            SizedBox(height: 10),

            buildStep(
              "Step 4: Send Message",
              "Press the Send button to convert the detected sign.",
              Icons.send,
            ),

            SizedBox(height: 10),

            buildStep(
              "Step 5: Speech Output",
              "The application converts the gesture into speech.",
              Icons.record_voice_over,
            ),

          ],
        ),
      ),
    );
  }
}