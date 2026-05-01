import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:permission_handler/permission_handler.dart';
import 'demo_screen.dart';
import 'camera_detection_screen.dart';

class HomeScreen extends StatelessWidget {

  Future<void> requestPermissions() async {
    // Request camera and microphone
    Map<Permission, PermissionStatus> statuses = await [
      Permission.camera,
      Permission.microphone,
    ].request();

    // Check result
    if (statuses[Permission.camera]!.isGranted &&
        statuses[Permission.microphone]!.isGranted) {
      print("Permissions granted ✅");
    } else {
      // Show a dialog if permissions are denied
      print("Permissions denied ❌");
      // Optionally, open app settings
      openAppSettings();
    }
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      appBar: AppBar(
        title: Text("Action to Speak"),
        centerTitle: true,
        backgroundColor: Color(0xFF2563EB),
      ),

      body: SingleChildScrollView(

        child: Padding(
          padding: const EdgeInsets.all(20),

          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              Text(
                "Welcome 👋",
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),

              SizedBox(height: 10),

              Text(
                "Convert sign language into speech using AI",
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
              ),

              SizedBox(height: 30),

              Center(
                child: Lottie.network(
                  "https://assets2.lottiefiles.com/packages/lf20_jcikwtux.json",
                  height: 220,
                ),
              ),

              SizedBox(height: 30),

              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15)),

                child: ListTile(
                  leading: Icon(Icons.camera_alt, color: Colors.blue),
                  title: Text("Start Camera Detection"),
                  subtitle: Text("Recognize hand gestures"),
                    onTap: () async {
                      await requestPermissions();

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => CameraDetectionScreen(),
                        ),
                      );
                    }
                ),
              ),

              SizedBox(height: 15),

              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15)),

                child: ListTile(
                  leading: Icon(Icons.play_circle, color: Colors.green),
                  title: Text("Demo / How to Use"),
                  subtitle: Text("See how the app works"),
                  onTap: () {


                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => DemoScreen(),
                        ),
                      );

                    },
                ),
              ),

              SizedBox(height: 15),

                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15)),

                  child: ListTile(
                    leading: Icon(Icons.privacy_tip, color: Colors.orange),
                    title: Text("Terms & Conditions"),
                    subtitle: Text("Read privacy policy"),
                    onTap: () {

                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(

                          title: Text("Terms & Conditions"),

                          content: SingleChildScrollView(
                            child: Text(
                                "1. This app uses your camera to detect hand gestures.\n\n"
                                    "2. The camera data is processed locally and not stored.\n\n"
                                    "3. The app converts detected gestures into speech.\n\n"
                                    "4. Do not misuse the application.\n\n"
                                    "5. By using this app, you agree to these terms."
                            ),
                          ),

                          actions: [
                            TextButton(
                              onPressed: () {
                                Navigator.pop(context);
                              },
                              child: Text("OK"),
                            )
                          ],
                        ),
                      );

                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}