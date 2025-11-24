import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'register_page.dart';
import 'course_page.dart';
import 'forgotpwd_page.dart';
import 'main_shell.dart';



class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _obscurePassword = true;


  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();


  Future<void> _login() async {
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const MainShell(initialIndex: 2)),
      );
    } on FirebaseAuthException catch (e) {
      String message;
      if (e.code == 'user-not-found') {
        message = "No user found with this email.";
      } else if (e.code == 'wrong-password') {
        message = "Incorrect password.";
      } else {
        message = "Login failed: ${e.message}";
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF8EBB87),
      appBar: AppBar(
        backgroundColor: const Color(0xFF8EBB87),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 40),

              // Title
              const Text(
                "Login",
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),

              const SizedBox(height: 40),

              // Email Label
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "E-mail",
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 6),

              // Email Input
              SizedBox(
                width: 358,
                height: 46,
                child: TextField(
                  controller: _emailController,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white,
                    hintText: "Enter your email",
                    hintStyle: const TextStyle(fontSize: 14, color: Colors.grey),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Password Label
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "Password",
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 6),

              // Password Input
              SizedBox(
                width: 358,
                height: 46,
                child: TextField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white,
                    hintText: "Enter your password",
                    hintStyle: const TextStyle(fontSize: 14, color: Colors.grey),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                        color: Colors.grey,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 6),

              // Forgot Password
              Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  onTap: () {
                    Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const ForgotPwdPage()),
                    );
                  },
                  child: const Text(
                    "Forgot Password?",
                    style: TextStyle(
                      fontSize: 14,
                      color: Color(0xFF346051),
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),



              const SizedBox(height: 30),

              // Login Button
              SizedBox(
                width: 358,
                height: 44,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2B8761),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(50),
                    ),
                  ),
                  onPressed: _login,
                  child: const Text(
                    "Login",
                    style: TextStyle(fontSize: 14, color: Colors.white),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Sign up prompt
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    "Don't have an account? Sign up ",
                    style: TextStyle(fontSize: 14, color: Colors.white),
                  ),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const RegisterPage()),
                      );
                    },
                    child: const Text(
                      "here",
                      style: TextStyle(
                        fontSize: 14,
                        color: Color(0xFF346051),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 40),

              /*// OR Login With (may or may not set up later)
              const Text(
                "OR",
                style: TextStyle(fontSize: 14, color: Colors.black),
              ),
              const SizedBox(height: 16),

              // Google login button
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
      ),
    );
  }
}
