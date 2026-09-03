import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'signup_screen.dart';
import 'chat_screen.dart';
import 'otp_screen.dart';

class login_screen extends StatefulWidget {
  const login_screen({super.key});

  @override
  State<login_screen> createState() => _login_screenState();
}

class _login_screenState extends State<login_screen> {
  final phoneEmailController = TextEditingController();
  final passwordController = TextEditingController();

  bool hidePassword = true;
  bool loggingIn = false;

  @override
  void dispose() {
    phoneEmailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  // ================================================================
  // LOGIN
  // ================================================================

  Future<void> _handleLogin() async {
    if (loggingIn) return;

    FocusScope.of(context).unfocus();

    final input = phoneEmailController.text.trim();
    final password = passwordController.text.trim();

    if (input.isEmpty) {
      message(
        'Please enter your phone number or email.',
      );
      return;
    }

    // ==============================================================
    // EMAIL LOGIN
    // ==============================================================

    if (input.contains('@')) {
      if (password.isEmpty) {
        message(
          'Please enter your password.',
        );
        return;
      }

      setState(() {
        loggingIn = true;
      });

      try {
        await FirebaseAuth.instance
            .signInWithEmailAndPassword(
          email: input,
          password: password,
        );

        if (!mounted) return;

        setState(() {
          loggingIn = false;
        });

        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (_) => const chat_screen(),
          ),
          (route) => false,
        );
      } on FirebaseAuthException catch (e) {
        if (!mounted) return;

        setState(() {
          loggingIn = false;
        });

        message(
          firebaseEmailLoginErrorMessage(e),
        );
      } catch (_) {
        if (!mounted) return;

        setState(() {
          loggingIn = false;
        });

        message(
          'Something went wrong. Please try again.',
        );
      }

      return;
    }

    // ==============================================================
    // PHONE LOGIN
    // ==============================================================

    String phoneNumber =
        input.replaceAll(RegExp(r'[\s()-]'), '');

    // Automatically add +91 for a 10-digit Indian number.
    if (RegExp(r'^[0-9]{10}$').hasMatch(phoneNumber)) {
      phoneNumber = '+91$phoneNumber';
    }

    // Basic international phone validation.
    if (!RegExp(
      r'^\+[1-9][0-9]{7,14}$',
    ).hasMatch(phoneNumber)) {
      message(
        'Please enter a valid phone number with country code.',
      );
      return;
    }

    setState(() {
      loggingIn = true;
    });

    // ==============================================================
    // WEB / CHROME
    // ==============================================================

