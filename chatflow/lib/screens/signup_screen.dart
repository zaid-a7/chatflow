import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'login_screen.dart';
import 'otp_screen.dart';

class signup_screen extends StatefulWidget {
  const signup_screen({super.key});

  @override
  State<signup_screen> createState() => _signup_screenState();
}

class _signup_screenState extends State<signup_screen> {
  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final phoneController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  bool hidePassword = true;
  bool hideConfirmPassword = true;
  bool agreeToTerms = false;
  bool creatingAccount = false;

  String selectedCountry = 'India';
  String selectedCode = '+91';

  final List<Map<String, String>> countries = [
    {
      'name': 'India',
      'flag': '🇮🇳',
      'code': '+91',
    },
    {
      'name': 'UAE',
      'flag': '🇦🇪',
      'code': '+971',
    },
    {
      'name': 'Saudi Arabia',
      'flag': '🇸🇦',
      'code': '+966',
    },
    {
      'name': 'United States',
      'flag': '🇺🇸',
      'code': '+1',
    },
  ];

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    phoneController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  // ================================================================
  // PASSWORD CHECKS
  // ================================================================

  bool get minLength =>
      passwordController.text.length >= 8;

  bool get uppercase =>
      RegExp(r'[A-Z]').hasMatch(passwordController.text);

  bool get lowercase =>
      RegExp(r'[a-z]').hasMatch(passwordController.text);

  bool get number =>
      RegExp(r'[0-9]').hasMatch(passwordController.text);

  bool get special =>
      RegExp(r'''[!@#$%^&*(),.?":{}|<>_\-+=/\\[\]]''')
          .hasMatch(passwordController.text);

  bool get passwordValid =>
      minLength &&
      uppercase &&
      lowercase &&
      number &&
      special;

  bool get passwordsMatch =>
      passwordController.text.isNotEmpty &&
      passwordController.text ==
          confirmPasswordController.text;

  // ================================================================
  // CREATE ACCOUNT
  // ================================================================

  Future<void> createAccount() async {
    FocusScope.of(context).unfocus();

    if (nameController.text.trim().isEmpty) {
      message('Please enter your full name.');
      return;
    }

    if (emailController.text.trim().isEmpty) {
      message('Please enter your email.');
      return;
    }

    if (!RegExp(
      r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
    ).hasMatch(emailController.text.trim())) {
      message('Please enter a valid email address.');
      return;
    }

    if (phoneController.text.trim().isEmpty) {
      message('Please enter your phone number.');
      return;
    }

    if (!passwordValid) {
      message('Please meet all password requirements.');
      return;
    }

    if (!passwordsMatch) {
      message('Passwords do not match.');
      return;
    }

    if (!agreeToTerms) {
      message('Please accept the Terms & Conditions.');
      return;
    }

    setState(() {
      creatingAccount = true;
    });

    User? user;

    try {
      // ------------------------------------------------------------
      // 1. CREATE EMAIL/PASSWORD ACCOUNT
      // ------------------------------------------------------------

      final credential =
          await FirebaseAuth.instance
              .createUserWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      user = credential.user;

      if (user == null) {
        throw FirebaseAuthException(
          code: 'account-creation-failed',
          message: 'Unable to create your account.',
        );
      }

      // ------------------------------------------------------------
      // 2. SAVE NAME TO FIREBASE AUTH
      // ------------------------------------------------------------

      await user.updateDisplayName(
        nameController.text.trim(),
      );

      // ------------------------------------------------------------
      // 3. SEND EMAIL VERIFICATION
      // ------------------------------------------------------------

      await user.sendEmailVerification();

      // ------------------------------------------------------------
      // 4. FORMAT PHONE NUMBER
      // ------------------------------------------------------------

      final phone =
          phoneController.text
              .trim()
              .replaceAll(RegExp(r'\D'), '');

      if (phone.isEmpty) {
        throw FirebaseAuthException(
          code: 'invalid-phone-number',
          message: 'Please enter a valid phone number.',
        );
      }

      final fullPhoneNumber =
          '$selectedCode$phone';

      // ------------------------------------------------------------
      // 5. START PHONE VERIFICATION
      // ------------------------------------------------------------

      if (kIsWeb) {
        await sendWebOTP(
          fullPhoneNumber,
          user,
        );
      } else {
        await sendAndroidOTP(
          fullPhoneNumber,
          user,
        );
      }
    } on FirebaseAuthException catch (e) {
      await deleteTemporaryUser(user);

      if (!mounted) return;

      setState(() {
        creatingAccount = false;
      });

      message(firebaseErrorMessage(e));
    } catch (e) {
      await deleteTemporaryUser(user);

      if (!mounted) return;

      setState(() {
        creatingAccount = false;
      });

      message(
        'Something went wrong. Please try again.',
      );
    }
  }

