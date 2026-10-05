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
  bool _introDismissed = false;
  bool _outroDismissed = false;
  Timer? _visibilityTimer;
  String? _visibleRangeKey;
  late final AnimationController _countdownController;

  @override
  void initState() {
    super.initState();
    _countdownController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
  }

  @override
  void dispose() {
    _visibilityTimer?.cancel();
    _countdownController.dispose();
    super.dispose();
  }

  void _showBriefly(String key, {required bool intro}) {
    if (_visibleRangeKey == key) return;
    _visibleRangeKey = key;
    _visibilityTimer?.cancel();
    _countdownController
      ..reset()
      ..forward();
    _visibilityTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() {
        if (intro) {
          _introDismissed = true;
        } else {
          _outroDismissed = true;
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(playerSettingsProvider);
    // Keep the manual action available whenever the playhead is inside a
    // detected intro/outro. Auto-skip normally moves past the range at once,
    // but this remains a reliable fallback while its seek is still pending.
    if (!settings.enableAniSkip) {
      return const SizedBox.shrink();
    }

    final currentEp = ref.watch(
      episodeDataProvider.select((s) => s.selectedEpisode),
    );
    if (currentEp != _lastEpisode) {
      _lastEpisode = currentEp;
      _introDismissed = false;
      _outroDismissed = false;
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

    String? label;
    VoidCallback? onSkip;

    if (currentSkip.interval != null) {
      final isOp =
          currentSkip.skipType == SkipType.op ||
          (currentSkip.skipType == SkipType.mixed &&
              currentSkip.interval!.startTime < 700);
      final isEd =
          currentSkip.skipType == SkipType.ed ||
          (currentSkip.skipType == SkipType.mixed &&
              currentSkip.interval!.startTime >= 700);
      final isSourceVerified =
          currentSkip.skipId?.startsWith('source-') ?? false;
      final durationMatches =
          currentSkip.episodeLength > 0 &&
          (currentSkip.episodeLength - dur.inSeconds).abs() <= 90;
      // AniSkip IDs are already tied to the selected MAL episode. Some valid
      // providers report rounded episode lengths, so a strict 90-second
      // duration match hid real intro/outro buttons. Placement checks below
      // still prevent unrelated ranges from appearing.
      final verified =
          isSourceVerified ||
          currentSkip.skipId?.isNotEmpty == true ||
          durationMatches;
      final plausiblePlacement =
          (isOp && currentSkip.interval!.startTime <= 180) ||
          (isEd &&
              dur.inSeconds > 0 &&
              currentSkip.interval!.startTime >= dur.inSeconds * .55);

      if (!verified || !plausiblePlacement) {
        return const SizedBox.shrink();
      }

      if (isOp && !_introDismissed) {
        _showBriefly(
          '${currentEp}_intro_${currentSkip.interval!.startTime}_${currentSkip.interval!.endTime}',
          intro: true,
        );
        label = 'Skip Intro';
        onSkip = () {
          setState(() => _introDismissed = true);
          final target = Duration(
            seconds: currentSkip.interval!.endTime.toInt() + 1,
          );
          ref.read(playerStateProvider.notifier).seek(target);
          ref.read(playerUIControllerProvider.notifier).restartHideTimer();
        };
      } else if (isEd && !_outroDismissed) {
        _showBriefly(
          '${currentEp}_outro_${currentSkip.interval!.startTime}_${currentSkip.interval!.endTime}',
          intro: false,
        );
        label = 'Skip Outro';
        onSkip = () {
          setState(() => _outroDismissed = true);
          final target = Duration(
            seconds: currentSkip.interval!.endTime.toInt() + 1,
          );
          ref.read(playerStateProvider.notifier).seek(target);
          ref.read(playerUIControllerProvider.notifier).restartHideTimer();
        };
      }
    }

    if (label == null || onSkip == null) {
      return const SizedBox.shrink();
    }

    final scheme = Theme.of(context).colorScheme;

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
                  color: Colors.black.withValues(alpha: 0.78),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: scheme.primary.withValues(alpha: 0.7),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
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
                            Icons.fast_forward_rounded,
                            size: 20,
                            color: scheme.primary,
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
                                scheme.primary,
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
