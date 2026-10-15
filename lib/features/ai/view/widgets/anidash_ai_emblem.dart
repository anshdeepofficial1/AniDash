import 'dart:math' as math;

import 'package:ani_dash/main.dart';
import 'package:flutter/material.dart';

const anyCoreLogoAnimationKey = 'anycore_logo_animation';
const anyCoreEnabledKey = 'anycore_enabled';

final ValueNotifier<int> anyCoreSettingsRevision = ValueNotifier<int>(0);

/// Original two-tone CoreBall emblem. The colors follow the app theme.
/// Rotation is used by the same component for AniCORE thinking and search.
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
    duration: const Duration(milliseconds: 1900),
  );

  bool get _shouldAnimate =>
      widget.animate ?? (sharedPrefs.getBool(anyCoreLogoAnimationKey) ?? true);

  @override
  void initState() {
    super.initState();
    anyCoreSettingsRevision.addListener(_settingsChanged);
    _updateAnimation();
  }

  void _settingsChanged() {
    if (!mounted) return;
    setState(() {});
    _updateAnimation();
  }

  void _updateAnimation() {
    if (_shouldAnimate && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!_shouldAnimate && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void didUpdateWidget(covariant AniDashAiEmblem oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateAnimation();
  }

  @override
  void dispose() {
    anyCoreSettingsRevision.removeListener(_settingsChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ball = SizedBox.square(
      dimension: widget.size,
      child: CustomPaint(
        painter: _CoreBallPainter(
          accent: scheme.primary,
          surface: scheme.surfaceContainerHighest,
          border: scheme.onSurface,
        ),
      ),
    );
    return Semantics(
      label: 'AniCORE',
      image: true,
      child: _shouldAnimate
          ? RotationTransition(turns: _controller, child: ball)
          : ball,
    );
  }
}

class _CoreBallPainter extends CustomPainter {
  const _CoreBallPainter({
    required this.accent,
    required this.surface,
    required this.border,
  });

  final Color accent;
  final Color surface;
  final Color border;

  @override
  void paint(Canvas canvas, Size size) {
    final diameter = math.min(size.width, size.height);
    if (diameter <= 0) return;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = diameter * .45;
    final circle = Path()
      ..addOval(Rect.fromCircle(center: center, radius: radius));
    canvas.save();
    canvas.clipPath(circle);

    canvas.drawRect(
      Rect.fromLTRB(
        center.dx - radius, center.dy - radius,
        center.dx + radius, center.dy,
      ),
      Paint()..color = accent,
    );
    canvas.drawRect(
      Rect.fromLTRB(
        center.dx - radius, center.dy,
        center.dx + radius, center.dy + radius,
      ),
      Paint()..color = surface,
    );
    canvas.drawLine(
      Offset(center.dx - radius, center.dy),
      Offset(center.dx + radius, center.dy),
      Paint()
        ..color = border
        ..strokeWidth = diameter * .092
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();

    final outline = Paint()
      ..color = border
      ..style = PaintingStyle.stroke
      ..strokeWidth = diameter * .085;
    canvas.drawCircle(center, radius, outline);
    canvas.drawCircle(
      center, radius * .26,
      Paint()..color = surface,
    );
    canvas.drawCircle(
      center, radius * .26,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = diameter * .07,
    );
    canvas.drawCircle(
      Offset(center.dx - radius * .46, center.dy - radius * .46),
      radius * .12,
      Paint()..color = Colors.white.withValues(alpha: .45),
    );
  }

  @override
  bool shouldRepaint(covariant _CoreBallPainter other) =>
      other.accent != accent ||
      other.surface != surface ||
      other.border != border;
}