    if (kIsWeb) {
      try {
        final confirmationResult =
            await FirebaseAuth.instance
                .signInWithPhoneNumber(
          phoneNumber,
        );

        if (!mounted) return;

        setState(() {
          loggingIn = false;
        });

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => otp_screen(
              phoneNumber: phoneNumber,
              confirmationResult:
                  confirmationResult,
              isLogin: true,
            ),
          ),
        );
      } on FirebaseAuthException catch (e) {
        if (!mounted) return;

        setState(() {
          loggingIn = false;
        });

        message(
          firebasePhoneLoginErrorMessage(e),
        );
      } catch (_) {
        if (!mounted) return;

        setState(() {
          loggingIn = false;
        });

        message(
          'Could not send OTP. Please try again.',
        );
      }

      return;
    }

    // ==============================================================
    // ANDROID
    // ==============================================================

    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phoneNumber,

        // ----------------------------------------------------------
        // AUTOMATIC ANDROID VERIFICATION
        // ----------------------------------------------------------

        verificationCompleted:
            (PhoneAuthCredential credential) async {
          try {
            await FirebaseAuth.instance
                .signInWithCredential(
              credential,
            );

            if (!mounted) return;

            setState(() {
              loggingIn = false;
            });

            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(
                builder: (_) => const chat_screen(),
              ),
              (route) => false,
            );
          } on FirebaseAuthException catch (e) {
            if (!mounted) return;

            setState(() {
              loggingIn = false;
            });

            message(
              firebasePhoneLoginErrorMessage(e),
            );
          } catch (_) {
            if (!mounted) return;

            setState(() {
              loggingIn = false;
            });

            message(
              'Phone login failed. Please try again.',
            );
          }
        },

        // ----------------------------------------------------------
        // VERIFICATION FAILED
        // ----------------------------------------------------------

        verificationFailed:
            (FirebaseAuthException e) {
          if (!mounted) return;

          setState(() {
            loggingIn = false;
          });

          message(
            firebasePhoneLoginErrorMessage(e),
          );
        },

        // ----------------------------------------------------------
        // OTP SENT
        // ----------------------------------------------------------

        codeSent: (
          String verificationId,
          int? resendToken,
        ) {
          if (!mounted) return;

          setState(() {
            loggingIn = false;
          });

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => otp_screen(
                phoneNumber: phoneNumber,
                verificationId: verificationId,
                isLogin: true,
              ),
            ),
          );
        },

        // ----------------------------------------------------------
        // TIMEOUT
        // ----------------------------------------------------------

        codeAutoRetrievalTimeout:
            (String verificationId) {},
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      setState(() {
        loggingIn = false;
      });

      message(
        firebasePhoneLoginErrorMessage(e),
      );
    } catch (_) {
      if (!mounted) return;

      setState(() {
        loggingIn = false;
      });

      message(
        'Could not send OTP. Please try again.',
      );
    }
  }

  // ================================================================
  // EMAIL LOGIN ERRORS
  // ================================================================

  String firebaseEmailLoginErrorMessage(
    FirebaseAuthException e,
  ) {
    switch (e.code) {
      case 'invalid-email':
        return 'Please enter a valid email address.';

      case 'invalid-credential':
        return 'Incorrect email or password.';

      case 'wrong-password':
        return 'Incorrect email or password.';

      case 'user-not-found':
        return 'No account exists with this email.';

      case 'user-disabled':
        return 'This account has been disabled.';

      case 'too-many-requests':
        return 'Too many attempts. Please wait and try again later.';

      case 'network-request-failed':
        return 'Check your internet connection.';

      case 'operation-not-allowed':
        return 'Email/password login is not enabled in Firebase.';

      default:
        return e.message ??
            'Login failed. Please try again.';
    }
  }

  // ================================================================
  // PHONE LOGIN ERRORS
  // ================================================================

  String firebasePhoneLoginErrorMessage(
    FirebaseAuthException e,
  ) {
    switch (e.code) {
      case 'invalid-phone-number':
        return 'The phone number is invalid.';

      case 'too-many-requests':
        return 'Too many verification attempts. Please wait and try again later.';

      case 'quota-exceeded':
        return 'SMS quota exceeded. Please try again later.';

      case 'captcha-check-failed':
        return 'reCAPTCHA verification failed. Please try again.';

      case 'app-not-authorized':
        return 'This app is not authorized for Firebase Phone Authentication.';

      case 'operation-not-allowed':
        return 'Phone authentication is not enabled in Firebase.';

      case 'network-request-failed':
        return 'Check your internet connection.';

      default:
        return e.message ??
            'Could not send OTP. Please try again.';
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
      body: Stack(
        children: [
          Container(
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
          ),

          const Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: LoginBackgroundPainter(),
              ),
            ),
          ),

          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: 25,
                vertical: 25,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 650,
                  ),
                  child: Column(
                    children: [
                      // =================================================
                      // LOGO
                      // =================================================

                      LayoutBuilder(
                        builder: (
                          context,
                          constraints,
                        ) {
                          final size =
                              constraints.maxWidth <
                                      500
                                  ? constraints
                                          .maxWidth *
                                      0.70
                                  : 320.0;

                          return SizedBox(
                            width: size,
                            height: size,
                            child: Image.asset(
                              'assets/splash.png',
                              fit: BoxFit.contain,
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 5),

                      // =================================================
                      // TITLE
                      // =================================================

                      RichText(
                        textAlign:
                            TextAlign.center,
                        text: const TextSpan(
                          children: [
                            TextSpan(
                              text: 'Welcome to ',
                              style: TextStyle(
                                fontSize: 34,
                                fontWeight:
                                    FontWeight.bold,
                                color:
                                    Color(0xFF102A5C),
                              ),
                            ),
                            TextSpan(
                              text: 'ChatFlow',
                              style: TextStyle(
                                fontSize: 34,
                                fontWeight:
                                    FontWeight.bold,
                                color:
                                    Color(0xFF16AFC1),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 45),

                      // =================================================
                      // PHONE / EMAIL
                      // =================================================

                      _label(
                        'Phone number or Email',
                      ),

                      const SizedBox(height: 10),

                      _inputField(
                        controller:
                            phoneEmailController,
                        hint:
                            'Enter phone no or email',
                        icon:
                            Icons.phone_android_rounded,
                      ),

                      const SizedBox(height: 24),

                      // =================================================
                      // PASSWORD
                      // =================================================

                      _label('Password'),

                      const SizedBox(height: 10),

                      _passwordField(),

                      const SizedBox(height: 10),

                      _passwordRequirements(
                        passwordController.text,
                      ),

                      Align(
                        alignment:
                            Alignment.centerRight,
                        child: TextButton(
                          onPressed:
                              loggingIn
                                  ? null
                                  : () {
                                      message(
                                        'Password reset will be added next.',
                                      );
                                    },
                          child: const Text(
                            'Forgot password?',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight:
                                  FontWeight.w600,
                              color:
                                  Color(0xFF149FB0),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 5),

                      // =================================================
                      // LOGIN BUTTON
                      // =================================================

                      _gradientButton(
                        text: loggingIn
                            ? 'Logging in...'
                            : 'Login',
                        onPressed: loggingIn
                            ? () {}
                            : _handleLogin,
                      ),

                      const SizedBox(height: 25),

                      // =================================================
                      // SIGN UP
                      // =================================================

                      Row(
                        mainAxisAlignment:
                            MainAxisAlignment.center,
                        children: [
                          const Text(
                            "Don't have an account? ",
                            style: TextStyle(
                              fontSize: 17,
                              color:
                                  Color(0xFF29344D),
                            ),
                          ),
                          TextButton(
                            onPressed: loggingIn
                                ? null
                                : () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const signup_screen(),
                                      ),
                                    );
                                  },
                            style: TextButton.styleFrom(
                              padding:
                                  EdgeInsets.zero,
                              minimumSize:
                                  Size.zero,
                              tapTargetSize:
                                  MaterialTapTargetSize
                                      .shrinkWrap,
                            ),
                            child: const Text(
                              'Sign Up',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight:
                                    FontWeight.bold,
                                color:
                                    Color(0xFF16AFC1),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ================================================================
  // LABEL
  // ================================================================

  Widget _label(String text) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Color(0xFF102A5C),
        ),
      ),
    );
  }

  // ================================================================
  // INPUT FIELD
  // ================================================================

  Widget _inputField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
  }) {
    return Container(
      height: 70,
      decoration: _fieldDecoration(),
      child: TextField(
        controller: controller,
        keyboardType:
            TextInputType.emailAddress,
        enabled: !loggingIn,
        style: const TextStyle(
          fontSize: 17,
          color: Color(0xFF283653),
        ),
        decoration: InputDecoration(
          border: InputBorder.none,
          prefixIcon: Icon(
            icon,
            color: const Color(0xFF287E89),
            size: 29,
          ),
          hintText: hint,
          hintStyle: const TextStyle(
            fontSize: 17,
            color: Color(0xFF68718A),
          ),
          contentPadding:
              const EdgeInsets.symmetric(
            vertical: 22,
            horizontal: 10,
          ),
        ),
      ),
    );
  }

  // ================================================================
  // PASSWORD FIELD
  // ================================================================

  Widget _passwordField() {
    return Container(
      height: 70,
      decoration: _fieldDecoration(),
      child: TextField(
        controller: passwordController,
        obscureText: hidePassword,
        enabled: !loggingIn,
        onChanged: (_) => setState(() {}),
        style: const TextStyle(
          fontSize: 17,
          color: Color(0xFF283653),
        ),
        decoration: InputDecoration(
          border: InputBorder.none,
          prefixIcon: const Icon(
            Icons.lock_outline_rounded,
            color: Color(0xFF287E89),
            size: 29,
          ),
          suffixIcon: IconButton(
            onPressed: loggingIn
                ? null
                : () {
                    setState(() {
                      hidePassword =
                          !hidePassword;
                    });
                  },
            icon: Icon(
              hidePassword
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              color:
                  const Color(0xFF287E89),
            ),
          ),
          hintText: 'Enter your password',
          hintStyle: const TextStyle(
            fontSize: 17,
            color: Color(0xFF68718A),
          ),
          contentPadding:
              const EdgeInsets.symmetric(
            vertical: 22,
            horizontal: 10,
          ),
        ),
      ),
    );
  }

  // ================================================================
  // FIELD DECORATION
  // ================================================================

  BoxDecoration _fieldDecoration() {
    return BoxDecoration(
      color: Colors.white.withOpacity(0.78),
      borderRadius:
          BorderRadius.circular(35),
      border: Border.all(
        color: const Color(0xFFBDEBE3),
        width: 2,
      ),
      boxShadow: [
        BoxShadow(
          color:
              Colors.black.withOpacity(0.06),
          blurRadius: 12,
          offset: const Offset(0, 5),
        ),
      ],
    );
  }

  // ================================================================
  // GRADIENT BUTTON
  // ================================================================

  Widget _gradientButton({
    required String text,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 70,
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
            onTap: onPressed,
            child: Center(
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight:
                      FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ================================================================
// PASSWORD REQUIREMENTS
// ================================================================

Widget _passwordRequirements(
  String password,
) {
  final requirements = [
    (
      'At least 8 characters',
      password.length >= 8,
    ),
    (
      'One uppercase letter',
      RegExp(r'[A-Z]').hasMatch(password),
    ),
    (
      'One lowercase letter',
      RegExp(r'[a-z]').hasMatch(password),
    ),
    (
      'One number',
      RegExp(r'[0-9]').hasMatch(password),
    ),
    (
      'One special character',
      RegExp(
        r'[!@#$%^&*(),.?":{}|<>_\-+=/\\[\]]',
      ).hasMatch(password),
    ),
  ];

  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color:
          Colors.white.withOpacity(0.45),
      borderRadius:
          BorderRadius.circular(18),
    ),
    child: Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        const Text(
          'Password requirements',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: Color(0xFF102A5C),
          ),
        ),
        const SizedBox(height: 8),
        ...requirements.map(
          (item) {
            final valid = item.$2;

            return Padding(
              padding:
                  const EdgeInsets.symmetric(
                vertical: 2,
              ),
              child: Row(
                children: [
                  Icon(
                    valid
                        ? Icons
                            .check_circle_rounded
                        : Icons
                            .circle_outlined,
                    size: 18,
                    color: valid
                        ? const Color(
                            0xFF16A36A)
                        : const Color(
                            0xFF7A8494),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    item.$1,
                    style: TextStyle(
                      fontSize: 14,
                      color: valid
                          ? const Color(
                              0xFF16A36A)
                          : const Color(
                              0xFF657080),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    ),
  );
}

// ================================================================
// LOGIN BACKGROUND
// ================================================================

class LoginBackgroundPainter
    extends CustomPainter {
  const LoginBackgroundPainter();

  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    final paint = Paint()
      ..color =
          const Color(0xFFBCEDE2)
              .withOpacity(0.45);

    final wave = Path()
      ..moveTo(0, 0)
      ..lineTo(
        size.width * .55,
        0,
      )
      ..cubicTo(
        size.width * .40,
        size.height * .06,
        size.width * .20,
        size.height * .09,
        0,
        size.height * .22,
      )
      ..close();

    canvas.drawPath(
      wave,
      paint,
    );

    final rightPaint = Paint()
      ..color =
          const Color(0xFFB4E9DD)
              .withOpacity(0.30);

    final rightWave = Path()
      ..moveTo(size.width, 0)
      ..lineTo(
        size.width,
        size.height * .38,
      )
      ..cubicTo(
        size.width * .88,
        size.height * .28,
        size.width * .92,
        size.height * .15,
        size.width * .68,
        0,
      )
      ..close();

    canvas.drawPath(
      rightWave,
      rightPaint,
    );

    final dotPaint = Paint()
      ..color =
          const Color(0xFF66CFC0)
              .withOpacity(0.35);

    for (int row = 0; row < 5; row++) {
      for (int col = 0; col < 5; col++) {
        canvas.drawCircle(
          Offset(
            size.width * .83 +
                col * 10,
            size.height * .12 +
                row * 10,
          ),
          2,
          dotPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(
    covariant CustomPainter oldDelegate,
  ) =>
      false;
}