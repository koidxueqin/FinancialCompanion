// lib/financial_summary.dart
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';

String _periodOf(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';
DateTime _monthStart(DateTime any) => DateTime(any.year, any.month, 1);
DateTime _monthEnd(DateTime any) => DateTime(any.year, any.month + 1, 0);
DateTime _dateKey(DateTime d) => DateTime(d.year, d.month, d.day);

Future<String> buildUserFinancialSummary(String userId) async {
  final now = DateTime.now();
  final periodKey = _periodOf(now);
  final monthStart = _monthStart(now);
  final monthEnd = _monthEnd(now);

  final userDoc = FirebaseFirestore.instance.collection('users').doc(userId);
  final budgetsCol = userDoc.collection('budgets');
  final goalsCol = userDoc.collection('goals');
  final txCol = userDoc.collection('transactions');

  try {
    final results = await Future.wait([
      budgetsCol.where('period', isEqualTo: periodKey).get(),
      goalsCol.where('period', isEqualTo: periodKey).get(),
      txCol
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(_dateKey(monthStart)))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(_dateKey(monthEnd)))
          .get(),
    ]);

    final budgets = (results[0] as QuerySnapshot<Map<String, dynamic>>)
        .docs
        .map((d) => {'label': d['label'], 'category': d['category'], 'amount': d['amount']})
        .toList();

    final goals = (results[1] as QuerySnapshot<Map<String, dynamic>>)
        .docs
        .map((d) => {'label': d['label'], 'category': d['category'], 'goalAmount': d['goalAmount']})
        .toList();

    final txSnap = results[2] as QuerySnapshot<Map<String, dynamic>>;
    final spendByCategory = <String, double>{};
    double totalSpending = 0;
    for (final d in txSnap.docs) {
      final m = d.data();
      final cats = (m['categories'] as List<dynamic>? ?? []).map((e) => e.toString()).toList();
      final amount = (m['amount'] ?? 0).toDouble();
      totalSpending += amount;
      if (cats.isEmpty) {
        spendByCategory['uncategorized'] = (spendByCategory['uncategorized'] ?? 0) + amount;
      } else {
        for (final c in cats) {
          final k = c.toLowerCase();
          spendByCategory[k] = (spendByCategory[k] ?? 0) + amount;
        }
      }
    }

    final summary = {
      'currentMonth': periodKey,
      'budgets': budgets,
      'goals': goals,
      'spendByCategory': spendByCategory,
      'totalSpending': totalSpending,
    };
    return jsonEncode(summary);
  } catch (e) {
    return jsonEncode({'error': 'Failed to fetch data', 'details': e.toString()});
  }
}
