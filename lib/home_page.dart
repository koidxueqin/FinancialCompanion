import 'dart:math';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_generative_ai/google_generative_ai.dart'; // <- for silent AI
import 'course_page.dart'; // for Course model
import 'main_shell.dart';


class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String get _uid => FirebaseAuth.instance.currentUser!.uid;
  DocumentReference<Map<String, dynamic>> get _userDoc =>
      FirebaseFirestore.instance.collection('users').doc(_uid);
  CollectionReference<Map<String, dynamic>> get _budgetsCol =>
      _userDoc.collection('budgets');
  CollectionReference<Map<String, dynamic>> get _txCol =>
      _userDoc.collection('transactions');
  CollectionReference<Map<String, dynamic>> get _coursesCol =>
      FirebaseFirestore.instance.collection('courses');

  String get _periodKey {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
  }

  // ---------- Streams ----------
  Stream<double> _monthlyBudgetTotal() {
    return _budgetsCol
        .where('period', isEqualTo: _periodKey)
        .snapshots()
        .map((snap) => snap.docs.fold<double>(
      0.0,
          (sum, d) => sum + (d.data()['amount'] ?? 0).toDouble(),
    ));
  }

  Stream<double> _monthlySpentTotal() {
    final start = DateTime(DateTime.now().year, DateTime.now().month, 1);
    final end = DateTime(DateTime.now().year, DateTime.now().month + 1, 0);
    return _txCol
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(end))
        .snapshots()
        .map((snap) {
      double sum = 0.0;
      for (final d in snap.docs) {
        final data = d.data();
        final amount = (data['amount'] ?? 0).toDouble();
        final cats = (data['categories'] as List<dynamic>? ?? [])
            .map((e) => '$e')
            .toList();
        final isIncome = cats.any((c) => c.toLowerCase() == 'salary');
        if (!isIncome) sum += amount.abs();
      }
      return sum;
    });
  }

  @override
  Widget build(BuildContext context) {
    // heights for the inner scroll areas
    const double kInnerListHeight = 280;

    return StreamBuilder<double>(
      stream: _monthlyBudgetTotal(),
      builder: (ctx, budgetSnap) {
        final budget = budgetSnap.data ?? 0.0;

        return StreamBuilder<double>(
          stream: _monthlySpentTotal(),
          builder: (ctx, spentSnap) {
            final spent = spentSnap.data ?? 0.0;
            final overspend = spent > budget ? (spent - budget) : 0.0;
            final used = min(spent, budget);
            final balance = max(0.0, budget - spent);

            return ListView(
              padding: const EdgeInsets.fromLTRB(0, 30, 0, 16),
              children: [
                const SizedBox(height: 12),

                // Donut card
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 180,
                          height: 180,
                          child: _BudgetDonut(
                            budget: budget,
                            used: used,
                            balance: balance,
                            overspend: overspend,
                          ),
                        ),
                        const SizedBox(width: 16),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _Legend(color: Color(0xFFB45C5C), text: 'Overspend'),
                              SizedBox(height: 10),
                              _Legend(color: Color(0xFFFBBF24), text: 'Used amount'),
                              SizedBox(height: 10),
                              _Legend(color: Color(0xFF22C55E), text: 'Balance'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                const _SectionTitle('Recent transactions'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    height: kInnerListHeight,
                    child: _RecentTransactionsList(
                      txCol: _txCol,
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                const _SectionTitle('Recommended for you'),
                // Silent AI picks categories -> we show only real courses from Firestore
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    height: kInnerListHeight,
                    child: _AiRecommendedCourses(
                      coursesCol: _coursesCol,
                      txCol: _txCol,
                      budgetsCol: _budgetsCol,
                      userId: _uid,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.text});
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
            width: 14,
            height: 14,
            decoration:
            BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
        const SizedBox(width: 10),
        Text(
          text,
          style: const TextStyle(
            fontFamily: 'Poppins',
            color: Color(0xFF214235),
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
      ],
    );
  }
}

/// ---------------- Donut with segment labels ----------------
class _BudgetDonut extends StatelessWidget {
  const _BudgetDonut({
    required this.budget,
    required this.used,
    required this.balance,
    required this.overspend,
  });

  final double budget;
  final double used;
  final double balance;
  final double overspend;

  @override
  Widget build(BuildContext context) {
    final segments = <_Seg>[];
    if (used > 0) {
      segments.add(_Seg(
        value: used,
        color: const Color(0xFFFBBF24), // orange (used)
        label: 'RM ${used.toStringAsFixed(0)}',
      ));
    }
    if (balance > 0) {
      segments.add(_Seg(
        value: balance,
        color: const Color(0xFF22C55E), // green (balance)
        label: 'RM ${balance.toStringAsFixed(0)}',
      ));
    }
    if (overspend > 0) {
      segments.add(_Seg(
        value: overspend,
        color: const Color(0xFFB45C5C), // red (overspend)
        label: 'RM ${overspend.toStringAsFixed(0)}',
      ));
    }

    final total = (overspend > 0) ? (overspend + budget) : max(1.0, budget);
    final centerText = 'Current Budget:\nRM ${budget.toStringAsFixed(0)}';

    return CustomPaint(
      painter: _DonutPainter(segments: segments, total: total),
      child: Center(
        child: Text(
          centerText,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            shadows: [Shadow(color: Colors.black45, blurRadius: 2, offset: Offset(0, 1))],
          ),
        ),
      ),
    );
  }
}

class _Seg {
  final double value;
  final Color color;
  final String label;
  _Seg({required this.value, required this.color, required this.label});
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.segments, required this.total});
  final List<_Seg> segments;
  final double total;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 20.0;
    final center = size.center(Offset.zero);
    final radius = min(size.width, size.height) / 2 - 6;

    // background ring
    final bg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = const Color(0xFFCDE5D2);
    canvas.drawCircle(center, radius, bg);

    if (total <= 0) return;

    double start = -pi / 2;

    for (final s in segments) {
      final sweep = (s.value / total) * 2 * pi;
      if (sweep <= 0) continue;

      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = s.color;

      // arc
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        sweep,
        false,
        p,
      );

      // label positioned on the segment
      final mid = start + sweep / 2;
      final dx = center.dx + cos(mid) * (radius - stroke * 0.25);
      final dy = center.dy + sin(mid) * (radius - stroke * 0.25);
      _drawChip(canvas, s.label, Offset(dx, dy), s.color);

      start += sweep + 0.0001;
    }
  }

  void _drawChip(Canvas canvas, String text, Offset center, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w700,
          fontSize: 11,
          color: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final padH = 8.0, padV = 4.0;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        center.dx - tp.width / 2 - padH,
        center.dy - tp.height / 2 - padV,
        tp.width + padH * 2,
        tp.height + padV * 2,
      ),
      const Radius.circular(10),
    );

    final paint = Paint()..color = color.withOpacity(0.9);
    canvas.drawRRect(rect, paint);
    tp.paint(
      canvas,
      Offset(rect.left + (rect.width - tp.width) / 2,
          rect.top + (rect.height - tp.height) / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.total != total || old.segments != segments;
}

/// ---------------- Recent transactions (own scroll) ----------------
class _RecentTransactionsList extends StatelessWidget {
  const _RecentTransactionsList({required this.txCol});
  final CollectionReference<Map<String, dynamic>> txCol;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: txCol.orderBy('date', descending: true).limit(50).snapshots(),
      builder: (ctx, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return const Center(
            child: Text(
              'No transactions yet.',
              style: TextStyle(fontFamily: 'Poppins', color: Color(0xFF475569)),
            ),
          );
        }
        return ListView.separated(
          primary: false,
          physics: const BouncingScrollPhysics(),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final d = docs[index];
            final m = d.data();
            final title = (m['title'] ?? '') as String;
            final desc = (m['description'] ?? '') as String;
            final amount = (m['amount'] ?? 0).toDouble();
            final ts = (m['date'] as Timestamp?)?.toDate();
            final dateStr =
            ts == null ? '' : '${_month(ts.month)} ${ts.day}, ${ts.year}';

            final cats = (m['categories'] as List<dynamic>? ?? [])
                .map((e) => e.toString())
                .toList();
            final isIncome = cats.any((c) => c.toLowerCase() == 'salary');
            final amountStr =
                '${isIncome ? '+' : '-'}RM ${amount.abs().toStringAsFixed(0)}';

            return _TxCard(
              leadingText:
              cats.isNotEmpty ? cats.first.characters.first.toUpperCase() : '•',
              title: title.isEmpty ? (cats.isEmpty ? 'Transaction' : cats.first) : title,
              subtitle: dateStr,
              rightPill: amountStr,
              description: desc,
            );
          },
        );
      },
    );
  }

  static String _month(int m) {
    const n = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return n[m - 1];
  }
}

