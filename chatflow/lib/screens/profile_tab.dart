// ============================================================================
// FILE PATH: lib/screens/profile_tab.dart
// ============================================================================
//
// Replaces your existing profile_tab.dart entirely.
//
// New in this version:
//   - Editable Name + About/status text (saved to Firestore users/{uid})
//   - Real photo saving — compressed to base64 and stored in Firestore,
//     same pattern your chat already uses for images (no Firebase Storage,
//     no billing plan required)
//   - Account settings section (Notifications, Privacy — see notes below)
//   - Starred Messages entry point
//   - Help / About ChatFlow screen
//   - Appearance (dark mode) — unchanged from before
//
// Depends on: lib/screens/starred_messages_screen.dart (new file, see below)
//
// ============================================================================

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'starred_messages_screen.dart';

class ProfileTab extends StatefulWidget {
  final bool isDarkMode;
  final Color primaryText;
  final Color secondaryText;
  final Color navy;
  final Color mint;
  final Color cyan;
  final Color skyBlue;
  final Color lightMint;
  final FirebaseAuth auth;
  final Function(bool) onThemeModeChanged;
  final VoidCallback onLogout;

  const ProfileTab({
    super.key,
    required this.isDarkMode,
    required this.primaryText,
    required this.secondaryText,
    required this.navy,
    required this.mint,
    required this.cyan,
    required this.skyBlue,
    required this.lightMint,
    required this.auth,
    required this.onThemeModeChanged,
    required this.onLogout,
  });

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  final ImagePicker _picker = ImagePicker();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _isSavingPhoto = false;

  String get _uid => widget.auth.currentUser?.uid ?? '';

  DocumentReference<Map<String, dynamic>> get _userDocRef =>
      _firestore.collection('users').doc(_uid);

  // ==========================================================================
  // IMAGE SOURCE SHEET
  // ==========================================================================

