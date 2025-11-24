// lib/tx_demo.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

enum TxType { income, expense }

class DemoNotification {
  final String source;
  final String text;
  final TxType type;
  DemoNotification(this.source, this.text, this.type);
}

final _whitelist = <String>[
  'Maybank', 'Maybank2u', 'CIMB', 'Touch \'n Go', 'TNG', 'GrabPay', 'ShopeePay', 'Boost'
];

final _amtRe = RegExp(r'RM\s?([\d,]+(?:\.\d{1,2})?)', caseSensitive: false);

double? _parseAmount(String text) {
  final m = _amtRe.firstMatch(text);
  if (m == null) return null;
  return double.tryParse(m.group(1)!.replaceAll(',', ''));
}

String _extractDesc(String text) {
  final m = RegExp(r'\b(?:to|for|at|from)\s+([A-Z0-9 \-\._]+)', caseSensitive: false).firstMatch(text);
  return (m != null) ? m.group(1)!.trim() : 'Auto-captured';
}

/// Map known notification sources to local asset icons.
/// - Maybank/MAE -> assets/mae.png
/// - Touch 'n Go / TNG -> assets/tng.png
String? _iconForSource(String source) {
  final s = source.toLowerCase();
  if (s.contains('maybank')) return 'assets/mae.png';
  if (s.contains("touch 'n go") || s.contains('tng')) return 'assets/tng.png';
  return null;
}

Future<void> _save(String source, String text, TxType type) async {
  // Only allow sources we expect
  if (!_whitelist.any((w) => source.toLowerCase().contains(w.toLowerCase()))) return;

  final amount = _parseAmount(text);
  if (amount == null) return;

  final uid = FirebaseAuth.instance.currentUser!.uid;
  final col = FirebaseFirestore.instance
      .collection('users').doc(uid)
      .collection('pending_auto');

  final now = DateTime.now();
  final dateKey = DateTime(now.year, now.month, now.day);

  final desc = _extractDesc(text);
  final signed = type == TxType.expense ? -amount : amount;

  await col.add({
    'date': Timestamp.fromDate(dateKey),
    'title': 'Auto-captured ($source)',
    'description': desc,
    'amount': signed.abs(), // store positive; UI decides +/- via category/income flag
    'categories': ['Uncategorized'],
    'demo': true,
    'icon': _iconForSource(source), // used by inbox card
  });
}

/// Call this to generate exactly two demo notifications: one expense, one income.
Future<void> simulatePair() async {
  final n1 = DemoNotification(
    'Touch \'n Go eWallet',
    "Payment: You have paid RM13.50 for BOOST JUICEBARS - CITY JNCTN.",
    TxType.expense,
  );
  final n2 = DemoNotification(
    'Maybank2u',
    "You've received money! COCO TEOH HUI HUI has transferred RM500.00 to you.",
    TxType.income,
  );
  await _save(n1.source, n1.text, n1.type);
  await _save(n2.source, n2.text, n2.type);
}
