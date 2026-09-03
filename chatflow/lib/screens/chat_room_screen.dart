// ============================================================================
// FILE PATH: lib/screens/chat_room_screen.dart
// ============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io'; 


import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';


import 'call_screen.dart';
import 'view_profile_screen.dart';

class ChatRoomScreen extends StatefulWidget {
  // ==========================================================================
  // ONE-TO-ONE PARAMETERS
  // ==========================================================================

  final String targetUserName;
  final String targetUserId;

  // ==========================================================================
  // GROUP PARAMETERS
  // ==========================================================================

  final bool isGroup;
  final String? groupId;
  final String? groupName;
  final List<String>? groupMembers;
  

  const ChatRoomScreen({
    super.key,
    required this.targetUserName,
    required this.targetUserId,
    this.isGroup = false,
    this.groupId,
    this.groupName,
    this.groupMembers,
    
  });

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
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

  final TextEditingController _messageController =
      TextEditingController();

  final TextEditingController _searchController =
      TextEditingController();

  // ==========================================================================
  // SERVICES
  // ==========================================================================

  final ImagePicker _imagePicker =
      ImagePicker();

  final AudioRecorder _audioRecorder =
      AudioRecorder();

  // ==========================================================================
  // STATE
  // ==========================================================================

  late String _chatRoomId;

  Map<String, dynamic>? _replyingToMessage;

  String? _replyingToMessageId;

  bool _isRecording = false;

  bool _isSendingFile = false;

  bool _isSearching = false;

  String _searchQuery = '';

  String? _wallpaperPath;
  Uint8List? _wallpaperBytes;

  Timer? _typingTimer;

  Stream<QuerySnapshot<Map<String, dynamic>>>? _messagesStream;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _roomStatusSubscription;

  bool _isRemovedByCurrentUser = false;
  bool _isBlockedByOtherUser = false;

  bool _isRemovedByOtherUser = false;
  String _removedByName = '';

    // ==========================================================================
  // GROUP LEAVE / REMOVAL STATUS
  // ==========================================================================

  bool _hasLeftGroup = false;
  bool _wasRemovedFromGroup = false;
  String _groupRemovedByName = '';

  // ==========================================================================
  // COLORS
  // ==========================================================================

  static const Color navy =
      Color(0xFF102A5C);

  static const Color skyBlue =
      Color(0xFF55C7E8);

  static const Color cyan =
      Color(0xFF16AFC1);

  static const Color mint =
      Color(0xFF66D6C1);

  // ==========================================================================
  // GETTERS
  // ==========================================================================

  bool get _isGroup => widget.isGroup;

  String get _displayName {
    if (_isGroup) {
      final name =
          widget.groupName?.trim();

      if (name != null && name.isNotEmpty) {
        return name;
      }

      return 'Group';
    }

    return widget.targetUserName;
  }

  String get _currentUserId {
    return _auth.currentUser?.uid ?? '';
  }

  // ==========================================================================
  // IMPORTANT:
  //
  // BOTH ONE-TO-ONE AND GROUP CHATS USE:
  //
  // chat_rooms/{chatRoomId}/messages
  //
  // This matches the group creation implementation.
  // ==========================================================================

  String get _messagesCollection {
    return 'chat_rooms';
  }

  // ==========================================================================
  // INIT
  // ==========================================================================

  @override
  void initState() {
    super.initState();

    final currentUserId =
        _auth.currentUser?.uid ?? '';

    // ------------------------------------------------------------------------
    // GROUP
    // ------------------------------------------------------------------------

    if (_isGroup) {
      _chatRoomId =
          widget.groupId?.trim() ?? '';
    }

    // ------------------------------------------------------------------------
    // ONE-TO-ONE
    // ------------------------------------------------------------------------

    else {
      final ids = [
        currentUserId,
        widget.targetUserId,
      ];

      ids.sort();

      _chatRoomId = ids.join('_');
    }

    _messageController.addListener(
      _handleTyping,
    );

    if (_chatRoomId.isNotEmpty) {
  _messagesStream = _messagesRef
      .orderBy(
        'timestamp',
        descending: true,
      )
      .snapshots();

  _listenToRoomStatus();
  _markMessagesAsRead();
  _cleanupOldMessages();
}
    _checkChatAccess();
    _loadSavedWallpaper();
  }

    // ==========================================================================
  // PERMANENT WALLPAPER RETRIEVAL ENGINE
  // ==========================================================================
  Future<void> _loadSavedWallpaper() async {
    if (_chatRoomId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? base64Image = prefs.getString('wallpaper_$_chatRoomId');
      
      if (base64Image != null && base64Image.isNotEmpty) {
        final decodedBytes = base64.decode(base64Image);
        setState(() {
          _wallpaperBytes = decodedBytes;
        });
      }
    } catch (e) {
      debugPrint('Error loading saved wallpaper: $e');
    }
  }


  //Check Chat Access
  Future<void> _checkChatAccess() async {
  if (widget.isGroup) {
  await _checkGroupAccess();
  return;
}

  final currentUser = _auth.currentUser;

  if (currentUser == null) return;

  final chatRoomDoc = await _firestore
      .collection('chat_rooms')
      .doc(_chatRoomId)
      .get();

  if (!chatRoomDoc.exists) return;

  final data = chatRoomDoc.data();

  if (data == null) return;

  final removedBy =
      List<String>.from(data['removedBy'] ?? []);

  if (removedBy.isEmpty) {
    if (mounted) {
      setState(() {
        _isRemovedByOtherUser = false;
        _removedByName = '';
      });
    }
    return;
  }

  final otherUserId = widget.targetUserId;

  if (removedBy.contains(otherUserId)) {
    String name = widget.targetUserName;

    if (mounted) {
      setState(() {
        _isRemovedByOtherUser = true;
        _removedByName = name;
      });
    }
  }
}

// ==========================================================================
// CHECK GROUP ACCESS
// ==========================================================================

Future<void> _checkGroupAccess() async {
  if (!_isGroup || _chatRoomId.isEmpty) {
    return;
  }

  try {
    final roomSnapshot = await _roomRef.get();

    if (!roomSnapshot.exists) {
      return;
    }

    final data = roomSnapshot.data();

    if (data == null || !mounted) {
      return;
    }

    final leftBy = data['leftBy'];

    final hasLeft = leftBy is Map &&
        leftBy[_currentUserId] == true;

    setState(() {
      _hasLeftGroup = hasLeft;
    });
  } catch (e) {
    debugPrint(
      'Check group access error: $e',
    );
  }
}

// ==========================================================================
// DELETE INDIVIDUAL CHAT
// ==========================================================================

Future<void> _deleteIndividualChat() async {
  // Groups are handled separately.
  if (_isGroup) return;

  final currentUser = _auth.currentUser;

  if (currentUser == null) return;

  final shouldDelete = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text(
          'Delete chat?',
        ),
        content: const Text(
          'This will remove the chat from your chat list. '
          'The other user will no longer be able to send you messages.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext, false);
            },
            child: const Text(
              'Cancel',
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext, true);
            },
            child: const Text(
              'Delete',
              style: TextStyle(
                color: Colors.redAccent,
              ),
            ),
          ),
        ],
      );
    },
  );

  if (shouldDelete != true) return;

  try {
    await _firestore
        .collection('chat_rooms')
        .doc(_chatRoomId)
        .update({
      'removedBy': FieldValue.arrayUnion([
        currentUser.uid,
      ]),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (!mounted) return;
    Navigator.pop(context); 

  } catch (e) {
    debugPrint(
      'Delete individual chat error: $e',
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Unable to delete chat. Please try again.',
        ),
      ),
    );
  }
}

  // ==========================================================================
  // INDIVIDUAL CHAT REMOVAL / BLOCK STATUS
  // ==========================================================================

  void _listenToRoomStatus() {
  if (_isGroup || _chatRoomId.isEmpty) {
    return;
  }

  _roomStatusSubscription?.cancel();

  _roomStatusSubscription = _roomRef.snapshots().listen(
    (snapshot) {
      final data = snapshot.data();
      final rawRemovedBy = data?['removedBy'];

      final removedBy = rawRemovedBy is List
          ? rawRemovedBy
              .map((id) => id.toString())
              .toSet()
          : <String>{};

      final otherUserId = widget.targetUserId;

      final newIsRemovedByCurrentUser =
          removedBy.contains(_currentUserId);

      final newIsBlockedByOtherUser =
          removedBy.contains(otherUserId);

      if (!mounted) {
        return;
      }

      // Only rebuild the screen if the actual
      // chat relationship status changed.
      if (_isRemovedByCurrentUser != newIsRemovedByCurrentUser ||
          _isBlockedByOtherUser != newIsBlockedByOtherUser) {
        setState(() {
          _isRemovedByCurrentUser =
              newIsRemovedByCurrentUser;

          _isBlockedByOtherUser =
              newIsBlockedByOtherUser;
        });
      }
    },
    onError: (error) {
      debugPrint(
        'Chat relationship listener error: $error',
      );
    },
  );
}

  // ==========================================================================
// REMOVE INDIVIDUAL CHAT
// ==========================================================================