  void _showImageSourceBottomSheet(BuildContext context) {
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
            padding:
                const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _sourceOptionTile(
                  icon: Icons.camera_alt_rounded,
                  label: 'Camera',
                  source: ImageSource.camera,
                ),
                _sourceOptionTile(
                  icon: Icons.photo_library_rounded,
                  label: 'Gallery',
                  source: ImageSource.gallery,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _sourceOptionTile({
    required IconData icon,
    required String label,
    required ImageSource source,
  }) {
    return InkWell(
      onTap: () {
        Navigator.pop(context);
        _pickAndSaveImage(source);
      },
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
          Text(
            label,
            style: TextStyle(
                color: widget.primaryText, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // PICK + SAVE PHOTO (base64 into Firestore — no Storage, no billing plan)
  // ==========================================================================

  Future<void> _pickAndSaveImage(ImageSource source) async {
  try {
    final XFile? pickedFile = await _picker.pickImage(
      source: source,
      imageQuality: 60,
      maxWidth: 400,
      maxHeight: 400,
    );

    if (pickedFile == null) {
      return;
    }

    setState(() {
      _isSavingPhoto = true;
    });

    // Read the image directly from XFile.
    // This works on Android, Windows and Web.
    final bytes = await pickedFile.readAsBytes();

    const maxSize = 700 * 1024;

    if (bytes.length > maxSize) {
      _showMessage(
        'Photo is too large. Please choose a smaller image.',
      );
      return;
    }

    final base64Photo = base64Encode(bytes);

    await _userDocRef.set(
      {
        'photoBase64': base64Photo,
      },
      SetOptions(merge: true),
    );

    _showMessage('Profile photo updated.');
  } catch (e) {
    debugPrint('Photo save error: $e');

    _showMessage(
      'Unable to update profile photo.',
    );
  } finally {
    if (mounted) {
      setState(() {
        _isSavingPhoto = false;
      });
    }
  }
}

  // ==========================================================================
  // EDIT NAME + ABOUT
  // ==========================================================================

  Future<void> _showEditProfileSheet(
    String currentName,
    String currentAbout,
  ) async {
    final nameController = TextEditingController(text: currentName);
    final aboutController = TextEditingController(text: currentAbout);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor:
          widget.isDarkMode ? const Color(0xFF10284A) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Edit Profile',
                style: TextStyle(
                  color: widget.primaryText,
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: nameController,
                maxLength: 40,
                style: TextStyle(color: widget.primaryText),
                decoration: InputDecoration(
                  labelText: 'Name',
                  labelStyle: TextStyle(color: widget.secondaryText),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              TextField(
                controller: aboutController,
                maxLength: 100,
                maxLines: 2,
                style: TextStyle(color: widget.primaryText),
                decoration: InputDecoration(
                  labelText: 'About',
                  hintText: 'Hey there! I am using ChatFlow.',
                  labelStyle: TextStyle(color: widget.secondaryText),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.cyan,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () async {
                    final newName = nameController.text.trim();
                    final newAbout = aboutController.text.trim();

                    Navigator.pop(sheetContext);

                    await _saveProfileDetails(newName, newAbout);
                  },
                  child: const Text(
                    'Save',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _saveProfileDetails(String name, String about) async {
    if (name.isEmpty) {
      _showMessage('Name cannot be empty.');
      return;
    }

    try {
      await widget.auth.currentUser?.updateDisplayName(name);

      await _userDocRef.set(
        {
          'name': name,
          'about': about,
        },
        SetOptions(merge: true),
      );

      _showMessage('Profile updated.');
    } catch (e) {
      debugPrint('Profile update error: $e');
      _showMessage('Unable to update profile.');
    }
  }

  // ==========================================================================
  // NOTIFICATIONS TOGGLE (stored in Firestore; not yet wired to real push —
  // see note in the tile itself)
  // ==========================================================================

  Future<void> _toggleNotifications(bool enabled) async {
    try {
      await _userDocRef.set(
        {'notificationsEnabled': enabled},
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('Notification setting error: $e');
    }
  }

  // ==========================================================================
  // PRIVACY SHEET (Last seen / Read receipts toggles)
  // ==========================================================================

  void _showPrivacySheet(Map<String, dynamic> userData) {
    bool lastSeenEnabled = userData['lastSeenEnabled'] != false;
    bool readReceiptsEnabled = userData['readReceiptsEnabled'] != false;

    showModalBottomSheet(
      context: context,
      backgroundColor:
          widget.isDarkMode ? const Color(0xFF10284A) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Privacy',
                      style: TextStyle(
                        color: widget.primaryText,
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'These preferences are saved to your profile. '
                      'Hooking them into last-seen and read-receipt '
                      'display is a follow-up step.',
                      style: TextStyle(
                          color: widget.secondaryText, fontSize: 12),
                    ),
                    const Divider(height: 28),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Show Last Seen',
                          style: TextStyle(color: widget.primaryText)),
                      value: lastSeenEnabled,
                      activeThumbColor: widget.cyan,
                      onChanged: (value) async {
                        setSheetState(() => lastSeenEnabled = value);
                        await _userDocRef.set(
                          {'lastSeenEnabled': value},
                          SetOptions(merge: true),
                        );
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Read Receipts',
                          style: TextStyle(color: widget.primaryText)),
                      value: readReceiptsEnabled,
                      activeThumbColor: widget.cyan,
                      onChanged: (value) async {
                        setSheetState(() => readReceiptsEnabled = value);
                        await _userDocRef.set(
                          {'readReceiptsEnabled': value},
                          SetOptions(merge: true),
                        );
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ==========================================================================
  // HELP / ABOUT
  // ==========================================================================

  void _showAboutSheet() {
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
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                            colors: [widget.mint, widget.cyan]),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.chat_bubble_rounded,
                          color: Colors.white),
                    ),
                    const SizedBox(width: 14),
                    Text(
                      'ChatFlow',
                      style: TextStyle(
                        color: widget.primaryText,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Version 1.0.0 (Private Beta)',
                  style: TextStyle(color: widget.secondaryText),
                ),
                const SizedBox(height: 10),
                Text(
                  'A real-time messaging app with one-to-one and group '
                  'chat, media sharing, and voice/video calling.',
                  style: TextStyle(color: widget.secondaryText, height: 1.4),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ==========================================================================
  // SNACKBAR
  // ==========================================================================

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  // ==========================================================================
  // BUILD
  // ==========================================================================

  @override
  Widget build(BuildContext context) {
    final User? authUser = widget.auth.currentUser;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _userDocRef.snapshots(),
      builder: (context, snapshot) {
        final userData = snapshot.data?.data() ?? <String, dynamic>{};

        final name = (userData['name'] as String?)?.trim().isNotEmpty == true
            ? userData['name'] as String
            : (authUser?.displayName ?? 'ChatFlow User');

        final about = (userData['about'] as String?)?.trim().isNotEmpty ==
                true
            ? userData['about'] as String
            : 'Hey there! I am using ChatFlow.';

        final photoBase64 = userData['photoBase64'] as String?;
        final notificationsEnabled =
            userData['notificationsEnabled'] != false;

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 35),
          child: Column(
            children: [
              // PROFILE HEADER CARD
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(vertical: 28, horizontal: 18),
                decoration: BoxDecoration(
                  color: widget.isDarkMode
                      ? const Color(0xFF10284A)
                      : Colors.white,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: widget.isDarkMode
                        ? const [Color(0xFF102F55), Color(0xFF123C5A)]
                        : const [Colors.white, Color(0xFFDDF8F1)],
                  ),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: widget.isDarkMode
                        ? const Color(0xFF24486A)
                        : const Color(0xFFBCEDE2),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color:
                          widget.mint.withOpacity(widget.isDarkMode ? 0.08 : 0.20),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Stack(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(colors: [
                              widget.mint,
                              widget.cyan,
                              widget.skyBlue
                            ]),
                          ),
                          child: CircleAvatar(
                            radius: 58,
                            backgroundColor:
                                widget.isDarkMode ? widget.navy : Colors.white,
                            backgroundImage: photoBase64 != null
                                ? MemoryImage(base64Decode(photoBase64))
                                : null,
                            child: photoBase64 == null
                                ? Text(
                                    name.isNotEmpty
                                        ? name[0].toUpperCase()
                                        : 'C',
                                    style: TextStyle(
                                      color: widget.isDarkMode
                                          ? Colors.white
                                          : widget.navy,
                                      fontSize: 42,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  )
                                : null,
                          ),
                        ),
                        Positioned(
                          bottom: 3,
                          right: 3,
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                  colors: [widget.cyan, widget.skyBlue]),
                            ),
                            child: _isSavingPhoto
                                ? const Padding(
                                    padding: EdgeInsets.all(10),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : IconButton(
                                    padding: EdgeInsets.zero,
                                    onPressed: () =>
                                        _showImageSourceBottomSheet(context),
                                    icon: const Icon(
                                        Icons.camera_alt_rounded,
                                        size: 19,
                                        color: Colors.white),
                                  ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      name,
                      style: TextStyle(
                          color: widget.primaryText,
                          fontSize: 23,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      about,
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(color: widget.secondaryText, fontSize: 14),
                    ),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: () =>
                          _showEditProfileSheet(name, about),
                      icon: Icon(Icons.edit_rounded,
                          size: 16, color: widget.cyan),
                      label: Text('Edit Profile',
                          style: TextStyle(color: widget.cyan)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: widget.cyan.withOpacity(0.4)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // CONTACT INFO
              _infoCard(Icons.email_outlined, 'Email Address',
                  authUser?.email ?? 'Not available'),
              const SizedBox(height: 20),

              // ACCOUNT SETTINGS SECTION
              _sectionCard(
                child: Column(
                  children: [
                    _settingsTile(
                      icon: Icons.star_outline_rounded,
                      title: 'Starred Messages',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const StarredMessagesScreen(),
                          ),
                        );
                      },
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      secondary: Icon(Icons.notifications_outlined,
                          color: widget.cyan),
                      title: Text('Notifications',
                          style: TextStyle(color: widget.primaryText)),
                      subtitle: Text(
                        'Message and call alerts',
                        style: TextStyle(
                            color: widget.secondaryText, fontSize: 12),
                      ),
                      value: notificationsEnabled,
                      activeThumbColor: widget.cyan,
                      onChanged: _toggleNotifications,
                    ),
                    const Divider(height: 1),
                    _settingsTile(
                      icon: Icons.lock_outline_rounded,
                      title: 'Privacy',
                      onTap: () => _showPrivacySheet(userData),
                    ),
                    const Divider(height: 1),
                    _settingsTile(
                      icon: Icons.help_outline_rounded,
                      title: 'Help & About',
                      onTap: _showAboutSheet,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // APPEARANCE
              _sectionCard(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          gradient:
                              LinearGradient(colors: [widget.mint, widget.cyan]),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          widget.isDarkMode
                              ? Icons.dark_mode_rounded
                              : Icons.light_mode_rounded,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Appearance',
                              style: TextStyle(
                                  color: widget.primaryText,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              widget.isDarkMode
                                  ? 'Dark mode enabled'
                                  : 'Light mode enabled',
                              style: TextStyle(
                                  color: widget.secondaryText, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: widget.isDarkMode,
                        thumbColor: const WidgetStatePropertyAll(Colors.white),
                        activeTrackColor: widget.cyan,
                        inactiveTrackColor: widget.mint,
                        onChanged: widget.onThemeModeChanged,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // LOGOUT
              SizedBox(
                width: double.infinity,
                height: 58,
                child: OutlinedButton.icon(
                  onPressed: widget.onLogout,
                  icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
                  label: const Text(
                    'Logout',
                    style: TextStyle(
                        color: Colors.redAccent,
                        fontSize: 16,
                        fontWeight: FontWeight.bold),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.redAccent.withOpacity(0.35)),
                    shape:
                        RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ==========================================================================
  // REUSABLE PIECES
  // ==========================================================================

  Widget _sectionCard({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: widget.isDarkMode ? const Color(0xFF10284A) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: widget.isDarkMode
              ? const Color(0xFF24486A)
              : const Color(0xFFBCEDE2),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: widget.mint.withOpacity(widget.isDarkMode ? 0.06 : 0.15),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _infoCard(IconData icon, String title, String value) {
    return _sectionCard(
      child: ListTile(
        leading: Container(
          width: 45,
          height: 45,
          decoration: BoxDecoration(
            color: widget.mint.withOpacity(widget.isDarkMode ? 0.14 : 0.22),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: widget.cyan),
        ),
        title: Text(title,
            style: TextStyle(color: widget.secondaryText, fontSize: 12)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(value,
              style: TextStyle(
                  color: widget.primaryText,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }

  Widget _settingsTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: widget.cyan),
      title: Text(title, style: TextStyle(color: widget.primaryText)),
      trailing: Icon(Icons.chevron_right_rounded,
          color: widget.secondaryText),
      onTap: onTap,
    );
  }
}