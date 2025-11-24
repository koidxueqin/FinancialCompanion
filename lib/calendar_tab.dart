// lib/calendar_tab.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'tx_demo.dart';

/// =============================================================
///  CalendarTab with Auto-capture Inbox
///  - ❕ icon above calendar shows count of pending auto items
///  - Half-height draggable inbox to review/edit/categorize
///  - Nothing is saved to `transactions` until you tap Save
///  - Auto items are expected in users/{uid}/pending_auto
///  - Category Manager (add/rename/delete/recolor)
/// =============================================================
class CalendarTab extends StatefulWidget {
  const CalendarTab({super.key});
  @override
  State<CalendarTab> createState() => _CalendarTabState();
}

class _CalendarTabState extends State<CalendarTab> {

  bool _demoBusy = false;



  Future<void> _runDemo() async {
    if (_demoBusy) return;
    setState(() => _demoBusy = true);
    try {
      await simulatePair();              // write two docs to pending_auto
      if (!mounted) return;
      await _showDemoShade();            // show shade with mae/tng icons
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Added 2 demo notifications to inbox. Tap ❕ to review.')),
        );
      }
    } finally {
      if (mounted) setState(() => _demoBusy = false);
    }
  }


  Future<void> _showDemoShade() async {
    // Visual notification shade (no inbox opening here)
    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'dismiss',
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (_, __, ___) => const SizedBox.shrink(),
      transitionBuilder: (ctx, anim, __, ___) {
        final slide = Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero).animate(anim);
        return Stack(
          children: [
            GestureDetector(
              onTap: () => Navigator.of(ctx).maybePop(),
              child: Container(color: Colors.black.withOpacity(0.35)),
            ),
            SlideTransition(
              position: slide,
              child: Align(
                alignment: Alignment.topCenter,
                child: SafeArea(
                  bottom: false,
                  child: Container(
                    width: double.infinity,
                    margin: const EdgeInsets.all(12),
                    padding: const EdgeInsets.only(top: 8, bottom: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1F2937),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 16, offset: const Offset(0, 6))],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        _DemoNotificationCard(
                          app: "Touch 'n Go eWallet",
                          title: 'Payment',
                          body: 'You have paid RM13.50 for BOOST JUICEBARS - CITY JNCTN.',
                          iconAsset: 'assets/tng.png',
                          iconSize: 22, // adjust if you want larger/smaller
                        ),
                        SizedBox(height: 8),
                        _DemoNotificationCard(
                          app: 'Maybank2u',
                          title: "You\'ve received money!",
                          body: 'COCO TEOH HUI HUI has transferred RM500.00 to you.',
                          iconAsset: 'assets/mae.png',
                          iconSize: 22, // adjust if you want larger/smaller
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }





  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay = _dateKey(DateTime.now());

  final Map<DateTime, List<TransactionEntry>> _byDate = {};
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _catSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _pendingSub;
  Timer? _midnightTicker;

  final List<String> _baseCategories = ['Salary', 'Food', 'Groceries', 'Transport'];
  final List<String> _userCategories = [];
  int _pendingCount = 0;

  // ---------- Firestore helpers ----------
  String get _uid => FirebaseAuth.instance.currentUser!.uid;
  CollectionReference<Map<String, dynamic>> _txCol(String uid) =>
      FirebaseFirestore.instance.collection('users').doc(uid).collection('transactions');
  CollectionReference<Map<String, dynamic>> _catCol(String uid) =>
      FirebaseFirestore.instance.collection('users').doc(uid).collection('categories');
  CollectionReference<Map<String, dynamic>> _pendingCol(String uid) =>
      FirebaseFirestore.instance.collection('users').doc(uid).collection('pending_auto');

  String _slug(String s) => s.trim().toLowerCase();

  @override
  void initState() {
    super.initState();
    _listenCategories();
    _listenMonth(_focusedDay);
    _listenPendingCount();
    _scheduleMidnightTick();
  }

  @override
  void dispose() {
    _midnightTicker?.cancel();
    _sub?.cancel();
    _catSub?.cancel();
    _pendingSub?.cancel();
    super.dispose();
  }

  void _listenCategories() {
    _catSub?.cancel();
    _catSub = _catCol(_uid).orderBy('name').snapshots().listen((snap) {
      final list = <String>[];
      for (final d in snap.docs) {
        final name = (d.data()['name'] ?? '').toString().trim();
        if (name.isNotEmpty) list.add(name);
      }
      setState(() { _userCategories..clear()..addAll(list); });
    });
  }

  void _listenPendingCount() {
    _pendingSub?.cancel();
    _pendingSub = _pendingCol(_uid).snapshots().listen((snap) {
      setState(() => _pendingCount = snap.size);
    });
  }

  // add / rename / delete / recolor
  Future<void> _addCategoryIfMissing(String name) async {
    final n = name.trim();
    if (n.isEmpty) return;
    final all = {
      ..._baseCategories.map((e) => e.toLowerCase()),
      ..._userCategories.map((e) => e.toLowerCase())
    };
    if (all.contains(n.toLowerCase())) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Category already exists')));
      }
      return;
    }
    await _catCol(_uid).doc(_slug(n)).set({'name': n, 'slug': _slug(n), 'createdAt': FieldValue.serverTimestamp()});
  }

  Future<void> _renameCategory(String id, String newName) async {
    final n = newName.trim();
    if (n.isEmpty) return;
    final all = {
      ..._baseCategories.map((e) => e.toLowerCase()),
      ..._userCategories.map((e) => e.toLowerCase())
    };
    if (all.contains(n.toLowerCase())) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Category already exists')));
      return;
    }
    await _catCol(_uid).doc(id).update({'name': n});
  }

  Future<void> _deleteCategory(String id) async {
    if (_baseCategories.map((e) => e.toLowerCase()).contains(id)) return;
    await _catCol(_uid).doc(id).delete();
  }

  Future<void> _updateCategoryColor(String id, Color color) async {
    if (_baseCategories.map((e) => e.toLowerCase()).contains(id)) return;
    await _catCol(_uid).doc(id).update({'color': color.value});
  }

  Future<Color?> _pickColor(Color start) async {
    Color tmp = start;
    return showDialog<Color>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Pick a color'),
        content: SingleChildScrollView(
          child: BlockPicker(
            pickerColor: tmp, onColorChanged: (c) => tmp = c,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, tmp), child: const Text('Done')),
        ],
      ),
    );
  }

  // ---------- calendar ----------
  static DateTime _dateKey(DateTime d) => DateTime(d.year, d.month, d.day);

  void _listenMonth(DateTime anchor) {
    _sub?.cancel();
    final start = DateTime(anchor.year, anchor.month, 1);
    final end = DateTime(anchor.year, anchor.month + 1, 0);
    _sub = _txCol(_uid)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(_dateKey(start)))
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(_dateKey(end)))
        .orderBy('date')
        .snapshots()
        .listen((snap) {
      final map = <DateTime, List<TransactionEntry>>{};
      for (final d in snap.docs) {
        final e = TransactionEntry.fromDoc(d);
        final key = _dateKey(e.date);
        map.putIfAbsent(key, () => []).add(e);
      }
      setState(() { _byDate..clear()..addAll(map); });
    });
  }

  void _scheduleMidnightTick() {
    final now = DateTime.now();
    final nextMidnight = DateTime(now.year, now.month, now.day + 1);
    _midnightTicker = Timer(nextMidnight.difference(now), () {
      if (!mounted) return;
      setState(() {}); // refresh “today”
      _scheduleMidnightTick();
    });
  }

  List<TransactionEntry> _eventsFor(DateTime day) => _byDate[_dateKey(day)] ?? const [];

  // ---------- tx CRUD ----------
  Future<void> _addTransaction({
    required DateTime date, required String title,
    required String description, required double amount,
    required List<String> categories,
  }) async {
    final keyDate = _dateKey(date);
    await _txCol(_uid).add({
      'date': Timestamp.fromDate(keyDate),
      'title': title,
      'description': description,
      'amount': amount,
      'categories': categories,
    });
  }

  Future<void> _updateTransaction({
    required String id, required DateTime date,
    required String title, required String description,
    required double amount, required List<String> categories,
  }) async {
    final keyDate = _dateKey(date);
    await _txCol(_uid).doc(id).update({
      'date': Timestamp.fromDate(keyDate),
      'title': title, 'description': description, 'amount': amount, 'categories': categories,
    });
  }

  Future<void> _deleteTransaction(String id) async {
    await _txCol(_uid).doc(id).delete();
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    final selected = _selectedDay ?? _dateKey(DateTime.now());
    final todaysList = _eventsFor(selected);

    return CustomScrollView(
      slivers: [
        const SliverToBoxAdapter(child: SizedBox(height: 8)),

        // ❕ inbox + 🧪 demo buttons row
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                // ❕ with badge
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    IconButton(
                      tooltip: 'Auto-captured inbox',
                      onPressed: _openAutoInbox,
                      icon: const Text('❕', style: TextStyle(fontSize: 18)),
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFFEFF6F1),
                        padding: const EdgeInsets.all(8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    if (_pendingCount > 0)
                      Positioned(
                        right: -2,
                        top: -2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDC2626),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '$_pendingCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 8),

                // 🧪 simulate notifications
                IconButton(
                  tooltip: _demoBusy ? 'Simulating…' : 'Simulate notifications',
                  onPressed: _demoBusy ? null : _runDemo,
                  icon: const Text('🧪', style: TextStyle(fontSize: 16)),
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFFEFF6F1),
                    padding: const EdgeInsets.all(8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ),
        ),


        // Calendar
        SliverToBoxAdapter(
          child: _RoundedPanel(
            child: TableCalendar(
              firstDay: DateTime.utc(2000, 1, 1),
              lastDay: DateTime.utc(2100, 12, 31),
              focusedDay: _focusedDay,
              calendarFormat: CalendarFormat.month,
              availableGestures: AvailableGestures.horizontalSwipe,
              selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
              onDaySelected: (sel, foc) {
                setState(() { _selectedDay = _dateKey(sel); _focusedDay = foc; });
              },
              onPageChanged: (foc) { setState(() => _focusedDay = foc); _listenMonth(foc); },
              headerStyle: const HeaderStyle(
                formatButtonVisible: false, titleCentered: true,
                leftChevronVisible: true, rightChevronVisible: true,
                titleTextStyle: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, color: Color(0xFF214235)),
              ),
              daysOfWeekStyle: const DaysOfWeekStyle(
                weekdayStyle: TextStyle(fontFamily: 'Poppins'),
                weekendStyle: TextStyle(fontFamily: 'Poppins'),
              ),
              calendarStyle: const CalendarStyle(
                todayDecoration: BoxDecoration(color: Color(0xFF7C58F5), shape: BoxShape.circle),
                selectedDecoration: BoxDecoration(color: Color(0xFF8AD03D), shape: BoxShape.circle),
                defaultTextStyle: TextStyle(fontFamily: 'Poppins'),
                weekendTextStyle: TextStyle(fontFamily: 'Poppins'),
                outsideTextStyle: TextStyle(color: Color(0xFF94A3B8), fontFamily: 'Poppins'),
                markersAutoAligned: false, markersMaxCount: 3,
              ),
              eventLoader: (day) => _eventsFor(day),
              calendarBuilders: CalendarBuilders(
                markerBuilder: (context, date, events) {
                  final count = events.length;
                  if (count == 0) return const SizedBox.shrink();
                  final dotsToShow = count >= 3 ? 3 : count;
                  return Padding(
                    padding: const EdgeInsets.only(top: 40),
                    child: SizedBox(
                      height: 10,
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        for (int i = 0; i < dotsToShow; i++)
                          Container(
                            width: 4, height: 4,
                            margin: const EdgeInsets.symmetric(horizontal: 1.5),
                            decoration: const BoxDecoration(color: Color(0xFF6C9BF7), shape: BoxShape.circle),
                          ),
                        if (count > 3)
                          Container(
                            alignment: Alignment.center, width: 8, height: 8, margin: const EdgeInsets.only(left: 2),
                            child: const FittedBox(
                              child: Text('+', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF6C9BF7))),
                            ),
                          ),
                      ]),
                    ),
                  );
                },
              ),
            ),
          ),
        ),

        // Header
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Transactions (${_prettyDate(selected)})',
              style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 16, color: Color(0xFF214235)),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 8)),

        // “Add” button
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _NewTransactionButton(onTap: () => _openAddTransactionSheet(context), compact: true),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 6)),

        // Transactions list
        // Transactions list
        SliverList(
          delegate: SliverChildBuilderDelegate(
                (context, i) {
              final e = todaysList[i];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Dismissible(
                  key: ValueKey('txn-${e.id}'),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(color: const Color(0xFFE85D5D), borderRadius: BorderRadius.circular(14)),
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  confirmDismiss: (_) async {
                    return await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Delete transaction?'),
                        content: const Text('This cannot be undone.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
                        ],
                      ),
                    ) ?? false;
                  },
                  onDismissed: (_) => _deleteTransaction(e.id),
                  child: _TransactionTile(entry: e, compact: true, onTap: () => _openEditTransactionSheet(context, e)),
                ),
              );
            },
            childCount: todaysList.length,
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 16)),
      ],
    );

  }

  // ---------- helpers ----------
  String _monthName(int m) {
    const names = ['January','February','March','April','May','June','July','August','September','October','November','December'];
    return names[m - 1];
  }
  String _weekdayShort(int w) {
    const names = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    return names[w - 1];
  }
  String _prettyDate(DateTime d) => '${_weekdayShort(d.weekday)} ${d.day} ${_monthName(d.month)}';

  // ---------- sheets ----------
  Future<void> _openAddTransactionSheet(BuildContext context) async {
    final date = _selectedDay ?? _dateKey(DateTime.now());
    final titleCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final selectedCats = <String>{};

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFE7F0E9),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return _TransactionFormSheet(
          title: 'Add New Transaction',
          baseCategories: _baseCategories,
          titleCtrl: titleCtrl, notesCtrl: notesCtrl, amountCtrl: amountCtrl,
          selectedCats: selectedCats,
          categoriesStream: _catCol(_uid).orderBy('name').snapshots(),
          onManageTap: () => _openManageCategories(ctx),
          onSubmit: () async {
            final title = titleCtrl.text.trim().isEmpty ? 'Transaction' : titleCtrl.text.trim();
            final desc = notesCtrl.text.trim();
            final amount = double.tryParse(amountCtrl.text.trim().replaceAll('RM', '').trim()) ?? 0.0;
            final cats = selectedCats.isEmpty ? ['Uncategorized'] : selectedCats.toList();
            await _addTransaction(date: date, title: title, description: desc, amount: amount, categories: cats);
            if (ctx.mounted) Navigator.pop(ctx);
          },
        );
      },
    );
  }

  Future<void> _openEditTransactionSheet(BuildContext context, TransactionEntry entry) async {
    final titleCtrl = TextEditingController(text: entry.title);
    final notesCtrl = TextEditingController(text: entry.description);
    final amountCtrl = TextEditingController(text: entry.amount.toStringAsFixed(2));
    final selectedCats = entry.categories.toSet();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFE7F0E9),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return _TransactionFormSheet(
          title: 'Edit Transaction',
          baseCategories: _baseCategories,
          titleCtrl: titleCtrl, notesCtrl: notesCtrl, amountCtrl: amountCtrl,
          selectedCats: selectedCats,
          categoriesStream: _catCol(_uid).orderBy('name').snapshots(),
          onManageTap: () => _openManageCategories(ctx),
          onSubmit: () async {
            final newTitle = titleCtrl.text.trim().isEmpty ? 'Transaction' : titleCtrl.text.trim();
            final newDesc = notesCtrl.text.trim();
            final newAmount = double.tryParse(amountCtrl.text.trim().replaceAll('RM', '').trim()) ?? entry.amount;
            final newCats = selectedCats.isEmpty ? ['Uncategorized'] : selectedCats.toList();
            await _updateTransaction(
              id: entry.id, date: entry.date, title: newTitle, description: newDesc, amount: newAmount, categories: newCats,
            );
            if (ctx.mounted) Navigator.pop(ctx);
          },
          onDeleteTap: () async {
            final yes = await showDialog<bool>(
              context: ctx,
              builder: (_) => AlertDialog(
                title: const Text('Delete transaction?'),
                content: const Text('This cannot be undone.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                  ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
                ],
              ),
            ) ?? false;
            if (yes) { await _deleteTransaction(entry.id); if (ctx.mounted) Navigator.pop(ctx); }
          },
        );
      },
    );
  }

  /// Auto-captured inbox (half height, no overflow)
  Future<void> _openAutoInbox() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent, // to keep rounded sheet nice
      builder: (_) {
        return DraggableScrollableSheet(
          initialChildSize: 0.70, minChildSize: 0.50, maxChildSize: 0.95,
          builder: (ctx, controller) {
            return Container(
              decoration: const BoxDecoration(
                color: Color(0xFFE7F0E9),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(width: 40, height: 4, decoration: BoxDecoration(
                      color: const Color(0xFF9CA3AF), borderRadius: BorderRadius.circular(4))),
                  const SizedBox(height: 10),
                  const Text('Auto-captured', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Expanded(
                    child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _pendingCol(_uid).orderBy('date', descending: true).snapshots(),
                      builder: (ctx, snap) {
                        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                        final docs = snap.data!.docs;
                        if (docs.isEmpty) {
                          return const Center(child: Text('No pending items 🙂',
                              style: TextStyle(fontFamily: 'Poppins', color: Color(0xFF64748B))));
                        }
                        return ListView.builder(
                          controller: controller,
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          itemCount: docs.length,
                          itemBuilder: (_, i) {
                            final doc = docs[i]; // capture once
                            return _AutoPendingCard(
                              key: ValueKey('pending-${doc.id}'),
                              doc: doc,
                              baseCategories: _baseCategories,
                              userCategories: _userCategories,
                              onSave: (title, desc, amount, cats) async {
                                // read fields from the captured doc
                                final data = doc.data();
                                final ts = data['date'] as Timestamp?;
                                final date = ts?.toDate() ?? DateTime.now();

                                // drop “Uncategorized” if any other category is selected
                                final cleaned = cats.where((c) => c.toLowerCase() != 'uncategorized').toList();
                                final finalCats = cleaned.isEmpty ? <String>['Uncategorized'] : cleaned;

                                // do an atomic move: add to transactions + delete from pending
                                final batch = FirebaseFirestore.instance.batch();
                                final newRef = _txCol(_uid).doc();
                                batch.set(newRef, {
                                  'date': Timestamp.fromDate(_dateKey(date)),
                                  'title': title,
                                  'description': desc,
                                  'amount': amount,
                                  'categories': finalCats,
                                });
                                batch.delete(_pendingCol(_uid).doc(doc.id));
                                await batch.commit();
                              },
                              onDelete: () async {
                                await _pendingCol(_uid).doc(doc.id).delete();
                              },
                            );
                          },

                        );
                      },
                    ),
                  ),
                ],
              ),
            );
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
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) {
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _catCol(_uid).orderBy('name').snapshots(),
          builder: (context, snap) {
            final items = <_CatItem>[
              ..._baseCategories.map((n) => _CatItem(id: _slug(n), name: n, color: _chipColor(n).value, isDefault: true)),
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
              pickColor: (start) => _pickColor(start),
            );
          },
        );
      },
    );
  }
}

