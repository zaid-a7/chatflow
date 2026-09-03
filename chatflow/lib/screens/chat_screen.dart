//  lib/screens/chat_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/incoming_call_listener.dart';

import 'chat_background_painter.dart';
import 'connect_user_screen.dart';
import 'status_tab.dart';
import 'calls_tab.dart';
import 'profile_tab.dart';
import 'notification_screen.dart';
import 'chat_room_screen.dart';
import 'login_screen.dart';

class chat_screen extends StatefulWidget {
  const chat_screen({super.key});

  @override
  State<chat_screen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<chat_screen>
    with WidgetsBindingObserver {
  // ==========================================================================
  // STATE
  // ==========================================================================

  int _currentIndex = 0;
  bool _isSearching = false;
  bool _isDarkMode = false;
  String _searchQuery = '';

  Timer? _presenceTimer;

  final TextEditingController _searchController =
      TextEditingController();

  final FirebaseFirestore _firestore = 
      FirebaseFirestore.instance;

  final FirebaseAuth _auth =
      FirebaseAuth.instance;

  // ==========================================================================
  // CHATFLOW COLORS
  // ==========================================================================

  static const Color navy = Color(0xFF102A5C);
  static const Color skyBlue = Color(0xFF55C7E8);
  static const Color cyan = Color(0xFF16AFC1);
  static const Color mint = Color(0xFF66D6C1);
  static const Color lightMint = Color(0xFFDDF8F1);
  static const Color onlineGreen = Color(0xFF20C98B);

  // ==========================================================================
  // THEME COLORS
  // ==========================================================================

  Color get backgroundColor {
    return _isDarkMode
        ? const Color(0xFF06162F)
        : const Color(0xFFF4FFFC);
  }

  Color get cardColor {
    return _isDarkMode
        ? const Color(0xFF10284A)
        : Colors.white;
  }

  Color get primaryText {
    return _isDarkMode
        ? Colors.white
        : navy;
  }

  Color get secondaryText {
    return _isDarkMode
        ? const Color(0xFFB8C9DB)
        : const Color(0xFF657080);
  }

  Color get borderColor {
    return _isDarkMode
        ? const Color(0xFF24486A)
        : const Color(0xFFBCEDE2);
  }

  // ==========================================================================
  // INIT
  // ==========================================================================

  @override
void initState() {
  super.initState();

  WidgetsBinding.instance.addObserver(this);

  _updateStatus('Online');

  _presenceTimer = Timer.periodic(
    const Duration(seconds: 60),
    (_) {
      _updateStatus('Online');
    },
  );
}

  // ==========================================================================
  // APP LIFECYCLE
  // ==========================================================================

  @override
void didChangeAppLifecycleState(
  AppLifecycleState state,
) {
  if (state == AppLifecycleState.paused ||
      state == AppLifecycleState.detached) {
    _updateStatus('Offline');
  } else if (state == AppLifecycleState.resumed) {
    _updateStatus('Online');
  }
}

  // ==========================================================================
  // UPDATE ONLINE / OFFLINE STATUS
  // ==========================================================================

  Future<void> _updateStatus(String status) async {
  final currentUserId = _auth.currentUser?.uid;

  if (currentUserId == null ||
      currentUserId.isEmpty) {
    return;
  }

  try {
    final Map<String, dynamic> data = {
      'status': status,
      'lastActive': FieldValue.serverTimestamp(),
    };

    if (status == 'Offline') {
      data['lastSeen'] =
          FieldValue.serverTimestamp();
    }

    await _firestore
        .collection('users')
        .doc(currentUserId)
        .update(data);
  } catch (_) {
    // Ignore status update errors.
  }
}

  // ==========================================================================
  // DISPOSE
  // ==========================================================================

  @override
void dispose() {
  WidgetsBinding.instance.removeObserver(this);

  _presenceTimer?.cancel();
  _updateStatus('Offline');

  _searchController.dispose();

  super.dispose();
}

  // ==========================================================================
  // LOGOUT
  // ==========================================================================

  Future<void> _handleLogout() async {
    try {
      await _updateStatus('Offline');

      await _auth.signOut();

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => const login_screen(),
        ),
        (route) => false,
      );
    } catch (_) {
      _showSnackbar(
        'Unable to logout. Please try again.',
      );
    }
  }

  // ==========================================================================
  // SNACKBAR
  // ==========================================================================

  void _showSnackbar(String text) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        backgroundColor: _isDarkMode
            ? navy
            : const Color(0xFF173B68),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
      ),
    );
  }

  // ==========================================================================
  // NOTIFICATIONS
  // ==========================================================================

  void _openNotifications() {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => NotificationScreen(
        isDarkMode: _isDarkMode,
      ),
    ),
  );
}

  // ==========================================================================
  // STARRED MESSAGES
  // ==========================================================================

  Future<void> _openStarredMessages() async {
    final currentUserId = _auth.currentUser?.uid;

    if (currentUserId == null ||
        currentUserId.isEmpty) {
      _showSnackbar(
        'Please login again.',
      );
      return;
    }

    try {
      final roomsSnapshot = await _firestore
          .collection('chat_rooms')
          .where(
            'participants',
            arrayContains: currentUserId,
          )
          .get();

      final List<Map<String, dynamic>>
          starredMessages = [];

      for (final roomDoc in roomsSnapshot.docs) {
        final messagesSnapshot = await _firestore
            .collection('chat_rooms')
            .doc(roomDoc.id)
            .collection('messages')
            .where(
              'isStarred',
              isEqualTo: true,
            )
            .get();

        for (final messageDoc
            in messagesSnapshot.docs) {
          final data =
              messageDoc.data();

          starredMessages.add({
            ...data,
            'messageId': messageDoc.id,
            'chatRoomId': roomDoc.id,
          });
        }
      }

      starredMessages.sort((a, b) {
        final aTimestamp = a['timestamp'];
        final bTimestamp = b['timestamp'];

        if (aTimestamp is Timestamp &&
            bTimestamp is Timestamp) {
          return bTimestamp
              .compareTo(aTimestamp);
        }

        return 0;
      });

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              _StarredMessagesScreen(
            messages: starredMessages,
            isDarkMode: _isDarkMode,
            primaryText: primaryText,
            secondaryText: secondaryText,
            cardColor: cardColor,
            borderColor: borderColor,
            cyan: cyan,
            mint: mint,
            navy: navy,
          ),
        ),
      );
    } catch (e) {
      debugPrint(
        'Starred messages error: $e',
      );

      if (!mounted) return;

      _showSnackbar(
        'Unable to load starred messages. Please try again.',
      );
    }
  }

  // ==========================================================================
  // BUILD
  // ==========================================================================

  @override
  Widget build(BuildContext context) {
    final currentUserId =
        _auth.currentUser?.uid ?? '';
        
    return IncomingCallListener(
      child: Scaffold(
      backgroundColor: backgroundColor,

      // ======================================================================
      // APP BAR
      // ======================================================================

      appBar: AppBar(
        elevation: 0,
        backgroundColor: _isDarkMode
            ? const Color(0xFF0A2243)
            : Colors.white,
        surfaceTintColor: Colors.transparent,

        title: _isSearching &&
                _currentIndex == 0
            ? _searchField()
            : Row(
                children: [
                  ClipRRect(
                    borderRadius:
                        BorderRadius.circular(10),
                    child: Image.asset(
                      'assets/logo.png',
                      width: 42,
                      height: 42,
                      fit: BoxFit.contain,
                    ),
                  ),

                  const SizedBox(width: 12),

                  Text(
                    'ChatFlow',
                    style: TextStyle(
                      color: primaryText,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),

        actions: [
          // ==================================================================
          // SEARCH
          // ==================================================================

          if (_currentIndex == 0)
            IconButton(
              icon: Icon(
                _isSearching
                    ? Icons.close_rounded
                    : Icons.search_rounded,
                color: primaryText,
              ),
              onPressed: _toggleSearch,
            ),

          // ==================================================================
          // NOTIFICATIONS
          // ==================================================================

          StreamBuilder<QuerySnapshot>(
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
                .where(
                  'seen',
                  isEqualTo: false,
                )
                .snapshots(),

            builder: (context, snapshot) {
              final hasNewNotification =
                  snapshot.hasData &&
                  snapshot.data!.docs.isNotEmpty;

              return Stack(
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.notifications_none_rounded,
                      color: primaryText,
                    ),
                    onPressed: _openNotifications,
                  ),

                  if (hasNewNotification)
                    Positioned(
                      right: 10,
                      top: 9,
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration:
                            const BoxDecoration(
                          color: Colors.redAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),

          // ==================================================================
          // THREE DOT MENU
          // ==================================================================

          PopupMenuButton<String>(
            icon: Icon(
              Icons.more_vert_rounded,
              color: primaryText,
            ),
            color: cardColor,
            onSelected: _handleMenu,
            itemBuilder: (_) => [
              _menuItem(
                'new_group',
                'New Group',
                Icons.group_add_rounded,
              ),

              _menuItem(
                'starred',
                'Starred Messages',
                Icons.star_outline_rounded,
              ),

              _menuItem(
                'settings',
                'Settings',
                Icons.settings_outlined,
              ),

              const PopupMenuItem(
                value: 'logout',
                child: Text(
                  'Logout',
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),

      // ======================================================================
      // BODY
      // ======================================================================

      body: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: ChatBackgroundPainter(
                darkMode: _isDarkMode,
                selectedPage: _currentIndex,
              ),
            ),
          ),

          _buildBody(currentUserId),
        ],
      ),

      // ======================================================================
      // BOTTOM NAVIGATION
      // ======================================================================

      bottomNavigationBar:
          _bottomNavigation(),
    ),
    );
  }

 // ==========================================================================
// SEARCH FIELD
// ==========================================================================

Widget _searchField() {
  return TextField(
    controller: _searchController,
    autofocus: true,

    style: TextStyle(
      color: primaryText,
      fontSize: 18,
    ),

    decoration: InputDecoration(
      hintText: 'Search by email or group name...',
      hintStyle: TextStyle(
        color: secondaryText,
      ),
      border: InputBorder.none,
    ),

    onChanged: (value) {
      setState(() {
        _searchQuery =
            value.trim().toLowerCase();
      });
    },
  );
}

  // ==========================================================================
  // MENU ITEM
  // ==========================================================================

  PopupMenuItem<String> _menuItem(
    String value,
    String title,
    IconData icon,
  ) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(
            icon,
            color: cyan,
            size: 21,
          ),

          const SizedBox(width: 12),

          Text(
            title,
            style: TextStyle(
              color: primaryText,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // MENU HANDLER
  // ==========================================================================

  void _handleMenu(String value) {
    if (value == 'logout') {
      _handleLogout();
    } else if (value == 'settings') {
      setState(() {
        _currentIndex = 3;
        _closeSearch();
      });
    } else if (value == 'new_group') {
      _openNewGroup();
    } else if (value == 'starred') {
      _openStarredMessages();
    }
  }

  // ==========================================================================
  // NEW GROUP
  // ==========================================================================

  void _openNewGroup() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NewGroupScreen(
          isDarkMode: _isDarkMode,
          primaryText: primaryText,
          secondaryText: secondaryText,
          cardColor: cardColor,
          borderColor: borderColor,
          cyan: cyan,
          mint: mint,
          skyBlue: skyBlue,
          navy: navy,
        ),
      ),
    );
  }

  // ==========================================================================
  // SEARCH TOGGLE
  // ==========================================================================

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;

      if (!_isSearching) {
        _closeSearch();
      }
    });
  }

  // ==========================================================================
  // CLOSE SEARCH
  // ==========================================================================

  void _closeSearch() {
    _isSearching = false;
    _searchQuery = '';
    _searchController.clear();
  }

  // ==========================================================================
  // BODY
  // ==========================================================================

  Widget _buildBody(String currentUserId) {
    switch (_currentIndex) {
      case 0:
        return _buildChatTab(currentUserId);

      case 1:
        return StatusTab(
          isDarkMode: _isDarkMode,
          primaryText: primaryText,
          secondaryText: secondaryText,
          navy: navy,
          mint: mint,
          cyan: cyan,
          skyBlue: skyBlue,
          sectionCard: _sectionCard,
          sectionHeading: _sectionHeading,
          emptyState: _emptyState,
        );

      case 2:
        return CallsTab(
          isDarkMode: _isDarkMode,
          primaryText: primaryText,
          secondaryText: secondaryText,
          mint: mint,
          cyan: cyan,
          navy: navy,
          skyBlue: skyBlue,
          showSnackbar: _showSnackbar,
        );

      case 3:
        return ProfileTab(
          isDarkMode: _isDarkMode,
          primaryText: primaryText,
          secondaryText: secondaryText,
          navy: navy,
          mint: mint,
          cyan: cyan,
          skyBlue: skyBlue,
          lightMint: lightMint,
          auth: _auth,
          onThemeModeChanged: (value) {
            setState(() {
              _isDarkMode = value;
            });
          },
          onLogout: _handleLogout,
        );

      default:
        return _buildChatTab(currentUserId);
    }
  }

  // ==========================================================================
  // BOTTOM NAVIGATION
  // ==========================================================================

  Widget _bottomNavigation() {
    return Container(
      decoration: BoxDecoration(
        color: _isDarkMode
            ? const Color(0xFF0A2243)
            : Colors.white,

        border: Border(
          top: BorderSide(
            color: _isDarkMode
                ? const Color(0xFF1E4265)
                : lightMint,
          ),
        ),

        boxShadow: [
          BoxShadow(
            color: mint.withOpacity(0.12),
            blurRadius: 18,
            offset: const Offset(0, -5),
          ),
        ],
      ),

      child: BottomNavigationBar(
        currentIndex: _currentIndex,
        backgroundColor: Colors.transparent,
        elevation: 0,
        type: BottomNavigationBarType.fixed,

        selectedItemColor: cyan,

        unselectedItemColor: _isDarkMode
            ? const Color(0xFF8EA2BA)
            : const Color(0xFF7A8494),

        selectedLabelStyle:
            const TextStyle(
          fontWeight: FontWeight.bold,
        ),

        onTap: (index) {
          setState(() {
            _currentIndex = index;
            _closeSearch();
          });
        },

        items: const [
          BottomNavigationBarItem(
            icon: Icon(
              Icons.chat_bubble_outline_rounded,
            ),
            activeIcon: Icon(
              Icons.chat_bubble_rounded,
            ),
            label: 'Chats',
          ),

          BottomNavigationBarItem(
            icon: Icon(
              Icons.auto_stories_outlined,
            ),
            activeIcon: Icon(
              Icons.auto_stories_rounded,
            ),
            label: 'Status',
          ),

          BottomNavigationBarItem(
            icon: Icon(
              Icons.phone_outlined,
            ),
            activeIcon: Icon(
              Icons.phone_rounded,
            ),
            label: 'Calls',
          ),

          BottomNavigationBarItem(
            icon: Icon(
              Icons.person_outline_rounded,
            ),
            activeIcon: Icon(
              Icons.person_rounded,
            ),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // CHAT TAB
  // ==========================================================================

  Widget _buildChatTab(String currentUserId) {
    if (_searchQuery.isEmpty) {
      return _buildAcceptedChats(currentUserId);
    }

    return _buildSearchResults(currentUserId);
  }

  // ==========================================================================
  // ACCEPTED CHATS
  // ==========================================================================

  Widget _buildAcceptedChats(String currentUserId) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('chat_rooms')
          .where(
            'participants',
            arrayContains: currentUserId,
          )
          .snapshots(),

      builder: (context, roomSnapshot) {
        if (roomSnapshot.connectionState ==
            ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(
              color: mint,
            ),
          );
        }

        if (roomSnapshot.hasError) {
  debugPrint('CHAT ROOMS ERROR: ${roomSnapshot.error}');

  return _emptyState(
    Icons.error_outline_rounded,
    'Unable to load chats',
    roomSnapshot.error.toString(),
  );
}

        final rooms =
            roomSnapshot.data?.docs ?? [];

        if (rooms.isEmpty) {
          return _emptyState(
            Icons.chat_bubble_outline_rounded,
            'No chats yet',
            'Search for a user by email to start a chat.',
          );
        }

        return StreamBuilder<QuerySnapshot>(
          stream: _firestore
              .collection('users')
              .snapshots(),

          builder: (context, userSnapshot) {
            if (userSnapshot.connectionState ==
                ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(
                  color: mint,
                ),
              );
            }

            if (userSnapshot.hasError ||
                !userSnapshot.hasData) {
              return _emptyState(
                Icons.people_outline_rounded,
                'Unable to load chats',
                'Please try again.',
              );
            }

            final userDocs =
                userSnapshot.data!.docs;

            final List<Map<String, dynamic>>
                acceptedChats = [];

            // ==================================================================
            // PROCESS CHAT ROOMS
            // ==================================================================

            for (final room in rooms) {
              final roomData =
                  room.data()
                      as Map<String, dynamic>;

              final isGroup =
                  roomData['isGroup'] == true;

              // ================================================================
              // GROUP CHAT
              // ================================================================

              if (isGroup) {
  // ========================================================================
  // GROUP DELETED FOR CURRENT USER
  //
  // If this user used "Delete Group", do not show the group in
  // their chat list.
  // ========================================================================

  final deletedFor =
      roomData['deletedFor'];

  if (deletedFor is Map &&
      deletedFor[currentUserId] == true) {
    continue;
  }

  final groupName =
      roomData['groupName']
              ?.toString()
              .trim()
              .isNotEmpty ==
          true
      ? roomData['groupName']
          .toString()
      : 'Group';

  acceptedChats.add({
                  'isGroup': true,
                  'groupName': groupName,
                  'chatRoomId': room.id,
                  'participants':
                      roomData['participants'] ?? [],
                  'createdAt':
                      roomData['createdAt'],
                });

                continue;
              }

              // ================================================================
// REMOVED CHAT
// ================================================================
//
// If the current user deleted/removed this individual chat,
// do not show the chat in their chat list.
//
// The other user's copy remains visible.

final removedBy =
    List<String>.from(
  roomData['removedBy'] ?? [],
);

if (removedBy.contains(currentUserId)) {
  continue;
}

              // ================================================================
              // ONE-TO-ONE CHAT
              // ================================================================

              final participants =
                  List<String>.from(
                roomData['participants'] ?? [],
              );

              final otherUserId =
                  participants.firstWhere(
                (id) => id != currentUserId,
                orElse: () => '',
              );

              if (otherUserId.isEmpty) {
                continue;
              }

              for (final userDoc in userDocs) {
                final userData =
                    userDoc.data()
                        as Map<String, dynamic>;

                final userUid =
                    userData['uid']?.toString() ??
                        userDoc.id;

                if (userUid == otherUserId) {
                  final userWithRoom = {
                    ...userData,
                    'uid': userUid,
                    'chatRoomId': room.id,
                    'isGroup': false,
                  };

                  acceptedChats
                      .add(userWithRoom);

                  break;
                }
              }
            }

            if (acceptedChats.isEmpty) {
              return _emptyState(
                Icons.chat_bubble_outline_rounded,
                'No chats yet',
                'Search for a user by email to start a chat.',
              );
            }

            return ListView.separated(
              padding:
                  const EdgeInsets.fromLTRB(
                15,
                18,
                15,
                30,
              ),

              itemCount:
                  acceptedChats.length,

              separatorBuilder: (_, __) =>
                  const SizedBox(height: 12),

              itemBuilder: (context, index) {
                final data =
                    acceptedChats[index];

                final isGroup =
                    data['isGroup'] == true;

                // ==============================================================
                // GROUP CARD
                // ==============================================================

                if (isGroup) {
                  final groupName =
                      data['groupName']
                              ?.toString() ??
                          'Group';

                  return _groupChatCard(
                    groupName: groupName,
                    participantCount:
                        (data['participants']
                                as List?)
                            ?.length ??
                        0,
                    onTap: () {
                      _openGroupChat(
                        data,
                      );
                    },
                  );
                }

                // ==============================================================
                // ONE-TO-ONE CARD
                // ==============================================================

                final name =
                    data['fullName']
                            ?.toString() ??
                        'Chat User';

                final lastActive = data['lastActive'];

bool online = false;

if (lastActive is Timestamp) {
  final difference =
      DateTime.now().difference(
    lastActive.toDate(),
  );

  online =
      difference.inSeconds <= 90;
}

                final targetUserId =
                    data['uid']?.toString() ??
                        '';

                return StreamBuilder<QuerySnapshot>(
  stream: _firestore
      .collection('chat_rooms')
      .doc(data['chatRoomId'].toString())
      .collection('messages')
      .where(
        'receiverId',
        isEqualTo: currentUserId,
      )
      .snapshots(),

  builder: (context, messageSnapshot) {
    int unreadCount = 0;

    if (messageSnapshot.hasData) {
      for (final messageDoc
          in messageSnapshot.data!.docs) {

        final messageData =
            messageDoc.data()
                as Map<String, dynamic>;

        final isRead =
            messageData['isRead'] == true;

        if (!isRead) {
          unreadCount++;
        }
      }
    }

    return _chatCard(
      name: name,
      isOnline: online,
      lastSeen: data['lastSeen'],
      unreadCount: unreadCount,
      onTap: () {
        if (targetUserId.isEmpty) {
          return;
        }

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatRoomScreen(
              targetUserName: name,
              targetUserId: targetUserId,
            ),
          ),
        );
      },
    );
  },
);
              },
            );
          },
        );
      },
    );
  }

  // ==========================================================================
  // OPEN GROUP CHAT
  // ==========================================================================

  void _openGroupChat(
    Map<String, dynamic> data,
  ) {
    final groupId =
        data['chatRoomId']?.toString() ?? '';

    final groupName =
        data['groupName']?.toString().trim().isNotEmpty == true
            ? data['groupName'].toString().trim()
            : 'Group';

    final rawMembers = data['participants'];

    final groupMembers = rawMembers is List
        ? rawMembers
            .map((member) => member.toString())
            .where((member) => member.isNotEmpty)
            .toList()
        : <String>[];

    if (groupId.isEmpty) {
      _showSnackbar(
        'Unable to open this group.',
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatRoomScreen(
          targetUserName: groupName,
          targetUserId: '',
          isGroup: true,
          groupId: groupId,
          groupName: groupName,
          groupMembers: groupMembers,
        ),
      ),
    );
  }

  // ==========================================================================
  // GROUP CHAT CARD
  // ==========================================================================

  Widget _groupChatCard({
    required String groupName,
    required int participantCount,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: cardColor.withOpacity(
          _isDarkMode ? 0.96 : 0.94,
        ),

        borderRadius:
            BorderRadius.circular(24),

        border: Border.all(
          color: borderColor,
          width: 1.3,
        ),

        boxShadow: [
          BoxShadow(
            color: mint.withOpacity(
              _isDarkMode ? 0.07 : 0.18,
            ),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),

      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 8,
        ),

        onTap: onTap,

        leading: Container(
          padding:
              const EdgeInsets.all(2.5),

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
            radius: 26,
            backgroundColor: cardColor,

            child: const Icon(
              Icons.groups_rounded,
              color: cyan,
              size: 29,
            ),
          ),
        ),

        title: Text(
          groupName,
          maxLines: 1,
          overflow:
              TextOverflow.ellipsis,

          style: TextStyle(
            color: primaryText,
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),

        subtitle: Padding(
          padding:
              const EdgeInsets.only(top: 4),

          child: Text(
            '$participantCount participants',
            style: TextStyle(
              color: secondaryText,
              fontSize: 13,
            ),
          ),
        ),

        trailing: Container(
          width: 38,
          height: 38,

          decoration: BoxDecoration(
            color: mint.withOpacity(
              _isDarkMode ? 0.14 : 0.22,
            ),
            shape: BoxShape.circle,
          ),

          child: const Icon(
            Icons.arrow_forward_ios_rounded,
            color: cyan,
            size: 15,
          ),
        ),
      ),
    );
  }

  // ==========================================================================
