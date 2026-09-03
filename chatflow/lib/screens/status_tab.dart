// ============================================================================
// FILE PATH: lib/screens/status_tab.dart
// ============================================================================
// CORRECTED VERSION — fixes on top of the previous version:
//   1. Post failures (text AND photo) now show a visible error via
//      SnackBar instead of silently doing nothing.
//   2. Fixed broken hex color generation for text status backgrounds.
//   3. The main status feed now surfaces Firestore errors (missing index,
//      permission denied) instead of silently showing an empty list.
// ============================================================================

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/status_service.dart';
import 'status_viewer_screen.dart';

class StatusTab extends StatefulWidget {
  final bool isDarkMode;
  final Color primaryText;
  final Color secondaryText;
  final Color navy;
  final Color mint;
  final Color cyan;
  final Color skyBlue;
  final Widget Function({required Widget child}) sectionCard;
  final Widget Function(String title) sectionHeading;
  final Widget Function(IconData icon, String title, String subtitle)
      emptyState;

  const StatusTab({
    super.key,
    required this.isDarkMode,
    required this.primaryText,
    required this.secondaryText,
    required this.navy,
    required this.mint,
    required this.cyan,
    required this.skyBlue,
    required this.sectionCard,
    required this.sectionHeading,
    required this.emptyState,
  });

  @override
  State<StatusTab> createState() => _StatusTabState();
}

class _StatusTabState extends State<StatusTab> {
  final StatusService _statusService = StatusService.instance;
  final ImagePicker _picker = ImagePicker();

  List<String> _contactIds = [];
  bool _loadingContacts = true;

  String get _myUid => FirebaseAuth.instance.currentUser?.uid ?? '';

  static const List<int> _bgColorPalette = [
    0xFF102A5C,
    0xFF16AFC1,
    0xFF66D6C1,
    0xFFB03A5B,
    0xFF7A4EAB,
    0xFF2C7A4F,
  ];

