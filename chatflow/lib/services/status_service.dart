// ============================================================================
// FILE PATH: lib/services/status_service.dart
// ============================================================================
//
// Handles everything Firestore-related for Status updates:
//   - Posting text or photo statuses (base64, same pattern as chat images —
//     no Firebase Storage needed)
//   - Figuring out who your "contacts" are (mutual accepted chat_requests)
//   - Marking a status as viewed
//   - Cleaning up expired (24h+) statuses
//
// ============================================================================

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class StatusService {
  StatusService._internal();

  static final StatusService instance = StatusService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String get _myUid => _auth.currentUser?.uid ?? '';

  CollectionReference<Map<String, dynamic>> get _statusesRef =>
      _firestore.collection('statuses');

  // ==========================================================================
  // CONTACTS (mutual accepted chat_requests)
  // ==========================================================================

  Future<List<String>> getContactIds() async {
    if (_myUid.isEmpty) return [];

    final sent = await _firestore
        .collection('chat_requests')
        .where('senderId', isEqualTo: _myUid)
        .where('status', isEqualTo: 'accepted')
        .get();

    final received = await _firestore
        .collection('chat_requests')
        .where('receiverId', isEqualTo: _myUid)
        .where('status', isEqualTo: 'accepted')
        .get();

    final contactIds = <String>{};

    for (final doc in sent.docs) {
      final receiverId = doc.data()['receiverId']?.toString();
      if (receiverId != null) contactIds.add(receiverId);
    }

    for (final doc in received.docs) {
      final senderId = doc.data()['senderId']?.toString();
      if (senderId != null) contactIds.add(senderId);
    }

    return contactIds.toList();
  }

  // ==========================================================================
  // POST TEXT STATUS
  // ==========================================================================

  Future<void> postTextStatus({
    required String text,
    required String backgroundColorHex,
  }) async {
    if (_myUid.isEmpty || text.trim().isEmpty) return;

    await _statusesRef.add({
      'userId': _myUid,
      'type': 'text',
      'content': text.trim(),
      'backgroundColor': backgroundColorHex,
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(
        DateTime.now().add(const Duration(hours: 24)),
      ),
      'viewedBy': <String>[],
    });
  }

  // ==========================================================================
  // POST PHOTO STATUS
  // ==========================================================================

  Future<void> postPhotoStatus({
    required List<int> imageBytes,
    String caption = '',
  }) async {
    if (_myUid.isEmpty || imageBytes.isEmpty) return;

    const maxSize = 700 * 1024;
    if (imageBytes.length > maxSize) {
      throw StateError('Image too large. Please pick a smaller photo.');
    }

    final base64Data = base64Encode(imageBytes);

    await _statusesRef.add({
      'userId': _myUid,
      'type': 'image',
      'content': base64Data,
      'caption': caption.trim(),
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(
        DateTime.now().add(const Duration(hours: 24)),
      ),
      'viewedBy': <String>[],
    });
  }

  // ==========================================================================
  // MARK VIEWED
  // ==========================================================================

  Future<void> markViewed(String statusId) async {
    if (_myUid.isEmpty) return;

    try {
      await _statusesRef.doc(statusId).update({
        'viewedBy': FieldValue.arrayUnion([_myUid]),
      });
    } catch (_) {
      // Non-fatal — viewing should never crash the UI.
    }
  }

  // ==========================================================================
  // DELETE MY STATUS
  // ==========================================================================

  Future<void> deleteStatus(String statusId) async {
    await _statusesRef.doc(statusId).delete();
  }

  // ==========================================================================
  // CLEANUP EXPIRED (run opportunistically when the tab opens)
  // ==========================================================================

  Future<void> cleanupExpiredForMe() async {
    if (_myUid.isEmpty) return;

    try {
      final expired = await _statusesRef
          .where('userId', isEqualTo: _myUid)
          .where('expiresAt', isLessThan: Timestamp.now())
          .get();

      if (expired.docs.isEmpty) return;

      final batch = _firestore.batch();
      for (final doc in expired.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } catch (_) {
      // Non-fatal.
    }
  }

  // ==========================================================================
  // STREAM: all non-expired statuses for a given set of user IDs
  // ==========================================================================

  Stream<QuerySnapshot<Map<String, dynamic>>> streamStatusesFor(
    List<String> userIds,
  ) {
    if (userIds.isEmpty) {
      return const Stream.empty();
    }

    // Firestore whereIn supports up to 30 values — fine for a beta app.
    final limitedIds = userIds.take(30).toList();

    return _statusesRef
        .where('userId', whereIn: limitedIds)
        .where('expiresAt', isGreaterThan: Timestamp.now())
        .orderBy('expiresAt')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }
}