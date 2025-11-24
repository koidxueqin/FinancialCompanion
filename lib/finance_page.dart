import 'package:flutter/material.dart';
import 'goals_tab.dart';
import 'assistant_tab.dart';
import 'summary_tab.dart';
import 'calendar_tab.dart';

enum FinanceTab { goals, assistant, summary, calendar }

class FinancePage extends StatefulWidget {
  const FinancePage({super.key});
  @override
  State<FinancePage> createState() => _FinancePageState();
}

class _FinancePageState extends State<FinancePage> {
  // Single source of truth for tab order
  static const List<FinanceTab> kTabs = <FinanceTab>[
    FinanceTab.goals,
    FinanceTab.assistant,
    FinanceTab.summary,
    FinanceTab.calendar,
  ];

  FinanceTab _current = kTabs.first;

  @override
  Widget build(BuildContext context) {
    if (!kTabs.contains(_current)) _current = kTabs.first;

    final Map<FinanceTab, Widget> tabPages = {
      FinanceTab.goals: const GoalsTab(),
      FinanceTab.assistant: const AssistantTab(),
      FinanceTab.summary: const SummaryTab(),
      FinanceTab.calendar: const CalendarTab(),
    };

    final currentIndex = kTabs.indexOf(_current);

    return Scaffold(
      backgroundColor: const Color(0xFF8EBB87),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 8),
            _TopIconBar(
              tabs: kTabs,
              current: _current,
              onChanged: (t) => setState(() => _current = t),
              // You can tune these live (pass different values from call site if needed)
              horizontalPadding: 15,
              spacing: 20,
              buttonSize: 70,
              iconSize: 100,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: IndexedStack(
                index: currentIndex,
                children: kTabs.map((t) => tabPages[t]!).toList(growable: false),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopIconBar extends StatelessWidget {
  const _TopIconBar({
    required this.tabs,
    required this.current,
    required this.onChanged,
    this.horizontalPadding = 15,
    this.spacing = 20,
    this.buttonSize = 70,
    this.iconSize = 100,
  });

  final List<FinanceTab> tabs;
  final FinanceTab current;
  final ValueChanged<FinanceTab> onChanged;

  final double horizontalPadding;
  final double spacing;
  final double buttonSize;
  final double iconSize;

  String _assetFor(FinanceTab t) {
    switch (t) {
      case FinanceTab.goals:     return 'assets/goals.png';
      case FinanceTab.assistant: return 'assets/assistant.png';
      case FinanceTab.summary:   return 'assets/summary.png';
      case FinanceTab.calendar:  return 'assets/calendar.png';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 6),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: spacing,
        children: tabs.map((tab) {
          final selected = current == tab;
          return GestureDetector(
            onTap: () => onChanged(tab),
            child: Container(
              width: buttonSize,
              height: buttonSize,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: selected
                    ? Border.all(color: const Color(0xFF264E3C), width: 2)
                    : null,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(.1),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  )
                ],
              ),
              alignment: Alignment.center,
              child: Image.asset(_assetFor(tab), width: iconSize, height: iconSize),
            ),
          );
        }).toList(growable: false),
      ),
    );
  }
}
