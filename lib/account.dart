class Account {
  String id;            // Unique identifier for the account
  String accountName;   // Name of the account
  double balance;       // Current balance of the account
  int iconId;           // Icon representing the account (can use asset index or IconData)

  Account({
    required this.id,
    required this.accountName,
    required this.balance,
    required this.iconId,
  });

  // Factory constructor for creating a dummy account with default values
  factory Account.create({
    required String accountName,
    double balance = 0.0,
    int iconId = 0,
  }) {
    return Account(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      accountName: accountName,
      balance: balance,
      iconId: iconId,
    );
  }

  @override
  String toString() {
    return "Account{id: $id, name: $accountName, balance: $balance, iconId: $iconId}";
  }
}
