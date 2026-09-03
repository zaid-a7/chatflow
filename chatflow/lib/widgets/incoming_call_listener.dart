// ============================================================================
// FILE PATH: lib/widgets/incoming_call_listener.dart
// ============================================================================
//
// Wrap this around your home/chat_screen widget tree (see usage note below).
// It listens for incoming calls via CallService.incomingCalls() and pushes
// CallScreen automatically the moment a call starts ringing for this user.
//
// ============================================================================

import 'package:flutter/material.dart';

import '../services/call_service.dart';
import '../screens/call_screen.dart';

class IncomingCallListener extends StatefulWidget {
  final Widget child;

  const IncomingCallListener({
    super.key,
    required this.child,
  });

  @override
  State<IncomingCallListener> createState() =>
      _IncomingCallListenerState();
}

class _IncomingCallListenerState extends State<IncomingCallListener> {
  // Tracks the call ID currently being shown, so we don't push the same
  // incoming call screen twice if Firestore fires the listener again.
  String? _activeCallId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: CallService.instance.incomingCalls(),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
          final callDoc = snapshot.data!.docs.first;
          final data = callDoc.data();

          if (_activeCallId != callDoc.id) {
            _activeCallId = callDoc.id;

            // Defer navigation until after this build completes.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _showIncomingCall(callDoc.id, data);
            });
          }
        }

        return widget.child;
      },
    );
  }

  void _showIncomingCall(String callId, Map<String, dynamic> data) {
    if (!mounted) return;

    final callerName =
        data['callerName']?.toString() ?? 'Unknown caller';
    final callerId = data['callerId']?.toString() ?? '';
    final isVideoCall = data['isVideoCall'] == true;

    Navigator.of(context, rootNavigator: true)
        .push(
      MaterialPageRoute(
        builder: (_) => CallScreen(
          peerId: callerId,
          peerName: callerName,
          isVideoCall: isVideoCall,
          isCaller: false,
          incomingCallId: callId,
        ),
        fullscreenDialog: true,
      ),
    )
        .then((_) {
      // Screen closed (call ended/declined/answered-and-finished) —
      // allow the next incoming call to trigger navigation again.
      _activeCallId = null;
    });
  }
}