import 'package:flutter/material.dart';

class RoundedPanel extends StatelessWidget {
  const RoundedPanel({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6F1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: child,
    );
  }
}
