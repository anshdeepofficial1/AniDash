import 'dart:async';
import 'dart:io';

import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screenshot/screenshot.dart';
import 'package:ani_dash/core/models/anime/source_model.dart';
import 'package:ani_dash/core/utils/app_logger.dart';
import 'package:ani_dash/features/watch/view/widgets/player/controls_overlay.dart';
import 'package:ani_dash/features/watch/view/widgets/player/player_gesture_handler.dart';

import 'package:ani_dash/features/watch/view/widgets/player/sheets/generic_selection_sheet.dart';
import 'package:ani_dash/features/watch/view/widgets/player/sheets/settings_sheet.dart';
import 'package:ani_dash/features/watch/view/widgets/player/sheets/subtitle_selection_sheet.dart';
import 'package:ani_dash/features/watch/view/widgets/player/speed_indicator_overlay.dart';
import 'package:ani_dash/features/watch/view/widgets/player/subtitle_overlay.dart';
import 'package:ani_dash/features/watch/view/widgets/player/volume_brightness_overlay.dart';
import 'package:ani_dash/features/watch/view_model/player/pip_controller.dart';
import 'package:ani_dash/features/watch/view/widgets/player/pip_overlay.dart';
import 'package:ani_dash/features/watch/view_model/episode_list_provider.dart';
import 'package:ani_dash/features/watch/view_model/episode_stream_provider.dart';
import 'package:ani_dash/features/watch/view_model/player/player_provider.dart';
import 'package:ani_dash/features/watch/view_model/player/player_ui_controller.dart';
import 'package:ani_dash/shared/providers/settings/player_notifier.dart';
import 'package:ani_dash/features/watch/view/widgets/player/seek_feedback_overlay.dart';
import 'package:ani_dash/features/watch/view/widgets/player/fetching_progress_badge.dart';
import 'package:ani_dash/features/watch/view/widgets/player/next_episode_prompt_overlay.dart';
import 'package:ani_dash/features/watch/view/widgets/player/floating_skip_button_overlay.dart';
import 'package:ani_dash/helpers/ui.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:window_manager/window_manager.dart';

class AniDashVideoPlayer extends ConsumerStatefulWidget {
  final VoidCallback? onEpisodesPressed;
  final VoidCallback? onPanelCloseRequest;
  final ScreenshotController? screenshotController;
  final String? localFilePath;
  final String? localTitle;
  final Duration localStartAt;

  const AniDashVideoPlayer({
    super.key,
    this.onEpisodesPressed,
    this.onPanelCloseRequest,
    this.screenshotController,
    this.localFilePath,
    this.localTitle,
    this.localStartAt = Duration.zero,
  });

  @override
  ConsumerState<AniDashVideoPlayer> createState() => _AniDashVideoPlayerState();
}

