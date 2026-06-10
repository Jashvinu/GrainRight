import 'package:flutter/material.dart';

class FarmHillsBackground extends StatelessWidget {
  const FarmHillsBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _FarmHillsPainter());
  }
}

class _FarmHillsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final sky = Paint()..color = const Color(0xFFEFF8F0);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), sky);

    final backHill = Path()
      ..moveTo(0, size.height * 0.64)
      ..cubicTo(
        size.width * 0.22,
        size.height * 0.36,
        size.width * 0.35,
        size.height * 0.82,
        size.width * 0.56,
        size.height * 0.55,
      )
      ..cubicTo(
        size.width * 0.72,
        size.height * 0.36,
        size.width * 0.86,
        size.height * 0.70,
        size.width,
        size.height * 0.48,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(backHill, Paint()..color = const Color(0xFFB7DFA6));

    final frontHill = Path()
      ..moveTo(0, size.height * 0.78)
      ..cubicTo(
        size.width * 0.18,
        size.height * 0.54,
        size.width * 0.28,
        size.height * 0.84,
        size.width * 0.45,
        size.height * 0.69,
      )
      ..cubicTo(
        size.width * 0.64,
        size.height * 0.52,
        size.width * 0.82,
        size.height * 0.90,
        size.width,
        size.height * 0.62,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(frontHill, Paint()..color = const Color(0xFF69B55B));

    final field = Paint()
      ..color = const Color(0xFF2D8C45)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < 8; i++) {
      final y = size.height * (0.76 + i * 0.035);
      final row = Path()
        ..moveTo(0, y)
        ..quadraticBezierTo(size.width * 0.45, y - 36, size.width, y - 8);
      canvas.drawPath(row, field);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
