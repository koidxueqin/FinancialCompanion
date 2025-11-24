import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

class GoalsTab extends StatefulWidget {
  const GoalsTab({super.key});
  @override
  State<GoalsTab> createState() => _GoalsTabState();
}

class _GoalsTabState extends State<GoalsTab> {
  // Defaults shown as chips (icon/color come from _visualFor/_chipColor)
  final List<String> _baseCategories = const [
    'Entertainment', 'Food', 'Groceries', 'Transport'
  ];

  // ---------- dates ----------
  DateTime _now = DateTime.now();
  late String _periodKey;
  static String _periodOf(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';
  static DateTime _monthStart(DateTime any) => DateTime(any.year, any.month, 1);
  static DateTime _monthEnd(DateTime any) => DateTime(any.year, any.month + 1, 0);
  static DateTime _dateKey(DateTime d) => DateTime(d.year, d.month, d.day);

  // ---------- firestore ----------
  String get _uid => FirebaseAuth.instance.currentUser!.uid;
  DocumentReference<Map<String, dynamic>> get _userDoc =>
      FirebaseFirestore.instance.collection('users').doc(_uid);
  CollectionReference<Map<String, dynamic>> get _budgetsCol => _userDoc.collection('budgets');
  CollectionReference<Map<String, dynamic>> get _goalsCol => _userDoc.collection('goals');
  CollectionReference<Map<String, dynamic>> get _txCol => _userDoc.collection('transactions');
  CollectionReference<Map<String, dynamic>> get _catCol => _userDoc.collection('categories');

  // ---------- state ----------
  final Map<String, double> _spendByCategory = {};
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _txSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _budgetsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _goalsSub;
  Timer? _midnightTicker;
  List<_Budget> _budgets = [];
  List<_Goal> _goals = [];

  // ---------- categories helpers ----------
  String _slug(String name) => name.trim().toLowerCase();

  Future<void> _addCategoryIfMissing(String rawName) async {
    final name = rawName.trim();
    if (name.isEmpty) return;

    final defaultsLower = _baseCategories.map((e) => e.toLowerCase()).toSet();
    if (defaultsLower.contains(_slug(name))) {
      _toast('Category already exists'); return;
    }

    final id = _slug(name);
    final ref = _catCol.doc(id);
    if ((await ref.get()).exists) {
      _toast('Category already exists'); return;
    }
    await ref.set({'name': name, 'slug': id, 'createdAt': FieldValue.serverTimestamp()});
  }

  Future<void> _renameCategory(String id, String newName) async {
    final name = newName.trim();
    if (name.isEmpty) return;

    final takenLower = <String>{
      ..._baseCategories.map((e) => e.toLowerCase()),
      ...(await _catCol.get())
          .docs.map((d) => (d.data()['name'] ?? '').toString().toLowerCase()),
    };
    if (takenLower.contains(name.toLowerCase())) {
      _toast('Category already exists'); return;
    }
    await _catCol.doc(id).update({'name': name});
  }

  Future<void> _deleteCategory(String id) async {
    if (_baseCategories.map((e) => e.toLowerCase()).contains(id)) {
      _toast('Default categories can’t be deleted'); return;
    }
    await _catCol.doc(id).delete();
  }

  Future<void> _updateCategoryColor(String id, Color color) async {
    if (_baseCategories.map((e) => e.toLowerCase()).contains(id)) {
      _toast('Default categories color can’t be changed'); return;
    }
    await _catCol.doc(id).update({'color': color.value});
  }

  Future<Color?> _pickColor(BuildContext context, Color start) async {
    Color tmp = start;
    return showDialog<Color>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Pick a color'),
        content: SingleChildScrollView(
          child: BlockPicker(
            pickerColor: tmp,
            onColorChanged: (c) => tmp = c,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, tmp), child: const Text('Done')),
        ],
      ),
    );
  }

  // ---------- lifecycle ----------
  @override
  void initState() {
    super.initState();
    _periodKey = _periodOf(_now);
    _listenTransactionsThisMonth();
    _listenBudgets();
    _listenGoals();
    _scheduleMidnightTick();
  }

  @override
  void dispose() {
    _txSub?.cancel(); _budgetsSub?.cancel(); _goalsSub?.cancel(); _midnightTicker?.cancel();
    super.dispose();
  }

  // ---------- listeners ----------
  void _listenTransactionsThisMonth() {
    _txSub?.cancel();
    final start = _monthStart(_now);
    final nextMonthStart = DateTime(_now.year, _now.month + 1, 1);

    _txSub = _txCol
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(_dateKey(start)))
        .where('date', isLessThan: Timestamp.fromDate(_dateKey(nextMonthStart)))
        .snapshots()
        .listen((snap) {
      final map = <String, double>{};
      for (final d in snap.docs) {
        final data = d.data();
        final cats = (data['categories'] as List<dynamic>? ?? []).map((e) => e.toString()).toList();
        final amount = (data['amount'] ?? 0).toDouble();
        if (cats.isEmpty) {
          map['uncategorized'] = (map['uncategorized'] ?? 0) + amount;
        } else {
          for (final c in cats) {
            final k = c.toLowerCase();
            map[k] = (map[k] ?? 0) + amount;
          }
        }
      }
      setState(() { _spendByCategory..clear()..addAll(map); });
    }, onError: (e) => _toast('Read transactions failed: $e'));
  }

  void _listenBudgets() {
    _budgetsSub?.cancel();
    _budgetsSub = _budgetsCol
        .where('period', isEqualTo: _periodKey)
        .snapshots()
        .listen((snap) {
      setState(() => _budgets = snap.docs.map((d) => _Budget.fromDoc(d)).toList());
    }, onError: (e) => _toast('Read budgets failed: $e'));
  }

  void _listenGoals() {
    _goalsSub?.cancel();
    _goalsSub = _goalsCol
        .where('period', isEqualTo: _periodKey)
        .snapshots()
        .listen((snap) async {
      setState(() => _goals = snap.docs.map((d) => _Goal.fromDoc(d)).toList());
      await _checkAndAwardCoins();
    }, onError: (e) => _toast('Read goals failed: $e'));
  }

  void _scheduleMidnightTick() {
    final now = DateTime.now();
    final nextMidnight = DateTime(now.year, now.month, now.day + 1);
    _midnightTicker = Timer(nextMidnight.difference(now), () {
      if (!mounted) return;
      _now = DateTime.now();
      _periodKey = _periodOf(_now);
      _listenTransactionsThisMonth();
      _listenBudgets();
      _listenGoals();
      _scheduleMidnightTick();
    });
  }

  // ---------- CRUD (NO NOTES) ----------
  Future<void> _addBudget({
    required String label, required String category, required double amount,
  }) async {
    try {
      await _budgetsCol.add({
        'label': label,'category': category,'amount': amount,
        'period': _periodKey,'createdAt': FieldValue.serverTimestamp(),
      });
      _toast('Budget added');
    } catch (e) { _toast('Failed to add budget: $e'); }
  }

  Future<void> _updateBudget(_Budget b,{
    required String label, required String category, required double amount,
  }) async {
    try {
      await _budgetsCol.doc(b.id).update({
        'label': label,'category': category,'amount': amount,
      });
      _toast('Budget updated');
    } catch (e) { _toast('Failed to update budget: $e'); }
  }

  Future<void> _deleteBudget(String id) async {
    try { await _budgetsCol.doc(id).delete(); _toast('Budget deleted'); }
    catch (e) { _toast('Failed to delete budget: $e'); }
  }

  Future<void> _addGoal({
    required String label, required String category, required double goalAmount,
  }) async {
    try {
      await _goalsCol.add({
        'label': label,'category': category,'goalAmount': goalAmount,
        'period': _periodKey,'awarded': false,'createdAt': FieldValue.serverTimestamp(),
      });
      _toast('Goal added');
    } catch (e) { _toast('Failed to add goal: $e'); }
  }

  Future<void> _updateGoal(_Goal g,{
    required String label, required String category, required double goalAmount,
  }) async {
    try {
      await _goalsCol.doc(g.id).update({
        'label': label,'category': category,'goalAmount': goalAmount,
      });
      _toast('Goal updated');
    } catch (e) { _toast('Failed to update goal: $e'); }
  }

  Future<void> _deleteGoal(String id) async {
    try { await _goalsCol.doc(id).delete(); _toast('Goal deleted'); }
    catch (e) { _toast('Failed to delete goal: $e'); }
  }

  // ---------- award coins ----------
  Future<void> _checkAndAwardCoins() async {
    final end = _monthEnd(_now);
    final bool monthEnded = DateTime.now().isAfter(
      DateTime(end.year, end.month, end.day, 23, 59, 59),
    );

    for (final g in _goals.where((x) => !x.awarded)) {
      final b = _budgets.firstWhere(
            (e) => e.category.toLowerCase() == g.category.toLowerCase(),
        orElse: () => _Budget.empty(),
      );
      if (b.isEmpty) continue;

      final spent = _spendByCategory[g.category.toLowerCase()] ?? 0.0;
      final notOverspent = spent <= b.amount;

      if (monthEnded && notOverspent) {
        final double safeGoal = (g.goalAmount <= 0) ? 1.0 : g.goalAmount;
        final int coins = max(1, (b.amount / safeGoal).ceil());

        await FirebaseFirestore.instance.runTransaction((tx) async {
          final snap = await tx.get(_userDoc);
          final current = (snap.data()?['pet_coins'] ?? 0) as int;
          tx.update(_userDoc, {'pet_coins': current + coins});
        });

        await _goalsCol.doc(g.id).update({'awarded': true});
      }
    }
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        // 1) Pet + speech bubble (reads from users/{uid}/userPet/current)
        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _userDoc.collection('userPet').doc('current').snapshots(),
          builder: (context, snap) {
            if (!snap.hasData || !snap.data!.exists) return const SizedBox.shrink();
            final data = snap.data!.data()!;
            final petImage = (data['asset'] ?? '').toString().trim();
            if (petImage.isEmpty) return const SizedBox.shrink();
            return _PetNudgeRow(petImagePath: petImage);
          },
        ),


        _SectionHeader(
          title: 'Budgets',
          subtitle: 'Monthly',
          trailing: TextButton.icon(
            onPressed: () => _openBudgetSheet(context),
            icon: const Icon(Icons.add, color: Color(0xFF214235)),
            label: const Text('Add new', style: TextStyle(color: Color(0xFF214235))),
          ),
        ),

        // 3) Budget cards
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: _budgets.map((b) {
              final spent = _spendByCategory[b.category.toLowerCase()] ?? 0.0;
              final pct = (b.amount <= 0) ? 0.0 : (spent / b.amount).clamp(0.0, 1.0);
              return _DismissibleCard(
                keyValue: 'budget-${b.id}',
                onConfirmDelete: () => _deleteBudget(b.id),
                child: _BudgetTile(
                  label: b.label,
                  category: b.category,              // icons/colors follow category
                  spent: spent, budget: b.amount, percent: pct,
                  onTap: () => _openBudgetSheet(context, existing: b),
                ),
              );
            }).toList(),
          ),
        ),

        const SizedBox(height: 10),

        // 4) Goals header
        _SectionHeader(
          title: 'Goals',
          trailing: TextButton.icon(
            onPressed: () => _openGoalSheet(context),
            icon: const Icon(Icons.add, color: Color(0xFF214235)),
            label: const Text('Add new', style: TextStyle(color: Color(0xFF214235))),
          ),
        ),

        // 5) Goals cards
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: _goals.map((g) {
              final budget = _budgets.firstWhere(
                    (b) => b.category.toLowerCase() == g.category.toLowerCase(),
                orElse: () => _Budget.empty(),
              );
              final spent = _spendByCategory[g.category.toLowerCase()] ?? 0.0;
              final total = budget.amount;
              final end = _monthEnd(_now);
              final monthEnded = DateTime.now().isAfter(DateTime(end.year, end.month, end.day, 23, 59, 59));
              final overspent = total > 0 ? spent > total : spent > 0;

// progress shown on the yellow ring while in-progress
              final progress = (total <= 0) ? 0.0 : (spent / total).clamp(0.0, 1.0);

// decide status
              late final _GoalStatus status;
              if (overspent) {
                status = _GoalStatus.overspent; // red
              } else if (monthEnded && !overspent) {
                status = _GoalStatus.reached;   // green
              } else {
                status = _GoalStatus.inProgress; // yellow
              }

// ring fill rule
              final ringValue = switch (status) {
                _GoalStatus.overspent => 1.0,         // FULL RED ring when failed
                _GoalStatus.inProgress => progress,   // partial yellow ring = spent/budget
                _GoalStatus.reached => 1.0,           // FULL GREEN ring when success
              };

              return _DismissibleCard(
                keyValue: 'goal-${g.id}',
                onConfirmDelete: () => _deleteGoal(g.id),
                child: _GoalTile(
                  category: g.category,
                  label: g.label,
                  status: status,
                  percent: ringValue,
                  onTap: () => _openGoalSheet(context, existing: g),
                ),
              );

            }).toList(),
          ),
        ),
      ],
    );
  }

  // ---------- sheets ----------
  Future<void> _openBudgetSheet(BuildContext context, { _Budget? existing }) async {
    final labelCtrl = TextEditingController(text: existing?.label ?? '');
    final amountCtrl = TextEditingController(text: existing == null ? '' : existing.amount.toStringAsFixed(2));
    final selectedCats = <String>{existing?.category ?? 'Food'};

    await showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFFE7F0E9),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (ctx) {
        return _GoalFormSheet(
          title: existing == null ? 'Add New Budget' : 'Edit Budget',
          titleCtrl: labelCtrl, amountCtrl: amountCtrl,
          baseCategories: _baseCategories, selectedCats: selectedCats,
          categoriesStream: _catCol.orderBy('name').snapshots(),
          submitButtonText: existing == null ? 'Add Budget' : 'Save changes',
          onCreateCategory: _addCategoryIfMissing,
          onManageTap: () => _openManageCategories(ctx),
          onDeleteTap: existing == null ? null : () async {
            final yes = await showDialog<bool>(
              context: ctx,
              builder: (_) => AlertDialog(
                title: const Text('Delete budget?'),
                content: const Text('This cannot be undone.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                  ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
                ],
              ),
            ) ?? false;
            if (yes) { await _deleteBudget(existing!.id); if (ctx.mounted) Navigator.pop(ctx); }
          },
          onSubmit: () async {
            final label = labelCtrl.text.trim().isEmpty ? 'Budget' : labelCtrl.text.trim();
            final amt = double.tryParse(amountCtrl.text.trim().replaceAll('RM', '').trim()) ?? 0.0;
            final cat = (selectedCats.isEmpty ? 'Uncategorized' : selectedCats.first);
            if (existing == null) {
              await _addBudget(label: label, category: cat, amount: amt);
            } else {
              await _updateBudget(existing, label: label, category: cat, amount: amt);
            }
            if (ctx.mounted) Navigator.pop(ctx);
          },
        );

      },
    );
  }

  Future<void> _openGoalSheet(BuildContext context, { _Goal? existing }) async {
    final labelCtrl = TextEditingController(text: existing?.label ?? '');
    final amountCtrl = TextEditingController(text: existing == null ? '' : existing.goalAmount.toStringAsFixed(2));
    final selectedCats = <String>{existing?.category ?? 'Food'};

    await showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFFE7F0E9),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (ctx) {
        return _GoalFormSheet(
          title: existing == null ? 'Add New Goal' : 'Edit Goal',
          titleCtrl: labelCtrl, amountCtrl: amountCtrl,
          baseCategories: _baseCategories, selectedCats: selectedCats,
          categoriesStream: _catCol.orderBy('name').snapshots(),
          submitButtonText: existing == null ? 'Add Goal' : 'Save changes',
          onCreateCategory: _addCategoryIfMissing,
          onManageTap: () => _openManageCategories(ctx),
          onDeleteTap: existing == null ? null : () async {
            final yes = await showDialog<bool>(
              context: ctx,
              builder: (_) => AlertDialog(
                title: const Text('Delete goal?'),
                content: const Text('This cannot be undone.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                  ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
                ],
              ),
            ) ?? false;
            if (yes) { await _deleteGoal(existing!.id); if (ctx.mounted) Navigator.pop(ctx); }
          },
          onSubmit: () async {
            final label = labelCtrl.text.trim().isEmpty ? 'Goal' : labelCtrl.text.trim();
            final amt = double.tryParse(amountCtrl.text.trim().replaceAll('RM', '').trim()) ?? 0.0;
            final cat = (selectedCats.isEmpty ? 'Uncategorized' : selectedCats.first);
            if (existing == null) {
              await _addGoal(label: label, category: cat, goalAmount: amt);
            } else {
              await _updateGoal(existing, label: label, category: cat, goalAmount: amt);
            }
            if (ctx.mounted) Navigator.pop(ctx);
          },
        );
      },
    );
  }

  Future<void> _openManageCategories(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFE7F0E9),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _catCol.orderBy('name').snapshots(),
          builder: (context, snap) {
            final items = <_CatItem>[
              ..._baseCategories.map((n) => _CatItem(
                id: _slug(n), name: n,
                color: _chipColor(n).value, isDefault: true,
              )),
              if (snap.hasData)
                ...snap.data!.docs.map((d) {
                  final m = d.data();
                  return _CatItem(
                    id: d.id,
                    name: (m['name'] ?? '').toString(),
                    color: (m['color'] as int?) ?? _chipColor('custom').value,
                    isDefault: false,
                  );
                }),
            ];
            return _ManageCategoriesSheet(
              items: items,
              onRename: (id, newName) async => _renameCategory(id, newName),
              onDelete: (id) async => _deleteCategory(id),
              onChangeColor: (id, color) async => _updateCategoryColor(id, color),
              onAdd: (name) async => _addCategoryIfMissing(name),
              pickColor: (start) => _pickColor(context, start),
            );
          },
        );
      },
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

