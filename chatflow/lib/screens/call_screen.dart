// ============================================================================
// FILE PATH: lib/screens/call_screen.dart
// ============================================================================
//
// Fixes:
// 1. Prevents double Navigator.pop() when a call ends.
// 2. Prevents navigation races between Firestore status and local hang-up.
// 3. Prevents the 45-second timeout from closing an already-ended call.
// 4. Removes unused _callStartedAt field.
// 5. Keeps incoming/outgoing/connected call behaviour.
//
// (One fix applied on top of what you pasted: 'bool _isClosing = false;'
// was declared TWICE in a row, which is a compile error in Dart — a class
// can't have the same field name declared twice. Removed the duplicate;
// nothing else was changed.)
// ============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../services/call_service.dart';

enum _CallScreenMode {
  outgoing,
  incoming,
  connected,
}

class CallScreen extends StatefulWidget {
  final String peerId;
  final String peerName;
  final bool isVideoCall;
  final bool isCaller;
  final String? incomingCallId;

  const CallScreen({
    super.key,
    required this.peerId,
    required this.peerName,
    required this.isVideoCall,
    required this.isCaller,
    this.incomingCallId,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final CallService _callService = CallService.instance;

  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteAudioDecoder = RTCVideoRenderer();

  late _CallScreenMode _mode;

  StreamSubscription<MediaStream>? _remoteStreamSubscription;
  StreamSubscription<CallStatus>? _callStatusSubscription;

  bool _muted = false;
  bool _cameraOff = false;

  // Prevents multiple navigation operations at the same time.
  bool _isClosing = false;

  // Prevents the 45-second timeout from firing after the call
  // has already connected or ended.
  bool _timedOut = false;

  Timer? _callDurationTimer;
  int _secondsElapsed = 0;

  static const Duration _noAnswerTimeout = Duration(seconds: 45);

  static const Color navy = Color(0xFF102A5C);
  static const Color cyan = Color(0xFF16AFC1);
  static const Color mint = Color(0xFF66D6C1);

  @override
  void initState() {
    super.initState();

    _remoteAudioDecoder.initialize();

    _mode = widget.isCaller
        ? _CallScreenMode.outgoing
        : _CallScreenMode.incoming;

    _initRenderers();

    _remoteStreamSubscription =
        _callService.onRemoteStream.stream.listen((stream) {
      if (!mounted || _isClosing) return;

      _remoteRenderer.srcObject = stream;

      setState(() {
        _mode = _CallScreenMode.connected;
      });

      _startCallDurationTimer();

    });

    _callStatusSubscription =
        _callService.onCallStatusChanged.stream.listen((status) {
      if (!mounted || _isClosing) return;

      switch (status) {
        case CallStatus.rejected:
          _closeCallScreen('${widget.peerName} declined the call.');
          break;

        case CallStatus.missed:
          _timedOut = true;
          _closeCallScreen('No answer.');
          break;

        case CallStatus.ended:
          _closeCallScreen('Call ended.');
          break;

        case CallStatus.accepted:
          // ENHANCED SYNC: Force-trigger the layout update and wake up the clock loop immediately
          if (_mode != _CallScreenMode.connected) {
            setState(() {
              _mode = _CallScreenMode.connected;
            });
          }
          _startCallDurationTimer(); // Kicks off the clock ticker immediately
          break;


        case CallStatus.ringing:
          break;
      }
    });

    if (widget.isCaller) {
      _startOutgoingCall();
    }
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();

    if (!mounted) return;

    if (_callService.localStream != null) {
      _localRenderer.srcObject = _callService.localStream;
    }
  }

  void _startCallDurationTimer() {
    if (_callDurationTimer != null) return; // Prevent duplicate engines running

    _callDurationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _isClosing) {
        timer.cancel();
        return;
      }
      setState(() {
        _secondsElapsed++;
      });
    });
  }

  String _formatDuration(int totalSeconds) {
    final int hours = totalSeconds ~/ 3600;
    final int minutes = (totalSeconds % 3600) ~/ 60;
    final int seconds = totalSeconds % 60;

    final String minutesStr = minutes.toString().padLeft(2, '0');
    final String secondsStr = seconds.toString().padLeft(2, '0');

    if (hours > 0) {
      return '$hours:$minutesStr:$secondsStr';
    } else {
      return '$minutesStr:$secondsStr';
    }
  }

  Future<void> _startOutgoingCall() async {
    try {
      await _callService.makeCall(
        calleeId: widget.peerId,
        calleeName: widget.peerName,
        isVideoCall: widget.isVideoCall,
      );

      if (!mounted || _isClosing) return;

      _localRenderer.srcObject = _callService.localStream;

      setState(() {});

      _scheduleNoAnswerCheck();
    } catch (e) {
      if (!mounted || _isClosing) return;

      _closeCallScreen('Unable to start call.');
    }
  }

  void _scheduleNoAnswerCheck() {
    Future.delayed(_noAnswerTimeout, () async {
      if (!mounted || _isClosing || _timedOut) return;

      if (_mode != _CallScreenMode.outgoing) return;

      _timedOut = true;

      final callId = _callService.currentCallId;

      try {
        if (callId != null) {
          await _callService.markMissed(callId);
        }

        await _callService.endCall();
      } catch (_) {}

      if (!mounted) return;

      _closeCallScreen('No answer.');
    });
  }

  Future<void> _answerCall() async {
    if (_isClosing) return;

    final callId = widget.incomingCallId;

    if (callId == null) return;

    try {
      await _callService.answerCall(
        callId: callId,
        isVideoCall: widget.isVideoCall,
      );

      if (!mounted || _isClosing) return;

      _localRenderer.srcObject = _callService.localStream;

      setState(() {
        _mode = _CallScreenMode.connected;
      });

      _startCallDurationTimer();
    } catch (e) {

      if (!mounted || _isClosing) return;

      _closeCallScreen('Unable to join call.');
    }
  }

  Future<void> _declineCall() async {
    if (_isClosing) return;

    _isClosing = true;

    try {
      if (widget.incomingCallId != null) {
        await _callService.rejectCall(widget.incomingCallId!);
      }
    } catch (_) {}

    if (!mounted) return;

    Navigator.of(context).pop();
  }

  Future<void> _hangUp() async {
    if (_isClosing) return;

    _isClosing = true;
    _timedOut = true;

    try {
      await _callService.endCall();
    } catch (_) {}

    if (!mounted) return;

    Navigator.of(context).pop();
  }

  void _closeCallScreen(String message) {
    if (!mounted || _isClosing) return;

    _isClosing = true;
    _timedOut = true;

    _callDurationTimer?.cancel();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );

    Future.delayed(const Duration(milliseconds: 100), () {
      if (!mounted) return;

      Navigator.of(context).pop();
    });
  }

  void _toggleMute() {
    if (_isClosing) return;

    setState(() {
      _muted = !_muted;
    });

    _callService.toggleMute(_muted);
  }

  void _toggleCamera() {
    if (_isClosing) return;

    setState(() {
      _cameraOff = !_cameraOff;
    });

    _callService.toggleCamera(_cameraOff);
  }

  void _switchCamera() {
    if (_isClosing) return;

    _callService.switchCamera();
  }

