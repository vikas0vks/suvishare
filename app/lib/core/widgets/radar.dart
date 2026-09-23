import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Animated concentric-ring radar with a slow sweep. Stops animating when the
/// platform asks for reduced motion.
class RadarView extends StatefulWidget {
  const RadarView({super.key, this.size = 220, this.child});
  final double size;
  final Widget? child;

  @override
  State<RadarView> createState() => _RadarViewState();
}

class _RadarViewState extends State<RadarView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.of(context).disableAnimations;
    if (reduce) {
      _c.stop();
      _c.value = 0.35;
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) => CustomPaint(
          painter: _RadarPainter(
            t: _c.value,
            ring: scheme.primary,
            sweep: scheme.primary,
            reduceMotion: MediaQuery.of(context).disableAnimations,
          ),
          child: Center(child: child),
        ),
        child: widget.child,
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({
    required this.t,
    required this.ring,
    required this.sweep,
    required this.reduceMotion,
  });

  final double t;
  final Color ring;
  final Color sweep;
  final bool reduceMotion;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxR = size.shortestSide / 2;
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    for (var i = 1; i <= 3; i++) {
      final r = maxR * i / 3;
      ringPaint.color = ring.withValues(alpha: 0.10 + 0.08 * (4 - i));
      canvas.drawCircle(center, r, ringPaint);
    }

    // Expanding pulse.
    if (!reduceMotion) {
      final pulseR = maxR * t;
      final pulse = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = ring.withValues(alpha: (1 - t) * 0.45);
      canvas.drawCircle(center, pulseR, pulse);
    }

    // Sweep wedge.
    final angle = t * 2 * math.pi - math.pi / 2;
    final sweepPaint = Paint()
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: 2 * math.pi,
        colors: [sweep.withValues(alpha: 0), sweep.withValues(alpha: 0.35)],
        stops: const [0.72, 1.0],
        transform: GradientRotation(angle - 2 * math.pi * 0.999),
      ).createShader(Rect.fromCircle(center: center, radius: maxR));
    canvas.drawCircle(center, maxR, sweepPaint);

    final dot = Paint()..color = sweep.withValues(alpha: 0.9);
    canvas.drawCircle(center, 4, dot);
  }

  @override
  bool shouldRepaint(covariant _RadarPainter old) =>
      old.t != t || old.ring != ring || old.reduceMotion != reduceMotion;
}