/// ===================== Models/UI helpers & shared widgets =====================
class _Budget {
  final String id; final String label; final String category;
  final double amount; final String period;
  const _Budget({required this.id, required this.label, required this.category, required this.amount, required this.period});
  bool get isEmpty => id.isEmpty;
  factory _Budget.empty() => const _Budget(id:'', label:'', category:'', amount:0, period:'');

  factory _Budget.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data()!;
    return _Budget(
      id: d.id,
      label: (m['label'] ?? '') as String,
      category: (m['category'] ?? 'Uncategorized') as String,
      amount: (m['amount'] ?? 0).toDouble(),
      period: (m['period'] ?? '') as String,
    );
  }
}

class _Goal {
  final String id; final String label; final String category;
  final double goalAmount; final String period; final bool awarded;
  const _Goal({required this.id, required this.label, required this.category, required this.goalAmount, required this.period, required this.awarded});
  factory _Goal.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data()!;
    return _Goal(
      id: d.id,
      label: (m['label'] ?? '') as String,
      category: (m['category'] ?? 'Uncategorized') as String,
      goalAmount: (m['goalAmount'] ?? 0).toDouble(),
      period: (m['period'] ?? '') as String,
      awarded: (m['awarded'] ?? false) as bool,
    );
  }
}

class _CatVisual {
  final IconData fallbackIcon;
  final Color color;
  final String? asset;
  const _CatVisual({required this.fallbackIcon, required this.color, this.asset});
}

