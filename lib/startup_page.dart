import 'package:flutter/material.dart';
import 'login_page.dart';
import 'register_page.dart';

class StartupPage extends StatelessWidget {
  const StartupPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF8EBB87), // your background colour
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const SizedBox(), // pushes text to middle
            // Title
            Column(
              children: [
                //puppy image
                Image.asset('assets/puppy.png',
                width:125,
                height: 107,
                ),
                const SizedBox(height:5),
                const Text(
                  "Financial Companion",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: "Poppins",
                    fontSize: 32,
                    color: Colors.white,
                  ),
                )
              ],
            ),
            // Buttons

            Padding(
              padding: const EdgeInsets.only(bottom: 40),
              child: Column(
                children: [
                  // Register & Login side by side
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Register button
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.black, width: 2),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(50),
                          ),
                          fixedSize: const Size(171, 44),
                        ),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const RegisterPage()),
                          );
                        },
                        child: const Text(
                          "Register",
                          style: TextStyle(
                            fontFamily: "Poppins",
                            fontSize: 14,
                            color: Colors.black,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Login button
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2B8761),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(50),
                          ),
                          fixedSize: const Size(171, 44),
                        ),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const LoginPage()),
                          );
                        },
                        child: const Text(
                          "Login",
                          style: TextStyle(
                            fontFamily: "Poppins",
                            fontSize: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 15),
                  /*Google login button(commented for now, may/may not setup later)
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white, width: 2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(50),
                      ),
                      fixedSize: const Size(352, 44),
                    ),
                    onPressed: () {
                      // Google login action
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Google logo
                        Image.asset(
                          'assets/google.png',
                          width: 50,
                          height: 50,
                        ),
                       //Login with google text
                        const Text(
                          "Login with Google",
                          style: TextStyle(
                            fontFamily: "Poppins",
                            fontSize: 14,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),*/

                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}