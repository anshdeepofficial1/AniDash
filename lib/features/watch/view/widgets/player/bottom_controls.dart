import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ani_dash/core/models/aniskip/aniskip_result.dart';
import 'package:ani_dash/core/utils/formatter.dart';
import 'package:ani_dash/features/watch/view_model/aniskip_notifier.dart';
import 'package:ani_dash/features/watch/view_model/episode_stream_provider.dart';
import 'package:ani_dash/features/watch/view_model/player/player_provider.dart';
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
                            if (!widget.isLocal) ...[
                              _FlatTextBtn(
                                text: ref.watch(
                                  episodeDataProvider.select(
                                    (s) =>
                                        s.selectedServer?.isDub == true
                                            ? 'DUB'
                                            : 'SUB',
                                  ),
                                ),
                                onTap: widget.onAudioPressed,
                                isAccent: true,
                                scheme: scheme,
                              ),
                              Builder(
                                builder: (context) {
                                  final servers = ref.watch(
                                    episodeDataProvider.select(
                                      (s) => s.servers,
                                    ),
                                  );
                                  final currentServer = ref.watch(
                                    episodeDataProvider.select(
                                      (s) => s.selectedServer,
                                    ),
                                  );
                                  final validServers =
                                      servers.where((s) {
                                        final id = s.id?.toLowerCase() ?? '';
                                        final name =
                                            s.name?.toLowerCase() ?? '';
                                        return id != 'ext' &&
                                            name != 'extension' &&
                                            id != 'default' &&
                                            name != 'default';
                                      }).toList();

                                  if (validServers.length <= 1) {
                                    return const SizedBox.shrink();
                                  }

                                  final serverName =
                                      currentServer?.name ??
                                      currentServer?.id ??
                                      'SERVER';
                                  if (serverName.toLowerCase() == 'extension' ||
                                      serverName.toLowerCase() == 'default') {
                                    return const SizedBox.shrink();
                                  }

                                  final cleanName =
                                      serverName
                                          .replaceAll(RegExp(r'\(.*?\)'), '')
                                          .trim()
                                          .toUpperCase();

                                  return _FlatTextBtn(
                                    text:
                                        cleanName.isEmpty
                                            ? 'SERVER'
                                            : cleanName,
                                    onTap: widget.onServerPressed,
                                    isAccent: false,
                                    scheme: scheme,
                                  );
                                },
                              ),
                            ],
                            _ToolbarIcon(
                              icon: Icons.subtitles_rounded,
                              onTap: widget.onSubtitlePressed,
                            ),
                            _ToolbarIcon(
                              icon: Icons.high_quality_rounded,
                              onTap: widget.onSourcePressed,
                            ),
                            if (widget.onEpisodePressed != null)
                              _ToolbarIcon(
                                icon: Icons.video_library_rounded,
                                onTap: widget.onEpisodePressed,
                              ),
                            _ToolbarIcon(
                              icon: Icons.fullscreen_rounded,
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

    final highlightSegments = <({double start, double end, String label})>[];

    for (final skip in skips) {
      if (skip.interval == null) continue;
      final start = skip.interval!.startTime * 1000;
      final end = skip.interval!.endTime * 1000;
      final segLength = end - start;
      if (start < 0 || end <= start) continue;
      // Ensure segment length is sensible (between 5s and 200s, max 35% of episode)
      if (segLength < 5000 || segLength > 200000 || segLength > total * 0.35) {
        continue;
      }

      final clampedStart = start.clamp(0.0, total);
      final clampedEnd = end.clamp(0.0, total);
      if (clampedEnd <= clampedStart) continue;

      final isOp =
          skip.skipType == SkipType.op ||
          (skip.skipType == SkipType.mixed && clampedStart <= 300000);
      final isEd =
          skip.skipType == SkipType.ed ||
          (skip.skipType == SkipType.mixed && clampedStart > 300000) ||
          (!isOp && clampedStart >= total * 0.6);
      final isRecap = skip.skipType == SkipType.recap;

      // Intro / recap must start within first 6 minutes (360,000 ms)
      if ((isOp || isRecap) && clampedStart > 360000) continue;
      // Outro must start after at least 5 minutes and in the latter half
      if (isEd && (clampedStart < 300000 || clampedStart < total * 0.5)) {
        continue;
      }

      highlightSegments.add((
        start: clampedStart,
        end: clampedEnd,
        label: isOp ? 'INTRO' : (isEd ? 'OUTRO' : (isRecap ? 'RECAP' : 'SKIP')),
      ));
    }

    return highlightSegments.map((seg) {
      final highlightColor = Color.lerp(scheme.primary, Colors.black, 0.45)!;
      final startRatio = seg.start / total;
      final endRatio = seg.end / total;
      final width = (endRatio - startRatio) * maxWidth;
      final displayWidth = width.clamp(6.0, maxWidth);

      return Positioned(
        left: startRatio * maxWidth,
        width: displayWidth,
        top: -2,
        bottom: -2,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Container(
              decoration: BoxDecoration(
                color: highlightColor.withValues(alpha: 0.68),
                borderRadius: BorderRadius.circular(2),
              ),
              child:
                  width >= 34
                      ? Center(
                        child: Text(
                          seg.label,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 7.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.2,
                            height: 1.0,
                          ),
                        ),
                      )
                      : null,
            ),
            // Floating badge above the bar for narrow segments (e.g. short Outro)
            if (width < 34)
              Positioned(
                top: -14,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: highlightColor.withValues(alpha: 0.82),
                    borderRadius: BorderRadius.circular(3),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black54,
                        blurRadius: 3,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Text(
                    seg.label,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 7,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.2,
                      height: 1.0,
                    ),
                  ),
                ),
              ),
          ],
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
          child: Icon(
            Icons.skip_next_rounded,
            color: Colors.white,
            size: 24,
          ),
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

class _FlatTextBtn extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  final bool isAccent;
  final ColorScheme? scheme;

  const _FlatTextBtn({
    required this.text,
    required this.onTap,
    this.isAccent = false,
    this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color:
            isAccent
                ? scheme?.primary.withValues(alpha: 0.15)
                : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: Text(
              text,
              style: TextStyle(
                color: isAccent ? scheme?.primary : Colors.white70,
                fontSize: 12,
                fontWeight: isAccent ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