class _DemoNotificationCard extends StatelessWidget {
  const _DemoNotificationCard({
    required this.app,
    required this.title,
    required this.body,
    required this.iconAsset,
    this.iconSize = 22,
  });

  final String app;
  final String title;
  final String body;
  final String iconAsset;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34, height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF0B1220),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Image.asset(iconAsset, width: iconSize, height: iconSize, fit: BoxFit.contain),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(app, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(body, style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


/// =============================================================
///  Models & small UI blocks
/// =============================================================
class TransactionEntry {
  final String id;
  final DateTime date;
  final String title;
  final String description;
  final double amount;
  final List<String> categories;
  TransactionEntry({required this.id, required this.date, required this.title, required this.description, required this.amount, required this.categories});
  bool get isIncome => categories.any((c) => c.toLowerCase() == 'salary');
  Map<String, dynamic> toMap() => {
    'date': Timestamp.fromDate(DateTime(date.year, date.month, date.day)),
    'title': title, 'description': description, 'amount': amount, 'categories': categories,
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

class _AutoPendingCard extends StatefulWidget {
  const _AutoPendingCard({
    super.key,
    required this.doc,
    required this.baseCategories,
    required this.userCategories,
    required this.onSave,
    required this.onDelete,
  });

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final List<String> baseCategories;
  final List<String> userCategories;
  final Future<void> Function(String title, String desc, double amount, List<String> categories) onSave;
  final Future<void> Function() onDelete;

  @override
  State<_AutoPendingCard> createState() => _AutoPendingCardState();
}

class _AutoPendingCardState extends State<_AutoPendingCard> {
  late final TextEditingController _title = TextEditingController(text: (widget.doc.data()['title'] ?? 'Transaction').toString());
  late final TextEditingController _notes = TextEditingController(text: (widget.doc.data()['description'] ?? '').toString());
  late final TextEditingController _amount = TextEditingController(text: ((widget.doc.data()['amount'] ?? 0.0) as num).toStringAsFixed(2));
  late final Set<String> _cats = {
    ...(widget.doc.data()['categories'] as List<dynamic>? ?? const <String>[])
        .map((e) => e.toString())
  };

  void _toggle(String c) {
    setState(() {
      if (_cats.contains(c)) { _cats.remove(c); } else { _cats.add(c); }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFF3B3B3B), borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(
          controller: _title,
          decoration: const InputDecoration(
            hintText: 'Title', filled: true, fillColor: Color(0xFFDDEBDD),
            border: OutlineInputBorder(borderSide: BorderSide.none, borderRadius: BorderRadius.all(Radius.circular(10))),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _notes,
          maxLines: 2,
          decoration: const InputDecoration(
            hintText: 'Description', filled: true, fillColor: Color(0xFFDDEBDD),
            border: OutlineInputBorder(borderSide: BorderSide.none, borderRadius: BorderRadius.all(Radius.circular(10))),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            hintText: 'RM 0.00', filled: true, fillColor: Color(0xFFDDEBDD),
            border: OutlineInputBorder(borderSide: BorderSide.none, borderRadius: BorderRadius.all(Radius.circular(10))),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8, runSpacing: 8,
          children: [
            ...widget.baseCategories.map((c) => _CategoryChip(
              label: c, selected: _cats.contains(c), onTap: () => _toggle(c), color: _chipColor(c),
            )),
            ...widget.userCategories.map((c) => _CategoryChip(
              label: c, selected: _cats.contains(c), onTap: () => _toggle(c), color: _chipColor('custom'),
            )),
          ],
        ),
        const SizedBox(height: 12),
        Row(children: [
          TextButton.icon(
            onPressed: widget.onDelete,
            icon: const Icon(Icons.close, size: 16, color: Color(0xFFE85D5D)),
            label: const Text('Dismiss', style: TextStyle(color: Color(0xFFE85D5D))),
          ),
          const Spacer(),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2B8761),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              final title = _title.text.trim().isEmpty ? 'Transaction' : _title.text.trim();
              final desc = _notes.text.trim();
              final amount = double.tryParse(_amount.text.replaceAll('RM', '').trim()) ?? 0.0;
              await widget.onSave(title, desc, amount, _cats.toList());
            },
            child: const Text('Save'),
          ),
        ]),
      ]),
    );
  }
}

class _RoundedPanel extends StatelessWidget {
  const _RoundedPanel({required this.child});
  final Widget child;
  @override Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFFEFF6F1), borderRadius: BorderRadius.circular(20)),
      child: child,
    );
  }
}

