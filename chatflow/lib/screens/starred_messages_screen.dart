// ============================================================================
// FILE PATH: lib/screens/starred_messages_screen.dart
// ============================================================================
//
// Shows every message the current user has starred, across all their chats
// and groups. Uses a Firestore collectionGroup query, which searches every
// 'messages' subcollection in the whole database at once — safe to do
// because your Firestore Security Rules already restrict each message to
// its actual participants, so this will only ever return messages you're
// allowed to see.
//
// ============================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class StarredMessagesScreen extends StatelessWidget {
  const StarredMessagesScreen({super.key});

  static const Color navy = Color(0xFF102A5C);
  static const Color cyan = Color(0xFF16AFC1);

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Starred Messages'),
        backgroundColor: navy,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collectionGroup('messages')
            .where('isStarred', isEqualTo: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: cyan),
            );
          }

          if (snapshot.hasError) {
            // Most likely cause: Firestore needs a single-field index for
            // 'isStarred' on a collection group, which it will usually
            // create automatically — check the Debug Console for a link
            // to create it manually if this error appears.
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Unable to load starred messages. If this persists, '
                  'check the Debug Console for a Firestore index link.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
            return const Center(
              child: Text(
                'No starred messages yet.',
                style: TextStyle(color: Colors.grey, fontSize: 15),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(15),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data();
              final isMe = data['senderId'] == currentUserId;

              DateTime? timestamp;
              if (data['timestamp'] is Timestamp) {
                timestamp = (data['timestamp'] as Timestamp).toDate();
              }

              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                child: ListTile(
                  leading: const Icon(Icons.star_rounded, color: Colors.amber),
                  title: Text(
                    data['message']?.toString() ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    isMe ? 'You' : 'Them',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: timestamp != null
                      ? Text(
                          '${timestamp.day}/${timestamp.month}/${timestamp.year}',
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                        )
                      : null,
                ),
              );
            },
          );
        },
      ),
    );
  }
}