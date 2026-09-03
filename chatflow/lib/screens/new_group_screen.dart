// ============================================================================
// FILE PATH: lib/screens/new_group_screen.dart
// ============================================================================

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'chat_room_screen.dart';

class NewGroupScreen extends StatefulWidget {
  const NewGroupScreen({super.key});

  @override
  State<NewGroupScreen> createState() => _NewGroupScreenState();
}

class _NewGroupScreenState extends State<NewGroupScreen> {
  // ==========================================================================
  // CHATFLOW COLORS
  // ==========================================================================

  static const Color navy = Color(0xFF102A5C);
  static const Color skyBlue = Color(0xFF55C7E8);
  static const Color cyan = Color(0xFF16AFC1);
  static const Color mint = Color(0xFF66D6C1);

  // ==========================================================================
  // FIREBASE
  // ==========================================================================

  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  final FirebaseAuth _auth =
      FirebaseAuth.instance;

  // ==========================================================================
  // CONTROLLERS
  // ==========================================================================

  final TextEditingController _searchController =
      TextEditingController();

  final TextEditingController _groupNameController =
      TextEditingController();

  // ==========================================================================
  // STATE
  // ==========================================================================

  final Set<String> _selectedUsers = {};

  bool _isCreating = false;
  bool _isDarkMode = false;
  String _contactDebugInfo = '';

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
    return _isDarkMode ? Colors.white : navy;
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
  // DISPOSE
  // ==========================================================================

  @override
  void dispose() {
    _searchController.dispose();
    _groupNameController.dispose();
    super.dispose();
  }

  // ==========================================================================
  // TOGGLE USER
  // ==========================================================================

  void _toggleUser(String uid) {
    setState(() {
      if (_selectedUsers.contains(uid)) {
        _selectedUsers.remove(uid);
      } else {
        _selectedUsers.add(uid);
      }
    });
  }

  // ==========================================================================
  // GO TO GROUP DETAILS
  // ==========================================================================