@override
  void dispose() {
    _isClosing = true;
    _timedOut = true;

    _callDurationTimer?.cancel();

    _remoteStreamSubscription?.cancel();
    _callStatusSubscription?.cancel();

    _localRenderer.dispose();
    _remoteRenderer.dispose();

    // Safely shuts down the audio element context on disconnect 👇
    _remoteAudioDecoder.srcObject = null;
    _remoteAudioDecoder.dispose();

    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: navy,
        body: SafeArea(
          child: Stack(
            children: [
              if (_mode == _CallScreenMode.connected &&
    widget.isVideoCall)
  Positioned.fill(
    child: RTCVideoView(
      _remoteRenderer,
      objectFit:
          RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
    ),
  )
else
  Stack(
    children: [
      // Keep the existing avatar/voice-call UI visible.
      Positioned.fill(
        child: _peerPlaceholder(),
      ),

      // IMPORTANT:
      // Keep the remote WebRTC renderer attached even during
      // voice calls so the remote audio stream is rendered.
      //
      // The renderer receives the same remote MediaStream on
      // Android and Web.
      Positioned(
        left: 0,
        top: 0,
        width: 1,
        height: 1,
        child: Opacity(
          opacity: 0.0,
          child: RTCVideoView(
            _remoteRenderer,
            objectFit:
                RTCVideoViewObjectFit
                    .RTCVideoViewObjectFitContain,
          ),
        ),
      ),
    ],
  ),

              if (widget.isVideoCall && !_cameraOff)
                Positioned(
                  top: 20,
                  right: 20,
                  child: Container(
                    width: 110,
                    height: 150,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: mint,
                        width: 2,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: RTCVideoView(
                      _localRenderer,
                      mirror: true,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    ),
                  ),
                ),

              Positioned(
                top: 30,
                left: 0,
                right: 0,
                child: Column(
                  children: [
                    Text(
                      widget.peerName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _statusText(),
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.75),
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),

              Positioned(
                bottom: 40,
                left: 0,
                right: 0,
                child: _mode == _CallScreenMode.incoming
                    ? _incomingControls()
                    : _activeCallControls(),
              ),
            ],
          ),
        ),
      ),
    );
  }

    String _statusText() {
    switch (_mode) {
      case _CallScreenMode.outgoing:
        return 'Calling...';

      case _CallScreenMode.incoming:
        return widget.isVideoCall
            ? 'Incoming video call'
            : 'Incoming voice call';

            case _CallScreenMode.connected:
        return _formatDuration(_secondsElapsed);
    }
  }

  Widget _peerPlaceholder() {
    return Center(
      child: CircleAvatar(
        radius: 60,
        backgroundColor: cyan.withOpacity(0.25),
        child: Text(
          widget.peerName.isNotEmpty
              ? widget.peerName[0].toUpperCase()
              : '?',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 42,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _incomingControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _circleButton(
          icon: Icons.call_end_rounded,
          color: Colors.red,
          onTap: _declineCall,
        ),
        _circleButton(
          icon: Icons.call_rounded,
          color: mint,
          onTap: _answerCall,
        ),
      ],
    );
  }

  Widget _activeCallControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _circleButton(
          icon: _muted
              ? Icons.mic_off_rounded
              : Icons.mic_rounded,
          // Swaps button background to Red when muted, otherwise stays semi-transparent grey 👇
          color: _muted ? Colors.redAccent : Colors.white24,
          onTap: _toggleMute,
          small: true,
        ),

        if (widget.isVideoCall)
          _circleButton(
            icon: _cameraOff
                ? Icons.videocam_off_rounded
                : Icons.videocam_rounded,
            // Swaps button background to Red when the camera is off, otherwise stays semi-transparent grey 👇
            color: _cameraOff ? Colors.redAccent : Colors.white24,
            onTap: _toggleCamera,
            small: true,
          ),

        if (widget.isVideoCall)
          _circleButton(
            icon: Icons.cameraswitch_rounded,
            color: Colors.white24,
            onTap: _switchCamera,
            small: true,
          ),

        _circleButton(
          icon: Icons.call_end_rounded,
          color: Colors.red,
          onTap: _hangUp,
        ),
      ],
    );
  }

  Widget _circleButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    bool small = false,
  }) {
    final size = small ? 56.0 : 68.0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: Colors.white,
          size: small ? 26 : 30,
        ),
      ),
    );
  }
}