/// icon/color strictly follow **category**
_CatVisual _visualFor(String category) {
  final s = category.toLowerCase();

  // hues tuned to your mock
  const foodColor = Color(0xFF4F6F91);          // blue (food.png)
  const transportColor = Color(0xFFE38AF7);     // pink (transport.png)
  const groceriesColor = Color(0xFF53D34F);     // green (grocery.png)
  const entertainmentColor = Color(0xFF5A28B1); // purple (entertainment.png)

  if (s.contains('transport')) {
    return const _CatVisual(
      fallbackIcon: Icons.directions_car,
      color: transportColor,
      asset: 'assets/transport.png',
    );
  }
  if (s.contains('food')) {
    return const _CatVisual(
      fallbackIcon: Icons.restaurant,
      color: foodColor,
      asset: 'assets/food.png',
    );
  }
  if (s.contains('groceries') || s.contains('grocery') || s.contains('market') || s.contains('shop')) {
    return const _CatVisual(
      fallbackIcon: Icons.local_grocery_store,
      color: groceriesColor,
      asset: 'assets/grocery.png', // <- ensure this filename exists
    );
  }

  if (s.contains('entertainment')) {
    return const _CatVisual(
      fallbackIcon: Icons.theaters,
      color: entertainmentColor,
      asset: 'assets/entertainment.png',
    );
  }

  return const _CatVisual(
    fallbackIcon: Icons.category,
    color: Color(0xFF94A3B8),
    asset: null,
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.trailing,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  fontSize: 22,
                  color: Color(0xFF214235),
                  height: 1.1,
                ),
              ),
              const Spacer(),
              trailing,
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Color(0xFF214235),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PetNudgeRow extends StatelessWidget {
  const _PetNudgeRow({required this.petImagePath});
  final String petImagePath;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const _SpeechBubble(), // bottom-right corner is square
          const SizedBox(width: 8),
          _PetSticker(imagePath: petImagePath),
        ],
      ),
    );
  }
}