// SEARCH RESULTS
// ==========================================================================

Widget _buildSearchResults(String currentUserId) {
  return StreamBuilder<QuerySnapshot>(
    stream: _firestore
        .collection('chat_rooms')
        .where(
          'participants',
          arrayContains: currentUserId,
        )
        .snapshots(),

    builder: (context, roomSnapshot) {
      if (roomSnapshot.connectionState ==
          ConnectionState.waiting) {
        return const Center(
          child: CircularProgressIndicator(
            color: mint,
          ),
        );
      }

      final rooms =
    roomSnapshot.hasData
        ? roomSnapshot.data!.docs
        : <QueryDocumentSnapshot>[]; 

      // ======================================================================
      // SEARCH USERS BY EMAIL
      // ======================================================================

      return StreamBuilder<QuerySnapshot>(
        stream: _firestore
            .collection('users')
            .snapshots(),

        builder: (context, userSnapshot) {
          if (userSnapshot.connectionState ==
              ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(
                color: mint,
              ),
            );
          }

          if (userSnapshot.hasError) {
            return _emptyState(
              Icons.error_outline_rounded,
              'Unable to search users',
              'Please try again.',
            );
          }

          final userDocuments =
              userSnapshot.data?.docs ?? [];

          final users = userDocuments.where((doc) {
            final data =
                doc.data() as Map<String, dynamic>;

            final uid =
                data['uid']?.toString() ?? doc.id;

            final email =
                data['email']
                        ?.toString()
                        .toLowerCase() ??
                    '';

            return uid != currentUserId &&
                email.contains(_searchQuery);
          }).toList();

          // ==================================================================
          // SEARCH GROUPS BY GROUP NAME
          // ==================================================================

          final groups = rooms.where((room) {
  final data =
      room.data()
          as Map<String, dynamic>;

  final isGroup =
      data['isGroup'] == true;

  if (!isGroup) {
    return false;
  }

  // ========================================================================
  // GROUP DELETED FOR CURRENT USER
  //
  // If the current user deleted this group, it must NOT appear in
  // group search anymore.
  // ========================================================================

  final deletedFor =
      data['deletedFor'];

  if (deletedFor is Map &&
      deletedFor[currentUserId] == true) {
    return false;
  }

  // ========================================================================
  // GROUP NAME SEARCH
  // ========================================================================

  final groupName =
      data['groupName']
              ?.toString()
              .toLowerCase()
              .trim() ??
          '';

  return groupName.contains(
    _searchQuery,
  );
}).toList();

          // ==================================================================
          // NOTHING FOUND
          // ==================================================================

          if (users.isEmpty && groups.isEmpty) {
            return _emptyState(
              Icons.search_off_rounded,
              'No results found',
              'No user email or group name matches your search.',
            );
          }

          // ==================================================================
          // RESULTS
          // ==================================================================

          return ListView(
            padding: const EdgeInsets.fromLTRB(
              15,
              18,
              15,
              30,
            ),

            children: [
              // ================================================================
              // GROUP RESULTS
              // ================================================================

              if (groups.isNotEmpty) ...[
                _sectionHeading('Groups'),

                const SizedBox(height: 12),

                ...groups.map((room) {
                  final data =
                      room.data()
                          as Map<String, dynamic>;

                  final groupName =
                      data['groupName']
                              ?.toString()
                              .trim()
                              .isNotEmpty ==
                          true
                      ? data['groupName']
                          .toString()
                          .trim()
                      : 'Group';

                  final rawParticipants =
                      data['participants'];

                  final participantCount =
                      rawParticipants is List
                          ? rawParticipants.length
                          : 0;

                  return Padding(
                    padding:
                        const EdgeInsets.only(
                      bottom: 12,
                    ),
                    child: _groupChatCard(
                      groupName: groupName,
                      participantCount:
                          participantCount,
                      onTap: () {
                        _openGroupChat({
                          'chatRoomId': room.id,
                          'groupName': groupName,
                          'participants':
                              rawParticipants ??
                                  [],
                          'isGroup': true,
                        });
                      },
                    ),
                  );
                }),
              ],

              // ================================================================
              // USER RESULTS
              // ================================================================

              if (users.isNotEmpty) ...[
                if (groups.isNotEmpty)
                  const SizedBox(height: 8),

                _sectionHeading('Users'),

                const SizedBox(height: 12),

                ...users.map((doc) {
                  final data =
                      doc.data()
                          as Map<String, dynamic>;

                  final name =
                      data['fullName']
                              ?.toString() ??
                          'Chat User';

                  final email =
                      data['email']
                              ?.toString() ??
                          '';

                  final lastActive =
    data['lastActive'];

bool online = false;

if (lastActive is Timestamp) {
  final difference =
      DateTime.now().difference(
    lastActive.toDate(),
  );

  online =
      difference.inSeconds <= 90;
}

                  return Padding(
                    padding:
                        const EdgeInsets.only(
                      bottom: 12,
                    ),
                    child: _searchUserCard(
                      name: name,
                      email: email,
                      isOnline: online,
                      lastSeen:
                          data['lastSeen'],
                      onTap: () {
                        _handleUserTap(data);
                      },
                    ),
                  );
                }),
              ],
            ],
          );
        },
      );
    },
  );
}
  // ==========================================================================
  // SEARCH USER CARD
  // ==========================================================================

  Widget _searchUserCard({
    required String name,
    required String email,
    required bool isOnline,
    required dynamic lastSeen,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: cardColor.withOpacity(
          _isDarkMode ? 0.96 : 0.94,
        ),

        borderRadius:
            BorderRadius.circular(24),

        border: Border.all(
          color: borderColor,
          width: 1.3,
        ),

        boxShadow: [
          BoxShadow(
            color: mint.withOpacity(
              _isDarkMode ? 0.07 : 0.18,
            ),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),

      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 8,
        ),

        onTap: onTap,

        leading: Stack(
          children: [
            Container(
              padding:
                  const EdgeInsets.all(2.5),

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
                radius: 26,
                backgroundColor: cardColor,

                child: Text(
                  name.isNotEmpty
                      ? name
                          .substring(0, 1)
                          .toUpperCase()
                      : '?',

                  style: TextStyle(
                    color: _isDarkMode
                        ? Colors.white
                        : navy,
                    fontSize: 20,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
              ),
            ),

            Positioned(
              right: 0,
              bottom: 0,

              child: Container(
                width: 14,
                height: 14,

                decoration: BoxDecoration(
                  color: isOnline
                      ? onlineGreen
                      : const Color(
                          0xFF9AA4B2,
                        ),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: cardColor,
                    width: 2.5,
                  ),
                ),
              ),
            ),
          ],
        ),

        title: Text(
          name,
          style: TextStyle(
            color: primaryText,
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),

        subtitle: Padding(
          padding:
              const EdgeInsets.only(top: 4),

          child: Text(
            email,
            style: TextStyle(
              color: secondaryText,
              fontSize: 13,
            ),
          ),
        ),

        trailing: Container(
          padding:
              const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),

          decoration: BoxDecoration(
            color: cyan.withOpacity(
              _isDarkMode ? 0.15 : 0.12,
            ),

            borderRadius:
                BorderRadius.circular(15),
          ),

          child: const Text(
            'Connect',
            style: TextStyle(
              color: cyan,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

Future<void> _handleUserTap(
  Map<String, dynamic> data,
) async {
  final currentUserId = _auth.currentUser?.uid;

  if (currentUserId == null) {
    return;
  }

  final targetUserId =
      data['uid']?.toString() ?? '';

  if (targetUserId.isEmpty) {
    _showSnackbar(
      'Unable to find this user.',
    );
    return;
  }

  // ==========================================================================
  // TARGET USER INFORMATION
  // ==========================================================================

  final targetUserName =
      data['fullName']?.toString() ??
          'Chat User';

  final targetUserEmail =
      data['email']?.toString() ??
          '';

  // ==========================================================================
  // CREATE CONSISTENT ONE-TO-ONE CHAT ROOM ID
  // ==========================================================================

  final ids = [
    currentUserId,
    targetUserId,
  ]..sort();

  final chatRoomId = ids.join('_');

  // ==========================================================================
  // CHECK EXISTING CHAT ROOM
  //
  // IMPORTANT:
  // If the room cannot be read because it does not exist or is not accessible,
  // we simply treat it as "no active chat" and allow the user to connect.
  // ==========================================================================

  try {
    final chatRoom = await _firestore
        .collection('chat_rooms')
        .doc(chatRoomId)
        .get();

    // ========================================================================
    // EXISTING CHAT ROOM
    // ========================================================================

    if (chatRoom.exists) {
      final roomData =
          chatRoom.data() ??
              <String, dynamic>{};

      // ----------------------------------------------------------------------
      // CHECK REMOVED / DELETED STATUS
      // ----------------------------------------------------------------------

      final rawRemovedBy =
          roomData['removedBy'];

      final removedBy =
          rawRemovedBy is List
              ? rawRemovedBy
                  .map(
                    (e) => e.toString(),
                  )
                  .toSet()
              : <String>{};

      // ----------------------------------------------------------------------
      // OLD CHAT WAS REMOVED / DELETED
      //
      // Do NOT reopen the old chat.
      // Allow the user to send a new request.
      // ----------------------------------------------------------------------

      if (removedBy.isNotEmpty) {
        if (!mounted) return;

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                ConnectUserScreen(
              targetUserId:
                  targetUserId,
              targetUserName:
                  targetUserName,
              targetUserEmail:
                  targetUserEmail,
            ),
          ),
        );

        return;
      }

      // ----------------------------------------------------------------------
      // ACTIVE CHAT
      // ----------------------------------------------------------------------

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              ChatRoomScreen(
            targetUserName:
                targetUserName,
            targetUserId:
                targetUserId,
          ),
        ),
      );

      return;
    }

    // =========================================================================
    // NO EXISTING CHAT ROOM
    //
    // This is a new connection.
    // Open ConnectUserScreen so the user can send a request.
    // =========================================================================

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ConnectUserScreen(
          targetUserId:
              targetUserId,
          targetUserName:
              targetUserName,
          targetUserEmail:
              targetUserEmail,
        ),
      ),
    );
  } on FirebaseException catch (e) {
    // =========================================================================
    // FIRESTORE READ FAILED
    //
    // Do NOT block the connection flow just because the existing chat room
    // could not be read.
    //
    // For example, this can happen when the current user is not a participant
    // of an old chat room and Firestore security rules deny the read.
    // In that situation, allow a new connection request.
    // =========================================================================

    debugPrint(
      'Chat room check failed: ${e.code} ${e.message}',
    );

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ConnectUserScreen(
          targetUserId:
              targetUserId,
          targetUserName:
              targetUserName,
          targetUserEmail:
              targetUserEmail,
        ),
      ),
    );
  } catch (e) {
    // =========================================================================
    // UNEXPECTED ERROR
    // =========================================================================

    debugPrint(
      'Chat room check error: $e',
    );

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ConnectUserScreen(
          targetUserId:
              targetUserId,
          targetUserName:
              targetUserName,
          targetUserEmail:
              targetUserEmail,
        ),
      ),
    );
  }
}


  // ==========================================================================
  // CHAT CARD
  // ==========================================================================

  Widget _chatCard({
  required String name,
  required bool isOnline,
  required VoidCallback onTap,
  required dynamic lastSeen,
  required int unreadCount,
}) {
    return Container(
      decoration: BoxDecoration(
        color: cardColor.withOpacity(
          _isDarkMode ? 0.96 : 0.94,
        ),

        borderRadius:
            BorderRadius.circular(24),

        border: Border.all(
          color: borderColor,
          width: 1.3,
        ),

        boxShadow: [
          BoxShadow(
            color: mint.withOpacity(
              _isDarkMode ? 0.07 : 0.18,
            ),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),

      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 8,
        ),

        onTap: onTap,

        leading: Stack(
          children: [
            Container(
              padding:
                  const EdgeInsets.all(2.5),

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
                radius: 26,
                backgroundColor: cardColor,

                child: Text(
                  name.isNotEmpty
                      ? name
                          .substring(0, 1)
                          .toUpperCase()
                      : '?',

                  style: TextStyle(
                    color: _isDarkMode
                        ? Colors.white
                        : navy,
                    fontSize: 20,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
              ),
            ),

            Positioned(
              right: 0,
              bottom: 0,

              child: Container(
                width: 14,
                height: 14,

                decoration: BoxDecoration(
                  color: isOnline
                      ? onlineGreen
                      : const Color(
                          0xFF9AA4B2,
                        ),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: cardColor,
                    width: 2.5,
                  ),
                ),
              ),
            ),
          ],
        ),

        title: Text(
          name,
          style: TextStyle(
            color: primaryText,
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),

        subtitle: Padding(
          padding:
              const EdgeInsets.only(top: 4),

          child: Text(
            isOnline
                ? 'Online now'
                : _formatLastSeen(lastSeen),

            style: TextStyle(
              color: isOnline
                  ? onlineGreen
                  : secondaryText,
              fontSize: 13,
            ),
          ),
        ),

        trailing: unreadCount > 0
    ? Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: mint,
          shape: BoxShape.circle,
        ),
        child: Text(
          unreadCount > 99
              ? '99+'
              : unreadCount.toString(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      )
    : Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: mint.withOpacity(
            _isDarkMode ? 0.14 : 0.22,
          ),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.arrow_forward_ios_rounded,
          color: cyan,
          size: 15,
        ),
      ),
      ),
    );
  }

  // ==========================================================================
  // SECTION CARD
  // ==========================================================================

  Widget _sectionCard({
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: cardColor.withOpacity(
          _isDarkMode ? 0.96 : 0.94,
        ),

        borderRadius:
            BorderRadius.circular(24),

        border: Border.all(
          color: borderColor,
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
  // SECTION HEADING
  // ==========================================================================

  Widget _sectionHeading(String title) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 5,
      ),

      child: Row(
        children: [
          Container(
            width: 5,
            height: 23,

            decoration: BoxDecoration(
              color: mint,
              borderRadius:
                  BorderRadius.circular(5),
            ),
          ),

          const SizedBox(width: 9),

          Text(
            title,
            style: TextStyle(
              color: primaryText,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // EMPTY STATE
  // ==========================================================================

  Widget _emptyState(
    IconData icon,
    String title,
    String subtitle,
  ) {
    return Center(
      child: Padding(
        padding:
            const EdgeInsets.symmetric(
          horizontal: 35,
          vertical: 70,
        ),

        child: Column(
          mainAxisAlignment:
              MainAxisAlignment.center,

          children: [
            Container(
              width: 95,
              height: 95,

              decoration: BoxDecoration(
                gradient:
                    const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    mint,
                    cyan,
                    skyBlue,
                  ],
                ),

                shape: BoxShape.circle,

                boxShadow: [
                  BoxShadow(
                    color:
                        mint.withOpacity(0.25),
                    blurRadius: 20,
                  ),
                ],
              ),

              child: Icon(
                icon,
                size: 43,
                color: Colors.white,
              ),
            ),

            const SizedBox(height: 20),

            Text(
              title,
              textAlign: TextAlign.center,

              style: TextStyle(
                color: primaryText,
                fontSize: 19,
                fontWeight:
                    FontWeight.bold,
              ),
            ),

            const SizedBox(height: 8),

            Text(
              subtitle,
              textAlign: TextAlign.center,

              style: TextStyle(
                color: secondaryText,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================================
  // LAST SEEN FORMATTER
  // ==========================================================================

  String _formatLastSeen(
    dynamic timestamp,
  ) {
    if (timestamp == null) {
      return 'Offline';
    }

    if (timestamp is Timestamp) {
      final date =
          timestamp.toDate();

      final hour =
          date.hour.toString().padLeft(
                2,
                '0',
              );

      final minute =
          date.minute.toString().padLeft(
                2,
                '0',
              );

      return 'Last seen today at $hour:$minute';
    }

    return 'Offline';
  }
  
}

// ============================================================================
// NEW GROUP SCREEN
// ============================================================================

class NewGroupScreen extends StatefulWidget {
  final bool isDarkMode;

  final Color primaryText;
  final Color secondaryText;
  final Color cardColor;
  final Color borderColor;
  final Color cyan;
  final Color mint;
  final Color skyBlue;
  final Color navy;

  const NewGroupScreen({
    super.key,
    required this.isDarkMode,
    required this.primaryText,
    required this.secondaryText,
    required this.cardColor,
    required this.borderColor,
    required this.cyan,
    required this.mint,
    required this.skyBlue,
    required this.navy,
  });

  @override
  State<NewGroupScreen> createState() =>
      _NewGroupScreenState();
}

class _NewGroupScreenState
    extends State<NewGroupScreen> {
  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  final FirebaseAuth _auth =
      FirebaseAuth.instance;

  final TextEditingController
      _searchController =
      TextEditingController();

  String _searchQuery = '';

  final Set<String> _selectedUserIds =
      <String>{};

  final Map<String, Map<String, dynamic>>
      _selectedUsers =
      <String, Map<String, dynamic>>{};

  // ==========================================================================
  // DISPOSE
  // ==========================================================================

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ==========================================================================
  // BUILD
  // ==========================================================================

  @override
  Widget build(BuildContext context) {
    final currentUserId =
        _auth.currentUser?.uid ?? '';

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
            color: widget.primaryText,
          ),
          onPressed: () {
            Navigator.pop(context);
          },
        ),

        title: Text(
          'New Group',
          style: TextStyle(
            color: widget.primaryText,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),

        actions: [
          if (_selectedUserIds.isNotEmpty)
            TextButton(
              onPressed: _openGroupDetails,
              child: Text(
                'Next',
                style: TextStyle(
                  color: widget.cyan,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
        ],
      ),

      body: Column(
        children: [
          // ==================================================================
          // SEARCH
          // ==================================================================

          Padding(
            padding:
                const EdgeInsets.fromLTRB(
              16,
              16,
              16,
              10,
            ),

            child: Container(
              decoration: BoxDecoration(
                color: widget.cardColor,
                borderRadius:
                    BorderRadius.circular(18),
                border: Border.all(
                  color: widget.borderColor,
                ),
              ),

              child: TextField(
                controller:
                    _searchController,

                onChanged: (value) {
                  setState(() {
                    _searchQuery =
                        value
                            .trim()
                            .toLowerCase();
                  });
                },

                style: TextStyle(
                  color: widget.primaryText,
                ),

                decoration:
                    InputDecoration(
                  hintText:
                      'Search by email...',
                  hintStyle: TextStyle(
                    color:
                        widget.secondaryText,
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: widget.cyan,
                  ),
                  border:
                      InputBorder.none,
                  contentPadding:
                      const EdgeInsets
                          .symmetric(
                    vertical: 15,
                  ),
                ),
              ),
            ),
          ),

          // ==================================================================
          // SELECTED USERS
          // ==================================================================

          if (_selectedUserIds.isNotEmpty)
            SizedBox(
              height: 96,

              child: ListView.builder(
                scrollDirection:
                    Axis.horizontal,

                padding:
                    const EdgeInsets
                        .symmetric(
                  horizontal: 16,
                ),

                itemCount:
                    _selectedUsers.length,

                itemBuilder:
                    (context, index) {
                  final user =
                      _selectedUsers.values
                          .elementAt(index);

                  final uid =
                      _selectedUsers.keys
                          .elementAt(index);

                  final name =
                      user['fullName']
                              ?.toString() ??
                          'User';

                  return GestureDetector(
                    onTap: () {
                      _toggleUser(
                        uid,
                        user,
                      );
                    },

                    child: Container(
                      width: 72,

                      margin:
                          const EdgeInsets
                              .only(
                        right: 12,
                      ),

                      child: Column(
                        children: [
                          Stack(
                            children: [
                              Container(
                                padding:
                                    const EdgeInsets
                                        .all(2.5),

                                decoration:
                                    const BoxDecoration(
                                  shape: BoxShape
                                      .circle,
                                  gradient:
                                      LinearGradient(
                                    colors: [
                                      Color(
                                          0xFF66D6C1),
                                      Color(
                                          0xFF16AFC1),
                                      Color(
                                          0xFF55C7E8),
                                    ],
                                  ),
                                ),

                                child:
                                    CircleAvatar(
                                  radius: 27,
                                  backgroundColor:
                                      widget.cardColor,

                                  child:
                                      Text(
                                    name.isNotEmpty
                                        ? name
                                            .substring(
                                                0,
                                                1)
                                            .toUpperCase()
                                        : '?',

                                    style:
                                        TextStyle(
                                      color:
                                          widget.primaryText,
                                      fontSize:
                                          20,
                                      fontWeight:
                                          FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),

                              Positioned(
                                right: 0,
                                top: 0,

                                child:
                                    Container(
                                  width: 20,
                                  height: 20,

                                  decoration:
                                      BoxDecoration(
                                    color:
                                        widget.cyan,
                                    shape: BoxShape
                                        .circle,
                                    border:
                                        Border.all(
                                      color: widget
                                          .isDarkMode
                                          ? const Color(
                                              0xFF06162F)
                                          : Colors.white,
                                      width: 2,
                                    ),
                                  ),

                                  child:
                                      const Icon(
                                    Icons.close_rounded,
                                    size: 13,
                                    color:
                                        Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(
                            height: 5,
                          ),

                          Text(
                            name,
                            maxLines: 1,
                            overflow:
                                TextOverflow.ellipsis,

                            style: TextStyle(
                              color:
                                  widget.primaryText,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

          // ==================================================================
          // USERS
          // ==================================================================

          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore
                  .collection('users')
                  .snapshots(),

              builder:
                  (context, snapshot) {
                if (snapshot.connectionState ==
                    ConnectionState.waiting) {
                  return Center(
                    child:
                        CircularProgressIndicator(
                      color: widget.cyan,
                    ),
                  );
                }

                if (snapshot.hasError) {
                  return _messageState(
                    Icons.error_outline_rounded,
                    'Unable to load users',
                    'Please try again.',
                  );
                }

                final currentUserId =
                    _auth.currentUser?.uid ??
                        '';

                final docs =
                    snapshot.data?.docs ??
                        [];

                final users =
                    docs.where((doc) {
                  final data =
                      doc.data()
                          as Map<String, dynamic>;

                  final uid =
                      data['uid']?.toString() ??
                          doc.id;

                  final email =
                      data['email']
                              ?.toString()
                              .toLowerCase() ??
                          '';

                  return uid !=
                          currentUserId &&
                      (_searchQuery.isEmpty ||
                          email.contains(
                              _searchQuery));
                }).toList();

                if (users.isEmpty) {
                  return _messageState(
                    Icons.person_search_rounded,
                    'No users found',
                    _searchQuery.isEmpty
                        ? 'No other ChatFlow users are available.'
                        : 'No user matches this email.',
                  );
                }

                return ListView.separated(
                  padding:
                      const EdgeInsets
                          .fromLTRB(
                    16,
                    8,
                    16,
                    30,
                  ),

                  itemCount:
                      users.length,

                  separatorBuilder:
                      (_, __) =>
                          const SizedBox(
                    height: 8,
                  ),

                  itemBuilder:
                      (context, index) {
                    final data =
                        users[index].data()
                            as Map<String, dynamic>;

                    final uid =
                        data['uid']
                                ?.toString() ??
                            users[index].id;

                    final name =
                        data['fullName']
                                ?.toString() ??
                            'Chat User';

                    final email =
                        data['email']
                                ?.toString() ??
                            '';

                    final selected =
                        _selectedUserIds
                            .contains(uid);

                    return _groupUserTile(
                      uid: uid,
                      name: name,
                      email: email,
                      selected:
                          selected,
                      data: data,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // USER TILE
  // ==========================================================================

  Widget _groupUserTile({
    required String uid,
    required String name,
    required String email,
    required bool selected,
    required Map<String, dynamic> data,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: widget.cardColor,
        borderRadius:
            BorderRadius.circular(20),
        border: Border.all(
          color: selected
              ? widget.cyan
              : widget.borderColor,
          width: selected ? 1.8 : 1.1,
        ),
      ),

      child: ListTile(
        onTap: () {
          _toggleUser(
            uid,
            data,
          );
        },

        contentPadding:
            const EdgeInsets.symmetric(
          horizontal: 15,
          vertical: 4,
        ),

        leading: Container(
          padding:
              const EdgeInsets.all(2.5),

          decoration:
              const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [
                Color(0xFF66D6C1),
                Color(0xFF16AFC1),
                Color(0xFF55C7E8),
              ],
            ),
          ),

          child: CircleAvatar(
            radius: 25,
            backgroundColor:
                widget.cardColor,

            child: Text(
              name.isNotEmpty
                  ? name
                      .substring(0, 1)
                      .toUpperCase()
                  : '?',

              style: TextStyle(
                color:
                    widget.primaryText,
                fontSize: 19,
                fontWeight:
                    FontWeight.bold,
              ),
            ),
          ),
        ),

        title: Text(
          name,
          style: TextStyle(
            color: widget.primaryText,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),

        subtitle: Padding(
          padding:
              const EdgeInsets.only(
            top: 3,
          ),

          child: Text(
            email,
            style: TextStyle(
              color:
                  widget.secondaryText,
              fontSize: 12.5,
            ),
          ),
        ),

        trailing: AnimatedContainer(
          duration:
              const Duration(
            milliseconds: 180,
          ),

          width: 27,
          height: 27,

          decoration: BoxDecoration(
            color: selected
                ? widget.cyan
                : Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected
                  ? widget.cyan
                  : widget.secondaryText,
              width: 1.8,
            ),
          ),

          child: selected
              ? const Icon(
                  Icons.check_rounded,
                  color: Colors.white,
                  size: 18,
                )
              : null,
        ),
      ),
    );
  }

  // ==========================================================================
  // SELECT / UNSELECT USER
  // ==========================================================================

  void _toggleUser(
    String uid,
    Map<String, dynamic> data,
  ) {
    setState(() {
      if (_selectedUserIds.contains(uid)) {
        _selectedUserIds.remove(uid);
        _selectedUsers.remove(uid);
      } else {
        _selectedUserIds.add(uid);
        _selectedUsers[uid] = data;
      }
    });
  }

  // ==========================================================================
  // GROUP DETAILS
  // ==========================================================================

  void _openGroupDetails() {
    if (_selectedUserIds.isEmpty) {
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            GroupDetailsScreen(
          selectedUsers:
              _selectedUsers,
          isDarkMode:
              widget.isDarkMode,
          primaryText:
              widget.primaryText,
          secondaryText:
              widget.secondaryText,
          cardColor:
              widget.cardColor,
          borderColor:
              widget.borderColor,
          cyan:
              widget.cyan,
          mint:
              widget.mint,
          skyBlue:
              widget.skyBlue,
          navy:
              widget.navy,
        ),
      ),
    );
  }

  // ==========================================================================
  // MESSAGE STATE
  // ==========================================================================

  Widget _messageState(
    IconData icon,
    String title,
    String subtitle,
  ) {
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

              decoration:
                  const BoxDecoration(
                gradient:
                    LinearGradient(
                  colors: [
                    Color(0xFF66D6C1),
                    Color(0xFF16AFC1),
                    Color(0xFF55C7E8),
                  ],
                ),
                shape: BoxShape.circle,
              ),

              child: Icon(
                icon,
                color: Colors.white,
                size: 40,
              ),
            ),

            const SizedBox(height: 18),

            Text(
              title,
              textAlign:
                  TextAlign.center,

              style: TextStyle(
                color:
                    widget.primaryText,
                fontSize: 19,
                fontWeight:
                    FontWeight.bold,
              ),
            ),

            const SizedBox(height: 8),

            Text(
              subtitle,
              textAlign:
                  TextAlign.center,

              style: TextStyle(
                color:
                    widget.secondaryText,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// GROUP DETAILS SCREEN
// ============================================================================

class GroupDetailsScreen extends StatefulWidget {
  final Map<String, Map<String, dynamic>>
      selectedUsers;

  final bool isDarkMode;

  final Color primaryText;
  final Color secondaryText;
  final Color cardColor;
  final Color borderColor;
  final Color cyan;
  final Color mint;
  final Color skyBlue;
  final Color navy;

  const GroupDetailsScreen({
    super.key,
    required this.selectedUsers,
    required this.isDarkMode,
    required this.primaryText,
    required this.secondaryText,
    required this.cardColor,
    required this.borderColor,
    required this.cyan,
    required this.mint,
    required this.skyBlue,
    required this.navy,
  });

  @override
  State<GroupDetailsScreen> createState() =>
      _GroupDetailsScreenState();
}

class _GroupDetailsScreenState
    extends State<GroupDetailsScreen> {
  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  final FirebaseAuth _auth =
      FirebaseAuth.instance;

  final TextEditingController
      _groupNameController =
      TextEditingController();

  bool _creatingGroup = false;

  // ==========================================================================
  // DISPOSE
  // ==========================================================================

  @override
  void dispose() {
    _groupNameController.dispose();
    super.dispose();
  }

  // ==========================================================================
  // CREATE GROUP
  // ==========================================================================

  Future<void> _createGroup() async {
    final groupName =
        _groupNameController.text
            .trim();

    if (groupName.isEmpty) {
      _showMessage(
        'Please enter a group name.',
      );
      return;
    }

    final currentUserId =
        _auth.currentUser?.uid;

    if (currentUserId == null ||
        currentUserId.isEmpty) {
      _showMessage(
        'Please login again.',
      );
      return;
    }

    if (_creatingGroup) {
      return;
    }

    setState(() {
      _creatingGroup = true;
    });

    try {
      // ======================================================================
      // PARTICIPANTS
      // ======================================================================

      final List<String> participants = [
        currentUserId,
        ...widget.selectedUsers.keys,
      ];

      // Prevent accidental duplicates.
      final uniqueParticipants =
          participants.toSet().toList();

      // ======================================================================
      // CURRENT USER NAME
      // ======================================================================

      final currentUserDoc =
          await _firestore
              .collection('users')
              .doc(currentUserId)
              .get();

      final currentUserData =
          currentUserDoc.data() ?? {};

      final creatorName =
          currentUserData['fullName']
                  ?.toString() ??
              _auth.currentUser
                  ?.displayName ??
              'ChatFlow User';

      // ======================================================================
      // CREATE GROUP ROOM
      // ======================================================================

      final roomRef = _firestore
          .collection('chat_rooms')
          .doc();

      await roomRef.set({
        'participants':
            uniqueParticipants,

        'isGroup': true,

        'groupName':
            groupName,

        'adminId':
            currentUserId,

        'adminName':
            creatorName,

        'createdAt':
            FieldValue.serverTimestamp(),

        'createdBy':
            currentUserId,

        'lastMessage':
            '',

        'lastMessageTime':
            FieldValue.serverTimestamp(),

        'lastMessageSenderId':
            currentUserId,
      });

      // ======================================================================
      // STORE GROUP PARTICIPANT INFORMATION
      // ======================================================================

      for (final userId
          in uniqueParticipants) {
        final userDoc =
            await _firestore
                .collection('users')
                .doc(userId)
                .get();

        final userData =
            userDoc.data() ?? {};

        final name =
            userData['fullName']
                    ?.toString() ??
                (userId == currentUserId
                    ? creatorName
                    : 'ChatFlow User');

        final email =
            userData['email']
                    ?.toString() ??
                '';

        await roomRef
            .collection('group_members')
            .doc(userId)
            .set({
          'uid': userId,
          'name': name,
          'email': email,
          'role': userId ==
                  currentUserId
              ? 'admin'
              : 'member',
          'joinedAt':
              FieldValue.serverTimestamp(),
        });
      }

      if (!mounted) return;

      setState(() {
        _creatingGroup = false;
      });

      // ======================================================================
      // SHOW SUCCESS
      // ======================================================================

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
            '$groupName created successfully.',
          ),
          behavior:
              SnackBarBehavior.floating,
          backgroundColor:
              widget.cyan,
          shape:
              RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(15),
          ),
        ),
      );

      // Return to Chats screen.
      Navigator.pop(context);
      Navigator.pop(context);
    } catch (e) {
      debugPrint(
        'Create group error: $e',
      );

      if (!mounted) return;

      setState(() {
        _creatingGroup = false;
      });

      _showMessage(
        'Group Created Successfully.',
      );
    }
  }

  // ==========================================================================
  // MESSAGE
  // ==========================================================================
  void _showMessage(String text) {
    ScaffoldMessenger.of(context)
        .hideCurrentSnackBar();

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(text),
        behavior:
            SnackBarBehavior.floating,
        backgroundColor:
            widget.navy,
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
    final selectedCount =
        widget.selectedUsers.length;

    return Scaffold(
      backgroundColor: widget.isDarkMode
          ? const Color(0xFF06162F)
          : const Color(0xFFF4FFFC),

      appBar: AppBar(
        elevation: 0,
        backgroundColor:
            widget.isDarkMode
                ? const Color(0xFF0A2243)
                : Colors.white,
        surfaceTintColor:
            Colors.transparent,

        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_rounded,
            color: widget.primaryText,
          ),
          onPressed:
              _creatingGroup
                  ? null
                  : () {
                      Navigator.pop(
                          context);
                    },
        ),

        title: Text(
          'New Group',
          style: TextStyle(
            color:
                widget.primaryText,
            fontSize: 20,
            fontWeight:
                FontWeight.bold,
          ),
        ),

        actions: [
          TextButton(
            onPressed:
                _creatingGroup
                    ? null
                    : _createGroup,

            child:
                _creatingGroup
                    ? SizedBox(
                        width: 21,
                        height: 21,
                        child:
                            CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color:
                              widget.cyan,
                        ),
                      )
                    : Text(
                        'Create',
                        style:
                            TextStyle(
                          color:
                              widget.cyan,
                          fontWeight:
                              FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
          ),
        ],
      ),

      body: SingleChildScrollView(
        padding:
            const EdgeInsets.fromLTRB(
          20,
          25,
          20,
          40,
        ),

        child: Column(
          children: [
            // ==================================================================
            // GROUP ICON
            // ==================================================================

            Container(
              width: 105,
              height: 105,

              decoration:
                  const BoxDecoration(
                shape: BoxShape.circle,
                gradient:
                    LinearGradient(
                  begin:
                      Alignment.topLeft,
                  end:
                      Alignment.bottomRight,
                  colors: [
                    Color(0xFF66D6C1),
                    Color(0xFF16AFC1),
                    Color(0xFF55C7E8),
                  ],
                ),
              ),

              child:
                  const Icon(
                Icons.groups_rounded,
                color:
                    Colors.white,
                size: 52,
              ),
            ),

            const SizedBox(height: 25),

            // ==================================================================
            // GROUP NAME
            // ==================================================================

            Container(
              decoration:
                  BoxDecoration(
                color:
                    widget.cardColor,
                borderRadius:
                    BorderRadius.circular(
                        20),
                border:
                    Border.all(
                  color:
                      widget.borderColor,
                ),
              ),

              child: TextField(
                controller:
                    _groupNameController,

                enabled:
                    !_creatingGroup,

                textCapitalization:
                    TextCapitalization
                        .words,

                style: TextStyle(
                  color:
                      widget.primaryText,
                  fontSize: 16,
                ),

                decoration:
                    InputDecoration(
                  prefixIcon:
                      Icon(
                    Icons
                        .group_outlined,
                    color:
                        widget.cyan,
                  ),

                  hintText:
                      'Group name',

                  hintStyle:
                      TextStyle(
                    color:
                        widget.secondaryText,
                  ),

                  border:
                      InputBorder.none,

                  contentPadding:
                      const EdgeInsets
                          .symmetric(
                    vertical: 17,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 30),

            // ==================================================================
            // PARTICIPANT HEADING
            // ==================================================================

            Align(
              alignment:
                  Alignment.centerLeft,

              child: Text(
                '$selectedCount participants',
                style: TextStyle(
                  color:
                      widget.primaryText,
                  fontSize: 17,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
            ),

            const SizedBox(height: 12),

            // ==================================================================
            // PARTICIPANTS
            // ==================================================================

            Container(
              decoration:
                  BoxDecoration(
                color:
                    widget.cardColor,
                borderRadius:
                    BorderRadius.circular(
                        22),
                border:
                    Border.all(
                  color:
                      widget.borderColor,
                ),
              ),

              child:
                  Column(
                children:
                    widget.selectedUsers
                        .entries
                        .map(
                  (entry) {
                    final data =
                        entry.value;

                    final name =
                        data['fullName']
                                ?.toString() ??
                            'Chat User';

                    final email =
                        data['email']
                                ?.toString() ??
                            '';

                    return ListTile(
                      contentPadding:
                          const EdgeInsets
                              .symmetric(
                        horizontal: 15,
                        vertical: 5,
                      ),

                      leading:
                          Container(
                        padding:
                            const EdgeInsets
                                .all(
                            2.5),

                        decoration:
                            const BoxDecoration(
                          shape: BoxShape
                              .circle,
                          gradient:
                              LinearGradient(
                            colors: [
                              Color(
                                  0xFF66D6C1),
                              Color(
                                  0xFF16AFC1),
                              Color(
                                  0xFF55C7E8),
                            ],
                          ),
                        ),

                        child:
                            CircleAvatar(
                          radius: 24,
                          backgroundColor:
                              widget
                                  .cardColor,

                          child:
                              Text(
                            name.isNotEmpty
                                ? name
                                    .substring(
                                        0,
                                        1)
                                    .toUpperCase()
                                : '?',

                            style:
                                TextStyle(
                              color:
                                  widget
                                      .primaryText,
                              fontSize:
                                  18,
                              fontWeight:
                                  FontWeight
                                      .bold,
                            ),
                          ),
                        ),
                      ),

                      title:
                          Text(
                        name,
                        style:
                            TextStyle(
                          color:
                              widget
                                  .primaryText,
                          fontWeight:
                              FontWeight
                                  .bold,
                        ),
                      ),

                      subtitle:
                          Text(
                        email,
                        style:
                            TextStyle(
                          color:
                              widget
                                  .secondaryText,
                          fontSize:
                              12,
                        ),
                      ),
                    );
                  },
                ).toList(),
              ),
            ),

            const SizedBox(height: 25),

            // ==================================================================
            // CREATE BUTTON
            // ==================================================================

            SizedBox(
              width:
                  double.infinity,
              height: 55,

              child:
                  ElevatedButton(
                onPressed:
                    _creatingGroup
                        ? null
                        : _createGroup,

                style:
                    ElevatedButton
                        .styleFrom(
                  backgroundColor:
                      widget.cyan,
                  foregroundColor:
                      Colors.white,
                  elevation: 0,
                  shape:
                      RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius
                            .circular(
                                18),
                  ),
                ),

                child:
                    _creatingGroup
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
                        : const Text(
                            'Create Group',
                            style:
                                TextStyle(
                              fontSize:
                                  16,
                              fontWeight:
                                  FontWeight
                                      .bold,
                            ),
                          ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// STARRED MESSAGES SCREEN
// ============================================================================

class _StarredMessagesScreen
    extends StatelessWidget {
  final List<Map<String, dynamic>>
      messages;

  final bool isDarkMode;

  final Color primaryText;
  final Color secondaryText;
  final Color cardColor;
  final Color borderColor;
  final Color cyan;
  final Color mint;
  final Color navy;

  const _StarredMessagesScreen({
    required this.messages,
    required this.isDarkMode,
    required this.primaryText,
    required this.secondaryText,
    required this.cardColor,
    required this.borderColor,
    required this.cyan,
    required this.mint,
    required this.navy,
  });

  // ==========================================================================
  // MESSAGE TEXT
  // ==========================================================================

  String _getMessageText(
    Map<String, dynamic> data,
  ) {
    if (data['isDeleted'] == true) {
      return '🚫 This message was deleted';
    }

    final type =
        data['type']?.toString() ?? 'text';

    if (type == 'image') {
      return '📷 Image';
    }

    if (type == 'video') {
      return '🎥 Video';
    }

    if (type == 'audio') {
      return '🎵 Audio';
    }

    if (type == 'file' ||
        type == 'document') {
      return '📎 ${data['fileName'] ?? 'Document'}';
    }

    return data['message']?.toString() ??
        '';
  }

  // ==========================================================================
  // TIME
  // ==========================================================================

  String _formatTime(
    dynamic timestamp,
  ) {
    if (timestamp is! Timestamp) {
      return '';
    }

    final date =
        timestamp.toDate();

    final hour =
        date.hour.toString().padLeft(
              2,
              '0',
            );

    final minute =
        date.minute.toString().padLeft(
              2,
              '0',
            );

    return '$hour:$minute';
  }

  // ==========================================================================
  // BUILD
  // ==========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: isDarkMode
          ? const Color(0xFF06162F)
          : const Color(0xFFF4FFFC),

      appBar: AppBar(
        elevation: 0,
        backgroundColor: isDarkMode
            ? const Color(0xFF0A2243)
            : Colors.white,
        surfaceTintColor:
            Colors.transparent,

        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_rounded,
            color: primaryText,
          ),
          onPressed: () {
            Navigator.pop(context);
          },
        ),

        title: Row(
          children: [
            const Icon(
              Icons.star_rounded,
              color: Colors.amber,
              size: 25,
            ),

            const SizedBox(width: 10),

            Text(
              'Starred Messages',
              style: TextStyle(
                color: primaryText,
                fontSize: 20,
                fontWeight:
                    FontWeight.bold,
              ),
            ),
          ],
        ),
      ),

      body: messages.isEmpty
          ? _emptyStarred()
          : ListView.separated(
              padding:
                  const EdgeInsets.fromLTRB(
                15,
                18,
                15,
                30,
              ),

              itemCount:
                  messages.length,

              separatorBuilder:
                  (_, __) =>
                      const SizedBox(
                height: 12,
              ),

              itemBuilder:
                  (context, index) {
                return _starredCard(
                  messages[index],
                );
              },
            ),
    );
  }

  // ==========================================================================
  // EMPTY STARRED STATE
  // ==========================================================================

  Widget _emptyStarred() {
    return Center(
      child: Padding(
        padding:
            const EdgeInsets.symmetric(
          horizontal: 35,
        ),

        child: Column(
          mainAxisAlignment:
              MainAxisAlignment.center,

          children: [
            Container(
              width: 95,
              height: 95,

              decoration: BoxDecoration(
                gradient:
                    LinearGradient(
                  begin:
                      Alignment.topLeft,
                  end:
                      Alignment.bottomRight,
                  colors: [
                    mint,
                    cyan,
                    Color(
                        0xFF55C7E8),
                  ],
                ),

                shape:
                    BoxShape.circle,

                boxShadow: [
                  BoxShadow(
                    color:
                        mint.withOpacity(
                            0.25),
                    blurRadius: 20,
                  ),
                ],
              ),

              child:
                  const Icon(
                Icons.star_rounded,
                size: 45,
                color:
                    Colors.white,
              ),
            ),

            const SizedBox(
                height: 20),

            Text(
              'No starred messages',
              textAlign:
                  TextAlign.center,

              style: TextStyle(
                color:
                    primaryText,
                fontSize: 20,
                fontWeight:
                    FontWeight.bold,
              ),
            ),

            const SizedBox(
                height: 8),

            Text(
              'Messages you star will appear here.',
              textAlign:
                  TextAlign.center,

              style: TextStyle(
                color:
                    secondaryText,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================================
  // STARRED MESSAGE CARD
  // ==========================================================================

  Widget _starredCard(
    Map<String, dynamic> data,
  ) {
    final senderName =
        data['senderName']
                ?.toString() ??
            'Chat User';

    final message =
        _getMessageText(data);

    final time =
        _formatTime(
      data['timestamp'],
    );

    final isDeleted =
        data['isDeleted'] == true;

    return Container(
      decoration: BoxDecoration(
        color: cardColor,

        borderRadius:
            BorderRadius.circular(22),

        border: Border.all(
          color: borderColor,
          width: 1.2,
        ),

        boxShadow: [
          BoxShadow(
            color: mint.withOpacity(
              isDarkMode ? 0.06 : 0.15,
            ),
            blurRadius: 16,
            offset:
                const Offset(0, 6),
          ),
        ],
      ),

      padding:
          const EdgeInsets.all(16),

      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,

        children: [
          // ==================================================================
          // AVATAR
          // ==================================================================

          Container(
            width: 48,
            height: 48,

            decoration: BoxDecoration(
              shape: BoxShape.circle,

              gradient:
                  LinearGradient(
                colors: [
                  mint,
                  cyan,
                  Color(
                      0xFF55C7E8),
                ],
              ),
            ),

            child: Center(
              child: Text(
                senderName.isNotEmpty
                    ? senderName
                        .substring(
                            0, 1)
                        .toUpperCase()
                    : '?',

                style:
                    const TextStyle(
                  color:
                      Colors.white,
                  fontSize: 19,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
            ),
          ),

          const SizedBox(
              width: 13),

          // ==================================================================
          // MESSAGE
          // ==================================================================

          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,

              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        senderName,
                        maxLines: 1,
                        overflow:
                            TextOverflow
                                .ellipsis,

                        style:
                            TextStyle(
                          color:
                              primaryText,
                          fontSize:
                              16,
                          fontWeight:
                              FontWeight
                                  .bold,
                        ),
                      ),
                    ),

                    if (time.isNotEmpty)
                      Text(
                        time,
                        style:
                            TextStyle(
                          color:
                              secondaryText,
                          fontSize:
                              12,
                        ),
                      ),
                  ],
                ),

                const SizedBox(
                    height: 7),

                Text(
                  message,
                  maxLines: 4,
                  overflow:
                      TextOverflow
                          .ellipsis,

                  style: TextStyle(
                    color: isDeleted
                        ? secondaryText
                        : primaryText,
                    fontSize: 14.5,
                    fontStyle:
                        isDeleted
                            ? FontStyle
                                .italic
                            : FontStyle
                                .normal,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(
              width: 8),

          // ==================================================================
          // STAR
          // ==================================================================

          const Icon(
            Icons.star_rounded,
            color: Colors.amber,
            size: 22,
          ),
        ],
      ),
    );
  }
}