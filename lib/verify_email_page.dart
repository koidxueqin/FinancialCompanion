import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'main_shell.dart'; // make sure this exists in your project

class VerifyEmailPage extends StatefulWidget {
  const VerifyEmailPage({super.key});

  @override
  State<VerifyEmailPage> createState() => _VerifyEmailPageState();
}

class _VerifyEmailPageState extends State<VerifyEmailPage> {
  Timer? _timer;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    // Gentle auto-poll every 3s
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _checkVerified());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _checkVerified() async {
    if (_checking) return;
    _checking = true;
    try {
      final user = FirebaseAuth.instance.currentUser;
      await user?.reload();
      if (FirebaseAuth.instance.currentUser?.emailVerified == true) {
        _timer?.cancel();
        if (!mounted) return;
        // ✅ Verified — go to your main app
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const MainShell()),
              (_) => false,
        );
      }
    } finally {
      _checking = false;
    }
  }

  Future<void> _resendEmail() async {
    final user = FirebaseAuth.instance.currentUser;
    try {
      await user?.sendEmailVerification();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Verification email re-sent.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to resend: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF8EBB87);
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Verify your email',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w700,
            color: Colors.black,
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'We sent a verification link to your email. Please click the link to activate your account.',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 16),
            const Text(
              'This screen will automatically continue once your email is verified.',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 12),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton(
                onPressed: _resendEmail,
                child: const Text('Resend verification email'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
                onPressed: _checkVerified, // manual "I’ve verified" tap
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2B8761),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                ),
                child: const Text('I’ve verified — Continue', style: TextStyle(color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
