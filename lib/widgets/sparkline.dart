import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Minimal trend sparkline — polyline of velocity values with a dashed
/// mean line and small dots. Used on history cards to telegraph session
/// shape at a glance without spending the screen budget of a full chart.
class Sparkline extends StatelessWidget {
  final List<int> values;
  final double mean;
  final double height;
  final bool showDots;

  const Sparkline({
    super.key,
    required this.values,
    required this.mean,
    this.height = 32,
    this.showDots = true,
  });

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) {
      return SizedBox(height: height);
    }
    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: _SparklinePainter(
          values: values,
          mean: mean,
          showDots: showDots,
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<int> values;
  final double mean;
  final bool showDots;

  _SparklinePainter({
    required this.values,
    required this.mean,
    required this.showDots,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final minV = values.reduce((a, b) => a < b ? a : b);
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final pad = ((maxV - minV) * 0.2).clamp(2.0, 10.0);
    final lo = minV - pad;
    final hi = maxV + pad;
    final range = (hi - lo).abs() < 0.01 ? 1.0 : (hi - lo);
    double y(double v) => size.height - ((v - lo) / range) * size.height;

    // Dashed mean line
    if (mean > 0) {
      final meanY = y(mean);
      final paint = Paint()
        ..color = AppColors.accentLine
        ..strokeWidth = 1;
      double x = 0;
      while (x < size.width) {
        canvas.drawLine(Offset(x, meanY), Offset(x + 3, meanY), paint);
        x += 6;
      }
    }

    // Polyline
    final linePaint = Paint()
      ..color = AppColors.accent
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final path = Path();
    for (int i = 0; i < values.length; i++) {
      final x = values.length == 1
          ? size.width / 2
          : (i / (values.length - 1)) * size.width;
      final py = y(values[i].toDouble());
      if (i == 0) {
        path.moveTo(x, py);
      } else {
        path.lineTo(x, py);
      }
    }
    canvas.drawPath(path, linePaint);

    // Dots
    if (showDots) {
      final dot = Paint()..color = AppColors.accent;
      for (int i = 0; i < values.length; i++) {
        final x = values.length == 1
            ? size.width / 2
            : (i / (values.length - 1)) * size.width;
        final py = y(values[i].toDouble());
        canvas.drawCircle(Offset(x, py), 1.6, dot);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter old) {
    return old.values != values || old.mean != mean;
  }
}
