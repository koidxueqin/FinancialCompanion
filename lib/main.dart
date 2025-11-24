// lib/main.dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'startup_page.dart';
import 'login_page.dart';
import 'register_page.dart';
import 'test_trans.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  runApp(const MyApp());

  // Start the listener after first frame so Overlay exists
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    final isLoggedIn = FirebaseAuth.instance.currentUser != null;

    if (isLoggedIn && navigatorKey.currentContext != null) {
      // Start banner-enabled listener
      await startNotificationListenerWithBanner(navigatorKey.currentContext!);

      // If you don't want banners, use:
      // await startNotificationListener();
    }
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey, // Required for banner overlay
      debugShowCheckedModeBanner: false,
      title: 'Financial Companion',
      theme: ThemeData(fontFamily: 'Poppins'),
      home: const StartupPage(),
      routes: {
        '/login': (_) => const LoginPage(),
        '/register': (_) => const RegisterPage(),
      },
    );
  }
}