  // ================================================================
  // WEB PHONE AUTHENTICATION
  // ================================================================

  Future<void> sendWebOTP(
    String phoneNumber,
    User user,
  ) async {
    try {
      final confirmationResult =
          await user.linkWithPhoneNumber(
        phoneNumber,
      );

      if (!mounted) return;

      setState(() {
        creatingAccount = false;
      });

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => otp_screen(
            phoneNumber: phoneNumber,
            fullName: nameController.text.trim(),
            email: emailController.text.trim(),
            confirmationResult:
                confirmationResult,
          ),
        ),
      );
    } on FirebaseAuthException catch (e) {
      await deleteTemporaryUser(user);

      if (!mounted) return;

      setState(() {
        creatingAccount = false;
      });

      message(firebasePhoneErrorMessage(e));
    } catch (e) {
      await deleteTemporaryUser(user);

      if (!mounted) return;

      setState(() {
        creatingAccount = false;
      });

      message(
        'Unable to start phone verification. Please try again.',
      );
    }
  }

  // ================================================================
  // ANDROID PHONE AUTHENTICATION
  // ================================================================

  Future<void> sendAndroidOTP(
    String phoneNumber,
    User user,
  ) async {
    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phoneNumber,

        // ----------------------------------------------------------
        // AUTOMATIC ANDROID VERIFICATION
        // ----------------------------------------------------------

        verificationCompleted:
            (PhoneAuthCredential credential) async {
          try {
            await user.linkWithCredential(
              credential,
            );

            // ------------------------------------------------------
            // CREATE FIRESTORE USER DOCUMENT
            // ------------------------------------------------------

            await _createUserDocument(
              user,
              phoneNumber,
            );

            if (!mounted) return;

            setState(() {
              creatingAccount = false;
            });

            message(
              'Account created and phone verified successfully!',
            );

            await Future.delayed(
              const Duration(milliseconds: 900),
            );

            if (!mounted) return;

            await FirebaseAuth.instance.signOut();

            if (!mounted) return;

            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => const login_screen(),
              ),
            );
          } on FirebaseAuthException catch (e) {
            await deleteTemporaryUser(user);

            if (!mounted) return;

            setState(() {
              creatingAccount = false;
            });

            message(
              e.message ??
                  'Phone verification failed.',
            );
          }
        },

        // ----------------------------------------------------------
        // VERIFICATION FAILED
        // ----------------------------------------------------------

        verificationFailed:
            (FirebaseAuthException e) async {
          await deleteTemporaryUser(user);

          if (!mounted) return;

          setState(() {
            creatingAccount = false;
          });

          message(
            firebasePhoneErrorMessage(e),
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
            creatingAccount = false;
          });

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => otp_screen(
                phoneNumber: phoneNumber,
                fullName: nameController.text.trim(),
                email: emailController.text.trim(),
                verificationId: verificationId,
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
      await deleteTemporaryUser(user);

      if (!mounted) return;

      setState(() {
        creatingAccount = false;
      });

      message(
        firebasePhoneErrorMessage(e),
      );
    } catch (e) {
      await deleteTemporaryUser(user);

      if (!mounted) return;

      setState(() {
        creatingAccount = false;
      });

      message(
        'Unable to send OTP. Please try again.',
      );
    }
  }

  // ================================================================
  // CREATE FIRESTORE USER DOCUMENT
  // ================================================================

  Future<void> _createUserDocument(
    User user,
    String phoneNumber,
  ) async {
    await _firestore
        .collection('users')
        .doc(user.uid)
        .set({
      'uid': user.uid,
      'fullName': nameController.text.trim(),
      'email': emailController.text.trim(),
      'phone': phoneNumber,
      'status': 'Offline',
      'lastSeen': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // ================================================================
  // DELETE TEMPORARY ACCOUNT
  // ================================================================

  Future<void> deleteTemporaryUser(
    User? user,
  ) async {
    if (user == null) return;

    try {
      if (FirebaseAuth.instance.currentUser?.uid ==
          user.uid) {
        await user.delete();
      }
    } catch (_) {}
  }

  // ================================================================
  // FIREBASE EMAIL ERRORS
  // ================================================================

  String firebaseErrorMessage(
    FirebaseAuthException e,
  ) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'An account already exists with this email.';

      case 'invalid-email':
        return 'Please enter a valid email address.';

      case 'weak-password':
        return 'The password is too weak.';

      case 'network-request-failed':
        return 'Check your internet connection.';

      case 'operation-not-allowed':
        return 'Email/password sign-in is not enabled in Firebase.';

      case 'too-many-requests':
        return 'Too many attempts. Please wait and try again later.';

      default:
        return e.message ??
            'Something went wrong. Please try again.';
    }
  }

  // ================================================================
  // FIREBASE PHONE ERRORS
  // ================================================================

  String firebasePhoneErrorMessage(
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

      case 'missing-phone-number':
        return 'Please enter a phone number.';

      case 'provider-already-linked':
        return 'A phone number is already linked to this account.';

      case 'credential-already-in-use':
        return 'This phone number is already linked to another account.';

      case 'operation-not-allowed':
        return 'Phone authentication is not enabled in Firebase.';

      default:
        return e.message ??
            'Unable to send OTP. Please try again.';
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
                painter: SignupBackgroundPainter(),
              ),
            ),
          ),

          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: 25,
                vertical: 20,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(
                    maxWidth: 650,
                  ),
                  child: Column(
                    children: [
                      // BACK BUTTON
                      Align(
                        alignment:
                            Alignment.centerLeft,
                        child: IconButton(
                          onPressed: () =>
                              Navigator.pop(context),
                          icon: const Icon(
                            Icons.arrow_back_rounded,
                            size: 30,
                            color: Color(0xFF102A5C),
                          ),
                        ),
                      ),

                      // LOGO
                      LayoutBuilder(
                        builder:
                            (context, constraints) {
                          final size =
                              constraints.maxWidth <
                                      500
                                  ? constraints
                                          .maxWidth *
                                      0.55
                                  : 270.0;

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

                      // TITLE
                      RichText(
                        textAlign:
                            TextAlign.center,
                        text: const TextSpan(
                          children: [
                            TextSpan(
                              text: 'Create your ',
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight:
                                    FontWeight.bold,
                                color:
                                    Color(0xFF102A5C),
                              ),
                            ),
                            TextSpan(
                              text: 'ChatFlow',
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight:
                                    FontWeight.bold,
                                color:
                                    Color(0xFF16AFC1),
                              ),
                            ),
                            TextSpan(
                              text: ' account',
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight:
                                    FontWeight.bold,
                                color:
                                    Color(0xFF102A5C),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 8),

                      const Text(
                        'Connect. Chat. Share.',
                        style: TextStyle(
                          fontSize: 18,
                          color:
                              Color(0xFF657080),
                          letterSpacing: 0.5,
                        ),
                      ),

                      const SizedBox(height: 38),

                      // FULL NAME
                      label('Full Name'),
                      const SizedBox(height: 10),
                      input(
                        nameController,
                        'Enter your full name',
                        Icons.person_outline_rounded,
                        TextInputType.name,
                      ),

                      const SizedBox(height: 20),

                      // EMAIL
                      label('Email'),
                      const SizedBox(height: 10),
                      input(
                        emailController,
                        'Enter your email',
                        Icons.email_outlined,
                        TextInputType.emailAddress,
                      ),

                      const SizedBox(height: 20),

                      // PHONE
                      label('Phone Number'),
                      const SizedBox(height: 10),
                      phoneInput(),

                      const SizedBox(height: 20),

                      // PASSWORD
                      label('Password'),
                      const SizedBox(height: 10),
                      passwordField(
                        passwordController,
                        'Create a password',
                        hidePassword,
                        () => setState(
                          () => hidePassword =
                              !hidePassword,
                        ),
                      ),

                      const SizedBox(height: 12),

                      requirements(),

                      const SizedBox(height: 20),

                      // CONFIRM PASSWORD
                      label('Confirm Password'),
                      const SizedBox(height: 10),
                      passwordField(
                        confirmPasswordController,
                        'Re-enter your password',
                        hideConfirmPassword,
                        () => setState(
                          () => hideConfirmPassword =
                              !hideConfirmPassword,
                        ),
                      ),

                      if (confirmPasswordController
                          .text
                          .isNotEmpty)
                        Padding(
                          padding:
                              const EdgeInsets.only(
                            top: 10,
                            left: 8,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                passwordsMatch
                                    ? Icons
                                        .check_circle_rounded
                                    : Icons
                                        .cancel_rounded,
                                size: 18,
                                color: passwordsMatch
                                    ? const Color(
                                        0xFF16A36A)
                                    : const Color(
                                        0xFFD9534F),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                passwordsMatch
                                    ? 'Passwords match'
                                    : 'Passwords do not match',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: passwordsMatch
                                      ? const Color(
                                          0xFF16A36A)
                                      : const Color(
                                          0xFFD9534F),
                                ),
                              ),
                            ],
                          ),
                        ),

                      const SizedBox(height: 12),

                      // TERMS
                      Row(
                        children: [
                          Checkbox(
                            value: agreeToTerms,
                            activeColor:
                                const Color(
                                    0xFF16AFC1),
                            onChanged: (value) {
                              setState(() {
                                agreeToTerms =
                                    value ?? false;
                              });
                            },
                          ),
                          Expanded(
                            child: Wrap(
                              children: [
                                const Text(
                                  'I agree to the ',
                                  style: TextStyle(
                                    fontSize: 15,
                                    color:
                                        Color(0xFF29344D),
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () {},
                                  child: const Text(
                                    'Terms & Conditions',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight:
                                          FontWeight.bold,
                                      color:
                                          Color(0xFF16AFC1),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 10),

                      // CREATE ACCOUNT
                      button(
                        creatingAccount
                            ? 'Creating Account...'
                            : 'Create Account',
                        creatingAccount
                            ? () {}
                            : createAccount,
                      ),

                      const SizedBox(height: 25),

                      // LOGIN
                      Row(
                        mainAxisAlignment:
                            MainAxisAlignment.center,
                        children: [
                          const Text(
                            'Already have an account? ',
                            style: TextStyle(
                              fontSize: 17,
                              color:
                                  Color(0xFF29344D),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator
                                  .pushReplacement(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const login_screen(),
                                ),
                              );
                            },
                            child: const Text(
                              'Login',
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

                      const SizedBox(height: 15),
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
  // PHONE INPUT
  // ================================================================

  Widget phoneInput() {
    final country = countries.firstWhere(
      (item) => item['name'] == selectedCountry,
    );

    return Container(
      height: 70,
      decoration: decoration(),
      child: Row(
        children: [
          PopupMenuButton<String>(
            onSelected: (value) {
              final selected =
                  countries.firstWhere(
                (item) =>
                    item['name'] == value,
              );

              setState(() {
                selectedCountry =
                    selected['name']!;
                selectedCode =
                    selected['code']!;
              });
            },
            itemBuilder: (context) {
              return countries.map((country) {
                return PopupMenuItem<String>(
                  value: country['name'],
                  child: Text(
                    '${country['flag']}  '
                    '${country['name']}  '
                    '${country['code']}',
                  ),
                );
              }).toList();
            },
            child: Padding(
              padding:
                  const EdgeInsets.only(left: 12),
              child: Row(
                children: [
                  Text(
                    country['flag']!,
                    style: const TextStyle(
                      fontSize: 22,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    selectedCode,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight:
                          FontWeight.bold,
                      color:
                          Color(0xFF102A5C),
                    ),
                  ),
                  const Icon(
                    Icons
                        .keyboard_arrow_down_rounded,
                    color:
                        Color(0xFF287E89),
                  ),
                ],
              ),
            ),
          ),

          Container(
            width: 1,
            height: 35,
            color:
                const Color(0xFFBDEBE3),
          ),

          Expanded(
            child: TextField(
              controller: phoneController,
              keyboardType:
                  TextInputType.phone,
              style: const TextStyle(
                fontSize: 17,
                color:
                    Color(0xFF283653),
              ),
              decoration:
                  const InputDecoration(
                border: InputBorder.none,
                hintText:
                    'Enter phone number',
                hintStyle: TextStyle(
                  fontSize: 17,
                  color:
                      Color(0xFF68718A),
                ),
                contentPadding:
                    EdgeInsets.symmetric(
                  vertical: 22,
                  horizontal: 12,
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

  Widget label(String text) {
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
  // INPUT
  // ================================================================

  Widget input(
    TextEditingController controller,
    String hint,
    IconData icon,
    TextInputType type,
  ) {
    return Container(
      height: 70,
      decoration: decoration(),
      child: TextField(
        controller: controller,
        keyboardType: type,
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

  Widget passwordField(
    TextEditingController controller,
    String hint,
    bool hidden,
    VoidCallback toggle,
  ) {
    return Container(
      height: 70,
      decoration: decoration(),
      child: TextField(
        controller: controller,
        obscureText: hidden,
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
            onPressed: toggle,
            icon: Icon(
              hidden
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              color:
                  const Color(0xFF287E89),
            ),
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
  // PASSWORD REQUIREMENTS
  // ================================================================

  Widget requirements() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.48),
        borderRadius:
            BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFD6F1EB),
        ),
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
          requirement(
            'At least 8 characters',
            minLength,
          ),
          requirement(
            'One uppercase letter',
            uppercase,
          ),
          requirement(
            'One lowercase letter',
            lowercase,
          ),
          requirement(
            'One number',
            number,
          ),
          requirement(
            'One special character',
            special,
          ),
        ],
      ),
    );
  }

  Widget requirement(
    String text,
    bool valid,
  ) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(
        vertical: 2,
      ),
      child: Row(
        children: [
          Icon(
            valid
                ? Icons.check_circle_rounded
                : Icons.circle_outlined,
            size: 18,
            color: valid
                ? const Color(0xFF16A36A)
                : const Color(0xFF7A8494),
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              fontSize: 14,
              color: valid
                  ? const Color(0xFF16A36A)
                  : const Color(0xFF657080),
            ),
          ),
        ],
      ),
    );
  }

  // ================================================================
  // FIELD DECORATION
  // ================================================================

  BoxDecoration decoration() {
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
  // BUTTON
  // ================================================================

  Widget button(
    String text,
    VoidCallback onPressed,
  ) {
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
                  fontSize: 20,
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

// ==================================================================
// BACKGROUND
// ==================================================================

class SignupBackgroundPainter
    extends CustomPainter {
  const SignupBackgroundPainter();

  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    final paint = Paint()
      ..color = const Color(0xFFBCEDE2)
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
      ..color = const Color(0xFFB4E9DD)
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

    final dots = Paint()
      ..color = const Color(0xFF66CFC0)
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
          dots,
        );
      }
    }
  }

  @override
  bool shouldRepaint(
    covariant CustomPainter oldDelegate,
  ) {
    return false;
  }
}