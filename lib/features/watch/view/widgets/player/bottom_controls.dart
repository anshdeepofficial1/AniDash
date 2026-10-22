import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ani_dash/core/models/aniskip/aniskip_result.dart';
import 'package:ani_dash/core/utils/formatter.dart';
import 'package:ani_dash/features/watch/view_model/aniskip_notifier.dart';
import 'package:ani_dash/features/watch/view_model/episode_stream_provider.dart';
import 'package:ani_dash/features/watch/view_model/player/player_provider.dart';
import 'package:ani_dash/helpers/ui.dart';
import 'package:ani_dash/main.dart';

class BottomControls extends ConsumerStatefulWidget {
  final VoidCallback onInteraction;
  final VoidCallback onLockPressed;
  final VoidCallback onSourcePressed;
  final VoidCallback onSubtitlePressed;
  final VoidCallback onServerPressed;
  final VoidCallback onAudioPressed;
  final VoidCallback onForwardPressed;
  final VoidCallback onSettingsPressed;
  final VoidCallback? onEpisodePressed;
  final VoidCallback? onFullScreenPressed;
  final bool isLocal;

  const BottomControls({
    super.key,
    required this.onInteraction,
    required this.onLockPressed,
    required this.onSourcePressed,
    required this.onSubtitlePressed,
    required this.onServerPressed,
    required this.onAudioPressed,
    required this.onForwardPressed,
    required this.onSettingsPressed,
    required this.onFullScreenPressed,
    this.onEpisodePressed,
    this.isLocal = false,
  });

  @override
  ConsumerState<BottomControls> createState() => _BottomControlsState();
}

class _BottomControlsState extends ConsumerState<BottomControls> {
  static const _remainingTimePreference = 'player_show_remaining_time';
  double? _draggedValue;
  double _dragPositionX = 0.0;
  bool _showRemainingTime = false;

  @override
  void initState() {
    super.initState();
    _showRemainingTime = sharedPrefs.getBool(_remainingTimePreference) ?? false;
  }