class _SpeechBubble extends StatelessWidget {
  const _SpeechBubble();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F7F4),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.zero,
        ),
        boxShadow: const [BoxShadow(blurRadius: 6, offset: Offset(0, 2), color: Colors.black12)],
      ),
      child: const Text(
        'You can do it!',
        style: TextStyle(
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w600,
          fontSize: 12,
          color: Color(0xFF214235),
        ),
      ),
    );
  }
}

class _PetSticker extends StatelessWidget {
  const _PetSticker({required this.imagePath});
  final String imagePath;
  bool get _isNetwork => imagePath.startsWith('http://') || imagePath.startsWith('https://');

  @override
  Widget build(BuildContext context) {
    final fallback = const CircleAvatar(radius: 16, child: Icon(Icons.pets, size: 18));
    if (imagePath.isEmpty) return fallback;

    return SizedBox(
      width: 80,
      height: 80,
      child: _isNetwork
          ? Image.network(imagePath, fit: BoxFit.contain, errorBuilder: (_, __, ___) => fallback)
          : Image.asset(imagePath, fit: BoxFit.contain, errorBuilder: (_, __, ___) => fallback),
    );
  }
}

class _DismissibleCard extends StatelessWidget {
  const _DismissibleCard({required this.keyValue, required this.child, required this.onConfirmDelete});
  final String keyValue; final Widget child; final Future<void> Function() onConfirmDelete;
  @override Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(keyValue), direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom:10),
        decoration: BoxDecoration(color: const Color(0xFFE85D5D), borderRadius: BorderRadius.circular(16)),
        alignment: Alignment.centerRight, padding: const EdgeInsets.symmetric(horizontal:16),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        final yes = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Delete item?'),
            content: const Text('This cannot be undone.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
            ],
          ),
        ) ?? false;
        if (yes) await onConfirmDelete();
        return yes;
      },
      child: child,
    );
  }
}