class _NewTransactionButton extends StatelessWidget {
  const _NewTransactionButton({required this.onTap, this.compact = false});
  final VoidCallback onTap; final bool compact;
  @override Widget build(BuildContext context) {
    final double vPad = compact ? 10 : 14;
    final double iconBox = compact ? 28 : 34;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(color: const Color(0xFF4E7752), borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.10), blurRadius: 6, offset: const Offset(0, 2))]),
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: vPad),
        child: Row(children: [
          Container(width: iconBox, height: iconBox, decoration: BoxDecoration(color: const Color(0xFFB1DAB5), borderRadius: BorderRadius.circular(10)), alignment: Alignment.center, child: const Icon(Icons.add, color: Colors.black, size: 16)),
          const SizedBox(width: 10),
          const Expanded(child: Text('New transaction', style: TextStyle(fontFamily:'Poppins', color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13))),
          Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4)),
        ]),
      ),
    );
  }
}

List<String> _visibleCats(List<String> cats) {
  final hasReal = cats.any((c) => c.toLowerCase() != 'uncategorized');
  if (!hasReal) return cats;
  return cats.where((c) => c.toLowerCase() != 'uncategorized').toList();
}


class _TransactionTile extends StatelessWidget {
  const _TransactionTile({required this.entry, this.compact = false, this.onTap});
  final TransactionEntry entry; final bool compact; final VoidCallback? onTap;
  @override Widget build(BuildContext context) {
    final double vPad = compact ? 10 : 14;
    final double avatar = compact ? 28 : 34;
    final double chipFS = compact ? 10.5 : 11.0;
    final isIncome = entry.isIncome;
    final String amountStr = '${isIncome ? '+' : '-'}RM ${entry.amount.abs().toStringAsFixed(2)}';
    return InkWell(
      onTap: onTap, borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(color: const Color(0xFFD8E9D9), borderRadius: BorderRadius.circular(14)),
        padding: EdgeInsets.all(vPad),
        child: Row(children: [
          Container(width: avatar, height: avatar, decoration: BoxDecoration(color: const Color(0xFFAED0B2), borderRadius: BorderRadius.circular(10)), alignment: Alignment.center,
              child: Text((entry.categories.isNotEmpty ? entry.categories.first.characters.first : '•').toUpperCase(), style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700))),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(entry.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'Poppins', color: Colors.black, fontWeight: FontWeight.w700, fontSize: 13.5)),
            if (entry.description.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(entry.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'Poppins', color: Colors.black, fontSize: 11.5)),
            ],
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 4, children: _visibleCats(entry.categories).map((c) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.black26)),
              child: Text(c, style: TextStyle(fontFamily: 'Poppins', color: Colors.black, fontSize: chipFS)),
            )).toList()),
          ])),
          const SizedBox(width: 10),
          // Amount pill: GREEN for salary (income), RED for expenses
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: isIncome
                  ? const Color(0xFF10B981) // green (income / Salary)
                  : const Color(0xFFB45C5C), // red (money paid)
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              amountStr,
              style: const TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
          ),

        ]),
      ),
    );
  }
}

