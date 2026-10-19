import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ani_dash/core/models/aniskip/aniskip_result.dart';
import 'package:ani_dash/features/watch/view_model/aniskip_notifier.dart';
import 'package:ani_dash/features/watch/view_model/player/player_provider.dart';
import 'package:ani_dash/features/watch/view_model/player/player_ui_controller.dart';
import 'package:ani_dash/features/watch/view_model/episode_stream_provider.dart';
import 'package:ani_dash/shared/providers/settings/player_notifier.dart';

class FloatingSkipButtonOverlay extends ConsumerStatefulWidget {
  const FloatingSkipButtonOverlay({super.key});

  @override
  ConsumerState<FloatingSkipButtonOverlay> createState() =>
      _FloatingSkipButtonOverlayState();
}

class _FloatingSkipButtonOverlayState
    extends ConsumerState<FloatingSkipButtonOverlay>
    with SingleTickerProviderStateMixin {
  int? _lastEpisode;
  final Set<String> _dismissedRangeKeys = <String>{};
  Timer? _visibilityTimer;
  String? _visibleRangeKey;
  late final AnimationController _countdownController;

  @override
  void initState() {
    super.initState();
    _countdownController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
  }

  final Set<String> _userManuallySkippedKeys = <String>{};

  @override
  void dispose() {
    _visibilityTimer?.cancel();
    _countdownController.dispose();
    super.dispose();
  }

  void _showBriefly(String key) {
    if (_visibleRangeKey == key) return;
    _visibleRangeKey = key;
    _visibilityTimer?.cancel();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _countdownController
        ..reset()
        ..forward();
    });
    _visibilityTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() {
        _dismissedRangeKeys.add(key);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(playerSettingsProvider);
    if (!settings.enableAniSkip) {
      return const SizedBox.shrink();
    }

    final currentEp = ref.watch(
      episodeDataProvider.select((s) => s.selectedEpisode),
    );
    if (currentEp != _lastEpisode) {
      _lastEpisode = currentEp;
      _dismissedRangeKeys.clear();
      _userManuallySkippedKeys.clear();
      _visibleRangeKey = null;
      _visibilityTimer?.cancel();
    }

    final (pos, dur) = ref.watch(
      playerStateProvider.select((p) => (p.position, p.duration)),
    );
    final isControlsVisible = ref.watch(
      playerUIControllerProvider.select((s) => s.isVisible),
    );

    final skips = ref.watch(aniSkipProvider);

    // Check AniSkip matching interval
    final currentSkip = skips.firstWhere(
      (s) =>
          s.interval != null &&
          pos >= Duration(seconds: s.interval!.startTime.toInt()) &&
          pos < Duration(seconds: s.interval!.endTime.toInt()),
      orElse:
          () => const AniSkipResultItem(
            skipType: SkipType.unknown,
            action: '',
            episodeLength: 0,
          ),
    );

    if (currentSkip.interval == null) {
      if (_visibleRangeKey != null) {
        _visibleRangeKey = null;
        _visibilityTimer?.cancel();
      }
      return const SizedBox.shrink();
    }

    final startTime = currentSkip.interval!.startTime;
    final isOp =
        (currentSkip.skipType == SkipType.op ||
            (currentSkip.skipType == SkipType.mixed && startTime <= 300)) &&
        startTime <= 600;
    final isEd =
        (currentSkip.skipType == SkipType.ed ||
            (currentSkip.skipType == SkipType.mixed && startTime >= 400)) &&
        startTime >= 360;
    final isRecap = currentSkip.skipType == SkipType.recap;

    final resolvedIsOp = isOp || (!isEd && !isRecap && startTime <= 600);
    final resolvedIsEd = isEd || (!resolvedIsOp && !isRecap && startTime >= 360);

    final plausiblePlacement =
        (resolvedIsOp && startTime <= 600) ||
        (isRecap && (dur.inSeconds <= 0 || startTime <= dur.inSeconds * 0.70)) ||
        (resolvedIsEd && startTime >= 360);

    if (!plausiblePlacement) {
      return const SizedBox.shrink();
    }

    final rangeKey =
        '${currentEp}_${currentSkip.skipType.name}_${currentSkip.interval!.startTime.toInt()}_${currentSkip.interval!.endTime.toInt()}';
    if (_userManuallySkippedKeys.contains(rangeKey)) {
      return const SizedBox.shrink();
    }

    final isDismissed = _dismissedRangeKeys.contains(rangeKey);
    if (isDismissed && !isControlsVisible) {
      return const SizedBox.shrink();
    }

    _showBriefly(rangeKey);

    final scheme = Theme.of(context).colorScheme;
    final accentColor = scheme.primary;

    String? label;
    VoidCallback? onSkip;
    IconData? buttonIcon;

    if (resolvedIsOp) {
      label = 'Skip Intro';
      buttonIcon = Icons.fast_forward_rounded;
      onSkip = () {
        setState(() {
          _userManuallySkippedKeys.add(rangeKey);
          _dismissedRangeKeys.add(rangeKey);
        });
        final target = Duration(
          seconds: currentSkip.interval!.endTime.ceil(),
        );
        ref.read(playerStateProvider.notifier).seek(target);
        ref.read(playerUIControllerProvider.notifier).restartHideTimer();
      };
    } else if (isRecap) {
      label = 'Skip Recap';
      buttonIcon = Icons.fast_forward_rounded;
      onSkip = () {
        setState(() {
          _userManuallySkippedKeys.add(rangeKey);
          _dismissedRangeKeys.add(rangeKey);
        });
        final target = Duration(
          seconds: currentSkip.interval!.endTime.ceil(),
        );
        ref.read(playerStateProvider.notifier).seek(target);
        ref.read(playerUIControllerProvider.notifier).restartHideTimer();
      };
    } else if (resolvedIsEd) {
      label = 'Skip Outro';
      buttonIcon = Icons.skip_next_rounded;
      onSkip = () {
        setState(() {
          _userManuallySkippedKeys.add(rangeKey);
          _dismissedRangeKeys.add(rangeKey);
        });
        final target = Duration(
          seconds: currentSkip.interval!.endTime.ceil(),
        );
        ref.read(playerStateProvider.notifier).seek(target);
        ref.read(playerUIControllerProvider.notifier).restartHideTimer();
      };
    }

    if (label == null || onSkip == null) {
      return const SizedBox.shrink();
    }

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      bottom: isControlsVisible ? 115 : 28,
      right: 24,
      child: Material(
        color: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: InkWell(
              onTap: onSkip,
              borderRadius: BorderRadius.circular(24),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: accentColor.withValues(alpha: 0.85),
                    width: 1.4,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: accentColor.withValues(alpha: 0.25),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 9, 16, 7),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            buttonIcon ?? Icons.fast_forward_rounded,
                            size: 20,
                            color: accentColor,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    AnimatedBuilder(
                      animation: _countdownController,
                      builder:
                          (context, _) => ClipRRect(
                            borderRadius: const BorderRadius.vertical(
                              bottom: Radius.circular(24),
                            ),
                            child: LinearProgressIndicator(
                              value: 1 - _countdownController.value,
                              minHeight: 2.5,
                              backgroundColor: Colors.white10,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                accentColor,
                              ),
                            ),
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
