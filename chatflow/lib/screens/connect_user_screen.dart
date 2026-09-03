// ============================================================================
// FILE PATH: lib/screens/connect_user_screen.dart
// ============================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ConnectUserScreen extends StatefulWidget {
  final String targetUserId;
  final String targetUserName;
  final String targetUserEmail;

  const ConnectUserScreen({
    super.key,
    required this.targetUserId,
    required this.targetUserName,
    required this.targetUserEmail,
  });

  @override
  State<ConnectUserScreen> createState() => _ConnectUserScreenState();
}

class _ConnectUserScreenState extends State<ConnectUserScreen> {
  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  final FirebaseAuth _auth =
      FirebaseAuth.instance;

  bool _loading = true;
  bool _requestSent = false;

  static const Color navy =
      Color(0xFF102A5C);

  static const Color cyan =
      Color(0xFF16AFC1);

  static const Color mint =
      Color(0xFF66D6C1);

  static const Color lightMint =
      Color(0xFFDDF8F1);

  // ==========================================================================
  // INIT
  // ==========================================================================

  @override
  void initState() {
    super.initState();
    _checkRequest();
  }

  // ==========================================================================
  // CHECK ONLY FOR A PENDING REQUEST
  //
  // IMPORTANT:
  // An old "accepted" or "rejected" request must NOT prevent the user
  // from sending another request.
  // ==========================================================================

  Future<void> _checkRequest() async {
    final currentUserId =
        _auth.currentUser?.uid;

    if (currentUserId == null) {
      if (!mounted) return;

      setState(() {
        _loading = false;
      });

      return;
    }

    try {
      // ----------------------------------------------------------------------
      // THE REQUEST ID IS THE OLD CONSISTENT ID.
      //
      // We only use this document to check whether THERE IS CURRENTLY
      // A pending request.
      // ----------------------------------------------------------------------

      final requestId =
          '${currentUserId}_${widget.targetUserId}';

      final request =
          await _firestore
              .collection('chat_requests')
              .doc(requestId)
              .get();

      if (!mounted) return;

      final data =
          request.data();

      final status =
          data?['status']
              ?.toString()
              .toLowerCase();

      setState(() {
        // ONLY pending means "Request already sent".
        //
        // accepted  -> user can send again
        // rejected  -> user can send again
        // missing   -> user can send
        _requestSent =
            request.exists &&
            status == 'pending';

        _loading = false;
      });
    } catch (e) {
      debugPrint(
        'Check request error: $e',
      );

      if (!mounted) return;

      setState(() {
        _loading = false;
      });
    }
  }

