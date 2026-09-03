// ============================================================================
// FILE PATH: lib/screens/status_viewer_screen.dart
// ============================================================================
//
// Full-screen story-style viewer for one user's set of active statuses.
// Auto-advances every 5 seconds (photos) / 4 seconds (text), tap right side
// to skip forward, tap left side to go back. Marks each status viewed as
// it's shown. If viewing your OWN status, shows a "Viewed by" bar instead
// of auto-advancing controls being hidden.
//
// ============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/status_service.dart';

class StatusViewerScreen extends StatefulWidget {
  final String userId;
  final String userName;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> statuses;

  const StatusViewerScreen({
    super.key,
    required this.userId,
    required this.userName,
    required this.statuses,
  });

  @override
  State<StatusViewerScreen> createState() => _StatusViewerScreenState();
}

class _StatusViewerScreenState extends State<StatusViewerScreen> {
  int _currentIndex = 0;
  Timer? _timer;
  double _progress = 0;

  MemoryImage? _currentImage;

  bool get _isMine =>
      widget.userId == FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _startForCurrent();
  }

  void _startForCurrent() {
  _timer?.cancel();

  if (!mounted ||
      widget.statuses.isEmpty ||
      _currentIndex < 0 ||
      _currentIndex >= widget.statuses.length) {
    return;
  }

  _progress = 0;

  final data = widget.statuses[_currentIndex].data();

  // ------------------------------------------------------------
  // Decode the image ONLY ONCE for the current status.
  // Do not decode it again on every progress-bar rebuild.
  // ------------------------------------------------------------
  _currentImage = null;

  if (data['type'] == 'image') {
    try {
      final base64Data = data['content']?.toString() ?? '';

      if (base64Data.isNotEmpty) {
        final bytes = base64Decode(base64Data);

        _currentImage = MemoryImage(
          Uint8List.fromList(bytes),
        );
      }
    } catch (_) {
      _currentImage = null;
    }
  }

  // Mark the current status as viewed.
  StatusService.instance.markViewed(
    widget.statuses[_currentIndex].id,
  );

  final durationSeconds = data['type'] == 'image' ? 5 : 4;

  const tick = Duration(milliseconds: 50);
  final totalTicks =
      (durationSeconds * 1000) ~/ tick.inMilliseconds;

  int ticksElapsed = 0;

  _timer = Timer.periodic(tick, (timer) {
    if (!mounted) {
      timer.cancel();
      return;
    }

    ticksElapsed++;

    if (ticksElapsed >= totalTicks) {
      timer.cancel();
      _goNext();
      return;
    }

    setState(() {
      _progress = ticksElapsed / totalTicks;
    });
  });
}

  void _goNext() {
  if (!mounted) return;

  _timer?.cancel();

  if (_currentIndex < widget.statuses.length - 1) {
    setState(() {
      _currentIndex++;
      _progress = 0;
    });

    _startForCurrent();
  } else {
    Navigator.of(context).pop();
  }
}

  void _goPrevious() {
  if (!mounted) return;

  _timer?.cancel();

  if (_currentIndex > 0) {
    setState(() {
      _currentIndex--;
      _progress = 0;
    });

    _startForCurrent();
  }
}

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _showViewers(Map<String, dynamic> data) {
    _timer?.cancel();

    final viewedBy = List<String>.from(data['viewedBy'] ?? []);

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF10284A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) {
        return SafeArea(
          child: SizedBox(
            height: 400,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Viewed by ${viewedBy.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Divider(color: Colors.white24, height: 1),
                Expanded(
                  child: viewedBy.isEmpty
                      ? const Center(
                          child: Text(
                            'No views yet.',
                            style: TextStyle(color: Colors.white54),
                          ),
                        )
                      : ListView.builder(
                          itemCount: viewedBy.length,
                          itemBuilder: (context, index) {
                            return _ViewerTile(userId: viewedBy[index]);
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    ).whenComplete(() {
      if (mounted) _startForCurrent();
    });
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.statuses[_currentIndex].data();
    final type = data['type']?.toString() ?? 'text';

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // ------------------------------------------------------------
            // CONTENT
            // ------------------------------------------------------------

            Positioned.fill(
              child: GestureDetector(
                onTapUp: (details) {
                  final width = MediaQuery.of(context).size.width;
                  if (details.globalPosition.dx < width / 3) {
                    _goPrevious();
                  } else {
                    _goNext();
                  }
                },
                child: type == 'image'
                    ? _imageContent(data)
                    : _textContent(data),
              ),
            ),

            // ------------------------------------------------------------
            // PROGRESS BARS
            // ------------------------------------------------------------

            Positioned(
              top: 8,
              left: 8,
              right: 8,
              child: Row(
                children: List.generate(widget.statuses.length, (index) {
                  return Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      height: 3,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: index < _currentIndex
                            ? 1
                            : index == _currentIndex
                                ? _progress.clamp(0, 1)
                                : 0,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),

            // ------------------------------------------------------------
            // HEADER
            // ------------------------------------------------------------

            Positioned(
              top: 20,
              left: 12,
              right: 12,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded,
                        color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: Colors.white24,
                    child: Text(
                      widget.userName.isNotEmpty
                          ? widget.userName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.userName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  if (_isMine)
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded,
                          color: Colors.white),
                      onPressed: () async {
                        _timer?.cancel();
                        await StatusService.instance.deleteStatus(
                          widget.statuses[_currentIndex].id,
                        );
                        if (mounted) Navigator.pop(context);
                      },
                    ),
                ],
              ),
            ),

            // ------------------------------------------------------------
            // VIEWER COUNT (own status only)
            // ------------------------------------------------------------

            if (_isMine)
              Positioned(
                bottom: 20,
                left: 0,
                right: 0,
                child: Center(
                  child: GestureDetector(
                    onTap: () => _showViewers(data),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.visibility_outlined,
                              color: Colors.white, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            '${(data['viewedBy'] as List?)?.length ?? 0} views',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _textContent(Map<String, dynamic> data) {
    Color bgColor;
    try {
      bgColor = Color(
        int.parse(data['backgroundColor']?.toString() ?? '0xFF102A5C'),
      );
    } catch (_) {
      bgColor = const Color(0xFF102A5C);
    }

    return Container(
      color: bgColor,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(30),
      child: Text(
        data['content']?.toString() ?? '',
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 26,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _imageContent(Map<String, dynamic> data) {
  final caption = data['caption']?.toString() ?? '';

  if (_currentImage == null) {
    return const Center(
      child: Icon(
        Icons.broken_image_rounded,
        color: Colors.white54,
        size: 60,
      ),
    );
  }

  return Container(
    color: Colors.black,
    alignment: Alignment.center,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(
          child: Center(
            child: Image(
              image: _currentImage!,
              fit: BoxFit.contain,
              width: double.infinity,
            ),
          ),
        ),
        if (caption.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              caption,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
              ),
            ),
          ),
      ],
    ),
  );
}
}

// ==============================================================================
// VIEWER TILE — resolves a user ID to a name for the viewer list
// ==============================================================================

class _ViewerTile extends StatelessWidget {
  final String userId;

  const _ViewerTile({required this.userId});

  @override
  Widget build(BuildContext context) {
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
            backgroundColor: Colors.white24,
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: const TextStyle(color: Colors.white),
            ),
          ),
          title: Text(name, style: const TextStyle(color: Colors.white)),
        );
      },
    );
  }
}