// ============================================================================
// FILE PATH: lib/services/call_service.dart
// ============================================================================
//
// ChatFlow CallService
//
// Handles:
// - Voice calls
// - Video calls
// - WebRTC offer/answer signaling through Firestore
// - ICE candidate exchange
// - Call status updates
// - Call history timestamps
// - Missed-call timeout support
//
// ============================================================================

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

enum CallStatus {
  ringing,
  accepted,
  rejected,
  ended,
  missed,
}

extension CallStatusValue on CallStatus {
  String get value => toString().split('.').last;
}

class CallService {
  CallService._internal();

  static final CallService instance = CallService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;


  // ==========================================================================
  // WEBRTC CONFIGURATION
  // ==========================================================================

  static const Map<String, dynamic> _iceServers = {
    'iceServers': [
      {
        'urls': ['stun:stun.l.google.com:19302'],
      },
      {
        'urls': ['turn:openrelay.metered.ca:80'],
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
      {
        'urls': ['turn:openrelay.metered.ca:443'],
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
      {
        'urls': ['turn:openrelay.metered.ca:443?transport=tcp'],
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
    ],
  };

  static const Map<String, dynamic> _sdpConstraints = {
    'mandatory': {
      'OfferToReceiveAudio': true,
      'OfferToReceiveVideo': true,
    },
    'optional': [],
  };

  // ==========================================================================
  // WEBRTC STATE
  // ==========================================================================

  RTCPeerConnection? _peerConnection;

  MediaStream? localStream;
  MediaStream? remoteStream;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _callDocSub;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
      _remoteCandidatesSub;

  String? currentCallId;

  // ==========================================================================
  // EVENTS
  // ==========================================================================

  final StreamController<MediaStream> onRemoteStream =
      StreamController<MediaStream>.broadcast();

  final StreamController<CallStatus> onCallStatusChanged =
      StreamController<CallStatus>.broadcast();

  final StreamController<RTCPeerConnectionState> onConnectionStateChanged =
      StreamController<RTCPeerConnectionState>.broadcast();

  // ==========================================================================
  // FIREBASE HELPERS
  // ==========================================================================

  String get _myUid => _auth.currentUser?.uid ?? '';

  CollectionReference<Map<String, dynamic>> get _callsRef =>
      _firestore.collection('calls');

  // ==========================================================================
  // LOCAL MEDIA
  // ==========================================================================

  Future<MediaStream> _getLocalStream(bool isVideoCall) async {
    final constraints = {
      'audio': true,
      'video': isVideoCall
          ? {
              'facingMode': 'user',
            }
          : false,
    };

    final stream = await navigator.mediaDevices.getUserMedia(constraints);

    localStream = stream;

    return stream;
  }

  // ==========================================================================
  // PEER CONNECTION
  // ==========================================================================

  Future<RTCPeerConnection> _createPeerConnection() async {
    final pc = await createPeerConnection(_iceServers);

    pc.onTrack = (RTCTrackEvent event) {
      if (event.streams.isEmpty) return;

      final stream = event.streams.first;

      remoteStream = stream;

      if (!onRemoteStream.isClosed) {
        onRemoteStream.add(stream);
      }
    };

    pc.onConnectionState = (RTCPeerConnectionState state) {
      if (!onConnectionStateChanged.isClosed) {
        onConnectionStateChanged.add(state);
      }

      // IMPORTANT:
      // Do NOT immediately end the call on DISCONNECTED.
      //
      // WebRTC can temporarily enter a disconnected state while trying
      // to recover network connectivity.
      //
      // FAILED is the state we treat as a real WebRTC failure.
      if (state ==
          RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        if (!onCallStatusChanged.isClosed) {
          onCallStatusChanged.add(CallStatus.ended);
        }
      }
    };

    _peerConnection = pc;

    return pc;
  }

  // ==========================================================================
  // MAKE OUTGOING CALL
  // ==========================================================================

  Future<String> makeCall({
    required String calleeId,
    required String calleeName,
    required bool isVideoCall,
  }) async {
    if (_myUid.isEmpty) {
      throw StateError('Not logged in.');
    }

    // Clean up any previous WebRTC session before starting a new one.
    await _cleanup();

    final callerName =
        _auth.currentUser?.displayName?.trim().isNotEmpty == true
            ? _auth.currentUser!.displayName!.trim()
            : 'ChatFlow User';

    // ------------------------------------------------------------------------
    // 1. Get microphone/camera FIRST.
    // ------------------------------------------------------------------------

    final stream = await _getLocalStream(isVideoCall);

    // ------------------------------------------------------------------------
    // 2. Create peer connection.
    // ------------------------------------------------------------------------

    final pc = await _createPeerConnection();

    // ------------------------------------------------------------------------
    // 3. Add local tracks.
    // ------------------------------------------------------------------------

    for (final track in stream.getTracks()) {
      await pc.addTrack(track, stream);
    }

    // ------------------------------------------------------------------------
    // 4. Create Firestore call document.
    //
    // IMPORTANT:
    // We do NOT mark the call as ringing until the offer has been created
    // and stored. This prevents the receiver from accepting a call before
    // the offer exists.
    // ------------------------------------------------------------------------

    final callDoc = _callsRef.doc();

    currentCallId = callDoc.id;

    // Initially create the call document without "ringing".
    await callDoc.set({
      'callerId': _myUid,
      'callerName': callerName,
      'calleeId': calleeId,
      'calleeName': calleeName,
      'isVideoCall': isVideoCall,
      'status': 'preparing',
      'createdAt': FieldValue.serverTimestamp(),
    });

    // ------------------------------------------------------------------------
    // 5. ICE candidates generated by caller.
    // ------------------------------------------------------------------------

    pc.onIceCandidate = (RTCIceCandidate candidate) async {
      try {
        await callDoc.collection('callerCandidates').add(
              candidate.toMap(),
            );
      } catch (_) {
        // Ignore candidate writes after the call has already ended.
      }
    };

    // ------------------------------------------------------------------------
    // 6. Create WebRTC offer.
    // ------------------------------------------------------------------------

    final offer = await pc.createOffer(_sdpConstraints);

    await pc.setLocalDescription(offer);

    // ------------------------------------------------------------------------
    // 7. Save offer AND change status to ringing atomically.
    //
    // The receiver's incomingCalls() listener only watches for "ringing".
    // Therefore, when the receiver sees the call, the offer is guaranteed
    // to already exist.
    // ------------------------------------------------------------------------

    await callDoc.update({
      'offer': {
        'sdp': offer.sdp,
        'type': offer.type,
      },
      'status': CallStatus.ringing.value,
    });

    // ------------------------------------------------------------------------
    // 8. Listen for answer/status changes.
    // ------------------------------------------------------------------------

    _callDocSub = callDoc.snapshots().listen(
      (snapshot) async {
        final data = snapshot.data();

        if (data == null) return;

        final status = data['status'] as String?;

        // --------------------------------------------------------------
        // Receiver accepted the call.
        // --------------------------------------------------------------

        if (status == CallStatus.accepted.value) {
          final answerData = data['answer'];

          if (answerData is Map<String, dynamic>) {
            final currentRemoteDescription =
                await pc.getRemoteDescription();

            if (currentRemoteDescription == null) {
              final sdp = answerData['sdp'] as String?;
              final type = answerData['type'] as String?;

              if (sdp != null && type != null) {
                await pc.setRemoteDescription(
                  RTCSessionDescription(
                    sdp,
                    type,
                  ),
                );
              }
            }
          }
        }

        // --------------------------------------------------------------
        // Rejected / missed / ended.
        // --------------------------------------------------------------

        if (status == CallStatus.rejected.value) {
          if (!onCallStatusChanged.isClosed) {
            onCallStatusChanged.add(CallStatus.rejected);
          }
        } else if (status == CallStatus.missed.value) {
          if (!onCallStatusChanged.isClosed) {
            onCallStatusChanged.add(CallStatus.missed);
          }
        } else if (status == CallStatus.ended.value) {
          if (!onCallStatusChanged.isClosed) {
            onCallStatusChanged.add(CallStatus.ended);
          }
        }
      },
      onError: (_) {
        // Firestore listener errors should not crash the call screen.
      },
    );

    // ------------------------------------------------------------------------
    // 9. Listen for receiver ICE candidates.
    // ------------------------------------------------------------------------

    _remoteCandidatesSub =
        callDoc.collection('calleeCandidates').snapshots().listen(
      (snapshot) async {
        for (final change in snapshot.docChanges) {
          if (change.type != DocumentChangeType.added) {
            continue;
          }

          final data = change.doc.data();

          if (data == null) continue;

          try {
            final candidate = RTCIceCandidate(
              data['candidate'] as String?,
              data['sdpMid'] as String?,
              data['sdpMLineIndex'] as int?,
            );

            await pc.addCandidate(candidate);
          } catch (_) {
            // Ignore malformed/late ICE candidates.
          }
        }
      },
      onError: (_) {},
    );

    return callDoc.id;
  }

  // ==========================================================================
  // INCOMING CALLS
  // ==========================================================================

  Stream<QuerySnapshot<Map<String, dynamic>>> incomingCalls() {
    if (_myUid.isEmpty) {
      return const Stream.empty();
    }

    return _callsRef
        .where('calleeId', isEqualTo: _myUid)
        .where('status', isEqualTo: CallStatus.ringing.value)
        .snapshots();
  }

  // ==========================================================================
  // ANSWER INCOMING CALL
  // ==========================================================================

  Future<void> answerCall({
    required String callId,
    required bool isVideoCall,
  }) async {
    if (_myUid.isEmpty) {
      throw StateError('Not logged in.');
    }

    // Clean up any old WebRTC session.
    await _cleanup();

    final callDoc = _callsRef.doc(callId);

    currentCallId = callId;

    // ------------------------------------------------------------------------
    // 1. Read the call document.
    // ------------------------------------------------------------------------

    final snapshot = await callDoc.get();

    if (!snapshot.exists) {
      throw StateError('Call no longer exists.');
    }

    final data = snapshot.data();

    if (data == null) {
      throw StateError('Call data is unavailable.');
    }

    final offerData = data['offer'];

    if (offerData is! Map<String, dynamic>) {
      throw StateError('Call offer is not available yet.');
    }

    final offerSdp = offerData['sdp'] as String?;
    final offerType = offerData['type'] as String?;

    if (offerSdp == null || offerType == null) {
      throw StateError('Invalid call offer.');
    }

    // ------------------------------------------------------------------------
    // 2. Get receiver microphone/camera.
    // ------------------------------------------------------------------------

    final stream = await _getLocalStream(isVideoCall);

    // ------------------------------------------------------------------------
    // 3. Create receiver peer connection.
    // ------------------------------------------------------------------------

    final pc = await _createPeerConnection();

    // ------------------------------------------------------------------------
    // 4. Add receiver tracks.
    // ------------------------------------------------------------------------

    for (final track in stream.getTracks()) {
      await pc.addTrack(track, stream);
    }

    // ------------------------------------------------------------------------
    // 5. Receiver ICE candidates.
    // ------------------------------------------------------------------------

    pc.onIceCandidate = (RTCIceCandidate candidate) async {
      try {
        await callDoc.collection('calleeCandidates').add(
              candidate.toMap(),
            );
      } catch (_) {
        // Ignore candidate writes after call ends.
      }
    };

    // ------------------------------------------------------------------------
    // 6. Set caller's offer as remote description.
    // ------------------------------------------------------------------------

    await pc.setRemoteDescription(
      RTCSessionDescription(
        offerSdp,
        offerType,
      ),
    );

    // ------------------------------------------------------------------------
    // 7. Create answer.
    // ------------------------------------------------------------------------

    final answer = await pc.createAnswer(_sdpConstraints);

    await pc.setLocalDescription(answer);

    // ------------------------------------------------------------------------
    // 8. Save answer and mark accepted.
    // ------------------------------------------------------------------------

    await callDoc.update({
      'status': CallStatus.accepted.value,
      'answeredAt': FieldValue.serverTimestamp(),
      'answer': {
        'sdp': answer.sdp,
        'type': answer.type,
      },
    });

    // ------------------------------------------------------------------------
    // 9. Listen for caller ICE candidates.
    // ------------------------------------------------------------------------

    _remoteCandidatesSub =
        callDoc.collection('callerCandidates').snapshots().listen(
      (snapshot) async {
        for (final change in snapshot.docChanges) {
          if (change.type != DocumentChangeType.added) {
            continue;
          }

          final candidateData = change.doc.data();

          if (candidateData == null) continue;

          try {
            final candidate = RTCIceCandidate(
              candidateData['candidate'] as String?,
              candidateData['sdpMid'] as String?,
              candidateData['sdpMLineIndex'] as int?,
            );

            await pc.addCandidate(candidate);
          } catch (_) {
            // Ignore malformed/late ICE candidates.
          }
        }
      },
      onError: (_) {},
    );

    // ------------------------------------------------------------------------
    // 10. Listen for call ending.
    // ------------------------------------------------------------------------

    _callDocSub = callDoc.snapshots().listen(
      (snapshot) {
        final snapshotData = snapshot.data();

        if (snapshotData == null) return;

        final status = snapshotData['status'] as String?;

        if (status == CallStatus.ended.value ||
            status == CallStatus.rejected.value ||
            status == CallStatus.missed.value) {
          if (!onCallStatusChanged.isClosed) {
            if (status == CallStatus.rejected.value) {
              onCallStatusChanged.add(CallStatus.rejected);
            } else if (status == CallStatus.missed.value) {
              onCallStatusChanged.add(CallStatus.missed);
            } else {
              onCallStatusChanged.add(CallStatus.ended);
            }
          }
        }
      },
      onError: (_) {},
    );
  }

  // ==========================================================================
  // REJECT CALL
  // ==========================================================================

  Future<void> rejectCall(String callId) async {
    try {
      await _callsRef.doc(callId).update({
        'status': CallStatus.rejected.value,
        'endedAt': FieldValue.serverTimestamp(),
      });
    } finally {
      await _cleanup();
    }
  }

  // ==========================================================================
  // MARK MISSED
  // ==========================================================================

  Future<void> markMissed(String callId) async {
    try {
      await _callsRef.doc(callId).update({
        'status': CallStatus.missed.value,
        'endedAt': FieldValue.serverTimestamp(),
      });
    } finally {
      await _cleanup();
    }
  }

  // ==========================================================================
  // END CALL
  // ==========================================================================

  Future<void> endCall() async {
    final callId = currentCallId;

    if (callId != null) {
      try {
        await _callsRef.doc(callId).update({
          'status': CallStatus.ended.value,
          'endedAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {
        // The call document may already have been removed/updated.
      }
    }

    await _cleanup();
  }

  // ==========================================================================
  // MUTE
  // ==========================================================================

  void toggleMute(bool mute) {
    final tracks = localStream?.getAudioTracks() ?? [];

    for (final track in tracks) {
      track.enabled = !mute;
    }
  }

  // ==========================================================================
  // CAMERA
  // ==========================================================================

  void toggleCamera(bool cameraOff) {
    final tracks = localStream?.getVideoTracks() ?? [];

    for (final track in tracks) {
      track.enabled = !cameraOff;
    }
  }

  // ==========================================================================
  // SWITCH CAMERA
  // ==========================================================================

  Future<void> switchCamera() async {
    final tracks = localStream?.getVideoTracks() ?? [];

    if (tracks.isEmpty) return;

    await Helper.switchCamera(tracks.first);
  }

  // ==========================================================================
  // CLEANUP
  // ==========================================================================

  Future<void> _cleanup() async {
    await _callDocSub?.cancel();
    _callDocSub = null;

    await _remoteCandidatesSub?.cancel();
    _remoteCandidatesSub = null;

    final stream = localStream;

    localStream = null;

    if (stream != null) {
      for (final track in stream.getTracks()) {
        try {
          await track.stop();
        } catch (_) {}
      }

      try {
        await stream.dispose();
      } catch (_) {}
    }

    final pc = _peerConnection;

    _peerConnection = null;

    if (pc != null) {
      try {
        await pc.close();
      } catch (_) {}
    }

    remoteStream = null;
  }

  // ==========================================================================
  // DISPOSE
  // ==========================================================================

  void dispose() {
    _cleanup();

    if (!onRemoteStream.isClosed) {
      onRemoteStream.close();
    }

    if (!onCallStatusChanged.isClosed) {
      onCallStatusChanged.close();
    }

    if (!onConnectionStateChanged.isClosed) {
      onConnectionStateChanged.close();
    }
  }
}