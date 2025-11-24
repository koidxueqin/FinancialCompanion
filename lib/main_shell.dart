import 'package:flutter/material.dart';

// Your pages:
import 'course_page.dart';
import 'finance_page.dart';
import 'home_page.dart';
import 'pet_page.dart';
import 'profile_page.dart';

class MainShell extends StatefulWidget {
  /// 0 = Courses, 1 = Finance, 2 = Home, 3 = Pet, 4 = Profile
  final int initialIndex;

  /// Course to highlight/open when landing on the Courses tab.
  final String? highlightCourseId;

  /// If true, Courses tab should open CoursePage detail immediately.
  /// (Your CoursePage can decide what this means; it's forwarded below.)
  final bool openCourseImmediately;

  const MainShell({
    super.key,
    this.initialIndex = 2,
    this.highlightCourseId,
    this.openCourseImmediately = false,
  });

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  late int _current;

  // One Navigator per tab to preserve each tab's own stack.
  final _navKeys = List.generate(5, (_) => GlobalKey<NavigatorState>());

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
  }

  Future<bool> _onWillPop() async {
    // Pop inner route first; if it can't pop, then allow system back.
    final canPop = await _navKeys[_current].currentState?.maybePop() ?? false;
    return !canPop;
  }

  Widget _navItem({
    required String icon,
    required String iconFilled,
    required int index,
    double size = 28,
  }) {
    final selected = _current == index;
    return GestureDetector(
      onTap: () {
        if (_current == index) {
          // Optional nicety: tapping the active tab pops to its root.
          _navKeys[index].currentState?.popUntil((r) => r.isFirst);
        } else {
          setState(() => _current = index);
        }
      },
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 8.0),
        child: Image.asset(
          selected ? iconFilled : icon,
          height: size,
          width: size,
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        extendBody: true,
        extendBodyBehindAppBar: true,
        backgroundColor: const Color(0xFF8EBB87),

        // Each tab has its own Navigator so the bottom bar persists
        body: IndexedStack(
          index: _current,
          children: [
            // 0) Courses — pass deep-link props through
            _TabNavigator(
              navigatorKey: _navKeys[0],
              child: CoursePage(
                highlightCourseId: widget.highlightCourseId,
                openCourseImmediately: widget.openCourseImmediately,
              ),
            ),
            // 1) Finance (Goals/Assistant/Summary/Calendar)
            _TabNavigator(
              navigatorKey: _navKeys[1],
              child: const FinancePage(),
            ),
            // 2) Home
            _TabNavigator(navigatorKey: _navKeys[2], child: const HomePage()),
            // 3) Pet
            _TabNavigator(navigatorKey: _navKeys[3], child: const PetPage()),
            // 4) Profile
            _TabNavigator(navigatorKey: _navKeys[4], child: const ProfilePage()),
          ],
        ),

        bottomNavigationBar: Container(
          height: 64,
          decoration: const BoxDecoration(
            color: Color(0xFF5E8A76),
            borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _navItem(icon: 'assets/course.png',  iconFilled: 'assets/course_filled.png',  index: 0),
              _navItem(icon: 'assets/dollar.png',  iconFilled: 'assets/dollar_filled.png',  index: 1),
              _navItem(icon: 'assets/home.png',    iconFilled: 'assets/home_filled.png',    index: 2),
              _navItem(icon: 'assets/paw.png',     iconFilled: 'assets/paw_filled.png',     index: 3),
              _navItem(icon: 'assets/user.png',    iconFilled: 'assets/user_filled.png',    index: 4),
            ],
          ),
        ),
      ),
    );
  }
}

// A small wrapper that gives each tab its own Navigator
class _TabNavigator extends StatelessWidget {
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;
  const _TabNavigator({required this.navigatorKey, required this.child});

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: navigatorKey,
      onGenerateRoute: (settings) => MaterialPageRoute(
        builder: (_) => child,
        settings: settings,
      ),
    );
  }
}
