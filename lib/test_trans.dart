// lib/test_trans.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:notifications/notifications.dart';

enum TxType { income, expense }

class TxNotification {
  final String source;
  final String text;
  final TxType type;
  TxNotification(this.source, this.text, this.type);
}

// Whitelist of sources
final _whitelist = <String>[
  'Maybank', 'Maybank2u', 'CIMB', 'Touch \'n Go', 'TNG', 'GrabPay', 'ShopeePay', 'Boost'
];

// Amount regex
final _amtRe = RegExp(r'RM\s?([\d,]+(?:\.\d{1,2})?)', caseSensitive: false);

// Parse amount
double? _parseAmount(String text) {
  final m = _amtRe.firstMatch(text);
  if (m == null) return null;
  return double.tryParse(m.group(1)!.replaceAll(',', ''));
}

// Extract description
String _extractDesc(String text) {
  final m = RegExp(r'\b(?:to|for|at|from)\s+([A-Z0-9 \-\._]+)', caseSensitive: false)
      .firstMatch(text);
  return (m != null) ? m.group(1)!.trim() : 'Auto-captured';
}

// Map source to icon asset
String? _iconForSource(String source) {
  final s = source.toLowerCase();
  if (s.contains('maybank')) return 'assets/mae.png';
  if (s.contains("touch 'n go") || s.contains('tng')) return 'assets/tng.png';
  return null;
}

// Save transaction to Firestore
Future<void> _saveTx(String source, String text, TxType type) async {
  if (!_whitelist.any((w) => source.toLowerCase().contains(w.toLowerCase()))) return;

  final amount = _parseAmount(text);
  if (amount == null) return;

  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;

  final col = FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('pending_auto');

  final now = DateTime.now();
  final dateKey = DateTime(now.year, now.month, now.day);

  final desc = _extractDesc(text);
  final signed = type == TxType.expense ? -amount : amount;

  await col.add({
    'date': Timestamp.fromDate(dateKey),
    'title': 'Auto-captured ($source)',
    'description': desc,
    'amount': signed.abs(), // keep as positive; UI handles +/- by category
    'categories': ['Uncategorized'],
    'demo': false,
    'icon': _iconForSource(source),
  });
}

// Detect type and handle notification
Future<void> handleNotification(String source, String text) async {
  final lower = text.toLowerCase();
  final type = lower.contains('received') || lower.contains('credited')
      ? TxType.income
      : TxType.expense;

  await _saveTx(source, text, type);
}

Notifications? _n;
StreamSubscription<NotificationEvent>? _subscription;

/// Basic listener (no banner). Call this once if you don't need UI feedback.
Future<void> startNotificationListener() async {
  _n = Notifications();

  try {
    _subscription = _n!.notificationStream!.listen((event) async {
      final source = event.packageName ?? 'Unknown';
      final text = event.title ?? event.message ?? '';

      debugPrint('Notification received: $source -> $text');

      await handleNotification(source, text);
    });

    debugPrint('Notification listener started.');
  } catch (e) {
    debugPrint('Error starting notification listener: $e');
  }
}

Future<void> stopNotificationListener() async {
  await _subscription?.cancel();
  _subscription = null;
  debugPrint('Notification listener stopped.');
}

// --------------------------
// In-app banner UI + helpers
// --------------------------

class _TxBanner extends StatelessWidget {
  final String? iconAsset;
  final String title;
  final String subtitle;
  final double amount; // positive number
  final bool isIncome;

  const _TxBanner({
    required this.iconAsset,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.isIncome,
  });

  @override
  Widget build(BuildContext context) {
    final color = isIncome ? const Color(0xFF10B981) : const Color(0xFFB45C5C);
    final sign = isIncome ? '+' : '-';
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Material(
          color: Colors.transparent,
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1F2937),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 16, offset: const Offset(0, 6))],
            ),
            child: Row(
              children: [
                Container(
                  width: 34, height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0B1220),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: iconAsset != null
                      ? Image.asset(iconAsset!, width: 20, height: 20, fit: BoxFit.contain)
                      : const Icon(Icons.notifications, color: Colors.white70, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ]),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(14)),
                  child: Text(
                    'RM ${amount.toStringAsFixed(2)}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

OverlayEntry? _currentBanner;

void _showTxBanner(
    BuildContext context, {
      required String? iconAsset,
      required String title,
      required String subtitle,
      required double amount,
      required bool isIncome,
      Duration duration = const Duration(seconds: 3),
    }) {
  // Remove any existing banner
  _currentBanner?.remove();
  _currentBanner = OverlayEntry(
    builder: (_) => _TxBanner(
      iconAsset: iconAsset,
      title: title,
      subtitle: subtitle,
      amount: amount,
      isIncome: isIncome,
    ),
  );

  final overlay = Overlay.of(context);
  overlay.insert(_currentBanner!);

  Future.delayed(duration, () {
    _currentBanner?.remove();
    _currentBanner = null;
  });
}

/// Banner-enabled listener. Pass a BuildContext that has an Overlay (top-level after first frame).
Future<void> startNotificationListenerWithBanner(BuildContext context) async {
  _n = Notifications();

  try {
    _subscription = _n!.notificationStream!.listen((event) async {
      final source = event.packageName ?? 'Unknown';
      final text = event.title ?? event.message ?? '';

      debugPrint('Notification received: $source -> $text');

      // Detect type and parse for banner
      final lower = text.toLowerCase();
      final type = lower.contains('received') || lower.contains('credited')
          ? TxType.income
          : TxType.expense;

      final amount = _parseAmount(text);
      final iconAsset = _iconForSource(source);
      final desc = _extractDesc(text);
      final isIncome = type == TxType.income;

      // Save to Firestore
      await _saveTx(source, text, type);

      // Show banner if we have an amount
      if (amount != null) {
        _showTxBanner(
          context,
          iconAsset: iconAsset,
          title: 'Auto-captured ($source)',
          subtitle: desc,
          amount: amount,
          isIncome: isIncome,
        );
      }
    });

    debugPrint('Notification listener (banner) started.');
  } catch (e) {
    debugPrint('Error starting notification listener (banner): $e');
  }
}