class _BudgetTile extends StatelessWidget {
  const _BudgetTile({
    required this.label,
    required this.category,
    required this.spent,
    required this.budget,
    required this.percent,
    required this.onTap,
  });

  final String label;
  final String category;
  final double spent;
  final double budget;
  final double percent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final vis = _visualFor(category); // 👈 icons/colors follow selected category

    return _Panel(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _RowIconTitle(
            icon: vis.fallbackIcon,
            title: label.isEmpty ? category : label,
            badgeColor: vis.color,
            assetPath: vis.asset,
            menu: const SizedBox(),
          ),
          const SizedBox(height: 10),
          _ProgressBar(value: percent, color: vis.color),
          const SizedBox(height: 10),
          Row(
            children: [
              _meta('Today\'s spending', 'RM ${spent.toStringAsFixed(0)}'),
              const Spacer(),
              _meta('Monthly budget', 'RM ${budget.toStringAsFixed(0)}'),
            ],
          ),
        ],
      ),
    );
  }
}

enum _GoalStatus { overspent, inProgress, reached }

class _GoalTile extends StatelessWidget {
  const _GoalTile({
    required this.label,
    required this.status,
    required this.percent,
    required this.onTap,
    this.category,
  });

  final String label;
  final _GoalStatus status;
  final double percent;
  final VoidCallback onTap;
  final String? category;

