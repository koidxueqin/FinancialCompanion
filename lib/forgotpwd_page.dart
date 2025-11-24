import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ForgotPwdPage extends StatefulWidget {
  const ForgotPwdPage({Key? key}) : super(key: key);

  @override
  State<ForgotPwdPage> createState() => _ForgotPwdPageState();
}

class _ForgotPwdPageState extends State<ForgotPwdPage> {
  final _emailCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _sending = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendResetEmail() async {
    // Validate before sending
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) return;

    setState(() => _sending = true);
    final email = _emailCtrl.text.trim();

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Password reset link sent to $email')),
      );
      // Go back to Login after a short pause
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      var msg = 'Failed to send reset email.';
      if (e.code == 'invalid-email') msg = 'Please enter a valid email address.';
      if (e.code == 'user-not-found') msg = 'No user found with this email.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Something went wrong. Please try again.')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF8EBB87), // green background
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 8),
                const Text(
                  'Forgot Password',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'No worries! Enter your email address below and we\n'
                      'will send you a link to reset your password.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 32),

                // E-mail label
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'E-mail',
                    style: TextStyle(fontSize: 14, color: Colors.white),
                  ),
                ),
                const SizedBox(height: 6),

                // E-mail input
                SizedBox(
                  width: 358,
                  height: 46,
                  child: TextFormField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.email],
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white,
                      hintText: 'Enter your email',
                      hintStyle: const TextStyle(fontSize: 14, color: Colors.grey),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    validator: (v) {
                      final value = (v ?? '').trim();
                      if (value.isEmpty) return 'Email is required';
                      final emailRx = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
                      if (!emailRx.hasMatch(value)) return 'Enter a valid email';
                      return null;
                    },
                    onFieldSubmitted: (_) {
                      if (!_sending) _sendResetEmail();
                    },
                  ),
                ),

                const SizedBox(height: 32),

                // Send button
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
                    onPressed: _sending ? null : _sendResetEmail,
                    child: _sending
                        ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                        : const Text(
                      'Send Reset Instruction',
                      style: TextStyle(fontSize: 14, color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
