import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Шар Мари. В покое «дышит»; если передан [level] (0..1) — пульсирует в такт голосу.
class MariOrb extends StatefulWidget {
  final double size;
  final double? level;
  final bool glow;
  final Widget? child;
  const MariOrb({super.key, this.size = 72, this.level, this.glow = true, this.child});

  @override
  State<MariOrb> createState() => _MariOrbState();
}

class _MariOrbState extends State<MariOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) {
        final breath = (math.sin(_c.value * 2 * math.pi) + 1) / 2; // 0..1
        final scale = widget.level != null ? 0.94 + 0.14 * widget.level!.clamp(0.0, 1.0) : 0.97 + 0.05 * breath;
        final turn = _c.value * 2 * math.pi;
        return Transform.scale(
          scale: scale,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                center: Alignment(-0.4 + 0.15 * math.cos(turn), -0.45 + 0.15 * math.sin(turn)),
                radius: 1.0,
                colors: const [AppColors.orbLight, AppColors.orbCyan, AppColors.orbViolet, AppColors.orbDeep],
                stops: const [0.0, 0.3, 0.64, 1.0],
              ),
              boxShadow: widget.glow
                  ? [BoxShadow(color: AppColors.orbViolet.withValues(alpha: context.isDark ? .55 : .35), blurRadius: widget.size * .5)]
                  : null,
            ),
            child: child,
          ),
        );
      },
      child: widget.child == null ? null : Center(child: widget.child),
    );
  }
}