  @override
  Widget build(BuildContext context) {
    final vis = _visualFor((category ?? ''));

    late final Color ringColor;
    late final String ringText;
    switch (status) {
      case _GoalStatus.overspent: ringColor = const Color(0xFFFF6B6B); ringText = 'Try harder'; break;
      case _GoalStatus.inProgress: ringColor = const Color(0xFFFFC107); ringText = 'In Progress'; break;
      case _GoalStatus.reached: ringColor = const Color(0xFF4CAF50); ringText = 'You Did It'; break;
    }

// `percent` already passed in from the caller
    final double value = switch (status) {
      _GoalStatus.overspent => 1.0,  // FULL red ring when failed
      _GoalStatus.inProgress => percent,
      _GoalStatus.reached => 1.0,
    };


    return _Panel(
      onTap: onTap,
      child: Row(
        children: [
          // left: category icon
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _RowIconTitle(
                  icon: vis.fallbackIcon,
                  title: category ?? 'Goal',
                  badgeColor: vis.color,
                  assetPath: vis.asset,
                  menu: const SizedBox(),
                ),
                const SizedBox(height: 8),
                Text(
                  label.isEmpty ? 'Goal' : label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _StatusRing(value: value, color: ringColor, label: ringText),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.onTap});
  final Widget child; final VoidCallback? onTap;
  @override Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap, borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity, margin: const EdgeInsets.only(bottom:10), padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF49634F),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.10),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}

class _RowIconTitle extends StatelessWidget {
  const _RowIconTitle({
    required this.icon,
    required this.title,
    required this.menu,
    this.badgeColor,
    this.assetPath,
  });

  final IconData icon;
  final String title;
  final Widget menu;
  final Color? badgeColor;
  final String? assetPath;

  @override
  Widget build(BuildContext context) {
    final color = badgeColor ?? const Color(0xFFEFB8C8);

    Widget badge;
    if (assetPath != null) {
      badge = Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color, width: 2),
        ),
        alignment: Alignment.center,
        child: Image.asset(
          assetPath!,
          width: 18,
          height: 18,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => Icon(icon, size: 16, color: color),
        ),
      );
    } else {
      badge = Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: color.withOpacity(0.25),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color, width: 2),
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 16, color: Colors.white),
      );
    }

    return Row(
      children: [
        badge,
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontFamily: 'Poppins',
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ),
        menu,
      ],
    );
  }
}

Widget _meta(String k, String v) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
  Text(k, style: const TextStyle(color: Colors.white70, fontFamily: 'Poppins', fontSize:11)),
  const SizedBox(height:4),
  Text(v, style: const TextStyle(color: Colors.white, fontFamily:'Poppins', fontWeight: FontWeight.w700)),
]);

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.value, required this.color});
  final double value; final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 8,
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.12)),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: value.clamp(0.0, 1.0),
            child: Container(color: color),
          ),
        ),
      ),
    );
  }
}

