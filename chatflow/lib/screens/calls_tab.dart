// ============================================================================
// FILE PATH: lib/screens/calls_tab.dart
// ============================================================================
//
// Replaces your existing calls_tab.dart entirely.
//
// - Real call history from the 'calls' collection (caller or callee == me)
// - Missed calls shown in red, with voice/video + incoming/outgoing icons
// - "New Call" button opens a contact picker (same contacts list used by
//   Status — mutual accepted chat_requests) so you can start a call to
//   anyone you're connected with, not just from inside a chat
// - Tapping a history entry calls that person back directly
//
// Depends on:
//   lib/services/call_service.dart   (updated version, with markMissed)
//   lib/services/status_service.dart (reused for getContactIds())
//   lib/screens/call_screen.dart     (updated version, with no-answer timeout)
//
// ============================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/call_service.dart';
import '../services/status_service.dart';
import 'call_screen.dart';

class CallsTab extends StatefulWidget {
  final bool isDarkMode;
  final Color primaryText;
  final Color secondaryText;
  final Color navy;
  final Color mint;
  final Color cyan;
  final Color skyBlue;
  final Function(String) showSnackbar;

  const CallsTab({
    super.key,
    required this.isDarkMode,
    required this.primaryText,
    required this.secondaryText,
    required this.navy,
    required this.mint,
    required this.cyan,
    required this.skyBlue,
    required this.showSnackbar,
  });

  @override
  State<CallsTab> createState() => _CallsTabState();
}

class _CallsTabState extends State<CallsTab> {
  String get _myUid => FirebaseAuth.instance.currentUser?.uid ?? '';

  // ==========================================================================
  // START A NEW CALL — CONTACT PICKER
  // ==========================================================================

