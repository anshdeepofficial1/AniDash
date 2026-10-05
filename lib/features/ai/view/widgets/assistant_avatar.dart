import 'dart:math' as math;
import 'package:flutter/material.dart';

enum AssistantMotion { idle, thinking, working, success, error }

class AssistantVisual {
  const AssistantVisual(this.asset, this.color, this.role);

  final String asset;
  final Color color;
  final String role;

  static AssistantVisual forId(String? id) => switch (id) {
    'coordinator' => const AssistantVisual(
      'assets/ai_assistants/mira.png',
      Color(0xFF8665E8),
      'Coordinator',
    ),
    'vision' => const AssistantVisual(
      'assets/ai_assistants/aira.png',
      Color(0xFF4C9FE8),
      'Visual specialist',
    ),
    'action' => const AssistantVisual(
      'assets/ai_assistants/kiro.png',
      Color(0xFFF0A23B),
      'Action specialist',
    ),
    _ => const AssistantVisual(
      'assets/ai_assistants/nia.png',
      Color(0xFF56B984),
      'Anime specialist',
    ),
  };
}

class AssistantAvatar extends StatefulWidget {
  const AssistantAvatar({
    super.key,
    required this.assistantId,
    this.size = 40,
    this.showStatus = false,
    this.motion = AssistantMotion.idle,
  });

  final String? assistantId;
  final double size;
  final bool showStatus;
  final AssistantMotion motion;

  @override
  State<AssistantAvatar> createState() => _AssistantAvatarState();
}

class _AssistantAvatarState extends State<AssistantAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
    _configure();
  }

  @override
  void didUpdateWidget(covariant AssistantAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.motion != widget.motion) _configure();
  }

  void _configure() {
    _controller
      ..stop()
      ..reset()
      ..duration = switch (widget.motion) {
        AssistantMotion.idle => const Duration(milliseconds: 2800),
        AssistantMotion.thinking => const Duration(milliseconds: 900),
        AssistantMotion.working => const Duration(milliseconds: 720),
        AssistantMotion.success => const Duration(milliseconds: 650),
        AssistantMotion.error => const Duration(milliseconds: 420),
      };
    if (widget.motion == AssistantMotion.success) {
      _controller.forward();
    } else {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visual = AssistantVisual.forId(widget.assistantId);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return SizedBox.square(
      dimension: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final t = reduceMotion ? 0.0 : _controller.value;
          final transform = Matrix4.identity();
          var scale = 1.0;
          switch (widget.motion) {
            case AssistantMotion.idle:
              scale = 1 + math.sin(t * math.pi * 2) * .018;
            case AssistantMotion.thinking:
              transform.translateByDouble(
                math.sin(t * math.pi * 2) * widget.size * .055,
                -math.sin(t * math.pi) * widget.size * .035,
                0,
                1,
              );
              transform.rotateZ(math.sin(t * math.pi * 2) * .055);
            case AssistantMotion.working:
              transform.translateByDouble(
                0,
                -math.sin(t * math.pi).abs() * widget.size * .08,
                0,
                1,
              );
              scale = 1 + math.sin(t * math.pi).abs() * .035;
            case AssistantMotion.success:
              scale = 1 + math.sin(t * math.pi) * .12;
            case AssistantMotion.error:
              transform.translateByDouble(
                math.sin(t * math.pi * 6) * widget.size * .06,
                0,
                0,
                1,
              );
          }
          transform.scaleByDouble(scale, scale, 1, 1);
          return Transform(
            alignment: Alignment.center,
            transform: transform,
            child: child,
          );
        },
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: visual.color.withValues(alpha: .24),
                    blurRadius: widget.size * .25,
                    spreadRadius: -widget.size * .12,
                    offset: Offset(0, widget.size * .08),
                  ),
                ],
              ),
              child: Image.asset(
                visual.asset,
                width: widget.size,
                height: widget.size,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            ),
            if (widget.motion == AssistantMotion.thinking)
              ...List.generate(3, (index) {
                final angle = (_controller.value * math.pi * 2) + index * 2.1;
                return Transform.translate(
                  offset: Offset(
                    math.cos(angle) * widget.size * .43,
                    math.sin(angle) * widget.size * .43,
                  ),
                  child: Container(
                    width: widget.size * .07,
                    height: widget.size * .07,
                    decoration: BoxDecoration(
                      color: visual.color.withValues(alpha: .8),
                      shape: BoxShape.circle,
                    ),
                  ),
                );
              }),
            if (widget.showStatus)
              Positioned(
                right: 0,
                bottom: 1,
                child: Container(
                  width: widget.size * .22,
                  height: widget.size * .22,
                  decoration: BoxDecoration(
                    color: const Color(0xFF42D783),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Theme.of(context).colorScheme.surface,
                      width: 2,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