/// Circular status ring used in Goals
class _StatusRing extends StatelessWidget {
  const _StatusRing({required this.value, required this.color, required this.label});
  final double value;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      height: 64,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 64, height: 64,
            child: CircularProgressIndicator(
              value: 1,
              strokeWidth: 8,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white24),
            ),
          ),
          SizedBox(
            width: 64, height: 64,
            child: CircularProgressIndicator(
              value: value.clamp(0, 1),
              strokeWidth: 8,
              valueColor: AlwaysStoppedAnimation<Color>(color),
              backgroundColor: Colors.transparent,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10.0),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w600,
                height: 1.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ---------- Shared form (Title + Amount + Category only) ----------
class _GoalFormSheet extends StatefulWidget {
  const _GoalFormSheet({
    required this.title,
    required this.titleCtrl,
    required this.amountCtrl,
    required this.baseCategories,
    required this.selectedCats,
    required this.categoriesStream,
    required this.onSubmit,
    required this.onManageTap,
    this.submitButtonText = 'Add',
    this.onDeleteTap,
    this.onCreateCategory,
  });

  final String title;
  final TextEditingController titleCtrl;
  final TextEditingController amountCtrl;
  final List<String> baseCategories;
  final Set<String> selectedCats;
  final Stream<QuerySnapshot<Map<String, dynamic>>> categoriesStream;
  final VoidCallback onSubmit;
  final String submitButtonText;
  final VoidCallback? onDeleteTap;
  final VoidCallback onManageTap;
  final Future<void> Function(String name)? onCreateCategory;

  @override State<_GoalFormSheet> createState() => _GoalFormSheetState();
}

class _GoalFormSheetState extends State<_GoalFormSheet> {
  void _toggleCat(String c) {
    setState(() {
      if (widget.selectedCats.contains(c)) {
        widget.selectedCats.remove(c);
      } else {
        widget.selectedCats..clear()..add(c);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final bottomInset = media.viewInsets.bottom;   // keyboard
    final safe = media.padding.bottom;             // home indicator / system inset
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: 16 + safe + bottomInset, // <- was just bottomInset before
      ),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children:[
            if (widget.onDeleteTap != null)
              IconButton(tooltip:'Delete', onPressed: widget.onDeleteTap, icon: const Icon(Icons.delete, color: Color(0xFFE85D5D))),
            const Spacer(),
            Text(widget.title, style: const TextStyle(fontFamily:'Poppins', fontWeight: FontWeight.w700, fontSize:16)),
            const Spacer(),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
          ]),
          const SizedBox(height:8),
          _InputBox(controller: widget.titleCtrl, hint: 'Title (e.g., Food Monthly budget)'),
          const SizedBox(height:10),
          _InputBox(
            controller: widget.amountCtrl,
            hint: 'Amount (e.g., RM 40)',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height:14),

          Row(children: [
            const Text('Select Category', style: TextStyle(fontFamily:'Poppins', fontWeight: FontWeight.w600, color: Color(0xFF214235))),
            const SizedBox(width:8),
            InkWell(onTap: widget.onManageTap, borderRadius: BorderRadius.circular(8),
              child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.edit, size:18, color: Color(0xFF64748B))),
            ),
          ]),
          const SizedBox(height:8),

          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: widget.categoriesStream,
            builder: (context, snap) {
              final customs = <_CatItem>[];
              if (snap.hasData) {
                for (final d in snap.data!.docs) {
                  final m = d.data();
                  customs.add(_CatItem(
                    id: d.id, name: (m['name'] ?? '').toString(),
                    color: (m['color'] as int?) ?? _chipColor('custom').value, isDefault: false,
                  ));
                }
              }
              return Wrap(spacing:8, runSpacing:8, children: [
                ...widget.baseCategories.map((c) => _CategoryChip(
                  label: c, selected: widget.selectedCats.contains(c), onTap: () => _toggleCat(c), color: _chipColor(c),
                )),
                ...customs.map((it) => _CategoryChip(
                  label: it.name, selected: widget.selectedCats.contains(it.name), onTap: () => _toggleCat(it.name), color: Color(it.color),
                )),
              ]);
            },
          ),

          const SizedBox(height:16),
          Row(children:[
            const Spacer(),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2B8761), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical:14, horizontal:18), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: widget.onSubmit,
              child: Text(widget.submitButtonText, style: const TextStyle(fontFamily:'Poppins', fontWeight: FontWeight.w700)),
            ),
          ]),
        ]),
      ),

    );
  }


}

class _ManageCategoriesSheet extends StatelessWidget {
  const _ManageCategoriesSheet({
    required this.items, required this.onRename, required this.onDelete,
    required this.onChangeColor, required this.onAdd, required this.pickColor,
  });
  final List<_CatItem> items;
  final Future<void> Function(String id, String newName) onRename;
  final Future<void> Function(String id) onDelete;
  final Future<void> Function(String id, Color newColor) onChangeColor;
  final Future<void> Function(String name) onAdd;
  final Future<Color?> Function(Color start) pickColor;

