
import 'package:flutter/material.dart';

// ============================================================================
// CHATFLOW BACKGROUND WAVES
// ============================================================================
class ChatBackgroundPainter extends CustomPainter {
  final bool darkMode;
  final int selectedPage;

  const ChatBackgroundPainter({
    required this.darkMode,
    required this.selectedPage,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // ------------------------------------------------------------------------
    // TOP LEFT MINT WAVE
    // ------------------------------------------------------------------------

    final mintWavePaint = Paint()
      ..color = const Color(0xFF66D6C1)
          .withOpacity(
        darkMode ? 0.10 : 0.28,
      );

    final topWave = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width * 0.70, 0)
      ..cubicTo(
        size.width * 0.55,
        size.height * 0.05,
        size.width * 0.33,
        size.height * 0.02,
        0,
        size.height * 0.19,
      )
      ..close();

    canvas.drawPath(
      topWave,
      mintWavePaint,
    );

    // ------------------------------------------------------------------------
    // SECOND TOP WAVE
    // ------------------------------------------------------------------------

    final cyanPaint = Paint()
      ..color = const Color(0xFF55C7E8)
          .withOpacity(
        darkMode ? 0.06 : 0.15,
      );

    final secondWave = Path()
      ..moveTo(0, size.height * 0.10)
      ..cubicTo(
        size.width * 0.25,
        size.height * 0.02,
        size.width * 0.52,
        size.height * 0.12,
        size.width * 0.78,
        0,
      )
      ..lineTo(0, 0)
      ..close();

    canvas.drawPath(
      secondWave,
      cyanPaint,
    );

    // ------------------------------------------------------------------------
    // PAGE-SPECIFIC WAVE
    // ------------------------------------------------------------------------

    final pagePaint = Paint()
      ..color = const Color(0xFF16AFC1)
          .withOpacity(
        darkMode ? 0.04 : 0.08,
      );

    final pageWave = Path();

    if (selectedPage == 0) {
      pageWave
        ..moveTo(size.width, size.height * 0.20)
        ..cubicTo(
          size.width * 0.78,
          size.height * 0.28,
          size.width * 0.90,
          size.height * 0.38,
          size.width,
          size.height * 0.48,
        )
        ..lineTo(size.width, size.height * 0.20)
        ..close();
    } else if (selectedPage == 1) {
      pageWave
        ..moveTo(0, size.height * 0.35)
        ..cubicTo(
          size.width * 0.25,
          size.height * 0.25,
          size.width * 0.45,
          size.height * 0.45,
          size.width * 0.70,
          size.height * 0.33,
        )
        ..lineTo(size.width, size.height * 0.25)
        ..lineTo(size.width, size.height * 0.42)
        ..cubicTo(
          size.width * 0.55,
          size.height * 0.55,
          size.width * 0.30,
          size.height * 0.42,
          0,
          size.height * 0.52,
        )
        ..close();
    } else if (selectedPage == 2) {
      pageWave
        ..moveTo(size.width, size.height * 0.42)
        ..cubicTo(
          size.width * 0.72,
          size.height * 0.32,
          size.width * 0.50,
          size.height * 0.52,
          size.width * 0.25,
          size.height * 0.42,
        )
        ..lineTo(0, size.height * 0.50)
        ..lineTo(0, size.height * 0.60)
        ..cubicTo(
          size.width * 0.40,
          size.height * 0.56,
          size.width * 0.70,
          size.height * 0.68,
          size.width,
          size.height * 0.55,
        )
        ..close();
    } else {
      pageWave
        ..moveTo(0, size.height * 0.30)
        ..cubicTo(
          size.width * 0.25,
          size.height * 0.20,
          size.width * 0.55,
          size.height * 0.32,
          size.width,
          size.height * 0.18,
        )
        ..lineTo(size.width, size.height * 0.35)
        ..cubicTo(
          size.width * 0.58,
          size.height * 0.45,
          size.width * 0.30,
          size.height * 0.32,
          0,
          size.height * 0.44,
        )
        ..close();
    }

    canvas.drawPath(
      pageWave,
      pagePaint,
    );

    // ------------------------------------------------------------------------
    // BOTTOM RIGHT MINT WAVE
    // ------------------------------------------------------------------------

    final bottomPaint = Paint()
      ..color = const Color(0xFFBCEDE2)
          .withOpacity(
        darkMode ? 0.08 : 0.32,
      );

    final bottomWave = Path()
      ..moveTo(size.width, size.height)
      ..lineTo(size.width * 0.28, size.height)
      ..cubicTo(
        size.width * 0.48,
        size.height * 0.86,
        size.width * 0.76,
        size.height * 0.94,
        size.width,
        size.height * 0.76,
      )
      ..close();

    canvas.drawPath(
      bottomWave,
      bottomPaint,
    );

    // ------------------------------------------------------------------------
    // BOTTOM CYAN WAVE
    // ------------------------------------------------------------------------

    final bottomCyan = Paint()
      ..color = const Color(0xFF55C7E8)
          .withOpacity(
        darkMode ? 0.04 : 0.09,
      );

    final cyanBottomWave = Path()
      ..moveTo(0, size.height)
      ..lineTo(0, size.height * 0.82)
      ..cubicTo(
        size.width * 0.20,
        size.height * 0.90,
        size.width * 0.42,
        size.height * 0.80,
        size.width * 0.65,
        size.height,
      )
      ..close();

    canvas.drawPath(
      cyanBottomWave,
      bottomCyan,
    );

    // ------------------------------------------------------------------------
    // DECORATIVE MINT DOTS
    // ------------------------------------------------------------------------

    final dots = Paint()
      ..color = const Color(0xFF66D6C1)
          .withOpacity(
        darkMode ? 0.16 : 0.28,
      );

    for (int row = 0; row < 4; row++) {
      for (int col = 0; col < 4; col++) {
        canvas.drawCircle(
          Offset(
            size.width * 0.08 + col * 11,
            size.height * 0.70 + row * 11,
          ),
          2,
          dots,
        );
      }
    }

    // ------------------------------------------------------------------------
    // CYAN DOTS
    // ------------------------------------------------------------------------

    final cyanDots = Paint()
      ..color = const Color(0xFF16AFC1)
          .withOpacity(
        darkMode ? 0.12 : 0.20,
      );

    for (int row = 0; row < 5; row++) {
      for (int col = 0; col < 5; col++) {
        canvas.drawCircle(
          Offset(
            size.width * 0.82 + col * 11,
            size.height * 0.30 + row * 11,
          ),
          2,
          cyanDots,
        );
      }
    }
  }

  @override
  bool shouldRepaint(
    covariant ChatBackgroundPainter oldDelegate,
  ) {
    return oldDelegate.darkMode != darkMode ||
        oldDelegate.selectedPage != selectedPage;
  }
}