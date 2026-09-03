// ============================================================================
// FILE PATH: lib/main.dart
// ============================================================================
// UPDATED — adds error handling so a Firebase init failure shows a real
// error screen instead of crashing to a blank white screen. Nothing else
// about your app's behavior or structure changes.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  Object? initError;

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    // Don't crash silently to a white screen — capture it and show a
    // real error screen below instead.
    initError = e;
  }

  runApp(MyApp(initError: initError));
}

class MyApp extends StatelessWidget {
  final Object? initError;

  const MyApp({super.key, this.initError});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "ChatFlow",
      home: initError != null
          ? _StartupErrorScreen(error: initError!)
          : const splash_screen(),
    );
  }
}

// ==============================================================================
// STARTUP ERROR SCREEN
// ==============================================================================
//
// Shown only if Firebase itself fails to start (e.g. no internet on first
// launch, misconfigured project). Every other error in the app (a failed
// message send, a failed call, etc.) is handled separately inside each
// screen and does NOT show this — this is only for the rare case where the
// app can't even start talking to Firebase at all.

class _StartupErrorScreen extends StatelessWidget {
  final Object error;

  const _StartupErrorScreen({required this.error});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF102A5C),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.cloud_off_rounded,
                  color: Colors.white70,
                  size: 60,
                ),
                const SizedBox(height: 20),
                const Text(
                  'Unable to start ChatFlow',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                const Text(
                  'Check your internet connection and try again.',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  error.toString(),
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}