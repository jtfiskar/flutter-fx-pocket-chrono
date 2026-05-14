import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/shot.dart';
import '../theme/app_theme.dart';

/// Per-shot velocity trend chart with mean line and ±1σ band.
///
/// Renders the last [maxShots] velocities as a polyline with dots, a dashed
/// mean line, and a filled ±1σ band centered on the mean. The most recent
/// shot gets a halo. Pure CustomPaint, no chart libraries.
class TrendChart extends StatelessWidget {
  final List<Shot> shots;
  final double meanFps;
  final double sdFps;

  /// User's velocity-unit preference. Internal calculations stay in fps;
  /// only the axis labels and the ±σ legend convert when this is false.
  final bool useFps;

  /// Label to suffix the ±σ band-width line (e.g. "fps" or "m/s").
  final String unitLabel;

  /// How many recent shots to show. The detail page uses a larger window.
  final int maxShots;

  /// Vertical space the chart occupies.
  final double height;

  /// Show the bottom legend row (first shot, ±σ, last shot).
  final bool showLegend;

  const TrendChart({
    super.key,
    required this.shots,
    required this.meanFps,
    required this.sdFps,
    required this.useFps,
    required this.unitLabel,
    this.maxShots = 12,
    this.height = 148,
    this.showLegend = true,
  });

  @override
  Widget build(BuildContext context) {
    final visible = shots.length <= maxShots
        ? shots
        : shots.sublist(shots.length - maxShots);

    if (visible.isEmpty) {
      return _empty();
    }

    final values = visible.map((s) => s.velocityFps).toList();
    final minV = values.reduce((a, b) => a < b ? a : b);
    final maxV = values.reduce((a, b) => a > b ? a : b);

    // Pad the value range so the polyline isn't pressed against the edges.
    final spread = (maxV - minV).clamp(4, 9999);
    final pad = (spread * 0.35).clamp(2.0, 20.0);
    final yMin = (meanFps - sdFps - pad).clamp(0.0, double.infinity);
    final yMax = (meanFps + sdFps + pad);
    final yLo = yMin > minV ? minV.toDouble() - pad : yMin;
    final yHi = yMax < maxV ? maxV.toDouble() + pad : yMax;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: height,
          child: CustomPaint(
            painter: _TrendPainter(
              values: values,
              mean: meanFps,
              sd: sdFps,
              yMin: yLo,
              yMax: yHi,
              useFps: useFps,
            ),
          ),
        ),
        if (showLegend) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                '#${visible.first.number}',
                style: const TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 10,
                  color: AppColors.textTertiary,
                ),
              ),
              const Spacer(),
              Text(
                '±${(useFps ? sdFps : sdFps * 0.3048).toStringAsFixed(1)} $unitLabel',
                style: const TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 10,
                  color: AppColors.accentSoft,
                ),
              ),
              const Spacer(),
              Text(
                '#${visible.last.number}',
                style: const TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 10,
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _empty() {
    return SizedBox(
      height: height,
      child: Center(
        child: Text(
          'No shots yet',
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textTertiary,
          ),
        ),
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  final List<int> values;
  final double mean;
  final double sd;
  final double yMin;
  final double yMax;
  final bool useFps;

  _TrendPainter({
    required this.values,
    required this.mean,
    required this.sd,
    required this.yMin,
    required this.yMax,
    required this.useFps,
  });

  String _fmtAxis(num fps) {
    final v = useFps ? fps.toDouble() : fps.toDouble() * 0.3048;
    return v.toStringAsFixed(0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    const labelGutter = 36.0;
    final chartW = size.width - labelGutter;
    final chartH = size.height;
    final yRange = (yMax - yMin).abs() < 0.01 ? 1.0 : (yMax - yMin);
    double yPx(double v) => chartH - ((v - yMin) / yRange) * chartH;

    // Gridlines — three horizontal dashed lines
    final gridPaint = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    for (int i = 1; i < 4; i++) {
      final y = chartH * (i / 4);
      _dashedLine(canvas, Offset(0, y), Offset(chartW, y), gridPaint, dash: 3, gap: 4);
    }

    // ±1σ band
    if (sd > 0) {
      final bandTop = yPx(mean + sd);
      final bandBot = yPx(mean - sd);
      final bandRect = Rect.fromLTRB(0, bandTop, chartW, bandBot);
      final bandPaint = Paint()..color = AppColors.accentBand;
      canvas.drawRect(bandRect, bandPaint);
    }

    // Mean line (dashed)
    if (mean > 0) {
      final meanY = yPx(mean);
      final meanPaint = Paint()
        ..color = AppColors.accentLine
        ..strokeWidth = 1.2;
      _dashedLine(canvas, Offset(0, meanY), Offset(chartW, meanY), meanPaint, dash: 4, gap: 3);
    }

    // Polyline + dots
    if (values.length > 1) {
      final linePaint = Paint()
        ..color = AppColors.accent
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round;
      final path = Path();
      for (int i = 0; i < values.length; i++) {
        final x = (i / (values.length - 1)) * chartW;
        final y = yPx(values[i].toDouble());
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, linePaint);
    }

    // Dots — every shot, halo on latest
    final dotPaint = Paint()..color = AppColors.accent;
    for (int i = 0; i < values.length; i++) {
      final x = values.length == 1 ? chartW / 2 : (i / (values.length - 1)) * chartW;
      final y = yPx(values[i].toDouble());
      if (i == values.length - 1) {
        final halo = Paint()..color = AppColors.accentGlow;
        canvas.drawCircle(Offset(x, y), 6.5, halo);
      }
      canvas.drawCircle(Offset(x, y), 2.6, dotPaint);
    }

    // Right-edge axis labels: max / avg / min — converted when in m/s.
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final minV = values.reduce((a, b) => a < b ? a : b);
    _label(canvas, _fmtAxis(maxV), Offset(chartW + 4, 0), AppColors.textTertiary);
    _label(canvas, mean > 0 ? _fmtAxis(mean) : '—',
        Offset(chartW + 4, chartH / 2 - 5), AppColors.accentSoft);
    _label(canvas, _fmtAxis(minV), Offset(chartW + 4, chartH - 10),
        AppColors.textTertiary);
  }

  void _dashedLine(Canvas canvas, Offset a, Offset b, Paint paint,
      {double dash = 4, double gap = 3}) {
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final span = math.sqrt(dx * dx + dy * dy);
    if (span == 0) return;
    final ux = dx / span;
    final uy = dy / span;
    double pos = 0;
    while (pos < span) {
      final segEnd = math.min(pos + dash, span);
      canvas.drawLine(
        Offset(a.dx + ux * pos, a.dy + uy * pos),
        Offset(a.dx + ux * segEnd, a.dy + uy * segEnd),
        paint,
      );
      pos += dash + gap;
    }
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
  bool shouldRepaint(covariant _TrendPainter old) {
    return old.values != values ||
        old.mean != mean ||
        old.sd != sd ||
        old.yMin != yMin ||
        old.yMax != yMax ||
        old.useFps != useFps;
  }
}