Future<void> _removeIndividualChat() async {
  if (_isGroup ||
      _currentUserId.isEmpty ||
      _chatRoomId.isEmpty) {
    return;
  }

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Delete chat?'),
        content: Text(
          'This will remove ${widget.targetUserName} from your chats. '
          'Your conversation history will remain available to the other person.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(
                dialogContext,
                false,
              );
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(
                dialogContext,
                true,
              );
            },
            child: const Text(
              'Delete Chat',
              style: TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      );
    },
  );

  if (confirmed != true) {
    return;
  }

  try {
    // ========================================================================
    // REMOVE CURRENT USER FROM THE ACTIVE PARTICIPANTS LIST
    //
    // The other user's UID remains in the room.
    // Therefore:
    //   User 1 -> no longer sees this chat
    //   User 2 -> still has access to the old chat
    // ========================================================================

    await _roomRef.update({
      'participants': FieldValue.arrayRemove([
        _currentUserId,
      ]),

      // ======================================================================
      // RECORD WHO REMOVED THE CHAT
      // ======================================================================

      'removedBy': FieldValue.arrayUnion([
        _currentUserId,
      ]),

      'removedAt.$_currentUserId':
          FieldValue.serverTimestamp(),
    });

    // ========================================================================
    // CLOSE THE CHAT
    // ========================================================================

    if (!mounted) {
      return;
    }

    Navigator.pop(context);
  } catch (e) {
    debugPrint(
      'Remove individual chat error: $e',
    );

    if (mounted) {
      _showMessage(
        'Unable to delete this chat. Please try again.',
      );
    }
  }
}

  // ==========================================================================
  // ROOM REFERENCE
  // ==========================================================================

  DocumentReference<Map<String, dynamic>>
      get _roomRef {
    return _firestore
        .collection(_messagesCollection)
        .doc(_chatRoomId);
  }

  // ==========================================================================
  // MESSAGES REFERENCE
  // ==========================================================================

  CollectionReference<Map<String, dynamic>>
      get _messagesRef {
    return _roomRef.collection('messages');
  }

  // ==========================================================================
  // PROFILE
  // ==========================================================================

  void _openUserProfile() {
    if (_isGroup) {
      _showGroupInfo();
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            ViewProfileScreen(
          targetUserId:
              widget.targetUserId,
          targetUserName:
              widget.targetUserName,
        ),
      ),
    );
  }

  // ==========================================================================
  // TYPING
  // ==========================================================================

  void _handleTyping() {
    final isTyping =
        _messageController.text
            .trim()
            .isNotEmpty;

    _setTypingStatus(isTyping);

    _typingTimer?.cancel();

    if (isTyping) {
      _typingTimer = Timer(
        const Duration(seconds: 2),
        () {
          _setTypingStatus(false);
        },
      );
    }
  }

  Future<void> _setTypingStatus(
    bool isTyping,
  ) async {
    if (_currentUserId.isEmpty ||
        _chatRoomId.isEmpty) {
      return;
    }

    try {
      await _roomRef.set(
        {
          'typing.$_currentUserId':
              isTyping,
        },
        SetOptions(merge: true),
      );
    } catch (_) {}
  }

  // ==========================================================================
  // MARK MESSAGES AS READ
  // ==========================================================================

  Future<void> _markMessagesAsRead() async {
    if (_currentUserId.isEmpty ||
        _chatRoomId.isEmpty) {
      return;
    }

    try {
      Query<Map<String, dynamic>> query =
          _messagesRef.where(
        'isRead',
        isEqualTo: false,
      );

      // For one-to-one chat, only mark messages
      // from the other person as read.
      if (!_isGroup) {
        query = query.where(
          'senderId',
          isEqualTo: widget.targetUserId,
        );
      }

      final snapshot =
          await query.get();

      if (snapshot.docs.isEmpty) {
        return;
      }

      final batch =
          _firestore.batch();

      for (final doc
          in snapshot.docs) {
        final data =
            doc.data();

        if (data['senderId'] ==
            _currentUserId) {
          continue;
        }

        if (_isGroup) {
          batch.update(
            doc.reference,
            {
              'readBy.$_currentUserId':
                  true,
            },
          );
        } else {
          batch.update(
            doc.reference,
            {
              'isRead': true,
              'readBy.$_currentUserId':
                  true,
            },
          );
        }
      }

      await batch.commit();
    } catch (e) {
      debugPrint(
        'Could not mark messages as read: $e',
      );
    }
  }

  // ==========================================================================
  // 7 DAY CLEANUP
  // ==========================================================================

  Future<void> _cleanupOldMessages() async {
    if (_chatRoomId.isEmpty) {
      return;
    }

    try {
      final sevenDaysAgo =
          Timestamp.fromDate(
        DateTime.now().subtract(
          const Duration(days: 7),
        ),
      );

      final oldMessages =
          await _messagesRef
              .where(
                'timestamp',
                isLessThan:
                    sevenDaysAgo,
              )
              .get();

      if (oldMessages.docs.isEmpty) {
        return;
      }

      final batch =
          _firestore.batch();

      for (final doc
          in oldMessages.docs) {
        batch.delete(
          doc.reference,
        );
      }

      await batch.commit();
    } catch (e) {
      debugPrint(
        'Message cleanup failed: $e',
      );
    }
  }

  // ==========================================================================
// SEND TEXT MESSAGE
// ==========================================================================

