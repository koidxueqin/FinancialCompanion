import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/gestures.dart';
import 'terms_and_condition.dart';
import 'privacy_policy.dart';
import 'verify_email_page.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _acceptedPolicy = false;

  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  late final TapGestureRecognizer _termsTap;
  late final TapGestureRecognizer _privacyTap;

  @override
  void initState() {
    super.initState();
    _termsTap = TapGestureRecognizer()
      ..onTap = () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const TermsAndConditionPage()),
        );
      };
    _privacyTap = TapGestureRecognizer()
      ..onTap = () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PrivacyPolicyPage()),
        );
      };
  }

  bool _isStrongPassword(String password) {
    final hasUpper = password.contains(RegExp(r'[A-Z]'));
    final hasLower = password.contains(RegExp(r'[a-z]'));
    final hasDigit = password.contains(RegExp(r'\d'));
    final hasSpecial = password.contains(RegExp(r'[!@#\$%^&*(),.?":{}|<>]'));
    final hasMinLength = password.length >= 8;

    return hasUpper && hasLower && hasDigit && hasSpecial && hasMinLength;
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _termsTap.dispose();
    _privacyTap.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_acceptedPolicy) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please accept the Privacy Policy and Terms.")),
      );
      return;
    }

    if (_passwordController.text.trim() != _confirmPasswordController.text.trim()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Passwords do not match")),
      );
      return;
    }

    if (!_isStrongPassword(_passwordController.text.trim())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Password must be at least 8 characters and include upper, lower, digit, and special character.",
          ),
        ),
      );
      return;
    }

    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      final uid = cred.user?.uid;
      if (uid != null) {
        await FirebaseFirestore.instance.collection("users").doc(uid).set({
          "firstName": _firstNameController.text.trim(),
          "lastName": _lastNameController.text.trim(),
          "email": _emailController.text.trim(),
          "favourites": [],
        });
      }

      await cred.user?.sendEmailVerification();

      if (!mounted) return;

      // ➜ Go to verify screen (auto-checks & logs in)
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const VerifyEmailPage()),
      );
    } on FirebaseAuthException catch (e) {
      final message = switch (e.code) {
        'weak-password' => "Password is too weak.",
        'email-already-in-use' => "This email is already registered.",
        _ => "Registration failed: ${e.message}",
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    const labelStyle = TextStyle(
      fontFamily: 'Poppins',
      fontSize: 12,
      color: Colors.black,
    );

    return Scaffold(
      backgroundColor: const Color(0xFF8EBB87),
      appBar: AppBar(
        backgroundColor: const Color(0xFF8EBB87),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 20),
              const Text(
                "Register",
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 40),

              // First & Last Name
              Row(
                children: [
                  Expanded(child: _buildTextField("First Name", "John", _firstNameController)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildTextField("Last Name", "Doe", _lastNameController)),
                ],
              ),

              const SizedBox(height: 16),

              // Email
              _buildTextField("E-mail", "Enter your email", _emailController),

              const SizedBox(height: 16),

              // Password
              _buildPasswordField("Password", true, _passwordController),
              const SizedBox(height: 4),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "must contain 8 char.",
                  style: TextStyle(fontSize: 12, color: Color(0xFF346051)),
                ),
              ),

              const SizedBox(height: 16),

              // Confirm Password
              _buildPasswordField("Confirm Password", false, _confirmPasswordController),

              const SizedBox(height: 24),

              // Terms & Privacy with circular checkbox
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: _acceptedPolicy,
                    onChanged: (v) => setState(() => _acceptedPolicy = v ?? false),
                    shape: const CircleBorder(),
                    side: const BorderSide(color: Color(0xFF346051), width: 1.6),
                    activeColor: const Color(0xFF2B8761),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: RichText(
                      textAlign: TextAlign.left,
                      text: TextSpan(
                        style: labelStyle,
                        children: [
                          const TextSpan(text: "I agree to the "),
                          TextSpan(
                            text: "Terms & Condition",
                            style: const TextStyle(
                              color: Color(0xFF346051),
                              decoration: TextDecoration.underline,
                              fontWeight: FontWeight.w600,
                            ),
                            recognizer: _termsTap,
                          ),
                          const TextSpan(text: " and "),
                          TextSpan(
                            text: "Privacy Policy",
                            style: const TextStyle(
                              color: Color(0xFF346051),
                              decoration: TextDecoration.underline,
                              fontWeight: FontWeight.w600,
                            ),
                            recognizer: _privacyTap,
                          ),
                          const TextSpan(text: "."),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Create Account Button
              SizedBox(
                width: 358,
                height: 44,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2B8761),
                    disabledBackgroundColor: const Color(0xFF2B8761).withOpacity(0.4),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                  ),
                  onPressed: _acceptedPolicy ? _register : null,
                  child: const Text(
                    "Create Account",
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 14, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 🔹 Text Field builder with controller
  Widget _buildTextField(String label, String hint, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontFamily: 'Poppins', fontSize: 14, color: Colors.black)),
        const SizedBox(height: 6),
        Container(
          height: 46,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
          child: TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 14, color: Colors.grey),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
        ),
      ],
    );
  }

  // 🔹 Password Field builder with controller
  Widget _buildPasswordField(String label, bool isPassword, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontFamily: 'Poppins', fontSize: 14, color: Colors.black)),
        const SizedBox(height: 6),
        Container(
          height: 46,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
          child: TextField(
            controller: controller,
            obscureText: isPassword ? _obscurePassword : _obscureConfirm,
            decoration: InputDecoration(
              hintText: "********",
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              suffixIcon: IconButton(
                icon: Icon(
                  (isPassword ? _obscurePassword : _obscureConfirm) ? Icons.visibility_off : Icons.visibility,
                  color: Colors.grey,
                ),
                onPressed: () {
                  setState(() {
                    if (isPassword) {
                      _obscurePassword = !_obscurePassword;
                    } else {
                      _obscureConfirm = !_obscureConfirm;
                    }
                  });
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}
