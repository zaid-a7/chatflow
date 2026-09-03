import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'chat_screen.dart';
import 'login_screen.dart';

class otp_screen extends StatefulWidget {
  final String phoneNumber;
  final String? fullName;
  final String? email;

  // Android
  final String? verificationId;

  // Chrome / Web
  final ConfirmationResult? confirmationResult;

  // true = phone login
  // false = phone signup
  final bool isLogin;

  const otp_screen({
    super.key,
    required this.phoneNumber,
    this.fullName,
    this.email,
    this.verificationId,
    this.confirmationResult,
    this.isLogin = false,
  });

  @override
  State<otp_screen> createState() => _otp_screenState();
}

class _otp_screenState extends State<otp_screen> {
  final TextEditingController otpController =
      TextEditingController();

  bool verifying = false;

  @override
  void dispose() {
    otpController.dispose();
    super.dispose();
  }

  // ================================================================
  // CREATE FIRESTORE USER DOCUMENT
  // ================================================================

  Future<void> _createUserDocument(User user) async {
    final name = widget.fullName?.trim() ?? '';
    final email = widget.email?.trim() ?? '';

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .set({
      'uid': user.uid,
      'fullName': name,
      'email': email,
      'phone': widget.phoneNumber,
      'status': 'Offline',
      'lastSeen': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // ================================================================
  // VERIFY OTP
  // ================================================================

  Future<void> verifyOTP() async {
    final code = otpController.text.trim();

    if (code.length != 6) {
      message('Please enter the 6-digit OTP.');
      return;
    }

    if (verifying) return;

    FocusScope.of(context).unfocus();

    setState(() {
      verifying = true;
    });

    try {
      // ============================================================
      // WEB / CHROME
      // ============================================================

      if (kIsWeb) {
        final confirmationResult =
            widget.confirmationResult;

        if (confirmationResult == null) {
          throw FirebaseAuthException(
            code: 'missing-confirmation-result',
            message:
                'The verification session has expired.',
          );
        }

        // ----------------------------------------------------------
        // WEB PHONE LOGIN
        // ----------------------------------------------------------

        if (widget.isLogin) {
          await confirmationResult.confirm(code);
        }

        // ----------------------------------------------------------
        // WEB PHONE SIGNUP
        // ----------------------------------------------------------

        else {
          final currentUser =
              FirebaseAuth.instance.currentUser;

          if (currentUser == null) {
            throw FirebaseAuthException(
              code: 'user-not-found',
              message:
                  'Your account session has expired.',
            );
          }

          final credential =
              PhoneAuthProvider.credential(
            verificationId:
                confirmationResult.verificationId,
            smsCode: code,
          );

          await currentUser.linkWithCredential(
            credential,
          );
        }
      }

      // ============================================================
      // ANDROID
      // ============================================================

      else {
        final verificationId =
            widget.verificationId;

        if (verificationId == null ||
            verificationId.isEmpty) {
          throw FirebaseAuthException(
            code: 'missing-verification-id',
            message:
                'The verification session has expired.',
          );
        }

        final credential =
            PhoneAuthProvider.credential(
          verificationId: verificationId,
          smsCode: code,
        );

        // ----------------------------------------------------------
        // ANDROID PHONE LOGIN
        // ----------------------------------------------------------

        if (widget.isLogin) {
          await FirebaseAuth.instance
              .signInWithCredential(
            credential,
          );
        }

        // ----------------------------------------------------------
        // ANDROID PHONE SIGNUP
        // ----------------------------------------------------------

        else {
          final currentUser =
              FirebaseAuth.instance.currentUser;

          if (currentUser == null) {
            throw FirebaseAuthException(
              code: 'user-not-found',
              message:
                  'Your account session has expired.',
            );
          }

          await currentUser.linkWithCredential(
            credential,
          );
        }
      }

      // ============================================================
      // CREATE FIRESTORE USER DOCUMENT
      // ============================================================

      if (!widget.isLogin) {
        final currentUser =
            FirebaseAuth.instance.currentUser;

        if (currentUser == null) {
          throw FirebaseAuthException(
            code: 'user-not-found',
            message:
                'Your account session has expired.',
          );
        }

        await _createUserDocument(
          currentUser,
        );
      }

      // ============================================================
      // SUCCESS
      // ============================================================

      if (!mounted) return;

      setState(() {
        verifying = false;
      });

      message(
        'Phone number verified successfully!',
      );

      await Future.delayed(
        const Duration(milliseconds: 900),
      );

      if (!mounted) return;

      // ============================================================
      // PHONE LOGIN SUCCESS
      // ============================================================

      if (widget.isLogin) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (_) => const chat_screen(),
          ),
          (route) => false,
        );

        return;
      }

      // ============================================================
      // PHONE SIGNUP SUCCESS
      // ============================================================

      await FirebaseAuth.instance.signOut();

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => const login_screen(),
        ),
        (route) => false,
      );
    }

    // ==============================================================
    // FIREBASE ERROR
    // ==============================================================

    on FirebaseAuthException catch (e) {
      if (!mounted) return;

      setState(() {
        verifying = false;
      });

      message(
        firebaseErrorMessage(e),
      );
    }

    // ==============================================================
    // OTHER ERROR
    // ==============================================================

    catch (e) {
      if (!mounted) return;

      setState(() {
        verifying = false;
      });

      message(
        'Something went wrong. Please try again.',
      );
    }
  }

  // ================================================================
  // FIREBASE ERROR MESSAGE
  // ================================================================

  String firebaseErrorMessage(
    FirebaseAuthException e,
  ) {
    switch (e.code) {
      case 'invalid-verification-code':
        return 'Incorrect OTP. Please try again.';

      case 'invalid-verification-id':
        return 'The verification session has expired.';

      case 'code-expired':
        return 'The OTP has expired. Please request a new one.';

      case 'session-expired':
        return 'The verification session has expired.';

      case 'missing-verification-id':
        return 'The verification session has expired.';

      case 'missing-confirmation-result':
        return 'The verification session has expired.';

      case 'credential-already-in-use':
        return 'This phone number is already linked to another account.';

      case 'provider-already-linked':
        return 'This phone number is already linked to your account.';

      case 'user-not-found':
        return 'Your account session has expired.';

      case 'too-many-requests':
        return 'Too many attempts. Please wait and try again later.';

      case 'quota-exceeded':
        return 'SMS quota exceeded. Please try again later.';

      case 'network-request-failed':
        return 'Check your internet connection.';

      case 'invalid-phone-number':
        return 'The phone number is invalid.';

      case 'captcha-check-failed':
        return 'reCAPTCHA verification failed. Please try again.';

      case 'app-not-authorized':
        return 'This app is not authorized for Firebase Phone Authentication.';

      case 'operation-not-allowed':
        return 'Phone authentication is not enabled in Firebase.';

      default:
        return e.message ??
            'OTP verification failed.';
    }
  }

  // ================================================================
  // MESSAGE
  // ================================================================

  void message(String text) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
      ),
    );
  }

  // ================================================================
  // UI
  // ================================================================

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
              Color(0xFFDDF8F1),
              Colors.white,
              Color(0xFFE7FAF5),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(25),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 550,
                ),
                child: Column(
                  children: [
                    // =================================================
                    // LOGO
                    // =================================================

                    Image.asset(
                      'assets/splash.png',
                      width: 190,
                      height: 190,
                    ),

                    const SizedBox(height: 20),

                    // =================================================
                    // TITLE
                    // =================================================

                    const Text(
                      'Verify your phone',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF102A5C),
                      ),
                    ),

                    const SizedBox(height: 10),

                    const Text(
                      'We sent a 6-digit verification code to',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        color: Color(0xFF657080),
                      ),
                    ),

                    const SizedBox(height: 5),

                    Text(
                      widget.phoneNumber,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF16AFC1),
                      ),
                    ),

                    const SizedBox(height: 35),

                    // =================================================
                    // OTP FIELD
                    // =================================================

                    Container(
                      height: 70,
                      decoration: BoxDecoration(
                        color:
                            Colors.white.withOpacity(0.78),
                        borderRadius:
                            BorderRadius.circular(35),
                        border: Border.all(
                          color:
                              const Color(0xFFBDEBE3),
                          width: 2,
                        ),
                      ),
                      child: TextField(
                        controller: otpController,
                        keyboardType:
                            TextInputType.number,
                        maxLength: 6,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 8,
                          color: Color(0xFF102A5C),
                        ),
                        decoration:
                            const InputDecoration(
                          counterText: '',
                          border: InputBorder.none,
                          hintText: '••••••',
                          hintStyle: TextStyle(
                            color: Color(0xFF9AA4B2),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 25),

                    // =================================================
                    // VERIFY BUTTON
                    // =================================================

                    SizedBox(
                      width: double.infinity,
                      height: 65,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius:
                              BorderRadius.circular(35),
                          gradient:
                              const LinearGradient(
                            colors: [
                              Color(0xFF10B7CE),
                              Color(0xFF123C87),
                            ],
                          ),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius:
                                BorderRadius.circular(35),
                            onTap: verifying
                                ? null
                                : verifyOTP,
                            child: Center(
                              child: Text(
                                verifying
                                    ? 'Verifying...'
                                    : 'Verify OTP',
                                style:
                                    const TextStyle(
                                  fontSize: 19,
                                  fontWeight:
                                      FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // =================================================
                    // CHANGE PHONE
                    // =================================================

                    TextButton(
                      onPressed: verifying
                          ? null
                          : () {
                              Navigator.pop(context);
                            },
                      child: const Text(
                        'Change phone number',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF16AFC1),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}