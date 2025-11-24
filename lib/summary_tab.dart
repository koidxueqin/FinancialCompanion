import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'course_page.dart' show UserPetAvatar;


enum _Period { weekly, monthly, yearly }

class SummaryTab extends StatefulWidget {
  const SummaryTab({super.key});
  @override
  State<SummaryTab> createState() => _SummaryTabState();
}

class _SummaryTabState extends State<SummaryTab> {
  _Period _period = _Period.weekly;

  CollectionReference<Map<String, dynamic>> _txCol(String uid) =>
      FirebaseFirestore.instance.collection('users').doc(uid).collection('transactions');

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Center(child: Text('Please sign in to view your summary.'));
    }

    final range = _rangeFor(_period, DateTime.now());

    final stream = _txCol(uid)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(range.start))
        .where('date', isLessThan: Timestamp.fromDate(range.end))
        .orderBy('date')
        .snapshots();

    return Scaffold(
      backgroundColor: const Color(0xFF8DB48E),
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: stream,
          builder: (context, snap) {
            final docs = snap.data?.docs ?? const [];
            final totals = _totals(docs);
            final grouped = _groupForChart(docs, _period);

            return CustomScrollView(
              slivers: [
                const SliverToBoxAdapter(child: SizedBox(height: 8)),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _HeaderWithCat(message: _messageFor(totals)),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: _PeriodSelector(
                      period: _period,
                      onChanged: (p) => setState(() => _period = p),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                    child: _ChartCard(
                      title: 'Income & Expenses',
                      xLabels: grouped.labels,
                      groups: grouped.groups,
                      incomeColor: const Color(0xFF40C37B),
                      expenseColor: const Color(0xFF4E9BE6),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    child: _Overview(
                      period: _period,
                      income: totals.income,
                      expense: totals.expense,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ----- Date ranges (Mon–Sun week; month; year) -----------------------------
  ({DateTime start, DateTime end}) _rangeFor(_Period p, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    switch (p) {
      case _Period.weekly:
        final mon = today.subtract(Duration(days: (today.weekday + 6) % 7));
        return (start: mon, end: mon.add(const Duration(days: 7)));
      case _Period.monthly:
        final first = DateTime(now.year, now.month, 1);
        final next = DateTime(now.year, now.month + 1, 1);
        return (start: first, end: next);
      case _Period.yearly:
        final first = DateTime(now.year, 1, 1);
        final next = DateTime(now.year + 1, 1, 1);
        return (start: first, end: next);
    }
  }

  // ----- Totals from docs ----------------------------------------------------
  _Totals _totals(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    double inc = 0, exp = 0;
    for (final d in docs) {
      final data = d.data();
      final amount = (data['amount'] as num?)?.toDouble() ?? 0;
      final cats = (data['categories'] as List<dynamic>? ?? []).cast<String>();
      final isIncome = cats.any((c) => c.toLowerCase() == 'salary');
      if (isIncome) {
        inc += amount.abs();
      } else {
        exp += amount.abs();
      }
    }
    return _Totals(income: inc, expense: exp);
  }

  // ----- Chart grouping (week days, month in W1..W5, year months) ------------
  _Grouped _groupForChart(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      _Period p,
      ) {
    late final List<String> labels;
    late final int slots;
    switch (p) {
      case _Period.weekly:
        labels = const ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
        slots = 7;
        break;
      case _Period.monthly:
        labels = const ['W1','W2','W3','W4','W5'];
        slots = 5;
        break;
      case _Period.yearly:
        labels = const ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
        slots = 12;
        break;
    }

    final inc = List<double>.filled(slots, 0);
    final exp = List<double>.filled(slots, 0);

    for (final d in docs) {
      final data = d.data();
      final date = (data['date'] as Timestamp).toDate();
      final cats = (data['categories'] as List<dynamic>? ?? []).cast<String>();
      final amt = (data['amount'] as num?)?.toDouble() ?? 0;
      final isIncome = cats.any((c) => c.toLowerCase() == 'salary');

      final i = switch (p) {
        _Period.weekly => ((date.weekday + 6) % 7),
        _Period.monthly => ((date.day - 1) ~/ 7).clamp(0, 4),
        _Period.yearly => date.month - 1,
      };
      if (isIncome) {
        inc[i] += amt.abs();
      } else {
        exp[i] += amt.abs();
      }
    }

    final groups = <BarChartGroupData>[];
    for (var i = 0; i < slots; i++) {
      groups.add(
        BarChartGroupData(
          x: i,
          barsSpace: 6,
          barRods: [
            BarChartRodData(toY: inc[i], width: 10, color: const Color(0xFF40C37B)),
            BarChartRodData(toY: exp[i], width: 10, color: const Color(0xFF4E9BE6)),
          ],
        ),
      );
    }
    return _Grouped(groups: groups, labels: labels);
  }

  String _messageFor(_Totals t) {
    if (t.income == 0 && t.expense == 0) return "No transactions!";
    if (t.income >= t.expense) return 'You are on track!';
    return 'Spending is high!';
  }
}

// ========================== UI Pieces ==========================

class _HeaderWithCat extends StatelessWidget {
  const _HeaderWithCat({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final cat = const UserPetAvatar(size: 84);


    // Keep bubble width reasonable so it wraps nicely
    final maxBubbleWidth = MediaQuery.of(context).size.width * 0.70;

    return SizedBox(
      height: 110,
      child: Align(
        alignment: Alignment.topRight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Bubble on the left of the cat, always adjacent
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxBubbleWidth),
              child: Padding(
                padding: const EdgeInsets.only(top: 4), // raise bubble slightly above cat
                child: _SpeechBubble(text: message),
              ),
            ),
            const SizedBox(width: 2),
            cat,
          ],
        ),
      ),
    );
  }

}

class _SpeechBubble extends StatelessWidget {
  const _SpeechBubble({required this.text, this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 8)});
  final String text;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.9),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(0),
        ),
        boxShadow: const [
          BoxShadow(blurRadius: 10, color: Colors.black12, offset: Offset(0, 3)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🐱', style: TextStyle(fontSize: 16)),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );

  }
}



/// Rounded rect with sharp bottom-right corner (no radius) to match your mock.
class _BubbleShape extends RoundedRectangleBorder {
  final double radius;
  final bool cutBottomRight;
  const _BubbleShape({required this.radius, required this.cutBottomRight}) : super(borderRadius: BorderRadius.zero);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final r = Radius.circular(radius);
    return Path()
      ..addRRect(RRect.fromRectAndCorners(
        rect,
        topLeft: r,
        topRight: r,
        bottomLeft: r,
        bottomRight: cutBottomRight ? Radius.zero : r,
      ));
  }
}

