import 'dart:math' as math;

import 'package:ani_dash/main.dart';
import 'package:flutter/material.dart';

const anyCoreLogoAnimationKey = 'anycore_logo_animation';

/// The shared AniDash AI mark used everywhere AI is surfaced in AniDash.
/// Features a modern, sleek AI sparkle constellation that seamlessly blends
/// with the app's Iconsax design language.
class AniDashAiEmblem extends StatefulWidget {
  const AniDashAiEmblem({super.key, this.size = 24, this.animate});

  final double size;
  final bool? animate;

  @override
  State<AniDashAiEmblem> createState() => _AniDashAiEmblemState();
}

class _AniDashAiEmblemState extends State<AniDashAiEmblem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );
  late final Animation<double> _scaleAnimation = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween<double>(begin: 1.0, end: 1.08)
          .chain(CurveTween(curve: Curves.easeInOut)),
      weight: 50,
    ),
    TweenSequenceItem(
      tween: Tween<double>(begin: 1.08, end: 1.0)
          .chain(CurveTween(curve: Curves.easeInOut)),
      weight: 50,
    ),
  ]).animate(_controller);

  bool get _shouldAnimate =>
      widget.animate ?? (sharedPrefs.getBool(anyCoreLogoAnimationKey) ?? true);

  @override
  void initState() {
    super.initState();
    if (_shouldAnimate) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant AniDashAiEmblem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_shouldAnimate && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!_shouldAnimate && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_shouldAnimate && !_controller.isAnimating) _controller.repeat();
    if (!_shouldAnimate && _controller.isAnimating) _controller.stop();
    final scheme = Theme.of(context).colorScheme;

    Widget child = SizedBox.square(
      dimension: widget.size,
      child: CustomPaint(
        painter: _AniDashAiSparklePainter(
          primaryColor: scheme.primary,
          secondaryColor: scheme.tertiary,
        ),
      ),
    );

    if (_shouldAnimate) {
      child = ScaleTransition(
        scale: _scaleAnimation,
        child: child,
      );
    }

    return Semantics(
      label: 'AniDash AI',
      image: true,
      child: child,
    );
  }
}

class _AniDashAiSparklePainter extends CustomPainter {
  const _AniDashAiSparklePainter({
    required this.primaryColor,
    required this.secondaryColor,
  });

  final Color primaryColor;
  final Color secondaryColor;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;

    final center = Offset(w * 0.44, h * 0.54);
    final mainRadius = math.min(w, h) * 0.38;

    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.lerp(primaryColor, Colors.white, 0.35)!,
          primaryColor,
          secondaryColor,
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h))
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    // 1. Primary 4-pointed curved star in center
    final mainStar = _createSparklePath(center, mainRadius, 0.22);
    canvas.drawPath(mainStar, paint);

    // 2. Secondary satellite sparkle at top-right
    final secCenter = Offset(w * 0.80, h * 0.24);
    final secRadius = mainRadius * 0.46;
    final secStar = _createSparklePath(secCenter, secRadius, 0.24);
    canvas.drawPath(secStar, paint);

    // 3. Subtle tertiary sparkle at bottom-left
    final tertCenter = Offset(w * 0.16, h * 0.82);
    final tertRadius = mainRadius * 0.22;
    final tertStar = _createSparklePath(tertCenter, tertRadius, 0.26);
    canvas.drawPath(tertStar, paint);
  }

  Path _createSparklePath(Offset center, double radius, double insetFactor) {
    final path = Path();
    final r = radius;
    final inset = r * insetFactor;

    path.moveTo(center.dx, center.dy - r);
    path.quadraticBezierTo(center.dx + inset, center.dy - inset, center.dx + r, center.dy);
    path.quadraticBezierTo(center.dx + inset, center.dy + inset, center.dx, center.dy + r);
    path.quadraticBezierTo(center.dx - inset, center.dy + inset, center.dx - r, center.dy);
    path.quadraticBezierTo(center.dx - inset, center.dy - inset, center.dx, center.dy - r);
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant _AniDashAiSparklePainter oldDelegate) =>
      oldDelegate.primaryColor != primaryColor ||
      oldDelegate.secondaryColor != secondaryColor;
}