Future<void> _sendMessage() async {
  // ------------------------------------------------------------------------
  // USER HAS BEEN REMOVED BY THE OTHER USER
  // ------------------------------------------------------------------------

  if (!_isGroup && _isRemovedByOtherUser) {
    if (mounted) {
      _showMessage(
        _removedByName.isNotEmpty
            ? 'You have been removed by $_removedByName.'
            : 'You have been removed from this chat.',
      );
    }
    return;
  }

  // ------------------------------------------------------------------------
  // CURRENT USER REMOVED / BLOCKED THE CHAT
  // ------------------------------------------------------------------------

  if (!_isGroup &&
      (_isRemovedByCurrentUser ||
          _isBlockedByOtherUser)) {
    if (mounted) {
      _showMessage(
        'You cannot send messages in this chat.',
      );
    }
    return;
  }

  // ------------------------------------------------------------------------
  // GET MESSAGE TEXT
  // ------------------------------------------------------------------------

  final text =
      _messageController.text.trim();

  if (text.isEmpty ||
      _currentUserId.isEmpty ||
      _chatRoomId.isEmpty) {
    return;
  }

  // ------------------------------------------------------------------------
  // CLEAR INPUT
  // ------------------------------------------------------------------------

  _messageController.clear();

  // ------------------------------------------------------------------------
  // MESSAGE DATA
  // ------------------------------------------------------------------------

  final messageData =
      <String, dynamic>{
    'senderId':
        _currentUserId,

    'message':
        text,

    'type':
        'text',

    'timestamp':
        FieldValue.serverTimestamp(),

    'isRead':
        false,

    'isDeleted':
        false,

    'isStarred':
        false,

    'reactions':
        <String, dynamic>{},

    'hiddenFor':
        <String>[],

    'readBy':
        <String, dynamic>{
      _currentUserId: true,
    },
  };

  // ------------------------------------------------------------------------
  // ONE-TO-ONE ONLY
  // ------------------------------------------------------------------------

  if (!_isGroup) {
    messageData['receiverId'] =
        widget.targetUserId;
  }

  // ------------------------------------------------------------------------
  // REPLY DATA
  // ------------------------------------------------------------------------

  _addReplyData(
    messageData,
  );

  // ------------------------------------------------------------------------
  // SEND
  // ------------------------------------------------------------------------

  try {
    await _updateRoomPreview(
      text,
    );

    await _messagesRef.add(
      messageData,
    );

    _clearReply();
  } catch (e) {
    debugPrint(
      'Send message error: $e',
    );

    if (mounted) {
      _showMessage(
        'Unable to send message.',
      );
    }
  }
}

  // ==========================================================================
  // ROOM PREVIEW
  // ==========================================================================

  Future<void> _updateRoomPreview(
    String message,
  ) async {
    if (_chatRoomId.isEmpty) {
      return;
    }

    final data =
        <String, dynamic>{
      'lastMessage': message,
      'lastMessageTime':
          FieldValue.serverTimestamp(),
    };

    if (_isGroup) {
      data['type'] = 'group';

      if (widget.groupName != null) {
        data['name'] =
            widget.groupName;
      }

      if (widget.groupMembers != null) {
        data['members'] =
            widget.groupMembers;
      }
    } else {
      data['participants'] = [
        _currentUserId,
        widget.targetUserId,
      ];
    }

    await _roomRef.set(
      data,
      SetOptions(merge: true),
    );
  }

  // ==========================================================================
  // REPLY DATA
  // ==========================================================================

  void _addReplyData(
    Map<String, dynamic> messageData,
  ) {
    if (_replyingToMessage ==
        null) {
      return;
    }

    messageData['replyToText'] =
        _replyingToMessage![
                'message'] ??
            '';

    if (_replyingToMessage![
            'senderId'] ==
        _currentUserId) {
      messageData[
          'replyToSender'] = 'You';
    } else {
      messageData[
          'replyToSender'] =
          _displayName;
    }

    messageData[
            'replyToMessageId'] =
        _replyingToMessageId;
  }

  void _clearReply() {
    if (!mounted) {
      return;
    }

    setState(() {
      _replyingToMessage =
          null;
      _replyingToMessageId =
          null;
    });
  }

  // ==========================================================================
  // PICK FILE
  // ==========================================================================

  Future<void> _pickFile() async {
    try {
      final result =
          await FilePicker.platform
              .pickFiles(
        type: FileType.any,
        allowMultiple: false,
        withData: true,
      );

      if (result == null ||
          result.files.isEmpty) {
        return;
      }

      final file =
          result.files.first;

      if (file.bytes == null ||
          file.bytes!.isEmpty) {
        _showMessage(
          'Unable to read the selected file.',
        );
        return;
      }

      await _sendAttachment(
        type: 'file',
        fileName: file.name,
        fileBytes: file.bytes!,
      );
    } catch (e) {
      debugPrint(
        'File picker error: $e',
      );

      _showMessage(
        'Unable to select file.',
      );
    }
  }

  // ==========================================================================
  // CAMERA
  // ==========================================================================

  Future<void> _openCamera() async {
    try {
      final image =
          await _imagePicker.pickImage(
        source:
            ImageSource.camera,
        imageQuality: 80,
      );

      if (image == null) {
        return;
      }

      final bytes =
          await image.readAsBytes();

      await _sendAttachment(
        type: 'image',
        fileName: 'Camera Photo',
        fileBytes: bytes,
      );
    } catch (e) {
      debugPrint(
        'Camera error: $e',
      );

      _showMessage(
        'Unable to open camera.',
      );
    }
  }

  // ==========================================================================
  // GALLERY
  // ==========================================================================

  Future<void> _pickImage() async {
    try {
      final image =
          await _imagePicker.pickImage(
        source:
            ImageSource.gallery,
        imageQuality: 80,
      );

      if (image == null) {
        return;
      }

      final bytes =
          await image.readAsBytes();

      await _sendAttachment(
        type: 'image',
        fileName: 'Image',
        fileBytes: bytes,
      );
    } catch (e) {
      debugPrint(
        'Gallery error: $e',
      );

      _showMessage(
        'Unable to select image.',
      );
    }
  }

  // ==========================================================================
  // SEND ATTACHMENT
  // ==========================================================================

  Future<void> _sendAttachment({
    required String type,
    required String fileName,
    required Uint8List fileBytes,
  }) async {
    if (_currentUserId.isEmpty ||
        _chatRoomId.isEmpty ||
        fileBytes.isEmpty) {
      return;
    }

    if (!_isGroup &&
        (_isRemovedByCurrentUser ||
            _isBlockedByOtherUser)) {
      _showMessage(
        'You cannot send attachments in this chat.',
      );
      return;
    }

    // ------------------------------------------------------------------------
    // Firebase Firestore document size is limited.
    //
    // We deliberately keep attachments below 700 KB because
    // Base64 increases the actual size.
    // ------------------------------------------------------------------------

    const maxFileSize =
        700 * 1024;

    if (fileBytes.length >
        maxFileSize) {
      _showMessage(
        'File is too large. Please select a file smaller than 700 KB.',
      );
      return;
    }

    if (mounted) {
      setState(() {
        _isSendingFile = true;
      });
    }

    try {
      final base64Data =
          base64Encode(
        fileBytes,
      );

      final message =
          type == 'image'
              ? '📷 Photo'
              : '📎 $fileName';

      final messageData =
          <String, dynamic>{
        'senderId':
            _currentUserId,
        'message': message,
        'type': type,
        'fileName': fileName,
        'fileData': base64Data,
        'fileSize':
            fileBytes.length,
        'timestamp':
            FieldValue.serverTimestamp(),
        'isRead': false,
        'isDeleted': false,
        'isStarred': false,
        'reactions':
            <String, dynamic>{},
        'hiddenFor':
            <String>[],
        'readBy':
            <String, dynamic>{
          _currentUserId: true,
        },
      };

      if (!_isGroup) {
        messageData['receiverId'] =
            widget.targetUserId;
      }

      _addReplyData(
        messageData,
      );

      await _updateRoomPreview(
        message,
      );

      await _messagesRef.add(
        messageData,
      );

      _clearReply();

      _showMessage(
        type == 'image'
            ? 'Photo sent successfully.'
            : 'File sent successfully.',
      );
    } catch (e) {
      debugPrint(
        'Attachment error: $e',
      );

      _showMessage(
        'Unable to send attachment.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSendingFile =
              false;
        });
      }
    }
  }

  // ==========================================================================
  // VOICE RECORDING
  // ==========================================================================

  Future<void> _toggleRecording() async {
    if (!_isGroup &&
        (_isRemovedByCurrentUser ||
            _isBlockedByOtherUser)) {
      _showMessage(
        'You cannot send messages in this chat.',
      );
      return;
    }

    if (_isRecording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    try {
      final permission =
          await _audioRecorder
              .hasPermission();

      if (!permission) {
        _showMessage(
          'Microphone permission is required.',
        );
        return;
      }

      final path =
          'chatflow_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _audioRecorder.start(
        const RecordConfig(
          encoder:
              AudioEncoder.aacLc,
        ),
        path: path,
      );

      if (mounted) {
        setState(() {
          _isRecording = true;
        });
      }
    } catch (e) {
      debugPrint(
        'Recording error: $e',
      );

      _showMessage(
        'Unable to start recording.',
      );
    }
  }

  Future<void> _stopRecording() async {
    try {
      final path =
          await _audioRecorder.stop();

      if (mounted) {
        setState(() {
          _isRecording = false;
        });
      }

      if (path == null ||
          path.isEmpty) {
        return;
      }

      // ----------------------------------------------------------------------
      // Firebase Storage is intentionally NOT used in this project.
      // ----------------------------------------------------------------------

      _showMessage(
        'Recording stopped. Audio upload depends on the recording platform.',
      );
    } catch (e) {
      debugPrint(
        'Stop recording error: $e',
      );

      if (mounted) {
        setState(() {
          _isRecording = false;
        });
      }
    }
  }

  // ==========================================================================
  // DELETE FOR EVERYONE
  // ==========================================================================

  Future<void> _deleteForEveryone(
    String messageId,
  ) async {
    try {
      final ref =
          _messagesRef.doc(
        messageId,
      );

      final snapshot =
          await ref.get();

      if (!snapshot.exists) {
        return;
      }

      final data =
          snapshot.data();

      if (data == null) {
        return;
      }

      if (data['senderId'] !=
          _currentUserId) {
        _showMessage(
          'You can only delete your own messages for everyone.',
        );
        return;
      }

      await ref.update({
        'message':
            '🚫 This message was deleted',
        'type': 'deleted',
        'isDeleted': true,
        'fileData':
            FieldValue.delete(),
        'fileName':
            FieldValue.delete(),
        'fileSize':
            FieldValue.delete(),
        'reactions':
            FieldValue.delete(),
        'isStarred':
            FieldValue.delete(),
      });

      await _updateLastMessageAfterDeletion();

      _showMessage(
        'Message deleted for everyone.',
      );
    } catch (e) {
      debugPrint(
        'Delete for everyone error: $e',
      );

      _showMessage(
        'Unable to delete message.',
      );
    }
  }

  // ==========================================================================
  // UPDATE LAST MESSAGE AFTER DELETE
  // ==========================================================================

  Future<void>
      _updateLastMessageAfterDeletion() async {
    try {
      final latest =
          await _messagesRef
              .orderBy(
                'timestamp',
                descending: true,
              )
              .limit(1)
              .get();

      if (latest.docs.isEmpty) {
        await _roomRef.set(
          {
            'lastMessage': '',
            'lastMessageTime':
                FieldValue.delete(),
          },
          SetOptions(merge: true),
        );

        return;
      }

      final data =
          latest.docs.first.data();

      await _roomRef.set(
        {
          'lastMessage':
              data['message'] ?? '',
          'lastMessageTime':
              data['timestamp'],
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint(
        'Preview update error: $e',
      );
    }
  }

  // ==========================================================================
  // DELETE FOR ME
  // ==========================================================================

  Future<void> _deleteForMe(
    String messageId,
  ) async {
    try {
      await _messagesRef
          .doc(messageId)
          .update({
        'hiddenFor':
            FieldValue.arrayUnion(
          [_currentUserId],
        ),
      });

      _showMessage(
        'Message deleted for you.',
      );
    } catch (e) {
      debugPrint(
        'Delete for me error: $e',
      );
    }
  }

  // ==========================================================================
  // STAR
  // ==========================================================================

  Future<void> _toggleStar(
    String messageId,
    bool starred,
  ) async {
    try {
      await _messagesRef
          .doc(messageId)
          .update({
        'isStarred': !starred,
      });
    } catch (e) {
      debugPrint(
        'Star error: $e',
      );
    }
  }

  // ==========================================================================
  // COPY
  // ==========================================================================

  Future<void> _copyMessage(
    String text,
  ) async {
    if (text.trim().isEmpty) {
      return;
    }

    await Clipboard.setData(
      ClipboardData(
        text: text,
      ),
    );

    _showMessage(
      'Message copied.',
    );
  }

  // ==========================================================================
  // REPLY
  // ==========================================================================

  void _replyToMessage(
    String messageId,
    Map<String, dynamic> data,
  ) {
    if (data['isDeleted'] ==
        true) {
      return;
    }

    setState(() {
      _replyingToMessage =
          data;
      _replyingToMessageId =
          messageId;
    });
  }

  // ==========================================================================
  // REACTION
  // ==========================================================================

  Future<void> _addReaction(
    String messageId,
    String emoji,
  ) async {
    try {
      await _messagesRef
          .doc(messageId)
          .update({
        'reactions.$_currentUserId':
            emoji,
      });
    } catch (e) {
      debugPrint(
        'Reaction error: $e',
      );
    }
  }

  // ==========================================================================
  // MESSAGE OPTIONS
  // ==========================================================================

  void _showMessageOptions(
    String messageId,
    Map<String, dynamic> data,
    bool isMe,
  ) {
    if (data['isDeleted'] ==
        true) {
      return;
    }

    final isText =
        (data['type'] ?? 'text') ==
            'text';

    final starred =
        data['isStarred'] == true;

    showModalBottomSheet(
      context: context,
      backgroundColor:
          Colors.white,
      shape:
          const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(
          top: Radius.circular(25),
        ),
      ),
      builder:
          (sheetContext) {
        return SafeArea(
          child: Wrap(
            children: [
              // --------------------------------------------------------------
              // REACTIONS
              // --------------------------------------------------------------

              Padding(
                padding:
                    const EdgeInsets.fromLTRB(
                  18,
                  18,
                  18,
                  8,
                ),
                child: Row(
                  mainAxisAlignment:
                      MainAxisAlignment
                          .spaceEvenly,
                  children: [
                    '❤️',
                    '😂',
                    '👍',
                    '😮',
                    '😢',
                    '🙏',
                  ].map(
                    (emoji) {
                      return GestureDetector(
                        onTap: () {
                          Navigator.pop(
                            sheetContext,
                          );

                          _addReaction(
                            messageId,
                            emoji,
                          );
                        },
                        child: Text(
                          emoji,
                          style:
                              const TextStyle(
                            fontSize: 28,
                          ),
                        ),
                      );
                    },
                  ).toList(),
                ),
              ),

              const Divider(),

              // --------------------------------------------------------------
              // REPLY
              // --------------------------------------------------------------

              ListTile(
                leading:
                    const Icon(
                  Icons.reply_rounded,
                  color: cyan,
                ),
                title:
                    const Text(
                  'Reply',
                ),
                onTap: () {
                  Navigator.pop(
                    sheetContext,
                  );

                  _replyToMessage(
                    messageId,
                    data,
                  );
                },
              ),

              // --------------------------------------------------------------
              // STAR
              // --------------------------------------------------------------

              ListTile(
                leading: Icon(
                  starred
                      ? Icons.star
                      : Icons.star_outline,
                  color:
                      Colors.amber,
                ),
                title: Text(
                  starred
                      ? 'Unstar Message'
                      : 'Star Message',
                ),
                onTap: () {
                  Navigator.pop(
                    sheetContext,
                  );

                  _toggleStar(
                    messageId,
                    starred,
                  );
                },
              ),

              // --------------------------------------------------------------
              // COPY
              // --------------------------------------------------------------

              if (isText)
                ListTile(
                  leading:
                      const Icon(
                    Icons.copy_rounded,
                    color: navy,
                  ),
                  title:
                      const Text(
                    'Copy',
                  ),
                  onTap: () {
                    Navigator.pop(
                      sheetContext,
                    );

                    _copyMessage(
                      data['message']
                              ?.toString() ??
                          '',
                    );
                  },
                ),

              // --------------------------------------------------------------
              // DELETE FOR ME
              // --------------------------------------------------------------

              ListTile(
                leading:
                    const Icon(
                  Icons
                      .delete_outline_rounded,
                  color:
                      Colors.redAccent,
                ),
                title:
                    const Text(
                  'Delete for me',
                ),
                onTap: () {
                  Navigator.pop(
                    sheetContext,
                  );

                  _deleteForMe(
                    messageId,
                  );
                },
              ),

              // --------------------------------------------------------------
              // DELETE FOR EVERYONE
              // --------------------------------------------------------------

              if (isMe)
                ListTile(
                  leading:
                      const Icon(
                    Icons
                        .delete_forever_rounded,
                    color:
                        Colors.redAccent,
                  ),
                  title:
                      const Text(
                    'Delete for everyone',
                  ),
                  onTap: () async {
                    Navigator.pop(
                      sheetContext,
                    );

                    await _confirmDeleteForEveryone(
                      messageId,
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  // ==========================================================================
  // CONFIRM DELETE
  // ==========================================================================

  Future<void>
      _confirmDeleteForEveryone(
    String messageId,
  ) async {
    final confirmed =
        await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) {
        return AlertDialog(
          title:
              const Text(
            'Delete for everyone?',
          ),
          content:
              const Text(
            'This message will be deleted for everyone in this chat.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  false,
                );
              },
              child:
                  const Text(
                'Cancel',
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  true,
                );
              },
              child:
                  const Text(
                'Delete',
                style:
                    TextStyle(
                  color:
                      Colors.redAccent,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await _deleteForEveryone(
        messageId,
      );
    }
  }

  // ==========================================================================
  // EMOJI PICKER
  // ==========================================================================

  void _showEmojiPicker() {
    const emojis = [
      '😀',
      '😂',
      '🤣',
      '😊',
      '😍',
      '🥰',
      '😘',
      '😎',
      '🤔',
      '😢',
      '😭',
      '😡',
      '😮',
      '😴',
      '👍',
      '👎',
      '👏',
      '🙏',
      '❤️',
      '🔥',
      '🎉',
      '💯',
      '✨',
      '💙',
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor:
          Colors.white,
      shape:
          const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(
          top: Radius.circular(25),
        ),
      ),
      builder: (pickerContext) {
        return SafeArea(
          child: Padding(
            padding:
                const EdgeInsets.all(
              18,
            ),
            child: GridView.builder(
              shrinkWrap: true,
              itemCount:
                  emojis.length,
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 6,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
              ),
              itemBuilder:
                  (_, index) {
                return GestureDetector(
                  onTap: () {
                    _messageController
                            .text +=
                        emojis[index];

                    _messageController
                            .selection =
                        TextSelection
                            .fromPosition(
                      TextPosition(
                        offset:
                            _messageController
                                .text
                                .length,
                      ),
                    );

                    Navigator.pop(
                      pickerContext,
                    );
                  },
                  child:
                      Center(
                    child: Text(
                      emojis[index],
                      style:
                          const TextStyle(
                        fontSize: 27,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  // ==========================================================================
  // ATTACHMENT MENU
  // ==========================================================================

  void _showAttachmentOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor:
          Colors.white,
      shape:
          const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(
          top: Radius.circular(25),
        ),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding:
                const EdgeInsets.all(
              20,
            ),
            child: Row(
              mainAxisAlignment:
                  MainAxisAlignment
                      .spaceEvenly,
              children: [
                _attachmentButton(
                  icon: Icons
                      .insert_drive_file_rounded,
                  label: 'Document',
                  color: navy,
                  onTap: () {
                    Navigator.pop(
                      sheetContext,
                    );
                    _pickFile();
                  },
                ),
                _attachmentButton(
                  icon:
                      Icons.photo_rounded,
                  label: 'Gallery',
                  color: cyan,
                  onTap: () {
                    Navigator.pop(
                      sheetContext,
                    );
                    _pickImage();
                  },
                ),
                _attachmentButton(
                  icon: Icons
                      .camera_alt_rounded,
                  label: 'Camera',
                  color: mint,
                  onTap: () {
                    Navigator.pop(
                      sheetContext,
                    );
                    _openCamera();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _attachmentButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize:
            MainAxisSize.min,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration:
                BoxDecoration(
              color:
                  color.withOpacity(
                0.12,
              ),
              shape:
                  BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: color,
              size: 28,
            ),
          ),
          const SizedBox(
            height: 8,
          ),
          Text(label),
        ],
      ),
    );
  }

  // ==========================================================================
  // SEARCH
  // ==========================================================================

  void _openMessageSearch() {
    setState(() {
      _isSearching = true;
    });
  }

  // ==========================================================================
  // WALLPAPER
  // ==========================================================================
  Future<void> _chooseWallpaper() async {
    try {
      final image = await _imagePicker.pickImage(source: ImageSource.gallery);
      if (image == null) return;
      
      final bytes = await image.readAsBytes();
      
      setState(() {
        _wallpaperPath = image.path;
        _wallpaperBytes = bytes;
      });

      if (_chatRoomId.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        String base64Image = base64.encode(bytes); 
        await prefs.setString('wallpaper_$_chatRoomId', base64Image);
      }
    } catch (e) {
      debugPrint('Wallpaper selection error: $e');
    }
  }


  // ==========================================================================
  // GROUP INFO
  // ==========================================================================

  void _showGroupInfo() {
    if (!_isGroup) {
      _openUserProfile();
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor:
          Colors.white,
      shape:
          const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(
          top: Radius.circular(25),
        ),
      ),
      builder: (sheetContext) {
        final members =
            widget.groupMembers ??
                [];

        return SafeArea(
          child: Padding(
            padding:
                const EdgeInsets.all(
              20,
            ),
            child: Column(
              mainAxisSize:
                  MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 38,
                  backgroundColor:
                      mint,
                  child: Text(
                    _displayName
                            .isNotEmpty
                        ? _displayName[0]
                            .toUpperCase()
                        : 'G',
                    style:
                        const TextStyle(
                      color:
                          Colors.white,
                      fontSize: 28,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                ),

                const SizedBox(
                  height: 12,
                ),

                Text(
                  _displayName,
                  style:
                      const TextStyle(
                    fontSize: 21,
                    fontWeight:
                        FontWeight.bold,
                    color: navy,
                  ),
                ),

                const SizedBox(
                  height: 5,
                ),

                Text(
                  '${members.length} members',
                  style:
                      const TextStyle(
                    color:
                        Colors.grey,
                  ),
                ),

                const Divider(
                  height: 30,
                ),

                ListTile(
                  leading:
                      const Icon(
                    Icons.people_outline,
                    color: cyan,
                  ),
                  title:
                      const Text(
                    'Group members',
                  ),
                  subtitle:
                      const Text(
                    'View members of this group',
                  ),
                  onTap: () {
                    Navigator.pop(
                      sheetContext,
                    );

                    _showGroupMembers();
                  },
                ),

                ListTile(
                  leading:
                      const Icon(
                    Icons
                        .wallpaper_rounded,
                    color: mint,
                  ),
                  title:
                      const Text(
                    'Wallpaper',
                  ),
                  onTap: () {
                    Navigator.pop(
                      sheetContext,
                    );

                    _chooseWallpaper();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ==========================================================================
  // GROUP MEMBERS
  // ==========================================================================

  void _showGroupMembers() {
    final members =
        widget.groupMembers ??
            [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor:
          Colors.white,
      shape:
          const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(
          top: Radius.circular(25),
        ),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: SizedBox(
            height:
                MediaQuery.of(
                  sheetContext,
                ).size.height *
                0.65,
            child: Column(
              children: [
                const Padding(
                  padding:
                      EdgeInsets.all(
                    18,
                  ),
                  child: Text(
                    'Group Members',
                    style:
                        TextStyle(
                      fontSize: 20,
                      fontWeight:
                          FontWeight.bold,
                      color: navy,
                    ),
                  ),
                ),

                const Divider(
                  height: 1,
                ),

                Expanded(
                  child: members
                          .isEmpty
                      ? const Center(
                          child:
                              Text(
                            'No members found.',
                          ),
                        )
                      : ListView.builder(
                          itemCount:
                              members.length,
                          itemBuilder:
                              (
                            context,
                            index,
                          ) {
                            return _buildMemberTile(
                              members[index],
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMemberTile(
    String userId,
  ) {
    return FutureBuilder<
        DocumentSnapshot<
            Map<String, dynamic>>>(
      future: _firestore
          .collection('users')
          .doc(userId)
          .get(),
      builder:
          (context, snapshot) {
        String name =
            'ChatFlow User';

        String? photo;

        if (snapshot.hasData &&
            snapshot.data!.exists) {
          final data =
              snapshot.data!.data();

          if (data != null) {
            name =
                data['name']
                        ?.toString() ??
                    data['displayName']
                        ?.toString() ??
                    data['email']
                        ?.toString() ??
                    name;

            photo =
                data['photoURL']
                    ?.toString();
          }
        }

        final isMe =
            userId ==
                _currentUserId;

        return ListTile(
          leading:
              CircleAvatar(
            backgroundColor:
                mint,
            backgroundImage:
                photo != null &&
                        photo.isNotEmpty
                    ? NetworkImage(
                        photo,
                      )
                    : null,
            child:
                photo == null ||
                        photo.isEmpty
                    ? Text(
                        name.isNotEmpty
                            ? name[0]
                                .toUpperCase()
                            : '?',
                        style:
                            const TextStyle(
                          color:
                              Colors.white,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      )
                    : null,
          ),
          title: Text(
            isMe
                ? '$name (You)'
                : name,
            style:
                const TextStyle(
              fontWeight:
                  FontWeight.w600,
            ),
          ),
          subtitle: Text(
            userId,
          ),
        );
      },
    );
  }

// ==========================================================================
// LEAVE GROUP
// ==========================================================================

Future<void> _leaveGroup() async {
  final currentUser = FirebaseAuth.instance.currentUser;

  if (currentUser == null) {
    _showMessage(
      'You must be logged in to leave the group.',
    );
    return;
  }

  if (!_isGroup) {
    _showMessage(
      'This is not a group chat.',
    );
    return;
  }

    // --------------------------------------------------------------------------
  // NEW SAFE DUAL-CHOICE SELECTION POPUP
  // --------------------------------------------------------------------------

  final String? deletionChoice = await showDialog<String>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text(
          'Delete Group Options',
          style: TextStyle(fontWeight: FontWeight.bold, color: navy),
        ),
        content: const Text(
          'Choose how you want to handle this group:\n\n'
          '• Delete for Me: Removes the card from your screen list. Other members stay in the chat.\n\n'
          '• Delete for Everyone: Destroys this group and all its message data history globally.',
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, 'everyone'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete for Everyone'),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, 'me'),
            style: ElevatedButton.styleFrom(
              backgroundColor: cyan,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete for Me'),
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'cancel'),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
        ],
      );
    },
  );

  // If you hit cancel or back out, stop immediately without touching your database
  if (deletionChoice == null || deletionChoice == 'cancel') {
    return;
  }


  try {
    // ------------------------------------------------------------------------
    // GET CURRENT GROUP DATA
    // ------------------------------------------------------------------------

    final roomSnapshot = await _roomRef.get();

    if (!roomSnapshot.exists) {
      if (mounted) {
        _showMessage(
          'This group no longer exists.',
        );
      }
      return;
    }

    final roomData = roomSnapshot.data();

    if (roomData == null) {
      if (mounted) {
        _showMessage(
          'Unable to read group information.',
        );
      }
      return;
    }

    // ------------------------------------------------------------------------
    // GET ACTIVE PARTICIPANTS
    // ------------------------------------------------------------------------

    final participants =
        List<String>.from(
      roomData['participants'] ?? <String>[],
    );

    participants.remove(_currentUserId);

    // ------------------------------------------------------------------------
    // LAST MEMBER
    // ------------------------------------------------------------------------

    if (participants.isEmpty) {
      // Delete messages and group_members first.
      await _deleteGroupSubcollections();

      // Delete the main group document last.
      await _roomRef.delete();

      if (!mounted) {
        return;
      }

      _showMessage(
        'Group deleted because you were the last member.',
      );

      Navigator.pop(context);
      return;
    }

    // ------------------------------------------------------------------------
    // OTHER MEMBERS STILL EXIST
    // ------------------------------------------------------------------------

    await _roomRef.update({
      'participants': participants,

      'leftBy.$_currentUserId': true,

      'leftAt.$_currentUserId':
          FieldValue.serverTimestamp(),

      'updatedAt':
          FieldValue.serverTimestamp(),
    });

    // ------------------------------------------------------------------------
    // REMOVE CURRENT USER FROM GROUP MEMBERS
    // ------------------------------------------------------------------------

    await _roomRef
        .collection('group_members')
        .doc(currentUser.uid)
        .delete();

    // ------------------------------------------------------------------------
    // UPDATE LOCAL STATE
    // ------------------------------------------------------------------------

    if (!mounted) {
      return;
    }

    setState(() {
      _hasLeftGroup = true;
      _wasRemovedFromGroup = false;
      _groupRemovedByName = '';
    });

    _showMessage(
      'You left the group.',
    );
  } on FirebaseException catch (e) {
    if (!mounted) {
      return;
    }

    _showMessage(
      'Leave failed: ${e.code}',
    );
  } catch (e) {
    if (!mounted) {
      return;
    }

    _showMessage(
      'Leave failed: $e',
    );
  }
}

// ==========================================================================
// DELETE GROUP SUBCOLLECTIONS
//
// Used when the LAST member leaves the group.
//
// Deletes:
//   - messages
//   - group_members
// ==========================================================================

Future<void> _deleteGroupSubcollections() async {
    if (_hasLeftGroup) {
    if (mounted) {
      _showMessage(
        'You have already left this group.',
      );
    }
    return;
  }
  // --------------------------------------------------------------------------
  // DELETE ALL MESSAGES
  // --------------------------------------------------------------------------

  final messagesSnapshot = await _roomRef
      .collection('messages')
      .get();

  if (messagesSnapshot.docs.isNotEmpty) {
    WriteBatch batch = _firestore.batch();
    int count = 0;

    for (final doc in messagesSnapshot.docs) {
      batch.delete(doc.reference);
      count++;

      if (count == 500) {
        await batch.commit();

        batch = _firestore.batch();
        count = 0;
      }
    }

    if (count > 0) {
      await batch.commit();
    }
  }

  // --------------------------------------------------------------------------
  // DELETE ALL GROUP MEMBERS
  // --------------------------------------------------------------------------

  final membersSnapshot = await _roomRef
      .collection('group_members')
      .get();

  if (membersSnapshot.docs.isNotEmpty) {
    WriteBatch batch = _firestore.batch();
    int count = 0;

    for (final doc in membersSnapshot.docs) {
      batch.delete(doc.reference);
      count++;

      if (count == 500) {
        await batch.commit();

        batch = _firestore.batch();
        count = 0;
      }
    }

    if (count > 0) {
      await batch.commit();
    }
  }
}

// ==========================================================================
// DELETE GROUP
//
// "Delete Group" = Leave Group.
//
// It does NOT delete the group for other members.
//
// If other members remain:
//   - Current user leaves.
//   - Other members keep the group.
//
// If no members remain:
//   - Messages are deleted.
//   - group_members are deleted.
//   - Main group document is deleted.
// ==========================================================================

Future<void> _deleteGroup() async {
  if (!_isGroup ||
      _currentUserId.isEmpty ||
      _chatRoomId.isEmpty) {
    return;
  }

    // --------------------------------------------------------------------------
  // NEW SAFE DUAL-CHOICE SELECTION POPUP
  // --------------------------------------------------------------------------

  final String? deletionChoice = await showDialog<String>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text(
          'Delete Group Options',
          style: TextStyle(fontWeight: FontWeight.bold, color: navy),
        ),
        content: const Text(
          'Choose how you want to handle this group:\n\n'
          '• Delete for Me: Removes the card from your screen list. Other members stay in the chat.\n\n'
          '• Delete for Everyone: Destroys this group and all its message data history globally.',
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, 'everyone'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete for Everyone'),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, 'me'),
            style: ElevatedButton.styleFrom(
              backgroundColor: cyan,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete for Me'),
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'cancel'),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
        ],
      );
    },
  );

  // If you hit cancel or back out, stop immediately without touching your database
  if (deletionChoice == null || deletionChoice == 'cancel') {
    return;
  }

   // Show a background loading spinner circle overlay frame while processing
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => const Center(child: CircularProgressIndicator(color: cyan)),
  );

  try {
    // ========================================================================
    // IF CHOICE IS: DELETE FOR EVERYONE (GLOBAL PURGE)
    // ========================================================================
    if (deletionChoice == 'everyone') {
      await _deleteGroupSubcollections(); // Purges nested database collections
      await _roomRef.delete();            // Wipes out the primary group document ledger

      if (!mounted) return;
      Navigator.pop(context); // Close loading spinner
      Navigator.pop(context); // Return cleanly back to the home dashboard roster
      _showMessage('Group deleted permanently for everyone.');
      return;
    }

    // ========================================================================
    // IF CHOICE IS: DELETE FOR ME (YOUR ORIGINAL PRESERVED USER FILTER LOGIC)
    // ========================================================================
    final roomSnapshot = await _roomRef.get();


    if (!roomSnapshot.exists) {
      if (mounted) {
        _showMessage(
          'This group no longer exists.',
        );
      }
      return;
    }

    final roomData = roomSnapshot.data();

    if (roomData == null) {
      if (mounted) {
        _showMessage(
          'Unable to read group information.',
        );
      }
      return;
    }

    // ------------------------------------------------------------------------
    // GET ACTIVE PARTICIPANTS
    // ------------------------------------------------------------------------

    final participants =
        List<String>.from(
      roomData['participants'] ?? <String>[],
    );

    participants.remove(_currentUserId);

    // ------------------------------------------------------------------------
    // LAST MEMBER
    //
    // There is nobody left after this user leaves.
    // ------------------------------------------------------------------------

    if (participants.isEmpty) {
      // Delete all messages and group member documents first.
      await _deleteGroupSubcollections();

      // Delete the main group document.
      await _roomRef.delete();

      if (!mounted) {
        return;
      }

      _showMessage(
        'Group deleted because you were the last member.',
      );

      Navigator.pop(context);
      return;
    }

    // ------------------------------------------------------------------------
    // OTHER MEMBERS REMAIN
    // ------------------------------------------------------------------------

    await _roomRef.update({
      'participants': participants,

      'leftBy.$_currentUserId': true,

      'leftAt.$_currentUserId':
          FieldValue.serverTimestamp(),

      'deletedFor.$_currentUserId': true,

      'deletedAt.$_currentUserId':
          FieldValue.serverTimestamp(),

      'updatedAt':
          FieldValue.serverTimestamp(),
    });

    // ------------------------------------------------------------------------
    // REMOVE CURRENT USER FROM GROUP MEMBERS
    // ------------------------------------------------------------------------

    await _roomRef
        .collection('group_members')
        .doc(_currentUserId)
        .delete();

    // ------------------------------------------------------------------------
    // UPDATE LOCAL STATE
    // ------------------------------------------------------------------------

    if (!mounted) {
      return;
    }

    setState(() {
      _hasLeftGroup = true;
      _wasRemovedFromGroup = false;
      _groupRemovedByName = '';
    });

    // ------------------------------------------------------------------------
    // RETURN TO CHAT LIST
    // ------------------------------------------------------------------------

    Navigator.pop(context);
  } on FirebaseException catch (e) {
    if (!mounted) {
      return;
    }

    _showMessage(
      'Delete failed: ${e.code}',
    );
  } catch (e) {
    if (!mounted) {
      return;
    }

    _showMessage(
      'Delete failed: $e',
    );
  }
}



// ==========================================================================
// TOP CHAT MENU
// ==========================================================================

void _showChatMenu() {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(25),
      ),
    ),
    builder: (sheetContext) {
      return SafeArea(
        child: Wrap(
          children: [
            // =================================================================
            // GROUP INFO / VIEW PROFILE
            // =================================================================

            ListTile(
              leading: Icon(
                _isGroup
                    ? Icons.info_outline_rounded
                    : Icons.person_outline_rounded,
                color: navy,
              ),
              title: Text(
                _isGroup
                    ? 'Group info'
                    : 'View Profile',
              ),
              onTap: () {
                Navigator.pop(sheetContext);

                if (_isGroup) {
                  _showGroupInfo();
                } else {
                  _openUserProfile();
                }
              },
            ),

            // =================================================================
            // SEARCH
            // =================================================================

            ListTile(
              leading: const Icon(
                Icons.search_rounded,
                color: cyan,
              ),
              title: const Text(
                'Search',
              ),
              onTap: () {
                Navigator.pop(sheetContext);

                _openMessageSearch();
              },
            ),

            // =================================================================
            // WALLPAPER
            // =================================================================

            ListTile(
              leading: const Icon(
                Icons.wallpaper_rounded,
                color: mint,
              ),
              title: const Text(
                'Wallpaper',
              ),
              onTap: () {
                Navigator.pop(sheetContext);

                _chooseWallpaper();
              },
            ),

            // =================================================================
            // LEAVE GROUP
            //
            // Available for every group participant.
            // =================================================================

            if (_isGroup)
              ListTile(
                leading: const Icon(
                  Icons.exit_to_app_rounded,
                  color: Colors.redAccent,
                ),
                title: const Text(
                  'Leave Group',
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);

                  _leaveGroup();
                },
              ),

            // =================================================================
            // DELETE GROUP
            //
            // IMPORTANT:
            // This is NOT admin-only.
            //
            // Any participant can use it.
            //
            // It will:
            //   - remove the group from THIS user's chat list
            //   - make the group unavailable to THIS user through search
            //   - record this user as having left the group
            //   - keep the group available to other participants
            //
            // The actual deletion logic will be added next.
            // =================================================================

            if (_isGroup && !_hasLeftGroup)
  ListTile(
    leading: const Icon(
      Icons.delete_forever_rounded,
      color: Colors.redAccent,
    ),
    title: const Text(
      'Delete Group',
      style: TextStyle(
        color: Colors.redAccent,
        fontWeight: FontWeight.w600,
      ),
    ),
    onTap: () {
      Navigator.pop(sheetContext);

      _deleteGroup();
    },
  ),
          ],
        ),
      );
    },
  );
}


  // ==========================================================================
  // DATE LABEL
  // ==========================================================================

  String _dateLabel(
    DateTime date,
  ) {
    final now =
        DateTime.now();

    final today =
        DateTime(
      now.year,
      now.month,
      now.day,
    );

    final messageDate =
        DateTime(
      date.year,
      date.month,
      date.day,
    );

    final difference =
        today
            .difference(
              messageDate,
            )
            .inDays;

    if (difference == 0) {
      return 'Today';
    }

    if (difference == 1) {
      return 'Yesterday';
    }

    return '${date.day}${_ordinal(date.day)} '
        '${_monthName(date.month)} ${date.year}';
  }

  String _ordinal(int day) {
    if (day >= 11 &&
        day <= 13) {
      return 'th';
    }

    switch (day % 10) {
      case 1:
        return 'st';
      case 2:
        return 'nd';
      case 3:
        return 'rd';
      default:
        return 'th';
    }
  }

  String _monthName(
    int month,
  ) {
    const months = [
      '',
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    if (month < 1 ||
        month > 12) {
      return '';
    }

    return months[month];
  }

  // ==========================================================================
  // TIME
  // ==========================================================================

  String _timeFormat(
    DateTime date,
  ) {
    final hour =
        date.hour == 0
            ? 12
            : date.hour > 12
                ? date.hour - 12
                : date.hour;

    final minute =
        date.minute
            .toString()
            .padLeft(
              2,
              '0',
            );

    final period =
        date.hour >= 12
            ? 'PM'
            : 'AM';

    return '$hour:$minute $period';
  }

  // ==========================================================================
  // SNACKBAR
  // ==========================================================================

  void _showMessage(
    String text,
  ) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).hideCurrentSnackBar();

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(
      SnackBar(
        content: Text(text),
        behavior:
            SnackBarBehavior.floating,
      ),
    );
  }

  // ==========================================================================
  // BUILD
  // ==========================================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    final isDarkMode =
        Theme.of(context)
                .brightness ==
            Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDarkMode
              ? const Color(
                  0xFF06162F,
                )
              : const Color(
                  0xFFF4FFFC,
                ),

      // ----------------------------------------------------------------------
      // APP BAR
      // ----------------------------------------------------------------------

      appBar: AppBar(
        elevation: 1,
        backgroundColor:
            isDarkMode
                ? const Color(
                    0xFF0A2243,
                  )
                : navy,

        leading:
            IconButton(
          icon:
              const Icon(
            Icons
                .arrow_back_rounded,
            color:
                Colors.white,
          ),
          onPressed: () {
            Navigator.pop(
              context,
            );
          },
        ),

        title: _isSearching
            ? TextField(
                controller:
                    _searchController,
                autofocus: true,
                style:
                    const TextStyle(
                  color:
                      Colors.white,
                ),
                decoration:
                    const InputDecoration(
                  hintText:
                      'Search messages...',
                  hintStyle:
                      TextStyle(
                    color:
                        Colors.white70,
                  ),
                  border:
                      InputBorder.none,
                ),
                onChanged:
                    (value) {
                  setState(() {
                    _searchQuery =
                        value
                            .toLowerCase();
                  });
                },
              )
            : GestureDetector(
                behavior:
                    HitTestBehavior
                        .opaque,
                onTap:
                    _openUserProfile,
                child: Row(
                  children: [
                    _buildHeaderAvatar(),

                    const SizedBox(
                      width: 10,
                    ),

                    Expanded(
                      child:
                          _buildHeaderTitle(),
                    ),
                  ],
                ),
              ),

        actions:
            _isSearching
                ? [
                    IconButton(
                      icon:
                          const Icon(
                        Icons
                            .close_rounded,
                        color:
                            Colors.white,
                      ),
                      onPressed:
                          () {
                        setState(
                          () {
                            _isSearching =
                                false;

                            _searchQuery =
                                '';

                            _searchController
                                .clear();
                          },
                        );
                      },
                    ),
                  ]
                : [
                    if (!_isGroup)
                      IconButton(
                        icon:
                            const Icon(
                          Icons
                              .phone_outlined,
                          color:
                              Colors.white,
                        ),
                        onPressed:
                            () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder:
                                  (_) =>
                                      CallScreen(
                                peerId:
                                    widget.targetUserId,
                                peerName:
                                    widget.targetUserName,
                                isVideoCall:
                                    false,
                                isCaller:
                                    true,
                              ),
                            ),
                          );
                        },
                      ),

                    if (!_isGroup)
                      IconButton(
                        icon:
                            const Icon(
                          Icons
                              .videocam_outlined,
                          color:
                              Colors.white,
                        ),
                        onPressed:
                            () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder:
                                  (_) =>
                                      CallScreen(
                                peerId:
                                    widget.targetUserId,
                                peerName:
                                    widget.targetUserName,
                                isVideoCall:
                                    true,
                                isCaller:
                                    true,
                              ),
                            ),
                          );
                        },
                      ),

                    IconButton(
                      icon:
                          const Icon(
                        Icons
                            .more_vert_rounded,
                        color:
                            Colors.white,
                      ),
                      onPressed:
                          _showChatMenu,
                    ),
                  ],
      ),

            // ----------------------------------------------------------------------
      // BODY
      // ----------------------------------------------------------------------
            // ----------------------------------------------------------------------
      // BODY
      // ----------------------------------------------------------------------
      // ----------------------------------------------------------------------
      // BODY
      // ----------------------------------------------------------------------
      body: Column(
        children: [
          Expanded(
            child: _chatRoomId.isEmpty
                ? const Center(child: Text('Unable to open this chat.'))
                : Container(
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      // LURKS THE RAW DATA STRAIGHT TO THE BACKGROUND CANVAS 👇
                      image: _wallpaperBytes != null
                          ? DecorationImage(
                              image: MemoryImage(_wallpaperBytes!),
                              fit: BoxFit.cover, // Fills your workspace canvas smoothly
                            )
                          : null,
                    ),
                    child: _buildMessages(_currentUserId, isDarkMode),
                  ),
          ),

          if (_replyingToMessage != null)
            _buildReplyBar(isDarkMode),

          if (!_isGroup && _isBlockedByOtherUser)
            _buildBlockedBanner(isDarkMode)
          else if (!_isGroup && _isRemovedByOtherUser)
            _buildRemovedByOtherUserBanner(isDarkMode)
          else if (!_isGroup && _isRemovedByCurrentUser)
            _buildRemovedBanner(isDarkMode)
          else
            _buildMessageInput(isDarkMode),
        ],
      ),
    );
  }


// ==========================================================================
// REMOVED BY OTHER USER BANNER
// ==========================================================================

Widget _buildRemovedByOtherUserBanner(
  bool isDarkMode,
) {
  final name = _removedByName.trim();

  return Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(
      18,
      14,
      18,
      14,
    ),
    decoration: BoxDecoration(
      color: isDarkMode
          ? const Color(0xFF10284A)
          : const Color(0xFFFFF4F4),
      border: Border(
        top: BorderSide(
          color: Colors.redAccent.withOpacity(0.25),
        ),
      ),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.block_rounded,
          color: Colors.redAccent,
          size: 24,
        ),

        const SizedBox(width: 12),

        Expanded(
          child: Text(
            name.isNotEmpty
                ? 'You have been removed by $name.'
                : 'You have been removed from this chat.',
            style: TextStyle(
              color: isDarkMode
                  ? Colors.white
                  : navy,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}
  // ==========================================================================
  // HEADER AVATAR
  // ==========================================================================

  Widget _buildHeaderAvatar() {
    if (_isGroup) {
      return CircleAvatar(
        radius: 20,
        backgroundColor:
            mint,
        child: Text(
          _displayName.isNotEmpty
              ? _displayName[0]
                  .toUpperCase()
              : 'G',
          style:
              const TextStyle(
            color:
                Colors.white,
            fontWeight:
                FontWeight.bold,
          ),
        ),
      );
    }

    return GestureDetector(
      onTap:
          _openUserProfile,
      child: FutureBuilder<
          DocumentSnapshot>(
        future: _firestore
            .collection('users')
            .doc(
              widget.targetUserId,
            )
            .get(),
        builder:
            (context, snapshot) {
          String? photoUrl;

          if (snapshot
                  .hasData &&
              snapshot
                  .data!
                  .exists) {
            final raw =
                snapshot.data!
                    .data();

            if (raw
                is Map<String, dynamic>) {
              photoUrl =
                  raw['photoURL']
                      ?.toString();
            }
          }

          return CircleAvatar(
            radius: 20,
            backgroundColor:
                mint,
            backgroundImage:
                photoUrl != null &&
                        photoUrl
                            .isNotEmpty
                    ? NetworkImage(
                        photoUrl,
                      )
                    : null,
            child:
                photoUrl == null ||
                        photoUrl
                            .isEmpty
                    ? Text(
                        _displayName
                                .isNotEmpty
                            ? _displayName[
                                    0]
                                .toUpperCase()
                            : '?',
                        style:
                            const TextStyle(
                          color:
                              Colors.white,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      )
                    : null,
          );
        },
      ),
    );
  }

  // ==========================================================================
  // HEADER TITLE
  // ==========================================================================

  Widget _buildHeaderTitle() {
    if (_isGroup) {
      return Column(
        crossAxisAlignment:
            CrossAxisAlignment
                .start,
        children: [
          Text(
            _displayName,
            overflow:
                TextOverflow.ellipsis,
            style:
                const TextStyle(
              color:
                  Colors.white,
              fontWeight:
                  FontWeight.bold,
              fontSize: 17,
            ),
          ),
          Text(
            '${widget.groupMembers?.length ?? 0} members',
            style:
                const TextStyle(
              color:
                  Colors.white70,
              fontSize: 11,
            ),
          ),
        ],
      );
    }

    return StreamBuilder<
        DocumentSnapshot>(
      stream:
          _roomRef.snapshots(),
      builder:
          (context, snapshot) {
        bool isTyping =
            false;

        if (snapshot
                .hasData &&
            snapshot
                .data!
                .exists) {
          final raw =
              snapshot.data!
                  .data();

          if (raw
              is Map<String, dynamic>) {
            final typing =
                raw['typing'];

            if (typing
                is Map<String, dynamic>) {
              isTyping =
                  typing[
                          widget
                              .targetUserId] ==
                      true;
            } else {
              isTyping =
                  raw[
                          widget
                              .targetUserId] ==
                      true;
            }
          }
        }

        return Column(
          crossAxisAlignment:
              CrossAxisAlignment
                  .start,
          children: [
            Text(
              _displayName,
              overflow:
                  TextOverflow.ellipsis,
              style:
                  const TextStyle(
                color:
                    Colors.white,
                fontWeight:
                    FontWeight.bold,
                fontSize: 17,
              ),
            ),
            Text(
              isTyping
                  ? 'typing...'
                  : 'ChatFlow',
              style:
                  TextStyle(
                color: isTyping
                    ? mint
                    : Colors.white70,
                fontSize: 11,
              ),
            ),
          ],
        );
      },
    );
  }


  // ==========================================================================
  // MESSAGES
  // ==========================================================================

  Widget _buildMessages(
    String currentUserId,
    bool isDarkMode,
  ) {
    return StreamBuilder<
    QuerySnapshot<Map<String, dynamic>>>(
  stream: _messagesStream,
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
          debugPrint(
            'Messages stream error: ${snapshot.error}',
          );

          return const Center(
            child: Text(
              'Unable to load messages.',
            ),
          );
        }

        final allDocs =
            snapshot.data?.docs ?? [];

        final docs = allDocs.where(
          (doc) {
            final data = doc.data();

            final hiddenFor =
                List<String>.from(
              data['hiddenFor'] ?? [],
            );

            if (hiddenFor.contains(
              currentUserId,
            )) {
              return false;
            }

            if (_searchQuery.isNotEmpty) {
              final message =
                  data['message']
                          ?.toString()
                          .toLowerCase() ??
                      '';

              return message.contains(
                _searchQuery,
              );
            }

            return true;
          },
        ).toList();

        if (docs.isEmpty) {
          return Center(
            child: Text(
              _searchQuery.isNotEmpty
                  ? 'No matching messages'
                  : 'Say hello to start the conversation! 👋',
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 15,
              ),
            ),
          );
        }

        return ListView.builder(
          reverse: true,
          padding: const EdgeInsets.fromLTRB(
            15,
            15,
            15,
            20,
          ),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];

            final data = doc.data();

            DateTime? timestamp;

            if (data['timestamp']
                is Timestamp) {
              timestamp =
                  (data['timestamp']
                          as Timestamp)
                      .toDate();
            }

            DateTime? previousTimestamp;

            if (index + 1 <
                docs.length) {
              final previous =
                  docs[index + 1].data();

              if (previous['timestamp']
                  is Timestamp) {
                previousTimestamp =
                    (previous['timestamp']
                            as Timestamp)
                        .toDate();
              }
            }

            final showDate =
                timestamp != null &&
                    (previousTimestamp ==
                            null ||
                        !_isSameDay(
                          timestamp,
                          previousTimestamp,
                        ));

            final isMe =
                data['senderId'] ==
                    currentUserId;

            return Column(
              children: [
                if (showDate)
                  _dateDivider(
                    _dateLabel(
                      timestamp!,
                    ),
                  ),

                _messageBubble(
                  doc.id,
                  data,
                  isMe,
                  isDarkMode,
                ),
              ],
            );
          },
        );
      },
    );
  }


  // ==========================================================================
  // SAME DAY
  // ==========================================================================

  bool _isSameDay(
    DateTime a,
    DateTime b,
  ) {
    return a.year == b.year &&
        a.month == b.month &&
        a.day == b.day;
  }

  // ==========================================================================
  // DATE DIVIDER
  // ==========================================================================

  Widget _dateDivider(
    String text,
  ) {
    return Padding(
      padding:
          const EdgeInsets
              .symmetric(
        vertical: 12,
      ),
      child: Container(
        padding:
            const EdgeInsets
                .symmetric(
          horizontal: 14,
          vertical: 6,
        ),
        decoration:
            BoxDecoration(
          color:
              mint.withOpacity(
            0.18,
          ),
          borderRadius:
              BorderRadius.circular(
            20,
          ),
        ),
        child: Text(
          text,
          style:
              const TextStyle(
            color: navy,
            fontSize: 12,
            fontWeight:
                FontWeight.bold,
          ),
        ),
      ),
    );
  }

  // ==========================================================================
  // MESSAGE BUBBLE
  // ==========================================================================

  Widget _messageBubble(
    String messageId,
    Map<String, dynamic> data,
    bool isMe,
    bool isDarkMode,
  ) {
    final isDeleted =
        data['isDeleted'] ==
            true;

    final type =
        data['type']
                ?.toString() ??
            'text';

    DateTime? timestamp;

    if (data['timestamp']
        is Timestamp) {
      timestamp =
          (data['timestamp']
                  as Timestamp)
              .toDate();
    }

    return GestureDetector(
      onLongPress: isDeleted
          ? null
          : () {
              _showMessageOptions(
                messageId,
                data,
                isMe,
              );
            },
      child: Align(
        alignment: isMe
            ? Alignment.centerRight
            : Alignment.centerLeft,
        child: Container(
          constraints:
              const BoxConstraints(
            maxWidth: 310,
          ),
          margin:
              const EdgeInsets
                  .symmetric(
            vertical: 4,
          ),
          padding:
              const EdgeInsets
                  .fromLTRB(
            12,
            9,
            10,
            7,
          ),
          decoration:
              BoxDecoration(
            color: isDeleted
                ? isDarkMode
                    ? const Color(
                        0xFF0F1E36,
                      )
                    : Colors
                        .grey
                        .shade200
                : isMe
                    ? cyan
                    : isDarkMode
                        ? const Color(
                            0xFF10284A,
                          )
                        : Colors.white,
            borderRadius:
                BorderRadius.circular(
              17,
            ),
            border: !isMe &&
                    !isDeleted
                ? Border.all(
                    color: Colors
                        .grey
                        .withOpacity(
                      0.15,
                    ),
                  )
                : null,
          ),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment
                    .end,
            children: [
              // --------------------------------------------------------------
              // GROUP SENDER
              // --------------------------------------------------------------

              if (_isGroup &&
                  !isMe &&
                  !isDeleted)
                _buildGroupSenderName(
                  data['senderId']
                      ?.toString(),
                ),

              // --------------------------------------------------------------
              // REPLY
              // --------------------------------------------------------------

              if (data[
                          'replyToText'] !=
                      null &&
                  !isDeleted)
                _buildReplyPreview(
                  data,
                  isMe,
                ),

              // --------------------------------------------------------------
              // MESSAGE CONTENT
              // --------------------------------------------------------------

              if (isDeleted)
                _buildDeletedMessage()
              else if (type ==
                  'image')
                _buildImageMessage(
                  data,
                  isMe,
                )
              else if (type ==
                  'file')
                _buildFileMessage(
                  data,
                  isMe,
                )
              else if (type ==
                  'audio')
                _buildAudioMessage(
                  data,
                  isMe,
                )
              else
                Align(
                  alignment:
                      Alignment.centerLeft,
                  child:
                      Text(
                    data['message']
                            ?.toString() ??
                        '',
                    style:
                        TextStyle(
                      color: isMe
                          ? Colors
                              .white
                          : isDarkMode
                              ? Colors
                                  .white
                              : navy,
                      fontSize:
                          15,
                    ),
                  ),
                ),

              const SizedBox(
                height: 3,
              ),

              // --------------------------------------------------------------
              // TIME / STAR / READ
              // --------------------------------------------------------------

              Row(
                mainAxisSize:
                    MainAxisSize.min,
                children: [
                  if (timestamp !=
                      null)
                    Text(
                      _timeFormat(
                        timestamp,
                      ),
                      style:
                          TextStyle(
                        color: isMe
                            ? Colors
                                .white70
                            : Colors
                                .grey,
                        fontSize:
                            10,
                      ),
                    ),

                  if (data[
                              'isStarred'] ==
                          true &&
                      !isDeleted)
                    const Padding(
                      padding:
                          EdgeInsets.only(
                        left: 5,
                      ),
                      child:
                          Icon(
                        Icons.star,
                        size: 12,
                        color:
                            Colors
                                .amber,
                      ),
                    ),

                  if (isMe &&
                      !isDeleted)
                    Padding(
                      padding:
                          const EdgeInsets
                              .only(
                        left: 4,
                      ),
                      child:
                          Icon(
                        _isMessageRead(
                                data)
                            ? Icons
                                .done_all_rounded
                            : Icons
                                .done_rounded,
                        size: 15,
                        color: _isMessageRead(
                                data)
                            ? navy
                            : Colors
                                .white70,
                      ),
                    ),
                ],
              ),

              // --------------------------------------------------------------
              // REACTIONS
              // --------------------------------------------------------------

              if (!isDeleted)
                _buildReactions(
                  data,
                  isMe,
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================================================
  // MESSAGE READ CHECK
  // ==========================================================================

  bool _isMessageRead(
    Map<String, dynamic> data,
  ) {
    if (!_isGroup) {
      return data['isRead'] ==
          true;
    }

    final raw =
        data['readBy'];

    if (raw is Map) {
      for (final entry
          in raw.entries) {
        if (entry.key
                .toString() !=
            _currentUserId &&
            entry.value == true) {
          return true;
        }
      }
    }

    return false;
  }

  // ==========================================================================
  // GROUP SENDER NAME
  // ==========================================================================

  Widget _buildGroupSenderName(
    String? senderId,
  ) {
    if (senderId == null ||
        senderId.isEmpty) {
      return const SizedBox
          .shrink();
    }

    return FutureBuilder<
        DocumentSnapshot<
            Map<String, dynamic>>>(
      future: _firestore
          .collection('users')
          .doc(senderId)
          .get(),
      builder:
          (context, snapshot) {
        String name =
            'ChatFlow User';

        if (snapshot
                .hasData &&
            snapshot
                .data!
                .exists) {
          final data =
              snapshot.data!
                  .data();

          if (data != null) {
            name =
                data['name']
                        ?.toString() ??
                    data['displayName']
                        ?.toString() ??
                    data['email']
                        ?.toString() ??
                    name;
          }
        }

        return Align(
          alignment:
              Alignment.centerLeft,
          child: Padding(
            padding:
                const EdgeInsets
                    .only(
              bottom: 4,
            ),
            child: Text(
              name,
              style:
                  const TextStyle(
                color: cyan,
                fontWeight:
                    FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        );
      },
    );
  }

  // ==========================================================================
  // REPLY PREVIEW
  // ==========================================================================

  Widget _buildReplyPreview(
    Map<String, dynamic> data,
    bool isMe,
  ) {
    return Container(
      width: double.infinity,
      margin:
          const EdgeInsets.only(
        bottom: 7,
      ),
      padding:
          const EdgeInsets.all(
        8,
      ),
      decoration:
          BoxDecoration(
        color:
            Colors.black
                .withOpacity(
          0.07,
        ),
        borderRadius:
            BorderRadius.circular(
          8,
        ),
        border:
            const Border(
          left: BorderSide(
            color: mint,
            width: 4,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment
                .start,
        children: [
          Text(
            data['replyToSender']
                    ?.toString() ??
                '',
            style:
                const TextStyle(
              fontSize: 11,
              fontWeight:
                  FontWeight.bold,
              color: navy,
            ),
          ),
          const SizedBox(
            height: 2,
          ),
          Text(
            data['replyToText']
                    ?.toString() ??
                '',
            maxLines: 1,
            overflow:
                TextOverflow.ellipsis,
            style:
                TextStyle(
              color: isMe
                  ? Colors.white70
                  : Colors.grey,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // DELETED MESSAGE
  // ==========================================================================

  Widget _buildDeletedMessage() {
    return const Row(
      mainAxisSize:
          MainAxisSize.min,
      children: [
        Icon(
          Icons.block_rounded,
          size: 17,
          color: Colors.grey,
        ),
        SizedBox(
          width: 6,
        ),
        Text(
          'This message was deleted',
          style:
              TextStyle(
            color:
                Colors.grey,
            fontSize: 14,
            fontStyle:
                FontStyle.italic,
          ),
        ),
      ],
    );
  }

  // ==========================================================================
  // IMAGE MESSAGE
  // ==========================================================================

  Widget _buildImageMessage(
    Map<String, dynamic> data,
    bool isMe,
  ) {
    final fileData =
        data['fileData']
            ?.toString();

    if (fileData != null &&
        fileData.isNotEmpty) {
      try {
        final bytes =
            base64Decode(
          fileData,
        );

        return ClipRRect(
          borderRadius:
              BorderRadius.circular(
            12,
          ),
          child:
              Image.memory(
            Uint8List.fromList(
              bytes,
            ),
            width: 230,
            height: 220,
            fit: BoxFit.cover,
            errorBuilder:
                (_, __, ___) {
              return const SizedBox(
                width: 230,
                height: 220,
                child: Center(
                  child:
                      Icon(
                    Icons
                        .broken_image_rounded,
                    color:
                        Colors.grey,
                  ),
                ),
              );
            },
          ),
        );
      } catch (e) {
        debugPrint(
          'Image Base64 error: $e',
        );
      }
    }

    return Row(
      mainAxisSize:
          MainAxisSize.min,
      children: [
        const Icon(
          Icons.image_rounded,
          color: cyan,
        ),
        const SizedBox(
          width: 7,
        ),
        Text(
          'Photo',
          style:
              TextStyle(
            color: isMe
                ? Colors.white
                : navy,
          ),
        ),
      ],
    );
  }

  // ==========================================================================
  // FILE MESSAGE
  // ==========================================================================

  Widget _buildFileMessage(
    Map<String, dynamic> data,
    bool isMe,
  ) {
    return Row(
      mainAxisSize:
          MainAxisSize.min,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration:
              BoxDecoration(
            color: Colors
                .white
                .withOpacity(
              0.15,
            ),
            shape:
                BoxShape.circle,
          ),
          child:
              const Icon(
            Icons
                .insert_drive_file_rounded,
            color:
                Colors.white,
          ),
        ),
        const SizedBox(
          width: 10,
        ),
        Flexible(
          child: Text(
            data['fileName']
                    ?.toString() ??
                'Document',
            style:
                TextStyle(
              color: isMe
                  ? Colors.white
                  : navy,
              fontWeight:
                  FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  // ==========================================================================
  // AUDIO MESSAGE
  // ==========================================================================

  Widget _buildAudioMessage(
    Map<String, dynamic> data,
    bool isMe,
  ) {
    return Row(
      mainAxisSize:
          MainAxisSize.min,
      children: [
        Icon(
          Icons
              .play_circle_fill_rounded,
          color: isMe
              ? Colors.white
              : cyan,
          size: 34,
        ),
        const SizedBox(
          width: 8,
        ),
        Text(
          'Voice message',
          style:
              TextStyle(
            color: isMe
                ? Colors.white
                : navy,
            fontWeight:
                FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // ==========================================================================
  // REACTIONS
  // ==========================================================================

  Widget _buildReactions(
    Map<String, dynamic> data,
    bool isMe,
  ) {
    final raw =
        data['reactions'];

    if (raw is! Map ||
        raw.isEmpty) {
      return const SizedBox
          .shrink();
    }

    final emojis =
        <String, int>{};

    for (final value
        in raw.values) {
      final emoji =
          value.toString();

      emojis[emoji] =
          (emojis[emoji] ?? 0) +
              1;
    }

    return Padding(
      padding:
          const EdgeInsets.only(
        top: 5,
      ),
      child: Align(
        alignment: isMe
            ? Alignment.centerRight
            : Alignment.centerLeft,
        child: Container(
          padding:
              const EdgeInsets
                  .symmetric(
            horizontal: 7,
            vertical: 3,
          ),
          decoration:
              BoxDecoration(
            color:
                Colors.white,
            borderRadius:
                BorderRadius.circular(
              15,
            ),
          ),
          child: Row(
            mainAxisSize:
                MainAxisSize.min,
            children: emojis.entries
                .map(
              (entry) {
                return Padding(
                  padding:
                      const EdgeInsets
                          .symmetric(
                    horizontal: 2,
                  ),
                  child: Text(
                    entry.key +
                        (entry.value >
                                1
                            ? ' ${entry.value}'
                            : ''),
                    style:
                        const TextStyle(
                      fontSize: 13,
                    ),
                  ),
                );
              },
            ).toList(),
          ),
        ),
      ),
    );
  }

  // ==========================================================================
  // REPLY BAR
  // ==========================================================================

  Widget _buildReplyBar(
    bool isDarkMode,
  ) {
    return Container(
      padding:
          const EdgeInsets
              .symmetric(
        horizontal: 15,
        vertical: 8,
      ),
      color: isDarkMode
          ? const Color(
              0xFF10284A,
            )
          : Colors.grey.shade100,
      child: Row(
        children: [
          const Icon(
            Icons.reply_rounded,
            color: cyan,
          ),

          const SizedBox(
            width: 10,
          ),

          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment
                      .start,
              children: [
                const Text(
                  'Replying to message',
                  style:
                      TextStyle(
                    color: cyan,
                    fontWeight:
                        FontWeight.bold,
                    fontSize: 12,
                  ),
                ),

                Text(
                  _replyingToMessage?[
                              'message']
                          ?.toString() ??
                      '',
                  maxLines: 1,
                  overflow:
                      TextOverflow.ellipsis,
                  style:
                      TextStyle(
                    color: isDarkMode
                        ? Colors
                            .white70
                        : navy,
                  ),
                ),
              ],
            ),
          ),

          IconButton(
            icon:
                const Icon(
              Icons
                  .close_rounded,
            ),
            onPressed:
                _clearReply,
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // BLOCKED / REMOVED BANNERS
  // ==========================================================================

  Widget _buildBlockedBanner(bool isDarkMode) {
    return SafeArea(
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(10, 7, 10, 10),
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        decoration: BoxDecoration(
          color: isDarkMode
              ? const Color(0xFF10284A)
              : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Colors.redAccent.withOpacity(0.25),
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.block_rounded,
              color: Colors.redAccent,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'You have been blocked by @${widget.targetUserName}',
                style: TextStyle(
                  color: isDarkMode ? Colors.white70 : navy,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRemovedBanner(bool isDarkMode) {
    return SafeArea(
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(10, 7, 10, 10),
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        decoration: BoxDecoration(
          color: isDarkMode
              ? const Color(0xFF10284A)
              : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: mint.withOpacity(0.35),
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.delete_outline_rounded,
              color: cyan,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'This chat has been removed from your chats.',
                style: TextStyle(
                  color: isDarkMode ? Colors.white70 : navy,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================================
  // MESSAGE INPUT
  // ==========================================================================

  Widget _buildMessageInput(
    bool isDarkMode,
  ) {
        // ==========================================================================
    // BLOCKED CHAT
    // ==========================================================================

    if (!_isGroup && _isRemovedByOtherUser) {
      return SafeArea(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 16,
          ),
          decoration: BoxDecoration(
            color: isDarkMode
                ? const Color(0xFF10284A)
                : Colors.white,
            border: Border(
              top: BorderSide(
                color: isDarkMode
                    ? Colors.white10
                    : Colors.grey.withOpacity(0.15),
              ),
            ),
          ),
          child: Text(
            'You have been blocked by $_removedByName',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isDarkMode
                  ? Colors.white70
                  : const Color(0xFF657080),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }
    return SafeArea(
      child: Padding(
        padding:
            const EdgeInsets
                .fromLTRB(
          10,
          7,
          10,
          10,
        ),
        child: Row(
          crossAxisAlignment:
              CrossAxisAlignment
                  .end,
          children: [
            // ------------------------------------------------------------------
            // TEXT FIELD
            // ------------------------------------------------------------------

            Expanded(
              child: Container(
                decoration:
                    BoxDecoration(
                  color: isDarkMode
                      ? const Color(
                          0xFF10284A,
                        )
                      : Colors.white,
                  borderRadius:
                      BorderRadius.circular(
                    25,
                  ),
                  border:
                      Border.all(
                    color: isDarkMode
                        ? Colors.white10
                        : Colors
                            .grey
                            .withOpacity(
                            0.2,
                          ),
                  ),
                ),
                child: Row(
                  children: [
                    // ----------------------------------------------------------
                    // EMOJI
                    // ----------------------------------------------------------

                    IconButton(
                      icon: Icon(
                        Icons
                            .emoji_emotions_outlined,
                        color: isDarkMode
                            ? mint
                            : cyan,
                      ),
                      onPressed:
                          _showEmojiPicker,
                    ),

                    // ----------------------------------------------------------
// TEXT / GROUP LEFT MESSAGE
// ----------------------------------------------------------

Expanded(
  child: _isGroup &&
          (_hasLeftGroup || _wasRemovedFromGroup)
      ? Center(
          child: Text(
            _wasRemovedFromGroup
                ? (_groupRemovedByName.isNotEmpty
                    ? 'You were removed by $_groupRemovedByName'
                    : 'You were removed from this group')
                : 'You left this group',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isDarkMode
                  ? Colors.white70
                  : Colors.grey.shade600,
              fontSize: 14,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w500,
            ),
          ),
        )
      : TextField(
          controller: _messageController,
          minLines: 1,
          maxLines: 5,
          textInputAction: TextInputAction.send,
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              _sendMessage();
            }
          },
          style: TextStyle(
            color: isDarkMode
                ? Colors.white
                : navy,
          ),
          decoration: const InputDecoration(
            hintText: 'Type a message...',
            hintStyle: TextStyle(
              color: Colors.grey,
            ),
            border: InputBorder.none,
          ),
        ),
),

                    // ----------------------------------------------------------
                    // ATTACHMENT
                    // ----------------------------------------------------------

                    IconButton(
                      icon: Icon(
                        Icons
                            .attach_file_rounded,
                        color: isDarkMode
                            ? mint
                            : cyan,
                      ),
                      onPressed:
                          _isSendingFile
                              ? null
                              : _showAttachmentOptions,
                    ),

                    // ----------------------------------------------------------
                    // CAMERA
                    // ----------------------------------------------------------

                    IconButton(
                      icon: Icon(
                        Icons
                            .camera_alt_outlined,
                        color: isDarkMode
                            ? mint
                            : cyan,
                      ),
                      onPressed:
                          _isSendingFile
                              ? null
                              : _openCamera,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(
              width: 7,
            ),

            // ------------------------------------------------------------------
            // RECORD
            // ------------------------------------------------------------------

            CircleAvatar(
              radius: 24,
              backgroundColor:
                  _isRecording
                      ? Colors
                          .redAccent
                      : cyan,
              child:
                  IconButton(
                icon: Icon(
                  _isRecording
                      ? Icons
                          .stop_rounded
                      : Icons
                          .mic_rounded,
                  color:
                      Colors.white,
                ),
                onPressed:
                    _toggleRecording,
              ),
            ),

            const SizedBox(
              width: 7,
            ),

            // ------------------------------------------------------------------
            // SEND
            // ------------------------------------------------------------------

            CircleAvatar(
  radius: 24,
  backgroundColor:
      (!_isGroup &&
              (_isRemovedByOtherUser ||
                  _isRemovedByCurrentUser ||
                  _isBlockedByOtherUser))
          ? Colors.grey
          : cyan,
  child: IconButton(
    icon: const Icon(
      Icons.send_rounded,
      color: Colors.white,
    ),
    onPressed:
        (!_isGroup &&
                (_isRemovedByOtherUser ||
                    _isRemovedByCurrentUser ||
                    _isBlockedByOtherUser))
            ? null
            : _sendMessage,
  ),
),
          ],
        ),
      ),
    );
  }

  // ==========================================================================
  // DISPOSE
  // ==========================================================================

  @override
  void dispose() {
    _typingTimer?.cancel();
    _roomStatusSubscription?.cancel();

    // We intentionally don't await this because dispose()
    // cannot be async.
    _setTypingStatus(false);

    _messageController
        .removeListener(
      _handleTyping,
    );

    _messageController
        .dispose();

    _searchController
        .dispose();

    _audioRecorder.dispose();

    super.dispose();
  }
}