/// ---------- Transaction Form (no inline add) ----------
class _TransactionFormSheet extends StatefulWidget {
  const _TransactionFormSheet({
    required this.title, required this.baseCategories,
    required this.titleCtrl, required this.notesCtrl, required this.amountCtrl,
    required this.selectedCats, required this.categoriesStream,
    required this.onSubmit, required this.onManageTap, this.onDeleteTap,
  });

  final String title;
  final List<String> baseCategories;
  final TextEditingController titleCtrl;
  final TextEditingController notesCtrl;
  final TextEditingController amountCtrl;
  final Set<String> selectedCats;
  final Stream<QuerySnapshot<Map<String, dynamic>>> categoriesStream;
  final VoidCallback onSubmit;
  final VoidCallback? onDeleteTap;
  final VoidCallback onManageTap;

  @override
  State<_TransactionFormSheet> createState() => _TransactionFormSheetState();
}

class _TransactionFormSheetState extends State<_TransactionFormSheet> {
  void _toggleCat(String c) {
    setState(() {
      if (widget.selectedCats.contains(c)) {
        widget.selectedCats.remove(c);
      } else {
        widget.selectedCats.add(c);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 12,
        bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              if (widget.onDeleteTap != null)
                IconButton(
                  tooltip: 'Delete',
                  onPressed: widget.onDeleteTap,
                  icon: const Icon(Icons.delete, color: Color(0xFFE85D5D)),
                ),
              const Spacer(),
              Text(
                widget.title,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ]),
            const SizedBox(height: 8),

            _InputBox(controller: widget.titleCtrl, hint: 'Title (e.g., Groceries)'),
            const SizedBox(height: 10),
            _InputBox(controller: widget.notesCtrl, hint: '• eggs, bread, rice', maxLines: 3),
            const SizedBox(height: 10),
            _InputBox(
              controller: widget.amountCtrl,
              hint: 'RM 20',
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 14),

            Row(children: [
              const Text(
                'Select Category',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF214235),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: widget.onManageTap,
                borderRadius: BorderRadius.circular(8),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.edit, size: 18, color: Color(0xFF64748B)),
                ),
              ),
            ]),
            const SizedBox(height: 8),

            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: widget.categoriesStream,
              builder: (context, snap) {
                final customs = <_CatItem>[];
                if (snap.hasData) {
                  for (final d in snap.data!.docs) {
                    final m = d.data();
                    customs.add(_CatItem(
                      id: d.id,
                      name: (m['name'] ?? '').toString(),
                      color: (m['color'] as int?) ?? _chipColor('custom').value,
                      isDefault: false,
                    ));
                  }
                }
                return Wrap(
                  spacing: 8, runSpacing: 8,
                  children: [
                    ...widget.baseCategories.map((c) => _CategoryChip(
                      label: c,
                      selected: widget.selectedCats.contains(c),
                      onTap: () => _toggleCat(c),
                      color: _chipColor(c),
                    )),
                    ...customs.map((it) => _CategoryChip(
                      label: it.name,
                      selected: widget.selectedCats.contains(it.name),
                      onTap: () => _toggleCat(it.name),
                      color: Color(it.color),
                    )),
                  ],
                );
              },
            ),

            const SizedBox(height: 16),

            Row(children: [
              const Spacer(),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2B8761),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: widget.onSubmit,
                child: const Text(
                  'Save',
                  style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700),
                ),
              ),
            ]),
          ],
        ),
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
            Text('Manage categories', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
            Spacer(),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: 'New category name', filled: true, fillColor: Color(0xFFDDEBDD),
                border: OutlineInputBorder(borderSide: BorderSide.none, borderRadius: BorderRadius.all(Radius.circular(10))),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            )),
            const SizedBox(width: 8),
            ElevatedButton(onPressed: () async {
              final n = controller.text.trim(); if (n.isEmpty) return;
              await onAdd(n); controller.clear();
            }, child: const Text('Add')),
          ]),
          const SizedBox(height: 12),
          ...items.map((it) {
            final color = Color(it.color);
            return Column(children: [
              Row(children: [
                InkWell(
                  customBorder: const CircleBorder(),
                  onTap: it.isDefault ? null : () async {
                    final picked = await pickColor(color);
                    if (picked != null) await onChangeColor(it.id, picked);
                  },
                  child: Container(width: 18, height: 18, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(it.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'Poppins'))),
                IconButton(
                  tooltip: 'Rename', icon: const Icon(Icons.edit, size: 18, color: Color(0xFF64748B)),
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
                  tooltip: 'Delete', icon: const Icon(Icons.delete, size: 18, color: Color(0xFF94A3B8)),
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
              const Divider(height: 16),
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

class _InputBox extends StatelessWidget {
  const _InputBox({required this.controller, required this.hint, this.maxLines = 1, this.keyboardType});
  final TextEditingController controller; final String hint; final int maxLines; final TextInputType? keyboardType;
  @override Widget build(BuildContext context) {
    return TextField(
      controller: controller, maxLines: maxLines, keyboardType: keyboardType,
      style: const TextStyle(fontFamily: 'Poppins', color: Color(0xFF1E293B), fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        hintText: hint, hintStyle: const TextStyle(fontFamily: 'Poppins', color: Color(0xFF94A3B8)),
        filled: true, fillColor: const Color(0xFFDDEBDD),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFC8DCC8))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF2B8761), width: 2)),
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: border)),
        child: Text(label, style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, color: text)),
      ),
    );
  }
}

Color _chipColor(String c) {
  switch (c.toLowerCase()) {
    case 'salary': return const Color(0xFF8B5CF6);
    case 'food': return const Color(0xFF22C55E);
    case 'groceries': return const Color(0xFF38BDF8);
    case 'transport': return const Color(0xFFF59E0B);
    case 'custom': return const Color(0xFF94A3B8);
    default: return const Color(0xFF94A3B8);
  }
}