class _AniDashVideoPlayerState extends ConsumerState<AniDashVideoPlayer>
    with WidgetsBindingObserver {
  final FocusNode _focusNode = FocusNode();

  // Local state for complex interactions that don't need to be global/persisted
  bool _isChangingVolume = false;
  bool _isChangingBrightness = false;
  bool _isDragLeft = false;
  bool _isSpeeding = false;
  double _lastSpeed = 1.0;
  Timer? _volumeOverlayTimer;
  Timer? _doubleTapTimer;
  Timer? _fitLabelTimer;
  String? _fitLabel;
  int _doubleTapPairCount = 0;
  Duration _doubleTapAnchor = Duration.zero;

  bool _isDraggingSeek = false;
  Duration _dragStartPos = Duration.zero;
  Duration _dragTargetPos = Duration.zero;
  Duration _dragDiff = Duration.zero;
  bool _isDragSeekForward = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (Platform.isAndroid || Platform.isIOS) {
      UIHelper.setVolumeKeyHandler(
        onVolumeUp: () => _handleHardwareVolumeKey(true),
        onVolumeDown: () => _handleHardwareVolumeKey(false),
        onVolumeChanged: _handleHardwareVolumeChanged,
      );
      _activatePlayerVolumeControls();
      FlutterVolumeController.getVolume().then((v) {
        if (mounted && v != null) {
          ref.read(playerUIControllerProvider.notifier).setVolume(v);
        }
      });
      FlutterVolumeController.addListener((volume) {
        if (!mounted || _isChangingVolume) return;
        _applyPlayerVolume(volume, updateSystemVolume: false);
      });
    }
    // Restart auto-hide timer on init
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
        ref.read(playerUIControllerProvider.notifier).restartHideTimer();
        final path = widget.localFilePath;
        if (path != null) {
          ref
              .read(playerStateProvider.notifier)
              .open(path, widget.localStartAt);
        }
      }
    });
  }

  Future<void> _activatePlayerVolumeControls() async {
    // Configure both layers in a deterministic order. Some Android devices
    // otherwise process the first key press before the native interceptor is
    // active and briefly show the system volume panel.
    await FlutterVolumeController.updateShowSystemUI(false);
    await UIHelper.enableVolumeInterception();
    if (!mounted) return;
    await FlutterVolumeController.updateShowSystemUI(false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _focusNode.dispose();
    _fitLabelTimer?.cancel();
    _volumeOverlayTimer?.cancel();
    _doubleTapTimer?.cancel();

    if (Platform.isAndroid || Platform.isIOS) {
      UIHelper.disableVolumeInterception();
      // Do not clear the shared platform-channel handler here. During an
      // episode switch the outgoing player can dispose after the incoming
      // player has already registered its callback, which used to remove the
      // new callback and leave hardware keys without the in-player overlay.
      // Interception is disabled above, so retaining the last callback is safe
      // after leaving the player as well.
      FlutterVolumeController.removeListener();
      FlutterVolumeController.updateShowSystemUI(true);
      try {
        ScreenBrightness().resetApplicationScreenBrightness();
      } catch (_) {}
    }
    if (!(Platform.isAndroid || Platform.isIOS)) {
      windowManager.setFullScreen(false);
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        (Platform.isAndroid || Platform.isIOS)) {
      UIHelper.setVolumeKeyHandler(
        onVolumeUp: () => _handleHardwareVolumeKey(true),
        onVolumeDown: () => _handleHardwareVolumeKey(false),
        onVolumeChanged: _handleHardwareVolumeChanged,
      );
      _activatePlayerVolumeControls();
    }
  }

  void _handleHardwareVolumeKey(bool isUp) {
    if (!mounted) return;

    FlutterVolumeController.updateShowSystemUI(false);

    final state = ref.read(playerUIControllerProvider);

    const step = 0.05; // 5% per press
    final newV = (state.volume + (isUp ? step : -step)).clamp(0.0, 1.0);

    _applyPlayerVolume(newV);
  }

  void _handleHardwareVolumeChanged(double value) {
    if (!mounted) return;
    _applyPlayerVolume(value.clamp(0.0, 1.0), updateSystemVolume: false);
  }

  void _applyPlayerVolume(double value, {bool updateSystemVolume = true}) {
    final newV = value.clamp(0.0, 1.0);
    final controller = ref.read(playerUIControllerProvider.notifier);

    setState(() {
      _isChangingVolume = true;
    });

    controller.setVolume(newV);

    if (updateSystemVolume) FlutterVolumeController.setVolume(newV);
    ref
        .read(playerStateProvider.notifier)
        .videoController
        .player
        .setVolume(100.0);

    _volumeOverlayTimer?.cancel();
    _volumeOverlayTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() {
          _isChangingVolume = false;
        });
      }
    });
  }

  void _onVerticalDragStart(DragStartDetails details) {
    if (ref.read(playerUIControllerProvider).isLocked) return;
    final w = MediaQuery.of(context).size.width;
    _isDragLeft = details.globalPosition.dx < w / 2;
    setState(() {
      if (_isDragLeft) {
        _isChangingBrightness = true;
      } else {
        _isChangingVolume = true;
      }
    });

    // Hide controls while dragging
    ref
        .read(playerUIControllerProvider.notifier)
        .toggleVisibility(override: false);
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) async {
    if (ref.read(playerUIControllerProvider).isLocked) return;
    final delta = -details.primaryDelta! / 300;

    final controller = ref.read(playerUIControllerProvider.notifier);
    final state = ref.read(playerUIControllerProvider);

    if (_isDragLeft) {
      double newB = (state.brightness + delta).clamp(0.0, 1.0);
      controller.setBrightness(newB);
    } else {
      final newV = (state.volume + delta).clamp(0.0, 1.0);

      // Update system/player volume
      controller.setVolume(newV);

      ref
          .read(playerStateProvider.notifier)
          .videoController
          .player
          .setVolume(100.0);
    }
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    setState(() {
      _isChangingBrightness = false;
      _isChangingVolume = false;
    });
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    if (ref.read(playerUIControllerProvider).isLocked) return;
    final playerState = ref.read(playerStateProvider);
    _dragStartPos = playerState.position;
    _dragTargetPos = playerState.position;
    _dragDiff = Duration.zero;
    setState(() {
      _isDraggingSeek = true;
    });
    ref
        .read(playerUIControllerProvider.notifier)
        .toggleVisibility(override: false);
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (!_isDraggingSeek) return;
    final w = MediaQuery.of(context).size.width;
    final playerState = ref.read(playerStateProvider);
    final total = playerState.duration;

    final deltaSec = (details.primaryDelta! / w) * 120;
    final currentTargetSec = _dragTargetPos.inMilliseconds / 1000.0 + deltaSec;
    final clampedSec = currentTargetSec.clamp(
      0.0,
      total.inSeconds > 0 ? total.inSeconds.toDouble() : 3600.0,
    );

    final newTarget = Duration(milliseconds: (clampedSec * 1000).toInt());
    final diff = Duration(
      milliseconds: newTarget.inMilliseconds - _dragStartPos.inMilliseconds,
    );

    setState(() {
      _dragTargetPos = newTarget;
      _dragDiff = diff;
      _isDragSeekForward = diff.inMilliseconds >= 0;
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (!_isDraggingSeek) return;
    setState(() {
      _isDraggingSeek = false;
    });
    ref.read(playerStateProvider.notifier).seek(_dragTargetPos);
  }

  void _onLongPressStart() {
    if (ref.read(playerUIControllerProvider).isLocked) return;
    ref
        .read(playerUIControllerProvider.notifier)
        .toggleVisibility(override: false);

    setState(() {
      _isSpeeding = true;
      _lastSpeed = 2.0;
    });
    ref.read(playerStateProvider.notifier).setSpeed(2.0);
  }

  void _onLongPressUpdate(double diff) {
    if (_isSpeeding) {
      double newRate = 2.0 + (diff / 50.0);
      newRate = (newRate * 4).round() / 4;
      newRate = newRate.clamp(0.25, 4.0);

      if (newRate != _lastSpeed) {
        setState(() => _lastSpeed = newRate);
        ref.read(playerStateProvider.notifier).setSpeed(newRate);
      }
    }
  }

  void _onLongPressEnd() {
    if (_isSpeeding) {
      setState(() => _isSpeeding = false);
      ref.read(playerStateProvider.notifier).setSpeed(1.0);
    }
  }

  // --- Sheet/Dialog Logic ---

  Future<void> _sheet(Widget child) async {
    final controller = ref.read(playerUIControllerProvider.notifier);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface.withAlpha(240),
      builder: (_) => child,
    );
    controller.restartHideTimer();
  }

  Future<void> _sideSheet(Widget child) async {
    final controller = ref.read(playerUIControllerProvider.notifier);
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close player settings',
      barrierColor: Colors.black45,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder:
          (context, animation, secondaryAnimation) => Align(
            alignment: Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: 0.38,
              heightFactor: 1,
              child: Material(
                color: Theme.of(context).colorScheme.surface.withAlpha(248),
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(24),
                ),
                clipBehavior: Clip.antiAlias,
                child: child,
              ),
            ),
          ),
      transitionBuilder:
          (context, animation, secondaryAnimation, child) => SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1, 0),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
    );
    controller.restartHideTimer();
  }

  void _openSettings() => _sideSheet(
    SettingsSheetContent(
      onSubtitlesPressed: _openSubtitle,
      onDismiss: () {
        ref.read(playerUIControllerProvider.notifier).restartHideTimer();
      },
    ),
  );

  void _openQuality() {
    final data = ref.read(episodeDataProvider);
    final notifier = ref.read(episodeDataProvider.notifier);

    _sheet(
      GenericSelectionSheet<Map<String, dynamic>>(
        title: 'Quality',
        items: data.qualityOptions,
        selectedIndex: data.selectedQualityIdx ?? -1,
        displayBuilder: (e) => e['quality'],
        onItemSelected: (i) {
          notifier.changeQuality(i);
          Navigator.pop(context);
        },
      ),
    );
  }

  void _openSource() {
    final data = ref.read(episodeDataProvider);
    final notifier = ref.read(episodeDataProvider.notifier);

    _sheet(
      GenericSelectionSheet<Source>(
        title: 'Source',
        items: data.sources,
        selectedIndex: data.selectedSourceIdx ?? -1,
        displayBuilder: (e) => e.quality ?? '',
        onItemSelected: (i) {
          notifier.changeSource(i);
          Navigator.pop(context);
        },
      ),
    );
  }

  void _openServer() {
    final data = ref.read(episodeDataProvider);
    if (data.servers.isEmpty) return;

    final selectedIdx = data.servers.indexWhere(
      (s) =>
          s.id == data.selectedServer?.id &&
          s.isDub == data.selectedServer?.isDub,
    );

    _sheet(
      GenericSelectionSheet<String>(
        title: 'Server',
        items:
            data.servers
                .map(
                  (e) =>
                      '${e.name ?? (e.id ?? 'Server').toUpperCase()} [${e.isDub ? 'DUB' : 'SUB'}]',
                )
                .toList(),
        selectedIndex: selectedIdx != -1 ? selectedIdx : 0,
        displayBuilder: (e) => e,
        onItemSelected: (i) {
          ref.read(episodeDataProvider.notifier).changeServer(data.servers[i]);
          Navigator.pop(context);
        },
      ),
    );
  }

  void _onDoubleTap(TapDownDetails details) {
    if (ref.read(playerUIControllerProvider).isLocked) return;
    final player = ref.read(playerStateProvider);
    final isForward =
        details.globalPosition.dx >= MediaQuery.sizeOf(context).width / 2;

    if (_doubleTapPairCount == 0 ||
        (_isDragSeekForward != isForward && _doubleTapPairCount > 0)) {
      _doubleTapPairCount = 1;
      _doubleTapAnchor = player.position;
    } else {
      _doubleTapPairCount++;
    }

    final seconds = _doubleTapPairCount * 10;
    final signed = isForward ? seconds : -seconds;
    final maxMs =
        player.duration.inMilliseconds > 0
            ? player.duration.inMilliseconds
            : 24 * 60 * 60 * 1000;
    final targetMs = (_doubleTapAnchor.inMilliseconds + signed * 1000).clamp(
      0,
      maxMs,
    );
    _dragTargetPos = Duration(milliseconds: targetMs);
    _dragDiff = Duration(seconds: signed);

    _isDragSeekForward = isForward;
    setState(() => _isDraggingSeek = true);

    // Apply every double-tap immediately. The accumulated overlay remains
    // visible briefly, but playback no longer waits for the tap sequence to
    // finish before moving by 10, 20, 30… seconds.
    unawaited(ref.read(playerStateProvider.notifier).seek(_dragTargetPos));
    _doubleTapTimer?.cancel();
    _doubleTapTimer = Timer(const Duration(milliseconds: 650), () {
      if (!mounted) return;
      setState(() {
        _isDraggingSeek = false;
        _doubleTapPairCount = 0;
      });
    });
  }

  void _openAudio() {
    final current = ref.read(playerSettingsProvider).preferredAudioLanguage;
    _sheet(
      SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Audio', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              for (final option in const [
                ('sub', 'Japanese', 'SUB'),
                ('dub', 'English', 'DUB'),
              ])
                ListTile(
                  leading: Icon(
                    current == option.$1
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                  ),
                  title: Text(option.$2),
                  subtitle: Text(option.$3),
                  onTap: () {
                    Navigator.pop(context);
                    if (current != option.$1) {
                      ref
                          .read(episodeDataProvider.notifier)
                          .switchAudioLanguage(option.$1);
                    }
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _cycleVideoFit() {
    final mode = ref.read(playerStateProvider.notifier).cycleFitMode();
    _fitLabelTimer?.cancel();
    setState(() => _fitLabel = mode.label);
    _fitLabelTimer = Timer(const Duration(milliseconds: 1100), () {
      if (mounted) setState(() => _fitLabel = null);
    });
  }

  void _openSubtitle() {
    _sheet(SubtitleSelectionSheet(onLocalFilePressed: _pickLocalSubtitle));
  }

  Future<void> _pickLocalSubtitle() async {
    final notifier = ref.read(episodeDataProvider.notifier);
    try {
      FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['srt', 'vtt', 'ass', 'ssa'],
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        await notifier.addLocalSubtitle(file);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Loaded: ${result.files.single.name}')),
        );
      }
    } catch (e) {
      AppLogger.e('Error picking file: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(playerStateProvider.notifier);
    final state = ref.watch(playerStateProvider);
    final uiState = ref.watch(playerUIControllerProvider);
    final uiController = ref.watch(playerUIControllerProvider.notifier);
    final isPiP = ref.watch(pipProvider);

    ref.listen(playerStateProvider.select((p) => p.isPlaying), (prev, next) {
      if (ref.read(pipProvider)) {
        ref.read(pipProvider.notifier).updatePlaybackState(next);
      }
    });

    final episodeStreamState = ref.watch(
      episodeDataProvider.select((e) => e.states),
    );
    final episodesLoading = ref.watch(
      episodeListProvider.select((e) => e.isLoading),
    );
    // Background server/quality discovery must never cover a video that is
    // already playing. Only a real underrun, seek, or initial open owns the
    // central loading indicator.
    final isBusy =
        // MPV may keep `buffering` true while it is filling the configured
        // forward cache even though frames and audio are already advancing.
        // Covering healthy playback with a spinner made a working stream look
        // permanently stuck. Initial startup and genuine paused underruns are
        // still represented by the conditions below.
        (state.isBuffering &&
            (!state.isPlaying || state.position == Duration.zero)) ||
        state.isSeeking ||
        (!state.isPlaying &&
            (state.isOpening ||
                episodesLoading ||
                episodeStreamState.contains(
                  EpisodeStreamState.SOURCE_LOADING,
                ) ||
                episodeStreamState.contains(
                  EpisodeStreamState.SERVER_LOADING,
                ) ||
                episodeStreamState.contains(
                  EpisodeStreamState.QUALITY_LOADING,
                )));

    Widget videoView = Video(
      controller: notifier.videoController,
      fit: state.fit,
      wakelock: true,
      filterQuality: kDebugMode ? FilterQuality.none : FilterQuality.low,
      controls: NoVideoControls,
      subtitleViewConfiguration: const SubtitleViewConfiguration(
        visible: false,
      ),
    );

    if (state.fitMode == VideoFitMode.ratio16x9 ||
        state.fitMode == VideoFitMode.ratio4x3) {
      videoView = Center(
        child: AspectRatio(
          aspectRatio: state.fitMode == VideoFitMode.ratio16x9 ? 16 / 9 : 4 / 3,
          child: videoView,
        ),
      );
    }

    if (widget.screenshotController != null) {
      videoView = Screenshot(
        controller: widget.screenshotController!,
        child: videoView,
      );
    }

    return MouseRegion(
      cursor:
          !uiState.isVisible
              ? SystemMouseCursors.none
              : SystemMouseCursors.click,
      onHover: (_) => uiController.toggleVisibility(override: true),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.space): notifier.togglePlay,
          const SingleActivator(LogicalKeyboardKey.keyK): notifier.togglePlay,
          const SingleActivator(LogicalKeyboardKey.keyL):
              uiController.toggleLock,
          const SingleActivator(LogicalKeyboardKey.arrowLeft):
              () => notifier.rewind(10),
          const SingleActivator(LogicalKeyboardKey.arrowRight):
              () => notifier.forward(10),
          const SingleActivator(LogicalKeyboardKey.keyM): notifier.toggleMute,
          const SingleActivator(LogicalKeyboardKey.f11): _cycleVideoFit,
          const SingleActivator(LogicalKeyboardKey.keyF): _cycleVideoFit,
        },
        child: Focus(
          focusNode: _focusNode,
          autofocus: true,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Video Layer
              videoView,

              if (isPiP)
                const Positioned.fill(child: PiPControlsOverlay())
              else ...[
                // Gesture Layer (Background)
                Positioned.fill(
                  child: PlayerGestureHandler(
                    onDoubleTapDown: _onDoubleTap,
                    onTap: () {
                      if (_isDraggingSeek) return;
                      widget.onPanelCloseRequest?.call();
                      uiController.toggleVisibility();
                    },

                    onLongPressStart: _onLongPressStart,
                    onLongPressUpdate: _onLongPressUpdate,
                    onLongPressEnd: _onLongPressEnd,
                    onVerticalDragStart: _onVerticalDragStart,
                    onVerticalDragUpdate: _onVerticalDragUpdate,
                    onVerticalDragEnd: _onVerticalDragEnd,
                    onHorizontalDragStart: _onHorizontalDragStart,
                    onHorizontalDragUpdate: _onHorizontalDragUpdate,
                    onHorizontalDragEnd: _onHorizontalDragEnd,
                    onEpisodesPressed: widget.onEpisodesPressed,
                    child: Container(color: Colors.transparent),
                  ),
                ),

                // Controls & UI Layer (Foreground)
                ControlsOverlay(
                  visible: uiState.isVisible,
                  locked: uiState.isLocked,
                  onLockPressed: uiController.toggleLock,
                  onRestartHide: uiController.restartHideTimer,
                  onEpisodesPressed: widget.onEpisodesPressed,
                  onSettingsPressed: _openSettings,
                  onQualityPressed: _openQuality,
                  onSourcePressed: _openSource,
                  onServerPressed: _openServer,
                  onAudioPressed: _openAudio,
                  onSubtitlePressed: _openSubtitle,
                  onFullScreenPressed: _cycleVideoFit,
                  localTitle: widget.localTitle,
                  isLocal: widget.localFilePath != null,
                ),

                if (state.playbackError != null)
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: Colors.white,
                            size: 36,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            state.playbackError!,
                            style: const TextStyle(color: Colors.white),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: notifier.retry,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (isBusy)
                  Center(
                    child: IgnorePointer(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const FetchingProgressBadge(isEpisode: false),
                          if (state.isOpening) ...[
                            const SizedBox(height: 8),
                            const Text(
                              'Starting video…',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                // Horizontal swipe and rapid double-tap seek indicator
                if (_isDraggingSeek)
                  SeekFeedbackOverlay(
                    targetPosition: _dragTargetPos,
                    totalDuration: ref.read(playerStateProvider).duration,
                    diffDuration: _dragDiff,
                    isForward: _isDragSeekForward,
                  ),

                // Speed Indicator
                if (_isSpeeding)
                  SpeedIndicatorOverlay(currentSpeed: _lastSpeed),

                if (_fitLabel != null)
                  Center(
                    child: IgnorePointer(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.72),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _fitLabel!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),

                // Volume/Brightness Overlays
                if (_isChangingBrightness)
                  Positioned.fill(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: VolumeBrightnessOverlay(
                        isVolume: false,
                        value: uiState.brightness,
                      ),
                    ),
                  ),
                if (_isChangingVolume)
                  Positioned.fill(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: VolumeBrightnessOverlay(
                        isVolume: true,
                        value: uiState.volume,
                      ),
                    ),
                  ),

                // Subtitles
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: uiState.isVisible ? 90 : 20,
                  child: const SubtitleOverlay(),
                ),

                // Floating Skip Intro/Outro Button
                const FloatingSkipButtonOverlay(),

                // Floating Next Episode Recommendation Prompt (at 95% progress)
                const NextEpisodePromptOverlay(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
