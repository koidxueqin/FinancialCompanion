import 'account.dart';

class Goal {
  String id;
  String label;
  double amount;
  DateTime? createDate;
  DateTime? dueDate;
  List<Account> accounts; // List of accounts associated with the goal
  String description;
  String status;
  bool rewardGiven;

  Goal({
    required this.id,
    required this.label,
    required this.amount,
    this.createDate,
    this.dueDate,
    this.accounts = const [],
    this.description = '',
    this.status = 'Pending',
    this.rewardGiven = false,
  });

  // Factory constructor for creating a dummy Goal with optional defaults
  factory Goal.create({
    required String label,
    double amount = 0,
    DateTime? createDate,
    DateTime? dueDate,
    List<Account>? accounts,
    String description = '',
    String status = 'Pending',
  }) {
    return Goal(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      label: label,
      amount: amount,
      createDate: createDate ?? DateTime.now(),
      dueDate: dueDate,
      accounts: accounts ?? [],
      description: description,
      status: status,
      rewardGiven: false,
    );
  }

  @override
  String toString() {
    final currentDateStr =
    createDate != null ? _formatDate(createDate!) : 'N/A';
    final dueDateStr = dueDate != null ? _formatDate(dueDate!) : 'N/A';
    return "Goal{id='$id', label='$label', amount=$amount, status='$status', createDate='$currentDateStr', dueDate='$dueDateStr'}";
  }

  String _formatDate(DateTime date) {
    return "${date.day.toString().padLeft(2, '0')}-${date.month.toString().padLeft(2, '0')}-${date.year}";
  }
}
