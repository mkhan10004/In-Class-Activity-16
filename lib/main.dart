import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'screens/quiz_screen.dart';
import 'screens/sign_in_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Object? setupError;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    setupError = e;
  }
  runApp(QuizApp(setupError: setupError));
}

class QuizApp extends StatelessWidget {
  const QuizApp({super.key, this.setupError});
  final Object? setupError;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'ICA16 A • Cloud Quiz',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF265E8A)),
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFFF6F8FB),
      cardTheme: const CardThemeData(elevation: 0.8),
    ),
    home: setupError != null
        ? Scaffold(
            appBar: AppBar(title: const Text('Firebase setup required')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: SelectableText('Connect this app to your Firebase project:\n\n'
                    '1. Enable Email/Password and Cloud Firestore.\n'
                    '2. Run flutterfire configure in the project folder.\n'
                    '3. Overwrite lib/firebase_options.dart.\n\n'
                    'Initialization detail: $setupError'),
              ),
            ),
          )
        : StreamBuilder<User?>(
            stream: FirebaseAuth.instance.authStateChanges(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Scaffold(body: Center(child: Text('Authentication error: ${snapshot.error}')));
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(body: Center(child: CircularProgressIndicator()));
              }
              final user = snapshot.data;
              if (user == null) return const SignInScreen();
              // Reconstruct round state on account changes; no user A data
              // is reused in user B's interface.
              return QuizScreen(key: ValueKey(user.uid), user: user);
            },
          ),
  );
}