  Future<void> _showNewCallSheet() async {
    final contactIds = await StatusService.instance.getContactIds();

    if (!mounted) return;

    if (contactIds.isEmpty) {
      widget.showSnackbar(
        'No contacts yet. Connect with someone from Chats first.',
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor:
          widget.isDarkMode ? const Color(0xFF10284A) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.7,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Text(
                    'Call a Contact',
                    style: TextStyle(
                      color: widget.primaryText,
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    itemCount: contactIds.length,
                    itemBuilder: (context, index) {
                      return _contactPickerTile(contactIds[index]);
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

  Widget _contactPickerTile(String userId) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future:
          FirebaseFirestore.instance.collection('users').doc(userId).get(),
      builder: (context, snapshot) {
        String name = 'ChatFlow User';

        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data();
          if (data != null) {
            name = data['name']?.toString() ??
                data['displayName']?.toString() ??
                data['email']?.toString() ??
                name;
          }
        }

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: widget.mint,
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: const TextStyle(color: Colors.white),
            ),
          ),
          title: Text(name, style: TextStyle(color: widget.primaryText)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(Icons.call_rounded, color: widget.cyan),
                onPressed: () {
                  Navigator.pop(context);
                  _startCall(userId, name, false);
                },
              ),
              IconButton(
                icon: Icon(Icons.videocam_rounded, color: widget.cyan),
                onPressed: () {
                  Navigator.pop(context);
                  _startCall(userId, name, true);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _startCall(String peerId, String peerName, bool isVideoCall) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CallScreen(
          peerId: peerId,
          peerName: peerName,
          isVideoCall: isVideoCall,
          isCaller: true,
        ),
      ),
    );
  }

  // ==========================================================================
  // BUILD
  // ==========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        backgroundColor: widget.cyan,
        onPressed: _showNewCallSheet,
        child: const Icon(Icons.add_call, color: Colors.white),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('calls')
            .where('callerId', isEqualTo: _myUid)
            .snapshots(),
        builder: (context, callerSnapshot) {
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('calls')
                .where('calleeId', isEqualTo: _myUid)
                .snapshots(),
            builder: (context, calleeSnapshot) {
              final allDocs = [
                ...(callerSnapshot.data?.docs ?? []),
                ...(calleeSnapshot.data?.docs ?? []),
              ];

              // Sort newest first.
              allDocs.sort((a, b) {
                final aTime = a.data()['createdAt'] as Timestamp?;
                final bTime = b.data()['createdAt'] as Timestamp?;
                if (aTime == null || bTime == null) return 0;
                return bTime.compareTo(aTime);
              });

              // Skip calls still ringing (not yet resolved) from history.
              final resolvedDocs = allDocs.where((doc) {
                final status = doc.data()['status'] as String?;
                return status != 'ringing';
              }).toList();

              return ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  InkWell(
                    onTap: _showNewCallSheet,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: widget.isDarkMode
                            ? const Color(0xFF10284A)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: widget.mint.withOpacity(0.4),
                        ),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 22,
                            backgroundColor: widget.cyan,
                            child: const Icon(Icons.add_call,
                                color: Colors.white),
                          ),
                          const SizedBox(width: 14),
                          Text(
                            'New Call',
                            style: TextStyle(
                              color: widget.primaryText,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (resolvedDocs.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 40),
                      child: Column(
                        children: [
                          Icon(Icons.call_outlined,
                              size: 50, color: widget.secondaryText),
                          const SizedBox(height: 14),
                          Text(
                            'No call history yet',
                            style: TextStyle(
                                color: widget.primaryText,
                                fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Calls you make or receive will show up here.',
                            style: TextStyle(color: widget.secondaryText),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  else
                    ...resolvedDocs.map((doc) => _callHistoryTile(doc)),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _callHistoryTile(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();

    final isOutgoing = data['callerId'] == _myUid;
    final peerName = isOutgoing
        ? (data['calleeName']?.toString() ?? 'ChatFlow User')
        : (data['callerName']?.toString() ?? 'ChatFlow User');
    final peerId = isOutgoing
        ? (data['calleeId']?.toString() ?? '')
        : (data['callerId']?.toString() ?? '');

    final status = data['status']?.toString() ?? '';
    final isVideoCall = data['isVideoCall'] == true;
    final isMissed = status == 'missed' ||
        (status == 'rejected' && !isOutgoing);

    DateTime? createdAt;
    if (data['createdAt'] is Timestamp) {
      createdAt = (data['createdAt'] as Timestamp).toDate();
    }

    String subtitleText;
    if (status == 'missed') {
      subtitleText = isOutgoing ? 'No answer' : 'Missed';
    } else if (status == 'rejected') {
      subtitleText = isOutgoing ? 'Declined' : 'Declined';
    } else {
      subtitleText = isOutgoing ? 'Outgoing' : 'Incoming';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: widget.isDarkMode ? const Color(0xFF10284A) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: widget.isDarkMode
              ? const Color(0xFF24486A)
              : const Color(0xFFBCEDE2),
          width: 1,
        ),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: widget.mint,
          child: Text(
            peerName.isNotEmpty ? peerName[0].toUpperCase() : '?',
            style: const TextStyle(color: Colors.white),
          ),
        ),
        title: Text(
          peerName,
          style: TextStyle(color: widget.primaryText, fontWeight: FontWeight.bold),
        ),
        subtitle: Row(
  children: [
    Icon(
      isOutgoing
          ? Icons.call_made_rounded
          : Icons.call_received_rounded,
      size: 14,
      color: isMissed
          ? Colors.redAccent
          : widget.secondaryText,
    ),

    const SizedBox(width: 4),

    Expanded(
      child: Text(
        createdAt != null
            ? '$subtitleText • ${_formatTime(createdAt)}'
            : subtitleText,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: isMissed
              ? Colors.redAccent
              : widget.secondaryText,
          fontSize: 12,
        ),
      ),
    ),
  ],
),
        trailing: IconButton(
          icon: Icon(
            isVideoCall ? Icons.videocam_rounded : Icons.call_rounded,
            color: widget.cyan,
          ),
          onPressed: peerId.isEmpty
              ? null
              : () => _startCall(peerId, peerName, isVideoCall),
        ),
      ),
    );
  }

  String _formatTime(DateTime date) {
    final now = DateTime.now();
    final isToday = now.year == date.year &&
        now.month == date.month &&
        now.day == date.day;

    final hour = date.hour == 0
        ? 12
        : date.hour > 12
            ? date.hour - 12
            : date.hour;
    final minute = date.minute.toString().padLeft(2, '0');
    final period = date.hour >= 12 ? 'PM' : 'AM';
    final time = '$hour:$minute $period';

    if (isToday) return time;
    return '${date.day}/${date.month} • $time';
  }
}