  @override
  Widget build(BuildContext context) {
    final controller = TextEditingController();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16,12,16,16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: const [
            Text('Manage categories', style: TextStyle(fontFamily:'Poppins', fontWeight: FontWeight.w700)),
            Spacer(),
          ]),
          const SizedBox(height:12),
          Row(children:[
            Expanded(child: TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: 'New category name', filled: true, fillColor: Color(0xFFDDEBDD),
                border: OutlineInputBorder(borderSide: BorderSide.none, borderRadius: BorderRadius.all(Radius.circular(10))),
                contentPadding: EdgeInsets.symmetric(horizontal:12, vertical:10),
              ),
            )),
            const SizedBox(width:8),
            ElevatedButton(onPressed: () async {
              final n = controller.text.trim(); if (n.isEmpty) return;
              await onAdd(n); controller.clear();
            }, child: const Text('Add')),
          ]),
          const SizedBox(height:12),
          ...items.map((it) {
            final color = Color(it.color);
            return Column(children:[
              Row(children: [
                InkWell(
                  customBorder: const CircleBorder(),
                  onTap: it.isDefault ? null : () async {
                    final picked = await pickColor(color);
                    if (picked != null) await onChangeColor(it.id, picked);
                  },
                  child: Container(width:18, height:18, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                ),
                const SizedBox(width:12),
                Expanded(child: Text(it.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily:'Poppins'))),
                IconButton(
                  tooltip: 'Rename',
                  icon: const Icon(Icons.edit, size:18, color: Color(0xFF64748B)),
                  onPressed: it.isDefault ? null : () async {
                    final ctrl = TextEditingController(text: it.name);
                    final newName = await showDialog<String>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Rename category'),
                        content: TextField(controller: ctrl, decoration: const InputDecoration(hintText: 'Category name')),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                          ElevatedButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('Save')),
                        ],
                      ),
                    );
                    if (newName != null && newName.isNotEmpty && newName != it.name) {
                      await onRename(it.id, newName);
                    }
                  },
                ),
                IconButton(
                  tooltip: 'Delete',
                  icon: const Icon(Icons.delete, size:18, color: Color(0xFF94A3B8)),
                  onPressed: it.isDefault ? null : () async {
                    final yes = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Delete category?'),
                        content: Text('Remove “${it.name}”?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
                        ],
                      ),
                    ) ?? false;
                    if (yes) await onDelete(it.id);
                  },
                ),
              ]),
              const Divider(height:16),
            ]);
          }),
        ]),
      ),
    );
  }
}

class _CatItem {
  final String id; final String name; final int color; final bool isDefault;
  const _CatItem({required this.id, required this.name, required this.color, required this.isDefault});
}

Color _chipColor(String c) {
  switch (c.toLowerCase()) {
    case 'entertainment': return const Color(0xFF8B5CF6);
    case 'food': return const Color(0xFF22C55E);
    case 'groceries': return const Color(0xFF38BDF8);
    case 'transport': return const Color(0xFFF59E0B);
    case 'custom': return const Color(0xFF94A3B8);
    default: return const Color(0xFF94A3B8);
  }
}

class _InputBox extends StatelessWidget {
  const _InputBox({required this.controller, required this.hint, this.maxLines = 1, this.keyboardType});
  final TextEditingController controller; final String hint; final int maxLines; final TextInputType? keyboardType;
  @override Widget build(BuildContext context) {
    return TextField(
      controller: controller, maxLines: maxLines, keyboardType: keyboardType,
      style: const TextStyle(fontFamily:'Poppins', color: Color(0xFF1E293B), fontWeight: FontWeight.w500),
      decoration: const InputDecoration().copyWith(
        hintText: hint,
        hintStyle: const TextStyle(fontFamily:'Poppins', color: Color(0xFF94A3B8)),
        filled: true, fillColor: const Color(0xFFDDEBDD),
        contentPadding: const EdgeInsets.symmetric(horizontal:14, vertical:12),
        enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFFC8DCC8)), borderRadius: BorderRadius.all(Radius.circular(12))),
        focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF2B8761), width: 2), borderRadius: BorderRadius.all(Radius.circular(12))),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.label, required this.selected, required this.onTap, required this.color});
  final String label; final bool selected; final VoidCallback onTap; final Color color;
  @override Widget build(BuildContext context) {
    final bg = selected ? color.withOpacity(0.25) : Colors.white;
    final border = selected ? color : const Color(0xFFCBD5E1);
    final text = selected ? Colors.black87 : const Color(0xFF475569);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal:12, vertical:8),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: border)),
        child: Text(label, style: TextStyle(fontFamily:'Poppins', fontWeight: FontWeight.w600, color: text)),
      ),
    );
  }
}