class _TxCard extends StatelessWidget {
  const _TxCard({
    required this.leadingText,
    required this.title,
    required this.subtitle,
    required this.rightPill,
    this.description = '',
  });

  final String leadingText;
  final String title;
  final String subtitle;
  final String rightPill;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Color(0xFF39683D),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.white.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFFA3C8A7),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Text(
              leadingText,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                color: Colors.black,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.white,
                    fontSize: 11.5,
                  ),
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      color: Colors.white,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFA2D5A7),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFA2D5A7)),
            ),
            child: Text(
              rightPill,
              style: const TextStyle(
                fontFamily: 'Poppins',
                color: Colors.black,
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ---------------- Silent AI recommendations (own scroll) ----------------
/// This widget:
/// 1) Builds a monthly financial summary from Firestore
/// 2) Asks Gemini (silently) for up to 3 categories
/// 3) Maps categories -> EXISTING courses in your 'courses' collection
/// 4) Displays them using the same card style you already have
class _AiRecommendedCourses extends StatefulWidget {
  const _AiRecommendedCourses({
    required this.coursesCol,
    required this.txCol,
    required this.budgetsCol,
    required this.userId,
  });

  final CollectionReference<Map<String, dynamic>> coursesCol;
  final CollectionReference<Map<String, dynamic>> txCol;
  final CollectionReference<Map<String, dynamic>> budgetsCol;
  final String userId;

  @override
  State<_AiRecommendedCourses> createState() => _AiRecommendedCoursesState();
}

class _AiRecommendedCoursesState extends State<_AiRecommendedCourses> {
  bool _loading = true;
  List<Course> _all = [];
  List<Course> _suggested = [];


  static const String _apiKey = 'AIzaSyAhxy_gk0FYEnaxzVa5VH2OqABxhNLxk8s';

  late final GenerativeModel _model = GenerativeModel(
    model: 'gemini-2.5-flash',
    apiKey: _apiKey,
    systemInstruction: Content.system(
      "You will receive a JSON summary of the user's budgets, goals, and spending. "
          "Reply with valid JSON containing ONLY the key 'suggested_categories' (array of up to 3 strings). "
          "Example: {\"suggested_categories\":[\"Budgeting\",\"Planning\"]}. "
          "Pick categories that EXIST in the app (e.g., Budgeting, Investing, Planning). "
          "No extra keys. No prose. No markdown.",
    ),
  );

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      // 1) Load all courses for local mapping
      final cdocs = await widget.coursesCol.get();
      _all = cdocs.docs.map((d) => Course.fromMap(d.data(), d.id)).toList();

      // 2) Build user financial summary (current month)
      final summaryJson = await _buildUserFinancialSummary(widget.userId);

      // 3) Ask AI for up to 3 categories (silent)
      final cats = await _pickCategories(summaryJson);

      // 4) Map categories -> courses you already have (title contains)
      final lowerCats = cats.map((c) => c.toLowerCase()).toList();
      final matches = <Course>{
        for (final c in lowerCats)
          ..._all.where((course) {
            final t1 = course.shortTitle.toLowerCase();
            final t2 = course.longTitle.toLowerCase();
            return t1.contains(c) || t2.contains(c);
          })
      };

      setState(() => _suggested = matches.toList());
    } catch (_) {
      setState(() => _suggested = []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<String>> _pickCategories(String financialSummaryJson) async {
    final prompt =
        "User financial summary: $financialSummaryJson\n\nUser message: Recommend up to 3 relevant learning categories.";
    final res = await _model.generateContent([Content.text(prompt)]);
    final raw = (res.text ?? '').trim();
    if (raw.isEmpty) return const [];
    final cleaned = raw.replaceAll('```json', '').replaceAll('```', '').trim();
    final map = jsonDecode(cleaned) as Map<String, dynamic>;
    final cats = (map['suggested_categories'] as List?)?.cast<String>() ?? const [];
    final set = <String>{};
    for (final c in cats) {
      final s = c.trim();
      if (s.isNotEmpty) set.add(s);
      if (set.length == 3) break;
    }
    return set.toList();
  }

  // Minimal, local version of your summary builder (current month)
  Future<String> _buildUserFinancialSummary(String userId) async {
    final now = DateTime.now();
    final periodKey = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
    final monthStart = DateTime(now.year, now.month, 1);
    final monthEnd = DateTime(now.year, now.month + 1, 0);

    final userDoc = FirebaseFirestore.instance.collection('users').doc(userId);
    final budgetsCol = userDoc.collection('budgets');
    final goalsCol = userDoc.collection('goals');
    final txCol = userDoc.collection('transactions');

    try {
      final results = await Future.wait([
        budgetsCol.where('period', isEqualTo: periodKey).get(),
        goalsCol.where('period', isEqualTo: periodKey).get(),
        txCol
            .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(DateTime(monthStart.year, monthStart.month, monthStart.day)))
            .where('date', isLessThanOrEqualTo: Timestamp.fromDate(DateTime(monthEnd.year, monthEnd.month, monthEnd.day)))
            .get(),
      ]);

      final budgets = (results[0] as QuerySnapshot<Map<String, dynamic>>)
          .docs
          .map((d) => {
        'label': d['label'],
        'category': d['category'],
        'amount': d['amount'],
      })
          .toList();

      final goals = (results[1] as QuerySnapshot<Map<String, dynamic>>)
          .docs
          .map((d) => {
        'label': d['label'],
        'category': d['category'],
        'goalAmount': d['goalAmount'],
      })
          .toList();

      final txSnap = results[2] as QuerySnapshot<Map<String, dynamic>>;
      final spendByCategory = <String, double>{};
      double totalSpending = 0;
      for (final d in txSnap.docs) {
        final m = d.data();
        final cats =
        (m['categories'] as List<dynamic>? ?? []).map((e) => e.toString()).toList();
        final amount = (m['amount'] ?? 0).toDouble();
        totalSpending += amount;
        if (cats.isEmpty) {
          spendByCategory['uncategorized'] =
              (spendByCategory['uncategorized'] ?? 0) + amount;
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

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_suggested.isEmpty) return const Center(child: Text('No suggestions yet.'));

    // Renders exactly like your regular course list cards
    return ListView.separated(
      primary: false,
      physics: const BouncingScrollPhysics(),
      itemCount: _suggested.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final course = _suggested[i];

        // Try to read minutes as an int from duration like "12 Min read"
        final minutes = int.tryParse(
          course.duration.replaceAll(RegExp(r'[^0-9]'), ''),
        ) ??
            5;

        return GestureDetector(
          onTap: () {
            // Deep link to Courses tab and auto-open this course
            Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
              MaterialPageRoute(
                builder: (_) => MainShell(
                  initialIndex: 0,                    // Courses tab
                  highlightCourseId: course.id,       // which course to scroll to
                  openCourseImmediately: true,        // auto-open its sheet
                ),
              ),
                  (route) => false,
            );
          },
          child: _CourseCard(
            title: course.shortTitle,
            author: course.author,
            minutes: minutes,
            hasQuiz: course.hasQuiz,
            imageUrl: '', // set if you have thumbnails
          ),
        );
      },

    );
  }
}

class _CourseCard extends StatelessWidget {
  const _CourseCard({
    required this.title,
    required this.author,
    required this.minutes,
    required this.hasQuiz,
    this.imageUrl = '',
  });

  final String title;
  final String author;
  final int minutes;
  final bool hasQuiz;
  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 88,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF214235).withOpacity(0.85),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          // Thumbnail
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFF94A3B8),
              borderRadius: BorderRadius.circular(8),
              image: imageUrl.isNotEmpty
                  ? DecorationImage(image: NetworkImage(imageUrl), fit: BoxFit.cover)
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          // Texts
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                    )),
                const SizedBox(height: 2),
                Text(
                  author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontFamily: 'Poppins', color: Colors.white70, fontSize: 11.5),
                ),
                const Spacer(),
                Row(
                  children: [
                    Container(
                      padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Text(
                        hasQuiz ? 'Quiz included' : 'No Quiz',
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          color: Colors.white,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${minutes} Min read',
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.white70,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w700,
          fontSize: 16,
          color: Color(0xFFEFF6F1),
        ),
      ),
    );
  }
}