  // VoidCallback _wrap(VoidCallback? cb) {
  //   return () {
  //     cb?.call();
  //     widget.onInteraction();
  //   };
  // }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final safeInsets = MediaQuery.viewPaddingOf(context);
    final maxSide = math.max(safeInsets.left, safeInsets.right);
    final sidePadding = (maxSide > 0 ? maxSide : 16.0) + 8.0;
    // final settings = ref.watch(playerSettingsProvider);

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black, Colors.black87, Colors.transparent],
          stops: [0.0, 0.6, 1.0],
        ),
      ),
      child: SafeArea(
        top: false,
        bottom: false,
        left: false,
        right: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            sidePadding,
            0,
            sidePadding,
            safeInsets.bottom.clamp(8.0, 24.0),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildEdgeScrubber(context, scheme),

              Padding(
                padding: const EdgeInsets.fromLTRB(10, 2, 10, 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildPlayPauseButton(scheme),
                        if (!widget.isLocal) ...[
                          const SizedBox(width: 2),
                          _buildNextEpisodeButton(),
                        ],
                        const SizedBox(width: 6),
                        _buildTimeDisplay(),
                      ],
                    ),

                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        reverse: true,
                        physics: const ClampingScrollPhysics(),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _ToolbarIcon(
                              icon: (MediaQuery.of(context).orientation ==
                                          Orientation.landscape ||
                                      UIHelper.isFullscreen)
                                  ? Icons.fullscreen_exit_rounded
                                  : Icons.fullscreen_rounded,
                              onTap: widget.onFullScreenPressed,
                            ),
                            _ToolbarIcon(
                              icon: Icons.more_vert_rounded,
                              onTap: widget.onSettingsPressed,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEdgeScrubber(BuildContext context, ColorScheme scheme) {
    final (pos, dur, buf) = ref.watch(
      playerStateProvider.select((p) => (p.position, p.duration, p.buffer)),
    );
    final hasDuration = dur.inMilliseconds > 0;
    final max = hasDuration ? dur.inMilliseconds.toDouble() : 1.0;
    final value =
        hasDuration
            ? (_draggedValue ?? pos.inMilliseconds.toDouble()).clamp(0, max)
            : 0.0;
    final buffer =
        hasDuration ? buf.inMilliseconds.toDouble().clamp(0, max) : 0.0;
    final isDragging = _draggedValue != null;

    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (details) => widget.onInteraction(),
          onHorizontalDragUpdate: (details) {
            if (!hasDuration) return;
            final percent = (details.localPosition.dx / constraints.maxWidth)
                .clamp(0.0, 1.0);
            setState(() {
              _draggedValue = percent * max;
              _dragPositionX = details.localPosition.dx;
            });
            widget.onInteraction();
          },
          onHorizontalDragEnd: (details) {
            if (_draggedValue != null) {
              ref
                  .read(playerStateProvider.notifier)
                  .seek(Duration(milliseconds: _draggedValue!.round()));
              setState(() => _draggedValue = null);
              widget.onInteraction();
            }
          },
          onTapDown: (details) {
            if (!hasDuration) return;
            final percent = (details.localPosition.dx / constraints.maxWidth)
                .clamp(0.0, 1.0);
            ref
                .read(playerStateProvider.notifier)
                .seek(Duration(milliseconds: (percent * max).round()));
            widget.onInteraction();
          },
          child: SizedBox(
            height: 14,
            child: Stack(
              alignment: Alignment.centerLeft,
              clipBehavior: Clip.none,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  height: isDragging ? 7 : 4,
                  width: double.infinity,
                  color: Colors.white24,
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    clipBehavior: Clip.none,
                    children: [
                      FractionallySizedBox(
                        widthFactor: buffer / max,
                        child: Container(color: Colors.white54),
                      ),
                      FractionallySizedBox(
                        widthFactor: value / max,
                        child: Container(
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            boxShadow: [
                              BoxShadow(
                                color: scheme.primary.withValues(alpha: .55),
                                blurRadius: 5,
                              ),
                            ],
                          ),
                        ),
                      ),
                      ..._buildHighlights(scheme, max, constraints.maxWidth),
                    ],
                  ),
                ),
                if (isDragging)
                  Positioned(
                    left: (value / max) * constraints.maxWidth - 6,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        shape: BoxShape.circle,
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 4,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                  ),
                if (isDragging)
                  Positioned(
                    left: (_dragPositionX - 25).clamp(
                      10.0,
                      constraints.maxWidth - 50.0,
                    ),
                    top: -20,
                    child: Text(
                      formatDuration(Duration(milliseconds: value.round())),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildHighlights(
    ColorScheme scheme,
    double total,
    double maxWidth,
  ) {
    final skips = ref.watch(aniSkipProvider);
    if (total < 30000) return [];

    final highlightSegments =
        <({double start, double end, String label, Color color, Color textColor})>[];

    for (final skip in skips) {
      if (skip.interval == null) continue;
      final start = skip.interval!.startTime * 1000;
      final end = skip.interval!.endTime * 1000;
      final segLength = end - start;
      if (start < 0 || end <= start) continue;
      // Ensure segment length is sensible (between 3s and 240s, max 40% of episode)
      if (segLength < 3000 || segLength > 240000 || segLength > total * 0.40) {
        continue;
      }

      final clampedStart = start.clamp(0.0, total);
      final clampedEnd = end.clamp(0.0, total);
      if (clampedEnd <= clampedStart) continue;

      final isOp =
          (skip.skipType == SkipType.op ||
              (skip.skipType == SkipType.mixed && clampedStart <= 300000)) &&
          clampedStart <= 600000;
      final isRecap = skip.skipType == SkipType.recap;
      final isEd =
          (skip.skipType == SkipType.ed ||
              (skip.skipType == SkipType.mixed && clampedStart > 300000) ||
              (!isOp && !isRecap && clampedStart >= total * 0.5)) &&
          clampedStart >= 360000;

      // Intro must start within first 10 minutes (600,000 ms)
      if (isOp && clampedStart > 600000) continue;
      // Recap must start within first 70% of episode
      if (isRecap && clampedStart > total * 0.70) continue;
      // Outro must start in the latter portion of episode
      if (isEd && clampedStart < 360000) continue;

      final Color segColor = isRecap
          ? Color.lerp(scheme.primary, Colors.lightBlueAccent, 0.35)!
          : (isOp
              ? Color.lerp(scheme.primary, Colors.white, 0.30)!
              : Color.lerp(scheme.primary, Colors.white, 0.45)!);

      final Color textColor =
          ThemeData.estimateBrightnessForColor(segColor) == Brightness.dark
              ? Colors.white
              : Colors.black87;

      highlightSegments.add((
        start: clampedStart,
        end: clampedEnd,
        label: isRecap ? 'RECAP' : (isOp ? 'INTRO' : (isEd ? 'OUTRO' : 'SKIP')),
        color: segColor,
        textColor: textColor,
      ));
    }

    return highlightSegments.map((seg) {
      final highlightColor = seg.color;
      final startRatio = seg.start / total;
      final endRatio = seg.end / total;
      final width = (endRatio - startRatio) * maxWidth;
      final displayWidth = width.clamp(6.0, maxWidth);

      return Positioned(
        left: startRatio * maxWidth,
        width: displayWidth,
        top: -2,
        bottom: -2,
        child: Container(
          decoration: BoxDecoration(
            color: highlightColor,
            borderRadius: BorderRadius.circular(2.5),
          ),
          child:
              width >= 34
                  ? Center(
                    child: Text(
                      seg.label,
                      style: TextStyle(
                        color: seg.textColor,
                        fontSize: 7.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.2,
                        height: 1.0,
                      ),
                    ),
                  )
                  : null,
        ),
      );
    }).toList();
  }

  Widget _buildPlayPauseButton(ColorScheme scheme) {
    final isPlaying = ref.watch(playerStateProvider.select((p) => p.isPlaying));
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          widget.onInteraction();
          ref.read(playerStateProvider.notifier).togglePlay();
        },
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(4.0),
          child: Icon(
            isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            color: Colors.white,
            size: 26,
          ),
        ),
      ),
    );
  }

  Widget _buildNextEpisodeButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          widget.onInteraction();
          ref.read(episodeDataProvider.notifier).changeEpisode(null, by: 1);
        },
        customBorder: const CircleBorder(),
        child: const Padding(
          padding: EdgeInsets.all(4.0),
          child: Icon(Icons.skip_next_rounded, color: Colors.white, size: 24),
        ),
      ),
    );
  }

  Widget _buildTimeDisplay() {
    final (pos, dur) = ref.watch(
      playerStateProvider.select((p) => (p.position, p.duration)),
    );

    final hasDuration = dur > Duration.zero;
    final remaining = hasDuration && dur > pos ? dur - pos : Duration.zero;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() => _showRemainingTime = !_showRemainingTime);
        sharedPrefs.setBool(_remainingTimePreference, _showRemainingTime);
        widget.onInteraction();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: formatDuration(pos),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const TextSpan(
                text: '  /  ',
                style: TextStyle(
                  color: Colors.white38,
                  fontWeight: FontWeight.w500,
                ),
              ),
              TextSpan(
                text:
                    !hasDuration
                        ? '--:--'
                        : _showRemainingTime
                        ? '-${formatDuration(remaining)}'
                        : formatDuration(dur),
                style: TextStyle(
                  color: Colors.white60,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          style: const TextStyle(
            fontSize: 12,
            letterSpacing: 0.5,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

class _ToolbarIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _ToolbarIcon({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,

        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(6.0),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}