  void _goToGroupDetails() {
    if (_selectedUsers.isEmpty) {
      _showSnackbar(
        'Please select at least one participant.',
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _groupDetailsSheet(),
    );
  }

  // ==========================================================================
  // GROUP DETAILS SHEET
  // ==========================================================================

  Widget _groupDetailsSheet() {
    return StatefulBuilder(
      builder: (context, setSheetState) {
        return Container(
          height:
              MediaQuery.of(context).size.height * 0.72,
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius:
                const BorderRadius.vertical(
              top: Radius.circular(28),
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                // ----------------------------------------------------------------
                // HANDLE
                // ----------------------------------------------------------------

                Container(
                  width: 45,
                  height: 5,
                  margin:
                      const EdgeInsets.only(top: 12),
                  decoration: BoxDecoration(
                    color:
                        secondaryText.withOpacity(0.35),
                    borderRadius:
                        BorderRadius.circular(10),
                  ),
                ),

                const SizedBox(height: 18),

                // ----------------------------------------------------------------
                // HEADER
                // ----------------------------------------------------------------

                Padding(
                  padding:
                      const EdgeInsets.symmetric(
                    horizontal: 20,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          Icons.arrow_back_rounded,
                          color: primaryText,
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                        },
                      ),

                      const SizedBox(width: 4),

                      Expanded(
                        child: Text(
                          'New Group',
                          style: TextStyle(
                            color: primaryText,
                            fontSize: 21,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),
                      ),

                      Text(
                        '${_selectedUsers.length} selected',
                        style: const TextStyle(
                          color: cyan,
                          fontWeight:
                              FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                // ----------------------------------------------------------------
                // GROUP IMAGE
                // ----------------------------------------------------------------

                Stack(
                  alignment:
                      Alignment.bottomRight,
                  children: [
                    Container(
                      width: 100,
                      height: 100,
                      decoration:
                          const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient:
                            LinearGradient(
                          colors: [
                            mint,
                            cyan,
                            skyBlue,
                          ],
                        ),
                      ),
                      padding:
                          const EdgeInsets.all(3),
                      child: CircleAvatar(
                        backgroundColor:
                            cardColor,
                        child: Icon(
                          Icons.groups_rounded,
                          size: 48,
                          color: cyan,
                        ),
                      ),
                    ),

                    Container(
                      width: 32,
                      height: 32,
                      decoration:
                          BoxDecoration(
                        color: cyan,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color:
                              backgroundColor,
                          width: 3,
                        ),
                      ),
                      child: const Icon(
                        Icons.camera_alt_rounded,
                        size: 17,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 22),

                // ----------------------------------------------------------------
                // GROUP NAME
                // ----------------------------------------------------------------

                Padding(
                  padding:
                      const EdgeInsets.symmetric(
                    horizontal: 22,
                  ),
                  child: TextField(
                    controller:
                        _groupNameController,
                    onChanged: (_) {
                      setSheetState(() {});
                    },
                    style: TextStyle(
                      color: primaryText,
                      fontSize: 16,
                    ),
                    decoration:
                        InputDecoration(
                      labelText: 'Group name',
                      labelStyle: TextStyle(
                        color: secondaryText,
                      ),
                      prefixIcon:
                          const Icon(
                        Icons.group_outlined,
                        color: cyan,
                      ),
                      filled: true,
                      fillColor: cardColor,
                      enabledBorder:
                          OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(
                          18,
                        ),
                        borderSide:
                            BorderSide(
                          color: borderColor,
                        ),
                      ),
                      focusedBorder:
                          OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(
                          18,
                        ),
                        borderSide:
                            const BorderSide(
                          color: cyan,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),

                const Spacer(),

                // ----------------------------------------------------------------
                // CREATE BUTTON
                // ----------------------------------------------------------------

                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(
                    22,
                    10,
                    22,
                    18,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed:
                          _groupNameController
                                      .text
                                      .trim()
                                      .isEmpty ||
                                  _isCreating
                              ? null
                              : () {
                                  _createGroup();
                                },
                      style:
                          ElevatedButton.styleFrom(
                        backgroundColor: cyan,
                        disabledBackgroundColor:
                            secondaryText
                                .withOpacity(0.25),
                        foregroundColor:
                            Colors.white,
                        elevation: 0,
                        shape:
                            RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(
                            18,
                          ),
                        ),
                      ),
                      child: _isCreating
                          ? const SizedBox(
                              width: 23,
                              height: 23,
                              child:
                                  CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color:
                                    Colors.white,
                              ),
                            )
                          : const Text(
                              'Create Group',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight:
                                    FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ==========================================================================
  // CREATE GROUP
  // ==========================================================================

  Future<void> _createGroup() async {
    final currentUser =
        _auth.currentUser;

    if (currentUser == null) {
      _showSnackbar(
        'Please login again.',
      );
      return;
    }

    final currentUserId =
        currentUser.uid;

    final groupName =
        _groupNameController.text.trim();

    if (groupName.isEmpty) {
      _showSnackbar(
        'Please enter a group name.',
      );
      return;
    }

    if (_selectedUsers.isEmpty) {
      _showSnackbar(
        'Please select at least one participant.',
      );
      return;
    }

    setState(() {
      _isCreating = true;
    });

    try {
      // ========================================================================
      // PARTICIPANTS
      // ========================================================================

      final participants = <String>[
        currentUserId,
        ..._selectedUsers.where(
          (uid) => uid != currentUserId,
        ),
      ];

      // ========================================================================
      // CREATE UNIQUE GROUP ROOM
      // ========================================================================

      final roomRef =
          _firestore.collection('chat_rooms').doc();

      // ========================================================================
      // GET CREATOR INFORMATION
      // ========================================================================

      final currentUserDoc =
          await _firestore
              .collection('users')
              .doc(currentUserId)
              .get();

      final currentUserData =
          currentUserDoc.data() ??
              <String, dynamic>{};

      final creatorName =
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
                  ? currentUser.displayName!
                      .trim()
                  : 'ChatFlow User';

      // ========================================================================
      // CREATE GROUP ROOM
      // ========================================================================

      await roomRef.set({
        'chatRoomId': roomRef.id,

        'type': 'group',
        'isGroup': true,

        'groupName': groupName,

        'participants': participants,

        'adminIds': [
          currentUserId,
        ],

        'createdBy': currentUserId,
        'createdByName': creatorName,

        'createdAt':
            FieldValue.serverTimestamp(),
        'updatedAt':
            FieldValue.serverTimestamp(),

        'lastMessage': '',
        'lastMessageTime': null,
        'lastMessageSenderId': '',
      });

      // ========================================================================
      // CREATE SYSTEM MESSAGE
      // ========================================================================

      final messageRef =
          roomRef.collection('messages').doc();

      await messageRef.set({
        'senderId': currentUserId,
        'senderName': creatorName,

        'message':
            '$creatorName created the group "$groupName"',

        'type': 'system',

        'timestamp':
            FieldValue.serverTimestamp(),

        'isDeleted': false,
        'isStarred': false,
      });

      // ========================================================================
      // UPDATE ROOM LAST MESSAGE
      // ========================================================================

      await roomRef.update({
        'lastMessage':
            '$creatorName created the group',
        'lastMessageSenderId':
            currentUserId,
        'lastMessageTime':
            FieldValue.serverTimestamp(),
        'updatedAt':
            FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      Navigator.pop(context);

      if (!mounted) return;

      // ========================================================================
      // OPEN GROUP CHAT (UPDATED SAFE NAVIGATION)
      // ========================================================================

      if (!mounted) return;

      // 1. Capture the parent Navigator BEFORE popping the modal bottom sheet
      final navigator = Navigator.of(context);

      // 2. Close the Modal Bottom Sheet
      navigator.pop();

      // 3. Push the ChatRoomScreen onto the primary navigator stack
      navigator.pushReplacement(
        MaterialPageRoute(
          builder: (_) => ChatRoomScreen(
            targetUserName: groupName,
            targetUserId: '',
            isGroup: true,
            groupId: roomRef.id,
            groupName: groupName,
            groupMembers: participants,
          ),
        ),
      );
    } catch (e) {
      debugPrint(
        'Create group error: $e',
      );


      if (!mounted) return;

      setState(() {
        _isCreating = false;
      });

      _showSnackbar(
        'Group created successully',
      );
    }
  }
  // ==========================================================================
// SNACKBAR
// ==========================================================================

void _showSnackbar(String message) {
  if (!mounted) return;

  ScaffoldMessenger.of(context).hideCurrentSnackBar();

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      backgroundColor:
          _isDarkMode ? navy : const Color(0xFF173B68),
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
    final currentUserId =
        _auth.currentUser?.uid ?? '';

    return Scaffold(
      backgroundColor: backgroundColor,

      // ========================================================================
      // APP BAR
      // ========================================================================

      appBar: AppBar(
        elevation: 0,
        backgroundColor:
            _isDarkMode
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

        title: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Text(
              'New Group',
              style: TextStyle(
                color: primaryText,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              _selectedUsers.isEmpty
                  ? 'Add participants'
                  : '${_selectedUsers.length} selected',
              style: TextStyle(
                color: secondaryText,
                fontSize: 12,
              ),
            ),
          ],
        ),

        actions: [
          TextButton(
            onPressed:
                _selectedUsers.isEmpty
                    ? null
                    : _goToGroupDetails,
            child: Text(
              'Next',
              style: TextStyle(
                color:
                    _selectedUsers.isEmpty
                        ? secondaryText
                        : cyan,
                fontSize: 15,
                fontWeight:
                    FontWeight.bold,
              ),
            ),
          ),
        ],
      ),

      // ========================================================================
      // BODY
      // ========================================================================

      body: Column(
        children: [
          // ======================================================================
          // SEARCH
          // ======================================================================

          Padding(
            padding:
                const EdgeInsets.fromLTRB(
              15,
              15,
              15,
              10,
            ),
            child: TextField(
              controller:
                  _searchController,
              style: TextStyle(
                color: primaryText,
              ),
              decoration:
                  InputDecoration(
                hintText:
                    'Search by email...',
                hintStyle: TextStyle(
                  color: secondaryText,
                ),
                prefixIcon:
                    const Icon(
                  Icons.search_rounded,
                  color: cyan,
                ),
                filled: true,
                fillColor: cardColor,
                border:
                    OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(
                    18,
                  ),
                  borderSide:
                      BorderSide.none,
                ),
              ),
              onChanged: (_) {
                setState(() {});
              },
            ),
          ),

          if (_contactDebugInfo.isNotEmpty)
  Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: 15,
      vertical: 5,
    ),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        _contactDebugInfo,
        style: const TextStyle(
          fontSize: 11,
          color: Colors.orange,
        ),
      ),
    ),
  ),

          // ======================================================================
          // SELECTED USERS
          // ======================================================================

          if (_selectedUsers.isNotEmpty)
            _selectedUsersSection(),

// ==========================================================================
// ACCEPTED CONTACTS
// ==========================================================================

Expanded(
  child: StreamBuilder<QuerySnapshot>(
    stream: _firestore
        .collection('chat_rooms')
        .where(
          'participants',
          arrayContains: currentUserId,
        )
        .snapshots(),

    builder: (context, roomSnapshot) {
      // ----------------------------------------------------------------------
      // LOADING
      // ----------------------------------------------------------------------

      if (roomSnapshot.connectionState ==
          ConnectionState.waiting) {
        return const Center(
          child: CircularProgressIndicator(
            color: cyan,
          ),
        );
      }

      // ----------------------------------------------------------------------
      // ERROR
      // ----------------------------------------------------------------------

      if (roomSnapshot.hasError) {
        return _emptyState(
          Icons.error_outline_rounded,
          'Unable to load contacts',
          'Please try again.',
        );
      }

      // ----------------------------------------------------------------------
      // FIND ACCEPTED CONTACTS
      // ----------------------------------------------------------------------

      final acceptedContactIds = <String>{};

      final rooms =
          roomSnapshot.data?.docs ?? [];

      for (final room in rooms) {
        final data =
            room.data() as Map<String, dynamic>;

        // ====================================================================
        // NEVER USE GROUP ROOMS AS CONTACT RELATIONSHIPS
        // ====================================================================

        final isGroup =
            data['isGroup'] == true ||
            data['type']
                    ?.toString()
                    .toLowerCase() ==
                'group';

        if (isGroup) {
          continue;
        }

        // ====================================================================
        // GET PARTICIPANTS
        // ====================================================================

        final rawParticipants =
            data['participants'];

        if (rawParticipants is! List) {
          continue;
        }

        final participants =
            rawParticipants
                .map((e) => e.toString())
                .where((id) => id.isNotEmpty)
                .toList();

        // ====================================================================
        // FIND THE OTHER USER
        // ====================================================================

        final otherUserIds = participants
            .where(
              (uid) => uid != currentUserId,
            )
            .toList();

        if (otherUserIds.isEmpty) {
          continue;
        }

        final otherUserId =
            otherUserIds.first;

        // ====================================================================
        // CHECK removedBy
        //
        // If the current user has removed this chat, this person MUST NOT
        // appear in New Group.
        // ====================================================================

        final rawRemovedBy =
            data['removedBy'];

        final removedBy =
            rawRemovedBy is List
                ? rawRemovedBy
                    .map(
                      (e) => e.toString(),
                    )
                    .toSet()
                : <String>{};

        if (removedBy.contains(currentUserId)) {
          // This contact was deleted by the current user.
          continue;
        }

        // ====================================================================
        // CONTACT IS STILL ACTIVE
        // ====================================================================

        acceptedContactIds.add(
          otherUserId,
        );
      }

      // ----------------------------------------------------------------------
      // NO ACCEPTED CONTACTS
      // ----------------------------------------------------------------------

      if (acceptedContactIds.isEmpty) {
        return _emptyState(
          Icons.people_outline_rounded,
          'No accepted contacts',
          'Only people you have accepted as chat contacts can be added to a group.',
        );
      }

      // ----------------------------------------------------------------------
      // LOAD USER PROFILES
      // ----------------------------------------------------------------------

      return StreamBuilder<QuerySnapshot>(
        stream: _firestore
            .collection('users')
            .snapshots(),

        builder: (context, userSnapshot) {
          // --------------------------------------------------------------------
          // LOADING
          // --------------------------------------------------------------------

          if (userSnapshot.connectionState ==
              ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(
                color: cyan,
              ),
            );
          }

          // --------------------------------------------------------------------
          // ERROR
          // --------------------------------------------------------------------

          if (userSnapshot.hasError ||
              !userSnapshot.hasData) {
            return _emptyState(
              Icons.error_outline_rounded,
              'Unable to load users',
              'Please try again.',
            );
          }

          // --------------------------------------------------------------------
          // SEARCH
          // --------------------------------------------------------------------

          final searchQuery =
              _searchController.text
                  .trim()
                  .toLowerCase();

          final documents =
              userSnapshot.data!.docs;

          // --------------------------------------------------------------------
          // FILTER USERS
          // --------------------------------------------------------------------

          final users =
              documents.where(
            (doc) {
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

              // Never show current user.
              if (uid == currentUserId) {
                return false;
              }

              // Only show active accepted contacts.
              if (!acceptedContactIds
                  .contains(uid)) {
                return false;
              }

              // Search ONLY by email.
              if (searchQuery.isNotEmpty &&
                  !email.contains(
                    searchQuery,
                  )) {
                return false;
              }

              return true;
            },
          ).toList();

          // --------------------------------------------------------------------
          // NO RESULTS
          // --------------------------------------------------------------------

          if (users.isEmpty) {
            return _emptyState(
              Icons.person_search_rounded,
              searchQuery.isEmpty
                  ? 'No accepted contacts'
                  : 'No contact found',
              searchQuery.isEmpty
                  ? 'Only accepted chat contacts can be added to a group.'
                  : 'No accepted contact matches this email.',
            );
          }

          // --------------------------------------------------------------------
          // USER LIST
          // --------------------------------------------------------------------

          return ListView.separated(
            padding:
                const EdgeInsets.fromLTRB(
              15,
              8,
              15,
              30,
            ),

            itemCount: users.length,

            separatorBuilder: (_, __) =>
                const SizedBox(height: 10),

            itemBuilder: (context, index) {
              final data =
                  users[index].data()
                      as Map<String, dynamic>;

              final uid =
                  data['uid']?.toString() ??
                      users[index].id;

              final name =
                  data['fullName']
                          ?.toString() ??
                      'Chat User';

              final email =
                  data['email']
                          ?.toString() ??
                      '';

              return _userTile(
                uid: uid,
                name: name,
                email: email,
              );
            },
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
  // SELECTED USERS SECTION
  // ==========================================================================

  Widget _selectedUsersSection() {
    return SizedBox(
      height: 105,
      child: StreamBuilder<QuerySnapshot>(
        stream: _firestore
            .collection('users')
            .snapshots(),

        builder:
            (context, snapshot) {
          if (!snapshot.hasData) {
            return const SizedBox();
          }

          final selectedDocs =
              snapshot.data!.docs.where(
            (doc) {
              final data =
                  doc.data()
                      as Map<String, dynamic>;

              final uid =
                  data['uid']?.toString() ??
                      doc.id;

              return _selectedUsers
                  .contains(uid);
            },
          ).toList();

          return ListView.separated(
            scrollDirection:
                Axis.horizontal,

            padding:
                const EdgeInsets.symmetric(
              horizontal: 15,
              vertical: 8,
            ),

            itemCount:
                selectedDocs.length,

            separatorBuilder:
                (_, __) =>
                    const SizedBox(
              width: 12,
            ),

            itemBuilder:
                (context, index) {
              final data =
                  selectedDocs[index]
                          .data()
                      as Map<String, dynamic>;

              final uid =
                  data['uid']
                          ?.toString() ??
                      selectedDocs[index].id;

              final name =
                  data['fullName']
                          ?.toString() ??
                      'User';

              return SizedBox(
                width: 72,
                child: Column(
                  children: [
                    Stack(
                      children: [
                        Container(
                          width: 58,
                          height: 58,
                          decoration:
                              const BoxDecoration(
                            shape:
                                BoxShape.circle,
                            gradient:
                                LinearGradient(
                              colors: [
                                mint,
                                cyan,
                                skyBlue,
                              ],
                            ),
                          ),
                          padding:
                              const EdgeInsets
                                  .all(
                            2.5,
                          ),
                          child:
                              CircleAvatar(
                            backgroundColor:
                                cardColor,
                            child: Text(
                              name.isNotEmpty
                                  ? name
                                      .substring(
                                        0,
                                        1,
                                      )
                                      .toUpperCase()
                                  : '?',
                              style: TextStyle(
                                color:
                                    primaryText,
                                fontWeight:
                                    FontWeight
                                        .bold,
                                fontSize: 20,
                              ),
                            ),
                          ),
                        ),

                        Positioned(
                          right: 0,
                          top: 0,
                          child:
                              GestureDetector(
                            onTap: () {
                              _toggleUser(
                                uid,
                              );
                            },
                            child:
                                Container(
                              width: 21,
                              height: 21,
                              decoration:
                                  const BoxDecoration(
                                color: navy,
                                shape:
                                    BoxShape
                                        .circle,
                              ),
                              child:
                                  const Icon(
                                Icons
                                    .close_rounded,
                                color:
                                    Colors.white,
                                size: 14,
                              ),
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
                          TextOverflow
                              .ellipsis,
                      style: TextStyle(
                        color:
                            primaryText,
                        fontSize: 11,
                        fontWeight:
                            FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  // ==========================================================================
  // USER TILE
  // ==========================================================================

  Widget _userTile({
    required String uid,
    required String name,
    required String email,
  }) {
    final isSelected =
        _selectedUsers.contains(uid);

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius:
            BorderRadius.circular(20),
        border: Border.all(
          color: isSelected
              ? cyan
              : borderColor,
          width:
              isSelected ? 1.5 : 1,
        ),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 5,
        ),

        onTap: () {
          _toggleUser(uid);
        },

        leading: Container(
          width: 50,
          height: 50,
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
          padding:
              const EdgeInsets.all(2.5),

          child: CircleAvatar(
            backgroundColor:
                cardColor,

            child: Text(
              name.isNotEmpty
                  ? name
                      .substring(
                        0,
                        1,
                      )
                      .toUpperCase()
                  : '?',

              style: TextStyle(
                color: primaryText,
                fontSize: 18,
                fontWeight:
                    FontWeight.bold,
              ),
            ),
          ),
        ),

        title: Text(
          name,
          style: TextStyle(
            color: primaryText,
            fontSize: 16,
            fontWeight:
                FontWeight.bold,
          ),
        ),

        subtitle: Padding(
          padding:
              const EdgeInsets.only(
            top: 3,
          ),
          child: Text(
            email,
            maxLines: 1,
            overflow:
                TextOverflow.ellipsis,
            style: TextStyle(
              color:
                  secondaryText,
              fontSize: 13,
            ),
          ),
        ),

        trailing:
            AnimatedContainer(
          duration:
              const Duration(
            milliseconds: 180,
          ),

          width: 27,
          height: 27,

          decoration:
              BoxDecoration(
            shape: BoxShape.circle,
            color: isSelected
                ? cyan
                : Colors.transparent,
            border: Border.all(
              color: isSelected
                  ? cyan
                  : secondaryText
                      .withOpacity(0.5),
              width: 1.5,
            ),
          ),

          child: isSelected
              ? const Icon(
                  Icons.check_rounded,
                  color:
                      Colors.white,
                  size: 18,
                )
              : null,
        ),
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
        ),

        child: Column(
          mainAxisAlignment:
              MainAxisAlignment.center,

          children: [
            Container(
              width: 90,
              height: 90,

              decoration:
                  const BoxDecoration(
                shape:
                    BoxShape.circle,
                gradient:
                    LinearGradient(
                  colors: [
                    mint,
                    cyan,
                    skyBlue,
                  ],
                ),
              ),

              child: Icon(
                icon,
                color:
                    Colors.white,
                size: 42,
              ),
            ),

            const SizedBox(
              height: 20,
            ),

            Text(
              title,
              textAlign:
                  TextAlign.center,
              style: TextStyle(
                color:
                    primaryText,
                fontSize: 19,
                fontWeight:
                    FontWeight.bold,
              ),
            ),

            const SizedBox(
              height: 8,
            ),

            Text(
              subtitle,
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
}