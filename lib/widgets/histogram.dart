import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Velocity distribution histogram with a Gaussian bell-curve overlay.
///
/// Pure CustomPaint — bins velocities at [binSize] fps, draws rounded
/// bars, then overlays a μ ± σ normal PDF as a filled smooth path. Mean
/// is marked with a dashed vertical line.
class Histogram extends StatelessWidget {
  final List<int> values;
  final double mean;
  final double sd;
  final int binSize;
  final double height;

  /// User's velocity-unit preference. Bins remain at fps integers (driven
  /// by the chronograph's reporting resolution); only axis labels convert.
  final bool useFps;

  const Histogram({
    super.key,
    required this.values,
    required this.mean,
    required this.sd,
    required this.useFps,
    this.binSize = 1,
    this.height = 140,
  });

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) {
      return SizedBox(
        height: height,
        child: const Center(
          child: Text(
            'Need at least 2 shots to plot distribution',
            style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
          ),
        ),
      );
    }
    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: _HistogramPainter(
          values: values,
          mean: mean,
          sd: sd,
          binSize: binSize,
          useFps: useFps,
        ),
      ),
    );
  }
}

class _HistogramPainter extends CustomPainter {
  final List<int> values;
  final double mean;
  final double sd;
  final int binSize;
  final bool useFps;

  _HistogramPainter({
    required this.values,
    required this.mean,
    required this.sd,
    required this.binSize,
    required this.useFps,
  });

  String _fmtAxis(num fps) {
    final v = useFps ? fps.toDouble() : fps.toDouble() * 0.3048;
    return v.toStringAsFixed(0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final minV = values.reduce(math.min);
    final maxV = values.reduce(math.max);
    final span = (maxV - minV).clamp(binSize, 9999);
    final binCount = (span ~/ binSize) + 1;

    final counts = List<int>.filled(binCount, 0);
    for (final v in values) {
      final i = ((v - minV) ~/ binSize).clamp(0, binCount - 1);
      counts[i] += 1;
    }
    final maxCount = counts.reduce(math.max);
    final modeBin = counts.indexOf(maxCount);

    const axisHeight = 14.0;
    final chartH = size.height - axisHeight;
    final chartW = size.width;
    final binWidth = chartW / binCount;
    final barW = math.min(binWidth * 0.86, 28.0);
    final barGap = binWidth - barW;

    // Baseline
    final basePaint = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, chartH),
      Offset(chartW, chartH),
      basePaint,
    );

    // ±σ band (vertical shaded strip behind bars)
    if (sd > 0 && mean > 0) {
      final lowX = ((mean - sd - minV) / span) * chartW;
      final hiX = ((mean + sd - minV) / span) * chartW;
      final bandPaint = Paint()..color = AppColors.accentBand;
      canvas.drawRect(
        Rect.fromLTRB(lowX.clamp(0, chartW), 0, hiX.clamp(0, chartW), chartH),
        bandPaint,
      );
    }

    // Bars
    final barPaint = Paint()..color = AppColors.accent;
    final modeBarPaint = Paint()..color = AppColors.accentSoft;
    for (int i = 0; i < binCount; i++) {
      if (counts[i] == 0) continue;
      final h = (counts[i] / maxCount) * (chartH - 4);
      final x = i * binWidth + barGap / 2;
      final y = chartH - h;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, barW, h),
        const Radius.circular(2),
      );
      canvas.drawRRect(rect, i == modeBin ? modeBarPaint : barPaint);
    }

    // Bell curve overlay (Gaussian PDF scaled to bar peak)
    if (sd > 0 && mean > 0) {
      final curve = Path();
      const samples = 80;
      // Peak of normal PDF
      final peakPdf = 1.0 / (sd * math.sqrt(2 * math.pi));
      for (int i = 0; i <= samples; i++) {
        final v = minV + (span * i / samples);
        final pdf = (1.0 / (sd * math.sqrt(2 * math.pi))) *
            math.exp(-math.pow(v - mean, 2) / (2 * sd * sd));
        final scaled = (pdf / peakPdf) * (maxCount > 0 ? 1.0 : 0.0);
        final cy = chartH - scaled * (chartH - 4);
        final cx = (i / samples) * chartW;
        if (i == 0) {
          curve.moveTo(cx, cy);
        } else {
          curve.lineTo(cx, cy);
        }
      }
      final curvePaint = Paint()
        ..color = AppColors.accentLine
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4;
      canvas.drawPath(curve, curvePaint);
    }

    // Mean line (dashed vertical)
    if (mean > 0) {
      final meanX = ((mean - minV) / span) * chartW;
      final meanPaint = Paint()
        ..color = AppColors.accentSoft
        ..strokeWidth = 1.2;
      double y = 0;
      while (y < chartH) {
        canvas.drawLine(Offset(meanX, y), Offset(meanX, y + 4), meanPaint);
        y += 7;
      }
    }

    // Axis labels at min, mean, max — converted to m/s when useFps is false.
    _label(canvas, _fmtAxis(minV), Offset(0, chartH + 2),
        AppColors.textTertiary);
    if (mean > 0) {
      final meanX = ((mean - minV) / span) * chartW;
      _label(canvas, _fmtAxis(mean),
          Offset((meanX - 12).clamp(0, chartW - 24), chartH + 2),
          AppColors.accentSoft);
    }
    _label(canvas, _fmtAxis(maxV), Offset(chartW - 24, chartH + 2),
        AppColors.textTertiary);
  }

  void _label(Canvas canvas, String text, Offset pos, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: AppFonts.mono,
          fontSize: 9,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos);
  }

  @override
  bool shouldRepaint(covariant _HistogramPainter old) {
    return old.values != values ||
        old.mean != mean ||
        old.sd != sd ||
        old.binSize != binSize ||
        old.useFps != useFps;
  }
}
