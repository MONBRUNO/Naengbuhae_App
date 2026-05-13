import 'dart:math' as math;

import 'package:flutter/material.dart';

// 웹의 recharts PieChart(innerRadius=35, outerRadius=50, paddingAngle=2)를 CustomPaint로 재현.
class DonutChart extends StatelessWidget {
  final List<DonutSegment> segments;
  final double size;
  final double innerRadiusRatio;
  final double paddingAngleDeg;

  const DonutChart({
    super.key,
    required this.segments,
    this.size = 120,
    this.innerRadiusRatio = 0.7, // 35/50
    this.paddingAngleDeg = 2,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _DonutPainter(segments, innerRadiusRatio, paddingAngleDeg)),
    );
  }
}

class DonutSegment {
  final double value;
  final Color color;
  const DonutSegment(this.value, this.color);
}

class _DonutPainter extends CustomPainter {
  final List<DonutSegment> segments;
  final double innerRadiusRatio;
  final double paddingAngleDeg;

  _DonutPainter(this.segments, this.innerRadiusRatio, this.paddingAngleDeg);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerR = size.width / 2;
    final innerR = outerR * innerRadiusRatio;
    final strokeWidth = outerR - innerR;
    final radius = (outerR + innerR) / 2;

    final total = segments.fold<double>(0, (s, e) => s + e.value);
    if (total <= 0) return;

    final gap = paddingAngleDeg * math.pi / 180;
    final nonzero = segments.where((s) => s.value > 0).toList();
    final totalGap = nonzero.length > 1 ? gap * nonzero.length : 0.0;
    final availableSweep = 2 * math.pi - totalGap;

    var start = -math.pi / 2 + gap / 2;
    for (final seg in nonzero) {
      final sweep = (seg.value / total) * availableSweep;
      final paint = Paint()
        ..color = seg.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        sweep,
        false,
        paint,
      );
      start += sweep + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.segments != segments ||
      old.innerRadiusRatio != innerRadiusRatio ||
      old.paddingAngleDeg != paddingAngleDeg;
}
