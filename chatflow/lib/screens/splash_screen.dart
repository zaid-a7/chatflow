import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:chatflow/screens/login_screen.dart';
import 'package:chatflow/screens/chat_screen.dart';

class splash_screen extends StatefulWidget {
  const splash_screen({super.key});

  @override
  State<splash_screen> createState() => _splash_screenState();
}

class _splash_screenState extends State<splash_screen>
    with TickerProviderStateMixin {
  late AnimationController _entranceController;
  late AnimationController _pulseController;

  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();

    // Main entrance animation
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeIn,
    );

    _scaleAnimation = Tween<double>(
      begin: 0.75,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: Curves.easeOutBack,
      ),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: Curves.easeOutCubic,
      ),
    );

    // Subtle continuous pulse
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );

    _entranceController.forward();

    // Start subtle floating animation
    _pulseController.repeat(reverse: true);

    // Check authentication after the splash screen
    Timer(
      const Duration(seconds: 3),
      _checkAuthentication,
    );
  }

  void _checkAuthentication() {
    if (!mounted) return;

    final User? user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      // User is already logged in.
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => const chat_screen(),
        ),
      );
    } else {
      // No logged-in user.
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => const login_screen(),
        ),
      );
    }
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF010520),
              Color(0xFF073B4C),
              Color(0xFF0B4D3B),
            ],
          ),
        ),
        child: Center(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: SlideTransition(
              position: _slideAnimation,
              child: AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  final pulse =
                      1.0 + (_pulseController.value * 0.015);

                  return Transform.scale(
                    scale: _scaleAnimation.value * pulse,
                    child: child,
                  );
                },
                child: Image.asset(
                  "assets/splash.png",
                  fit: BoxFit.contain,
                  width: 400,
                  height: 400,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}