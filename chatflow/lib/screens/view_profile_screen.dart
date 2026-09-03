// ============================================================================
// FILE PATH: lib/screens/view_profile_screen.dart
// ============================================================================

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';

class ViewProfileScreen extends StatefulWidget {
  final String targetUserId;
  final String targetUserName;

  const ViewProfileScreen({
    super.key,
    required this.targetUserId,
    required this.targetUserName,
  });

  @override
  State<ViewProfileScreen> createState() =>
      _ViewProfileScreenState();
}

class _ViewProfileScreenState
    extends State<ViewProfileScreen> {
  static const Color navy = Color(0xFF102A5C);
  static const Color skyBlue = Color(0xFF55C7E8);
  static const Color cyan = Color(0xFF16AFC1);
  static const Color mint = Color(0xFF66D6C1);
  static const Color onlineGreen = Color(0xFF20C98B);

  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  bool _isDarkMode = false;

  // ==========================================================================
  // LOAD USER PROFILE
  // ==========================================================================

  Stream<DocumentSnapshot<Map<String, dynamic>>>
      _userStream() {
    return _firestore
        .collection('users')
        .doc(widget.targetUserId)
        .snapshots();
  }

  // ==========================================================================
  // LAST SEEN
  // ==========================================================================

  String _formatLastSeen(dynamic timestamp) {
    if (timestamp == null) {
      return 'Offline';
    }

    if (timestamp is Timestamp) {
      final date = timestamp.toDate();

      final hour =
          date.hour.toString().padLeft(2, '0');

      final minute =
          date.minute.toString().padLeft(2, '0');

      return 'Last seen today at $hour:$minute';
    }

    return 'Offline';
  }

  // ==========================================================================
  // BUILD
  // ==========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _isDarkMode
          ? const Color(0xFF06162F)
          : const Color(0xFFF4FFFC),

      appBar: AppBar(
        elevation: 0,
        backgroundColor: _isDarkMode
            ? const Color(0xFF0A2243)
            : Colors.white,
        surfaceTintColor: Colors.transparent,

        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_rounded,
            color: _isDarkMode
                ? Colors.white
                : navy,
          ),
          onPressed: () {
            Navigator.pop(context);
          },
        ),

        title: Text(
          'Profile',
          style: TextStyle(
            color: _isDarkMode
                ? Colors.white
                : navy,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),

      body: StreamBuilder<
          DocumentSnapshot<Map<String, dynamic>>>(
        stream: _userStream(),

        builder: (context, snapshot) {
          if (snapshot.connectionState ==
              ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(
                color: cyan,
              ),
            );
          }

          if (snapshot.hasError ||
              !snapshot.hasData ||
              !snapshot.data!.exists) {
            return _errorState();
          }

          final data =
              snapshot.data!.data() ?? {};

          return _buildProfile(data);
        },
      ),
    );
  }

  // ==========================================================================
  // PROFILE
  // ==========================================================================

  Widget _buildProfile(
    Map<String, dynamic> data,
  ) {
    final name =
        data['name']?.toString() ??
            widget.targetUserName;

    final photoBase64 = data['photoBase64']?.toString();

    final email =
        data['email']?.toString() ?? '';

    final status =
        data['status']?.toString() ?? 'Offline';

    final isOnline =
        status == 'Online';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        20,
        25,
        20,
        35,
      ),

      child: Column(
        children: [
          // ==================================================================
          // PROFILE PICTURE
          // ==================================================================

          Stack(
            alignment: Alignment.bottomRight,
            children: [
              Container(
                padding:
                    const EdgeInsets.all(4),

                decoration:
                    const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      mint,
                      cyan,
                      skyBlue,
                    ],
                  ),
                ),

                child: CircleAvatar(
                  radius: 65,

                  backgroundColor:
                      _isDarkMode
                          ? const Color(
                              0xFF10284A,
                            )
                          : Colors.white,

                  backgroundImage:
                      photoBase64 != null &&
                              photoBase64.isNotEmpty
                          ? MemoryImage(
                              base64Decode(photoBase64),
                            )
                          : null,

                  child: photoBase64 == null ||
                          photoBase64.isEmpty
                      ? Text(
                          name.isNotEmpty
                              ? name
                                  .substring(0, 1)
                                  .toUpperCase()
                              : '?',

                          style: TextStyle(
                            color: _isDarkMode
                                ? Colors.white
                                : navy,
                            fontSize: 48,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        )
                      : null,
                ),
              ),

              Container(
                width: 22,
                height: 22,

                decoration: BoxDecoration(
                  color: isOnline
                      ? onlineGreen
                      : const Color(
                          0xFF9AA4B2,
                        ),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _isDarkMode
                        ? const Color(
                            0xFF06162F,
                          )
                        : Colors.white,
                    width: 3,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // ==================================================================
          // NAME
          // ==================================================================

          Text(
            name,
            textAlign: TextAlign.center,

            style: TextStyle(
              color: _isDarkMode
                  ? Colors.white
                  : navy,
              fontSize: 25,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 7),

          // ==================================================================
          // ONLINE / OFFLINE
          // ==================================================================

          Text(
            isOnline
                ? 'Online'
                : _formatLastSeen(
                    data['lastSeen'],
                  ),

            style: TextStyle(
              color: isOnline
                  ? onlineGreen
                  : (_isDarkMode
                      ? const Color(
                          0xFFB8C9DB,
                        )
                      : const Color(
                          0xFF657080,
                        )),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),

          const SizedBox(height: 30),

          // ==================================================================
          // INFORMATION CARD
          // ==================================================================

          _infoCard(
            child: Column(
              children: [
                _infoTile(
                  icon: Icons.person_outline_rounded,
                  title: 'Name',
                  value: name,
                ),

                _divider(),

                _infoTile(
                  icon: Icons.email_outlined,
                  title: 'Email',
                  value: email.isEmpty
                      ? 'Not available'
                      : email,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // INFO CARD
  // ==========================================================================

  Widget _infoCard({
    required Widget child,
  }) {
    return Container(
      width: double.infinity,

      decoration: BoxDecoration(
        color: _isDarkMode
            ? const Color(0xFF10284A)
            : Colors.white,

        borderRadius:
            BorderRadius.circular(24),

        border: Border.all(
          color: _isDarkMode
              ? const Color(0xFF24486A)
              : const Color(0xFFBCEDE2),
          width: 1.2,
        ),

        boxShadow: [
          BoxShadow(
            color: mint.withOpacity(
              _isDarkMode ? 0.06 : 0.15,
            ),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),

      child: child,
    );
  }

  // ==========================================================================
  // INFO TILE
  // ==========================================================================

  Widget _infoTile({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.all(17),

      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,

            decoration: BoxDecoration(
              color: cyan.withOpacity(
                _isDarkMode ? 0.15 : 0.10,
              ),
              shape: BoxShape.circle,
            ),

            child: Icon(
              icon,
              color: cyan,
              size: 22,
            ),
          ),

          const SizedBox(width: 14),

          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,

              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: _isDarkMode
                        ? const Color(
                            0xFFB8C9DB,
                          )
                        : const Color(
                            0xFF657080,
                          ),
                    fontSize: 12,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  value,
                  style: TextStyle(
                    color: _isDarkMode
                        ? Colors.white
                        : navy,
                    fontSize: 15,
                    fontWeight:
                        FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // DIVIDER
  // ==========================================================================

  Widget _divider() {
    return Divider(
      height: 1,
      indent: 75,
      endIndent: 17,
      color: _isDarkMode
          ? const Color(0xFF24486A)
          : const Color(0xFFE2F1ED),
    );
  }

  // ==========================================================================
  // ERROR STATE
  // ==========================================================================

  Widget _errorState() {
    return Center(
      child: Padding(
        padding:
            const EdgeInsets.all(30),

        child: Column(
          mainAxisAlignment:
              MainAxisAlignment.center,

          children: [
            Container(
              width: 85,
              height: 85,

              decoration: const BoxDecoration(
                color: cyan,
                shape: BoxShape.circle,
              ),

              child: const Icon(
                Icons.person_off_outlined,
                color: Colors.white,
                size: 40,
              ),
            ),

            const SizedBox(height: 18),

            Text(
              'Unable to load profile',
              textAlign: TextAlign.center,

              style: TextStyle(
                color: _isDarkMode
                    ? Colors.white
                    : navy,
                fontSize: 19,
                fontWeight:
                    FontWeight.bold,
              ),
            ),

            const SizedBox(height: 8),

            Text(
              'Please try again later.',
              textAlign: TextAlign.center,

              style: TextStyle(
                color: _isDarkMode
                    ? const Color(
                        0xFFB8C9DB,
                      )
                    : const Color(
                        0xFF657080,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}