  @override
  void initState() {
    super.initState();
    _statusService.cleanupExpiredForMe();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    final ids = await _statusService.getContactIds();
    if (!mounted) return;
    setState(() {
      _contactIds = ids;
      _loadingContacts = false;
    });
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ==========================================================================
  // CREATE STATUS SHEET
  // ==========================================================================

  void _showCreateStatusSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor:
          widget.isDarkMode ? const Color(0xFF10284A) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _createOptionTile(
                  icon: Icons.text_fields_rounded,
                  label: 'Text',
                  onTap: () {
                    Navigator.pop(context);
                    _showTextComposer();
                  },
                ),
                _createOptionTile(
                  icon: Icons.photo_camera_rounded,
                  label: 'Camera',
                  onTap: () {
                    Navigator.pop(context);
                    _pickAndPostPhoto(ImageSource.camera);
                  },
                ),
                _createOptionTile(
                  icon: Icons.photo_library_rounded,
                  label: 'Gallery',
                  onTap: () {
                    Navigator.pop(context);
                    _pickAndPostPhoto(ImageSource.gallery);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _createOptionTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor:
                widget.mint.withOpacity(widget.isDarkMode ? 0.15 : 0.22),
            child: Icon(icon, color: widget.cyan, size: 28),
          ),
          const SizedBox(height: 8),
          Text(label,
              style: TextStyle(
                  color: widget.primaryText, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // ==========================================================================
  // TEXT STATUS COMPOSER
  // ==========================================================================

  // FIXED: was producing a malformed hex string before. This now correctly
  // converts an int color (e.g. 0xFF102A5C) into an '0xFF102A5C'-style
  // string that Color(int.parse(...)) can parse back reliably.
  String _colorToHexString(int colorValue) {
    return '0x${colorValue.toRadixString(16).toUpperCase().padLeft(8, '0')}';
  }

  void _showTextComposer() {
    final controller = TextEditingController();
    int selectedColor = _bgColorPalette[0];
    bool isPosting = false;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setPageState) {
              Future<void> handlePost() async {
                if (controller.text.trim().isEmpty || isPosting) return;

                setPageState(() => isPosting = true);

                try {
                  await _statusService.postTextStatus(
                    text: controller.text,
                    backgroundColorHex: _colorToHexString(selectedColor),
                  );

                  if (context.mounted) Navigator.pop(context);
                } catch (e) {
                  setPageState(() => isPosting = false);

                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Unable to post status: ${e.toString()}',
                        ),
                        backgroundColor: Colors.redAccent,
                      ),
                    );
                  }
                }
              }

              return Scaffold(
                backgroundColor: Color(selectedColor),
                appBar: AppBar(
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  actions: [
                    isPosting
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                          )
                        : TextButton(
                            onPressed: handlePost,
                            child: const Text(
                              'Post',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                  ],
                ),
                body: Column(
                  children: [
                    Expanded(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(30),
                          child: TextField(
                            controller: controller,
                            autofocus: true,
                            maxLines: null,
                            maxLength: 150,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w600),
                            decoration: const InputDecoration(
                              hintText: "What's on your mind?",
                              hintStyle: TextStyle(color: Colors.white70),
                              border: InputBorder.none,
                              counterStyle: TextStyle(color: Colors.white54),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 30),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: _bgColorPalette.map((colorValue) {
                          return GestureDetector(
                            onTap: () {
                              setPageState(() => selectedColor = colorValue);
                            },
                            child: Container(
                              margin:
                                  const EdgeInsets.symmetric(horizontal: 6),
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: Color(colorValue),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: selectedColor == colorValue ? 3 : 1,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
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
  // PHOTO STATUS
  // ==========================================================================

  Future<void> _pickAndPostPhoto(ImageSource source) async {
  try {
    final picked = await _picker.pickImage(
      source: source,
      imageQuality: 60,
      maxWidth: 900,
    );

    if (picked == null) return;

    // Cross-platform: works on Android and Web.
    final bytes = await picked.readAsBytes();

    await _statusService.postPhotoStatus(
      imageBytes: bytes,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Status posted.'),
        ),
      );
    }
  } catch (e) {
    _showError(
      'Unable to post status: ${e.toString()}',
    );
  }
}

  // ==========================================================================
  // BUILD
  // ==========================================================================

  @override
  Widget build(BuildContext context) {
    if (_loadingContacts) {
      return const Center(child: CircularProgressIndicator());
    }

    final allRelevantIds = [..._contactIds, _myUid];

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _statusService.streamStatusesFor(allRelevantIds),
      builder: (context, snapshot) {
        // FIXED: previously any Firestore error here (missing index,
        // permission denied) resulted in a silently empty list with no
        // explanation. Now it's shown directly.
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline_rounded,
                      color: Colors.redAccent, size: 40),
                  const SizedBox(height: 12),
                  Text(
                    'Unable to load status updates.',
                    style: TextStyle(
                        color: widget.primaryText,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${snapshot.error}',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(color: widget.secondaryText, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'If this mentions an index, check the Debug Console for '
                    'a link to create it. If it mentions permissions, '
                    'confirm the Firestore Rules for the "statuses" '
                    'collection have been published.',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(color: widget.secondaryText, fontSize: 12),
                  ),
                ],
              ),
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? [];

        final Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>
            grouped = {};

        for (final doc in docs) {
          final userId = doc.data()['userId']?.toString() ?? '';
          grouped.putIfAbsent(userId, () => []).add(doc);
        }

        final myStatuses = grouped[_myUid] ?? [];

        final recentEntries = <MapEntry<String,
            List<QueryDocumentSnapshot<Map<String, dynamic>>>>>[];
        final viewedEntries = <MapEntry<String,
            List<QueryDocumentSnapshot<Map<String, dynamic>>>>>[];

        grouped.forEach((userId, statuses) {
          if (userId == _myUid) return;

          final allViewed = statuses.every((doc) {
            final viewedBy = List<String>.from(doc.data()['viewedBy'] ?? []);
            return viewedBy.contains(_myUid);
          });

          final entry = MapEntry(userId, statuses);
          if (allViewed) {
            viewedEntries.add(entry);
          } else {
            recentEntries.add(entry);
          }
        });

        return ListView(
          padding: const EdgeInsets.all(18),
          children: [
            widget.sectionCard(
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                onTap: myStatuses.isNotEmpty
                    ? () => _openViewer(_myUid, 'You', myStatuses)
                    : _showCreateStatusSheet,
                leading: Stack(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: myStatuses.isNotEmpty
                              ? [widget.mint, widget.cyan, widget.skyBlue]
                              : [Colors.grey.shade400, Colors.grey.shade400],
                        ),
                      ),
                      child: CircleAvatar(
                        radius: 27,
                        backgroundColor:
                            widget.isDarkMode ? widget.navy : Colors.white,
                        child: Icon(
                          Icons.person_rounded,
                          color: widget.isDarkMode ? Colors.white : widget.navy,
                          size: 29,
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: _showCreateStatusSheet,
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: widget.mint,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.add,
                              size: 15, color: widget.navy),
                        ),
                      ),
                    ),
                  ],
                ),
                title: Text(
                  'My Status',
                  style: TextStyle(
                      color: widget.primaryText,
                      fontSize: 17,
                      fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  myStatuses.isNotEmpty
                      ? '${myStatuses.length} update${myStatuses.length > 1 ? 's' : ''} • tap to view'
                      : 'Tap to add a status • 24 hours',
                  style: TextStyle(color: widget.secondaryText, fontSize: 13),
                ),
                trailing: Icon(Icons.arrow_forward_ios_rounded,
                    color: widget.mint, size: 16),
              ),
            ),
            const SizedBox(height: 28),

            widget.sectionHeading('Recent updates'),
            const SizedBox(height: 14),

            if (recentEntries.isEmpty && viewedEntries.isEmpty)
              widget.emptyState(
                Icons.auto_stories_outlined,
                'No status updates',
                'Status updates from your contacts will appear here.',
              )
            else if (recentEntries.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  'No new updates.',
                  style: TextStyle(color: widget.secondaryText),
                ),
              )
            else
              ...recentEntries.map((entry) => _contactStatusTile(entry, false)),

            if (viewedEntries.isNotEmpty) ...[
              const SizedBox(height: 24),
              widget.sectionHeading('Viewed updates'),
              const SizedBox(height: 14),
              ...viewedEntries.map((entry) => _contactStatusTile(entry, true)),
            ],
          ],
        );
      },
    );
  }

  void _openViewer(
    String userId,
    String userName,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> statuses,
  ) {
    final ordered = statuses.reversed.toList();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StatusViewerScreen(
          userId: userId,
          userName: userName,
          statuses: ordered,
        ),
      ),
    );
  }

  Widget _contactStatusTile(
    MapEntry<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>> entry,
    bool viewed,
  ) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance
          .collection('users')
          .doc(entry.key)
          .get(),
      builder: (context, snapshot) {
        String name = 'ChatFlow User';
        String? photoBase64;

        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data();
          if (data != null) {
            name = data['name']?.toString() ??
                data['displayName']?.toString() ??
                data['email']?.toString() ??
                name;
            photoBase64 = data['photoBase64']?.toString();
          }
        }

        return widget.sectionCard(
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            onTap: () => _openViewer(entry.key, name, entry.value),
            leading: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: viewed
                      ? [Colors.grey.shade400, Colors.grey.shade400]
                      : [widget.mint, widget.cyan, widget.skyBlue],
                ),
              ),
              child: CircleAvatar(
                radius: 27,
                backgroundColor: widget.isDarkMode ? widget.navy : Colors.white,
                backgroundImage: photoBase64 != null && photoBase64.isNotEmpty
                    ? MemoryImage(base64Decode(photoBase64))
                    : null,
                child: photoBase64 == null || photoBase64.isEmpty
                    ? Text(
                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: TextStyle(
                          color: widget.isDarkMode ? Colors.white : widget.navy,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    : null,
              ),
            ),
            title: Text(name,
                style: TextStyle(
                    color: widget.primaryText, fontWeight: FontWeight.bold)),
            subtitle: Text(
              '${entry.value.length} update${entry.value.length > 1 ? 's' : ''}',
              style: TextStyle(color: widget.secondaryText, fontSize: 13),
            ),
          ),
        );
      },
    );
  }
}