class _PeriodSelector extends StatelessWidget {
  const _PeriodSelector({required this.period, required this.onChanged});
  final _Period period;
  final ValueChanged<_Period> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: Colors.white.withOpacity(.6), borderRadius: BorderRadius.circular(20)),
      padding: const EdgeInsets.all(6),
      child: Row(
        children: _Period.values.map((p) {
          final sel = p == period;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: GestureDetector(
                onTap: () => onChanged(p),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(color: sel ? Colors.white : Colors.transparent, borderRadius: BorderRadius.circular(16)),
                  alignment: Alignment.center,
                  child: Text(
                    switch (p) { _Period.weekly => 'Weekly', _Period.monthly => 'Monthly', _Period.yearly => 'Year' },
                    style: TextStyle(fontWeight: FontWeight.w700, color: sel ? Colors.black : Colors.black87),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.title,
    required this.xLabels,
    required this.groups,
    required this.incomeColor,
    required this.expenseColor,
  });

  final String title;
  final List<String> xLabels;
  final List<BarChartGroupData> groups;
  final Color incomeColor;
  final Color expenseColor;

  @override
  Widget build(BuildContext context) {
    final maxY = _maxY(groups);
    final step = maxY / 4;

    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: const [
        BoxShadow(blurRadius: 10, color: Colors.black12, offset: Offset(0, 6))
      ]),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const Spacer(),
          _Legend(color: incomeColor, label: 'Income'),
          const SizedBox(width: 12),
          _Legend(color: expenseColor, label: 'Expenses'),
        ]),
        const SizedBox(height: 10),
        SizedBox(
          height: 220,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              barGroups: groups,
              maxY: maxY,
              borderData: FlBorderData(show: false),
              gridData: FlGridData(show: true, horizontalInterval: step),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: true, reservedSize: 40, interval: step),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (v, meta) {
                      final i = v.toInt();
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          i >= 0 && i < xLabels.length ? xLabels[i] : '',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  double _maxY(List<BarChartGroupData> groups) {
    double m = 0;
    for (final g in groups) {
      for (final r in g.barRods) {
        m = math.max(m, r.toY);
      }
    }
    if (m == 0) return 100;
    final p10 = math.pow(10, (math.log(m) / math.ln10).floor()).toDouble();
    return ((m / p10).ceil() * p10).toDouble();
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 6),
      Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    ]);
  }
}

class _Overview extends StatelessWidget {
  const _Overview({required this.period, required this.income, required this.expense});
  final _Period period;
  final double income;
  final double expense;

  @override
  Widget build(BuildContext context) {
    final title = switch (period) {
      _Period.weekly => "This Week's Overview",
      _Period.monthly => "This Month's Overview",
      _Period.yearly => "This Year's Overview",
    };

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
      const SizedBox(height: 12),
      _OverviewCard(label: 'Income', amount: income, prefix: '+'),
      const SizedBox(height: 14),
      _OverviewCard(label: 'Expenses', amount: expense, prefix: '-'),
    ]);
  }
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({required this.label, required this.amount, required this.prefix});
  final String label;
  final double amount;
  final String prefix;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: Colors.white.withOpacity(.96), borderRadius: BorderRadius.circular(22), boxShadow: const [
        BoxShadow(blurRadius: 10, color: Colors.black12, offset: Offset(0, 6))
      ]),
      padding: const EdgeInsets.all(16),
      child: Row(children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(14)),
          alignment: Alignment.center,
          child: const Text('💰', style: TextStyle(fontSize: 20)),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: Colors.black.withOpacity(.06), borderRadius: BorderRadius.circular(14)),
          child: Text('$prefix RM ${amount.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
      ]),
    );
  }
}

// small data containers
class _Totals {
  final double income;
  final double expense;
  const _Totals({required this.income, required this.expense});
}

class _Grouped {
  final List<BarChartGroupData> groups;
  final List<String> labels;
  const _Grouped({required this.groups, required this.labels});
}
