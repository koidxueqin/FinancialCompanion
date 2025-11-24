import 'package:cloud_firestore/cloud_firestore.dart';

class TransactionEntry {
  final String id;
  final DateTime date;
  final String title;
  final String description;
  final double amount;
  final List<String> categories;

  TransactionEntry({
    required this.id,
    required this.date,
    required this.title,
    required this.description,
    required this.amount,
    required this.categories,
  });

  bool get isIncome => categories.any((c) => c.toLowerCase() == 'salary');

  Map<String, dynamic> toMap() => {
    'date': Timestamp.fromDate(DateTime(date.year, date.month, date.day)),
    'title': title,
    'description': description,
    'amount': amount,
    'categories': categories,
  };

  static TransactionEntry fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data()!;
    return TransactionEntry(
      id: d.id,
      date: (data['date'] as Timestamp).toDate(),
      title: (data['title'] ?? '') as String,
      description: (data['description'] ?? '') as String,
      amount: (data['amount'] ?? 0).toDouble(),
      categories: (data['categories'] as List<dynamic>? ?? []).cast<String>(),
    );
  }
}