  // ==========================================================================
// SEND NEW REQUEST
//
// IMPORTANT:
// We intentionally DO NOT read the old request document.
//
// Why?
// The old request may be an accepted/rejected request, or it may not exist.
// Reading a missing/old request can trigger Firestore permission errors.
//
// Every new connection attempt gets a NEW chat_requests document ID.
// This allows a user to reconnect after a previous chat was deleted/blocked.
// ==========================================================================

Future<void> _sendRequest() async {
  final currentUser = _auth.currentUser;

  if (currentUser == null) {
    _showMessage(
      'Your login session has expired. Please login again.',
    );
    return;
  }

  if (currentUser.uid == widget.targetUserId) {
    _showMessage(
      'You cannot send a request to yourself.',
    );
    return;
  }

  if (_loading) return;

  setState(() {
    _loading = true;
  });

  try {
    // ======================================================================
    // GET CURRENT USER INFORMATION
    // ======================================================================

    final currentUserDoc = await _firestore
        .collection('users')
        .doc(currentUser.uid)
        .get();

    final currentUserData =
        currentUserDoc.data() ?? <String, dynamic>{};

    final senderName =
        currentUserData['fullName']
                    ?.toString()
                    .trim()
                    .isNotEmpty ==
                true
            ? currentUserData['fullName']
                .toString()
                .trim()
            : currentUser.displayName
                        ?.trim()
                        .isNotEmpty ==
                    true
                ? currentUser.displayName!.trim()
                : 'ChatFlow User';

    final senderEmail =
        currentUserData['email']
                ?.toString()
                .trim()
                .isNotEmpty ==
            true
        ? currentUserData['email']
            .toString()
            .trim()
        : currentUser.email ?? '';

    // ======================================================================
    // CREATE A COMPLETELY NEW REQUEST
    //
    // DO NOT reuse the previous request ID.
    //
    // This means:
    //
    // Old request:
    //   User A -> User B
    //   status = accepted
    //
    // Chat deleted / contact removed
    //
    // New request:
    //   User A -> User B
    //   NEW document
    //   status = pending
    //
    // ======================================================================

    final newRequestRef = _firestore
        .collection('chat_requests')
        .doc();

    await newRequestRef.set({
      'senderId': currentUser.uid,
      'senderName': senderName,
      'senderEmail': senderEmail,
      'receiverId': widget.targetUserId,
      'receiverName': widget.targetUserName,
      'status': 'pending',
      'seen': false,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // ======================================================================
    // UPDATE UI
    // ======================================================================

    if (!mounted) return;

    setState(() {
      _requestSent = true;
      _loading = false;
    });

    _showMessage(
      'Chat request sent to ${widget.targetUserName}.',
    );
  } on FirebaseException catch (e) {
    debugPrint(
      'Send request Firebase error: ${e.code} ${e.message}',
    );

    if (!mounted) return;

    setState(() {
      _loading = false;
    });

    _showMessage(
      e.message ??
          'Unable to send the request. Please try again.',
    );
  } catch (e) {
    debugPrint(
      'Send request error: $e',
    );

    if (!mounted) return;

    setState(() {
      _loading = false;
    });

    _showMessage(
      'Unable to send the request. Please try again.',
    );
  }
}

  // ==========================================================================
  // SNACKBAR
  // ==========================================================================

  void _showMessage(
    String message,
  ) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .hideCurrentSnackBar();

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(message),
        behavior:
            SnackBarBehavior.floating,
        backgroundColor: navy,
        shape:
            RoundedRectangleBorder(
          borderRadius:
              BorderRadius.circular(15),
        ),
      ),
    );
  }

  // ==========================================================================
  // BUILD
  // ==========================================================================

  @override
  Widget build(BuildContext context) {
    final initial =
        widget.targetUserName.isNotEmpty
            ? widget.targetUserName[0]
                .toUpperCase()
            : '?';

    return Scaffold(
      backgroundColor:
          const Color(0xFFF4FFFC),

      // ========================================================================
      // APP BAR
      // ========================================================================

      appBar: AppBar(
        backgroundColor:
            Colors.white,

        elevation: 0,

        surfaceTintColor:
            Colors.transparent,

        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: navy,
          ),
          onPressed: () =>
              Navigator.pop(context),
        ),

        title: const Text(
          'Connect',
          style: TextStyle(
            color: navy,
            fontWeight:
                FontWeight.bold,
          ),
        ),
      ),

      // ========================================================================
      // BODY
      // ========================================================================

      body: Center(
        child: SingleChildScrollView(
          padding:
              const EdgeInsets.all(25),

          child: ConstrainedBox(
            constraints:
                const BoxConstraints(
              maxWidth: 500,
            ),

            child: Column(
              children: [
                // ==================================================================
                // PROFILE
                // ==================================================================

                Container(
                  padding:
                      const EdgeInsets.all(4),

                  decoration:
                      const BoxDecoration(
                    shape:
                        BoxShape.circle,
                    gradient:
                        LinearGradient(
                      colors: [
                        mint,
                        cyan,
                        Color(0xFF55C7E8),
                      ],
                    ),
                  ),

                  child: CircleAvatar(
                    radius: 55,

                    backgroundColor:
                        Colors.white,

                    child: Text(
                      initial,

                      style:
                          const TextStyle(
                        color: navy,
                        fontSize: 42,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                const SizedBox(
                  height: 25,
                ),

                // ==================================================================
                // NAME
                // ==================================================================

                Text(
                  widget.targetUserName,

                  textAlign:
                      TextAlign.center,

                  style:
                      const TextStyle(
                    color: navy,
                    fontSize: 25,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),

                const SizedBox(
                  height: 8,
                ),

                // ==================================================================
                // EMAIL
                // ==================================================================

                Text(
                  widget.targetUserEmail,

                  textAlign:
                      TextAlign.center,

                  style:
                      const TextStyle(
                    color:
                        Color(0xFF657080),
                    fontSize: 16,
                  ),
                ),

                const SizedBox(
                  height: 35,
                ),

                // ==================================================================
                // INFORMATION CARD
                // ==================================================================

                Container(
                  width:
                      double.infinity,

                  padding:
                      const EdgeInsets.all(
                    20,
                  ),

                  decoration:
                      BoxDecoration(
                    color:
                        Colors.white,

                    borderRadius:
                        BorderRadius.circular(
                      22,
                    ),

                    border:
                        Border.all(
                      color: lightMint,
                      width: 1.5,
                    ),

                    boxShadow: [
                      BoxShadow(
                        color: mint
                            .withOpacity(
                          0.15,
                        ),
                        blurRadius: 18,
                        offset:
                            const Offset(
                          0,
                          7,
                        ),
                      ),
                    ],
                  ),

                  child:
                      const Column(
                    children: [
                      Icon(
                        Icons
                            .people_alt_outlined,
                        color: cyan,
                        size: 35,
                      ),

                      SizedBox(
                        height: 12,
                      ),

                      Text(
                        'Connect on ChatFlow',

                        style:
                            TextStyle(
                          color: navy,
                          fontSize: 18,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),

                      SizedBox(
                        height: 7,
                      ),

                      Text(
                        'Send a chat request to connect with this user.',

                        textAlign:
                            TextAlign.center,

                        style:
                            TextStyle(
                          color: Color(
                            0xFF657080,
                          ),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(
                  height: 30,
                ),

                // ==================================================================
                // SEND REQUEST BUTTON
                // ==================================================================

                SizedBox(
                  width:
                      double.infinity,

                  height: 58,

                  child:
                      ElevatedButton(
                    onPressed:
                        _loading ||
                                _requestSent
                            ? null
                            : _sendRequest,

                    style:
                        ElevatedButton
                            .styleFrom(
                      backgroundColor:
                          _requestSent
                              ? Colors.grey
                              : cyan,

                      disabledBackgroundColor:
                          _requestSent
                              ? const Color(
                                  0xFFB8C1C9,
                                )
                              : cyan.withOpacity(
                                  0.7,
                                ),

                      foregroundColor:
                          Colors.white,

                      elevation: 0,

                      shape:
                          RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(
                          30,
                        ),
                      ),
                    ),

                    child: _loading
                        ? const SizedBox(
                            width: 24,
                            height: 24,

                            child:
                                CircularProgressIndicator(
                              strokeWidth:
                                  2.5,
                              color:
                                  Colors.white,
                            ),
                          )
                        : Row(
                            mainAxisAlignment:
                                MainAxisAlignment
                                    .center,

                            children: [
                              Icon(
                                _requestSent
                                    ? Icons
                                        .check_circle_outline
                                    : Icons
                                        .person_add_alt_1_rounded,
                              ),

                              const SizedBox(
                                width: 10,
                              ),

                              Text(
                                _requestSent
                                    ? 'Request Sent'
                                    : 'Send Request',

                                style:
                                    const TextStyle(
                                  fontSize: 17,
                                  fontWeight:
                                      FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}