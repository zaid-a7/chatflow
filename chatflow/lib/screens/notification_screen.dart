// ============================================================================
// FILE PATH: lib/screens/notification_screen.dart
// ============================================================================

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class NotificationScreen extends StatefulWidget {
  final bool isDarkMode;

  const NotificationScreen({
    super.key,
    required this.isDarkMode,
  });

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // ==========================================================================
  // COLORS
  // ==========================================================================

  static const Color navy = Color(0xFF102A5C);
  static const Color cyan = Color(0xFF16AFC1);
  static const Color mint = Color(0xFF66D6C1);
  static const Color lightMint = Color(0xFFDDF8F1);

  bool _processingRequest = false;

  // ==========================================================================
  // CURRENT USER
  // ==========================================================================

  User? get currentUser => _auth.currentUser;

  // ==========================================================================
// ACCEPT REQUEST
// ==========================================================================

Future<void> _acceptRequest(
  String requestId,
  Map<String, dynamic> data,
) async {
  if (_processingRequest) return;

  final user = _auth.currentUser;

  if (user == null) {
    _showMessage(
      'Your login session has expired. Please login again.',
    );
    return;
  }

  final currentUserId = user.uid;

  final senderId =
      data['senderId']?.toString() ?? '';

  if (senderId.isEmpty) {
    _showMessage('Invalid chat request.');
    return;
  }

  setState(() {
    _processingRequest = true;
  });

  try {
    // ==============================================================
    // CREATE CONSISTENT CHAT ROOM ID
    // ==============================================================

    final ids = [
      currentUserId,
      senderId,
    ];

    ids.sort();

    final chatRoomId = ids.join('_');

    // ==============================================================
    // GET SENDER INFORMATION
    // ==============================================================

    final senderUserDoc = await _firestore
        .collection('users')
        .doc(senderId)
        .get();

    final senderUserData =
        senderUserDoc.data() ??
            <String, dynamic>{};

    final senderName =
        senderUserData['fullName']
                ?.toString()
                .trim()
                .isNotEmpty ==
            true
        ? senderUserData['fullName']
            .toString()
            .trim()
        : data['senderName']
                    ?.toString()
                    .trim()
                    .isNotEmpty ==
                true
            ? data['senderName']
                .toString()
                .trim()
            : 'ChatFlow User';

    final senderEmail =
        senderUserData['email']
                ?.toString() ??
            data['senderEmail']
                ?.toString() ??
            '';

    // ==============================================================
    // RESTORE ONE-TO-ONE CHAT ROOM
    //
    // IMPORTANT:
    // If this chat was previously deleted, its old chat room may
    // contain:
    //
    // removedBy: [userA, userB]
    //
    // A new accepted request means the relationship is restored.
    // Therefore removedBy MUST be cleared.
    // ==============================================================

    await _firestore
    .collection('chat_rooms')
    .doc(chatRoomId)
    .set(
  {
    // Restore both users as active participants.
    'participants': [
      currentUserId,
      senderId,
    ],

    // IMPORTANT:
    // Remove the old deleted-chat state.
    'removedBy': FieldValue.arrayRemove([
      currentUserId,
      senderId,
    ]),

    'createdAt':
        FieldValue.serverTimestamp(),

    'lastMessage': '',
    'lastMessageTime': null,
  },
  SetOptions(merge: true),
);

    // ==============================================================
    // UPDATE REQUEST
    // ==============================================================

    await _firestore
        .collection('chat_requests')
        .doc(requestId)
        .update({
      'status': 'accepted',
      'seen': true,
      'acceptedAt':
          FieldValue.serverTimestamp(),
    });

    if (!mounted) return;

    _showMessage(
      'Chat request accepted. You can now chat with $senderName.',
    );
  } on FirebaseException catch (e) {
    if (!mounted) return;

    _showMessage(
      e.message ??
          'Unable to accept the request.',
    );
  } catch (e) {
    if (!mounted) return;

    _showMessage(
      'Unable to accept the request. Please try again.',
    );
  } finally {
    if (mounted) {
      setState(() {
        _processingRequest = false;
      });
    }
  }
}

  // ==========================================================================
  // REJECT REQUEST
  // ==========================================================================

  Future<void> _rejectRequest(String requestId) async {
    if (_processingRequest) return;

    final user = _auth.currentUser;

    if (user == null) {
      _showMessage(
        'Your login session has expired. Please login again.',
      );
      return;
    }

    setState(() {
      _processingRequest = true;
    });

    try {
      await _firestore
          .collection('chat_requests')
          .doc(requestId)
          .update({
        'status': 'rejected',
        'seen': true,
        'rejectedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      _showMessage('Chat request rejected.');
    } on FirebaseException catch (e) {
      if (!mounted) return;

      _showMessage(
        e.message ?? 'Unable to reject the request.',
      );
    } catch (e) {
      if (!mounted) return;

      _showMessage(
        'Unable to reject the request. Please try again.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _processingRequest = false;
        });
      }
    }
  }

  // ==========================================================================
  // SNACKBAR
  // ==========================================================================

  void _showMessage(String text) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        backgroundColor: navy,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
      ),
    );
  }

  // ==========================================================================
  // BUILD
  // ==========================================================================

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;

    // ------------------------------------------------------------------------
    // IMPORTANT:
    // If the screen is opened while FirebaseAuth is still restoring the
    // session, give it a moment instead of immediately saying "Please login".
    // ------------------------------------------------------------------------

    if (user == null) {
      return StreamBuilder<User?>(
        stream: _auth.authStateChanges(),
        builder: (context, authSnapshot) {
          if (authSnapshot.connectionState ==
              ConnectionState.waiting) {
            return _buildLoadingScreen();
          }

          final restoredUser = authSnapshot.data;

          if (restoredUser == null) {
            return _buildLoginRequiredScreen();
          }

          return _buildNotificationScreen(
            restoredUser.uid,
          );
        },
      );
    }

    return _buildNotificationScreen(user.uid);
  }

  // ==========================================================================
  // LOADING SCREEN
  // ==========================================================================

  Widget _buildLoadingScreen() {
  return Scaffold(
    backgroundColor: widget.isDarkMode
        ? const Color(0xFF06162F)
        : const Color(0xFFF4FFFC),
    body: const Center(
      child: CircularProgressIndicator(
        color: cyan,
      ),
    ),
  );
}

  // ==========================================================================
  // LOGIN REQUIRED SCREEN
  // ==========================================================================

  Widget _buildLoginRequiredScreen() {
  return Scaffold(
    backgroundColor: widget.isDarkMode
        ? const Color(0xFF06162F)
        : const Color(0xFFF4FFFC),

    appBar: AppBar(
      elevation: 0,
      backgroundColor: widget.isDarkMode
          ? const Color(0xFF0A2243)
          : Colors.white,
      surfaceTintColor: Colors.transparent,

      leading: IconButton(
        icon: Icon(
          Icons.arrow_back_rounded,
          color: widget.isDarkMode
              ? Colors.white
              : navy,
        ),
        onPressed: () {
          Navigator.pop(context);
        },
      ),

      title: Text(
        'Notifications',
        style: TextStyle(
          color: widget.isDarkMode
              ? Colors.white
              : navy,
          fontSize: 21,
          fontWeight: FontWeight.bold,
        ),
      ),
    ),

    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Text(
          'Your login session has expired.\nPlease login again.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: widget.isDarkMode
                ? Colors.white
                : navy,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ),
  );
}

  // ==========================================================================
  // NOTIFICATION SCREEN
  // ==========================================================================

  Widget _buildNotificationScreen(String currentUserId) {
  return Scaffold(
    backgroundColor: widget.isDarkMode
        ? const Color(0xFF06162F)
        : const Color(0xFFF4FFFC),

    appBar: AppBar(
      elevation: 0,
      backgroundColor: widget.isDarkMode
          ? const Color(0xFF0A2243)
          : Colors.white,
      surfaceTintColor: Colors.transparent,

      leading: IconButton(
        icon: Icon(
          Icons.arrow_back_rounded,
          color: widget.isDarkMode
              ? Colors.white
              : navy,
        ),
        onPressed: () {
          Navigator.pop(context);
        },
      ),

      title: Text(
        'Notifications',
        style: TextStyle(
          color: widget.isDarkMode
              ? Colors.white
              : navy,
          fontSize: 21,
          fontWeight: FontWeight.bold,
        ),
      ),
    ),

    body: StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('chat_requests')
          .where(
            'receiverId',
            isEqualTo: currentUserId,
          )
          .where(
            'status',
            isEqualTo: 'pending',
          )
          .snapshots(),

      builder: (context, snapshot) {
        if (snapshot.connectionState ==
            ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(
              color: cyan,
            ),
          );
        }

        if (snapshot.hasError) {
          return _errorState(
            snapshot.error.toString(),
          );
        }

        final documents =
            snapshot.data?.docs ?? [];

        if (documents.isEmpty) {
          return _emptyState();
        }

        return ListView.separated(
          padding: const EdgeInsets.all(18),
          itemCount: documents.length,

          separatorBuilder: (_, __) {
            return const SizedBox(height: 12);
          },

          itemBuilder: (context, index) {
            final doc = documents[index];

            final data =
                doc.data()
                    as Map<String, dynamic>;

            return _requestCard(
              requestId: doc.id,
              data: data,
            );
          },
        );
      },
    ),
  );
}

  // ==========================================================================
  // REQUEST CARD
  // ==========================================================================

  Widget _requestCard({
  required String requestId,
  required Map<String, dynamic> data,
}) {
  final senderName =
      data['senderName']?.toString() ??
      'ChatFlow User';

  final senderEmail =
      data['senderEmail']?.toString() ??
      '';

  final firstLetter = senderName.isNotEmpty
      ? senderName.substring(0, 1).toUpperCase()
      : '?';

  final cardColor = widget.isDarkMode
      ? const Color(0xFF10284A)
      : Colors.white;

  final primaryTextColor = widget.isDarkMode
      ? Colors.white
      : navy;

  final secondaryTextColor = widget.isDarkMode
      ? const Color(0xFFB8C9DB)
      : const Color(0xFF657080);

  final borderColor = widget.isDarkMode
      ? const Color(0xFF24486A)
      : const Color(0xFFBCEDE2);

  return Container(
    padding: const EdgeInsets.all(16),

    decoration: BoxDecoration(
      color: cardColor,
      borderRadius: BorderRadius.circular(24),

      border: Border.all(
        color: borderColor,
        width: 1.2,
      ),

      boxShadow: [
        BoxShadow(
          color: mint.withOpacity(
            widget.isDarkMode ? 0.07 : 0.15,
          ),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ],
    ),

    child: Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [

        Row(
          children: [
            Container(
              width: 52,
              height: 52,

              decoration:
                  const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    mint,
                    cyan,
                  ],
                ),
              ),

              child: Center(
                child: Text(
                  firstLetter,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            const SizedBox(width: 13),

            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    senderName,
                    maxLines: 1,
                    overflow:
                        TextOverflow.ellipsis,
                    style: TextStyle(
                      color: primaryTextColor,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 3),

                  if (senderEmail.isNotEmpty)
                    Text(
                      senderEmail,
                      maxLines: 1,
                      overflow:
                          TextOverflow.ellipsis,
                      style: TextStyle(
                        color: secondaryTextColor,
                        fontSize: 13,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 14),

        Text(
          'wants to start a chat with you.',
          style: TextStyle(
            color: secondaryTextColor,
            fontSize: 14,
          ),
        ),

        const SizedBox(height: 16),

        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _processingRequest
                    ? null
                    : () {
                        _rejectRequest(
                          requestId,
                        );
                      },

                style:
                    OutlinedButton.styleFrom(
                  foregroundColor:
                      Colors.redAccent,
                  side: BorderSide(
                    color: Colors.redAccent
                        .withOpacity(0.35),
                  ),
                  shape:
                      RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(15),
                  ),
                  padding:
                      const EdgeInsets.symmetric(
                    vertical: 13,
                  ),
                ),

                child: const Text(
                  'Reject',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            const SizedBox(width: 10),

            Expanded(
              child: ElevatedButton(
                onPressed: _processingRequest
                    ? null
                    : () {
                        _acceptRequest(
                          requestId,
                          data,
                        );
                      },

                style:
                    ElevatedButton.styleFrom(
                  backgroundColor: cyan,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor:
                      cyan.withOpacity(0.5),
                  elevation: 0,
                  shape:
                      RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(15),
                  ),
                  padding:
                      const EdgeInsets.symmetric(
                    vertical: 13,
                  ),
                ),

                child: _processingRequest
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child:
                            CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Accept',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

  // ==========================================================================
  // ERROR STATE
  // ==========================================================================

  Widget _errorState(String error) {
  final primaryTextColor = widget.isDarkMode
      ? Colors.white
      : navy;

  final secondaryTextColor = widget.isDarkMode
      ? const Color(0xFFB8C9DB)
      : const Color(0xFF657080);

  return Center(
    child: Padding(
      padding: const EdgeInsets.all(30),
      child: Column(
        mainAxisAlignment:
            MainAxisAlignment.center,
        children: [
          Container(
            width: 85,
            height: 85,
            decoration: BoxDecoration(
              color: widget.isDarkMode
                  ? const Color(0xFF3A2025)
                  : const Color(0xFFFFE9E9),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.error_outline_rounded,
              color: Colors.redAccent,
              size: 42,
            ),
          ),

          const SizedBox(height: 18),

          Text(
            'Unable to load notifications',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: primaryTextColor,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            'Please check your connection and try again.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: secondaryTextColor,
              fontSize: 14,
            ),
          ),
        ],
      ),
    ),
  );
}

  // ==========================================================================
  // EMPTY STATE
  // ==========================================================================

  Widget _emptyState() {
  final primaryTextColor = widget.isDarkMode
      ? Colors.white
      : navy;

  final secondaryTextColor = widget.isDarkMode
      ? const Color(0xFFB8C9DB)
      : const Color(0xFF657080);

  return Center(
    child: Padding(
      padding: const EdgeInsets.all(35),

      child: Column(
        mainAxisAlignment:
            MainAxisAlignment.center,

        children: [
          Container(
            width: 90,
            height: 90,

            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  mint,
                  cyan,
                ],
              ),
              shape: BoxShape.circle,
            ),

            child: const Icon(
              Icons.notifications_none_rounded,
              color: Colors.white,
              size: 42,
            ),
          ),

          const SizedBox(height: 20),

          Text(
            'No notifications',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: primaryTextColor,
              fontSize: 19,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            'You are all caught up!',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: secondaryTextColor,
              fontSize: 14,
            ),
          ),
        ],
      ),
    ),
  );
}
}