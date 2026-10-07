import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:screenshot/screenshot.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:ani_dash/core/models/anime/episode_model.dart';
import 'package:ani_dash/core/models/anime/server_model.dart';
import 'package:ani_dash/features/watch/view/widgets/episodes_panel.dart';
import 'package:ani_dash/features/watch/view/widgets/player/shonenx_video_player.dart';
import 'package:ani_dash/features/watch/view/widgets/portrait_player_details.dart';
import 'package:ani_dash/features/watch/view_model/episode_list_provider.dart';
import 'package:ani_dash/features/watch/view_model/episode_stream_provider.dart';
import 'package:ani_dash/features/watch/view_model/watch_controller.dart';
import 'package:ani_dash/helpers/ui.dart';
import 'package:ani_dash/shared/providers/settings/sync_settings_notifier.dart';
import 'package:ani_dash/features/watch/view_model/watch_sync_notifier.dart';
import 'package:ani_dash/features/watch/view_model/player/player_provider.dart';
import 'package:ani_dash/features/watch/view_model/player/pip_controller.dart';

class WatchScreen extends ConsumerStatefulWidget {
  final String mediaId;
  final String? animeId;
  final String animeName;
  final String? animeFormat;
  final String animeCover;
  final int episode;
  final int? malId;
  final int? startAtPosition;
  final List<EpisodeDataModel>? episodes;

  const WatchScreen({
    super.key,
    required this.mediaId,
    required this.animeName,
    this.animeFormat,
    required this.animeCover,
    this.animeId,
    this.episode = 1,
    this.malId,
    this.startAtPosition,
    this.episodes = const [],
    this.fromHentaiHub = false,
    this.forceRefetch = false,
  });

  final bool fromHentaiHub;
  final bool forceRefetch;

  @override
  ConsumerState<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends ConsumerState<WatchScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _panelController;
  late final CurvedAnimation _panelAnimation;
  final ScreenshotController _screenshotController = ScreenshotController();
  bool _isLandscapeFullscreen = false;

  @override
  void initState() {
    super.initState();
    _setupSystemUI();

    _panelController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _panelAnimation = CurvedAnimation(
      parent: _panelController,
      curve: Curves.easeOutCubic,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      ref
          .read(watchControllerProvider.notifier)
          .initialize(
            animeName: widget.animeName,
            animeId: widget.animeId,
            episodes: widget.episodes ?? [],
            initialEpisode: widget.episode,
            mediaId: widget.mediaId,
            animeFormat: widget.animeFormat,
            animeCover: widget.animeCover,
            fromHentaiHub: widget.fromHentaiHub,
            malId: widget.malId,
            startAtPosition: widget.startAtPosition,
            forceRefetch: widget.forceRefetch,
          );
      ref
          .read(watchControllerProvider.notifier)
          .setScreenshotController(_screenshotController);
    });
  }

  void _togglePanel() {
    _panelController.isCompleted
        ? _panelController.reverse()
        : _panelController.forward();
  }

  void _openEpisodesSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFF141416),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: EpisodesPanel(
                  panelAnimation: _panelController,
                  mediaId: widget.mediaId,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _setupSystemUI() async {
    UIHelper.setWatchInitialLockMode();
    UIHelper.enableVolumeInterception();
    await UIHelper.forcePortrait();
  }

  Future<void> _toggleFullscreen() async {
    final isDesktop = !Platform.isAndroid && !Platform.isIOS;
    final target = !_isLandscapeFullscreen;
    setState(() {
      _isLandscapeFullscreen = target;
    });

    if (isDesktop) {
      if (UIHelper.isFullscreen != target) {
        await UIHelper.handleToggleFullscreen();
      }
    } else {
      if (target) {
        await Future.wait([
          UIHelper.enableImmersiveMode(),
          UIHelper.forceLandscape(),
        ]);
      } else {
        await Future.wait([
          UIHelper.exitImmersiveMode(),
          UIHelper.forcePortrait(),
        ]);
      }
    }
  }

  bool _isExiting = false;

  Future<void> _handleBack() async {
    if (_isExiting) return;

    if (_panelController.isCompleted || _panelController.value > 0) {
      _panelController.reverse();
      return;
    }

    if (_isLandscapeFullscreen) {
      // 1. First Back while in Landscape Fullscreen:
      // Return to portrait mode without stopping video playback!
      await _toggleFullscreen();
      return;
    }

    // 2. Second Back (or Back while in Portrait):
      // Cleanly stop playback and pop back to previous screen.
    _isExiting = true;
    await ref.read(watchControllerProvider.notifier).cleanup();
    await ref.read(playerStateProvider.notifier).stop();
    if (!mounted) return;
    Navigator.of(context).pop();
    _resetSystemUI();
  }

  Future<void> _resetSystemUI() async {
    try {
      await ScreenBrightness().resetApplicationScreenBrightness();
    } catch (error) {
      debugPrint('Could not reset screen brightness: $error');
    }
    try {
      await FlutterVolumeController.updateShowSystemUI(true);
      await UIHelper.disableVolumeInterception();
    } catch (error) {
      debugPrint('Could not restore volume controls: $error');
    }
    await UIHelper.resetOrientation();
    await UIHelper.exitImmersiveMode();
  }

  @override
  void dispose() {
    if (!_isExiting) {
      unawaited(
        ref
            .read(watchControllerProvider.notifier)
            .cleanup()
            .whenComplete(
              () => ref
                  .read(playerStateProvider.notifier)
                  .stopIfSession(widget.mediaId),
            ),
      );
    }
    _resetSystemUI();
    _panelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Keep controller alive to ensure listeners work
    ref.watch(watchControllerProvider);

    final selectedEp = ref.watch(
      episodeDataProvider.select((s) => s.selectedEpisode),
    ) ?? widget.episode;

    final allEpisodes = ref.watch(
      episodeListProvider.select((s) => s.episodes),
    );
    final effectiveEpisodes = allEpisodes.isNotEmpty
        ? allEpisodes
        : (widget.episodes ?? <EpisodeDataModel>[]);

    final currentEpModel = effectiveEpisodes.firstWhereOrNull(
      (e) => e.number == selectedEp,
    );
    final currentEpTitle = currentEpModel?.title;
    final currentEpThumb = currentEpModel?.thumbnail;
    final currentEpDesc = currentEpModel?.description;

    // Listen for episode changes — if askBeforeSync is on, show confirmation dialog
    ref.listen(episodeDataProvider.select((s) => s.selectedEpisode), (
      prev,
      next,
    ) async {
      if (next == null || next == prev) return;

      final syncSettings = ref.read(syncSettingsProvider);
      if (!syncSettings.askBeforeSync) return;

      // Delay to ensure user is actually watching (matches controller delay)
      await Future.delayed(const Duration(seconds: 5));
      if (!context.mounted) return;

      // Re-check index in case it changed quickly
      final currentEp = ref.read(episodeDataProvider).selectedEpisode;
      if (currentEp != next) return;

      final episodeNum = next;

      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder:
          (context) => AlertDialog(
            title: const Text('Update Progress?'),
            content: Text(
              'Do you want to update your list progress to Episode $episodeNum?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('No'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Yes'),
              ),
            ],
          ),
      );

      if (confirmed == true && context.mounted) {
        ref
            .read(watchSyncProvider.notifier)
            .updateTracking(mediaId: widget.mediaId, episodeNum: episodeNum);
      }
    });

    ref.listen(episodeDataProvider.select((s) => s.languageNotice), (
      previous,
      next,
    ) {
      if (next == null || next == previous || !context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(next),
          action: SnackBarAction(
            label: 'WATCH SUB',
            onPressed:
                () => ref
                    .read(episodeDataProvider.notifier)
                    .changeServer(
                      ServerData(
                        id: 'megaplay',
                        name: 'Momo (HLS)',
                        isDub: false,
                      ),
                    ),
          ),
        ),
      );
    });

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        unawaited(_handleBack());
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: OrientationBuilder(
          builder: (_, orientation) {
            final isPiP = ref.watch(pipProvider);
            if (isPiP && _panelController.value > 0) {
              _panelController.reset();
            }

            final isLandscape = orientation == Orientation.landscape || _isLandscapeFullscreen;

            final player = AniDashVideoPlayer(
              onEpisodesPressed: isLandscape ? _togglePanel : _openEpisodesSheet,
              onPanelCloseRequest: () => _panelController.reverse(),
              screenshotController: _screenshotController,
              onFullScreenPressed: _toggleFullscreen,
            );

            final isDesktop = !Platform.isAndroid && !Platform.isIOS;
            final screenWidth = MediaQuery.of(context).size.width;

            // Desktop Crunchyroll/YouTube Theater View (when not in full-screen)
            if (isDesktop && !_isLandscapeFullscreen && !isPiP && screenWidth > 900) {
              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Top Area: Video Player + Right-Side Episodes Carousel/Panel
                    Container(
                      color: Colors.black,
                      height: (screenWidth * 0.52).clamp(380.0, 560.0),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 7,
                            child: player,
                          ),
                          Container(
                            width: 380,
                            decoration: BoxDecoration(
                              color: const Color(0xFF141416),
                              border: Border(
                                left: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.08),
                                  width: 1,
                                ),
                              ),
                            ),
                            child: EpisodesPanel(
                              panelAnimation: _panelController,
                              mediaId: widget.mediaId,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Bottom Area: Anime Info, Synopsis, Advisory, Comments & World Chat
                    Container(
                      color: Colors.black,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1200),
                        child: PortraitPlayerDetails(
                          animeTitle: widget.animeName,
                          animeFormat: widget.animeFormat,
                          animeCover: widget.animeCover,
                          episodeNumber: selectedEp,
                          episodeTitle: currentEpTitle,
                          episodeThumbnail: currentEpThumb,
                          episodeDescription: currentEpDesc,
                          episodes: effectiveEpisodes,
                          mediaId: widget.mediaId,
                          onAllEpisodesPressed: _openEpisodesSheet,
                          onMoreOptionsPressed: _openEpisodesSheet,
                          onToggleFullscreen: _toggleFullscreen,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }

            if (isLandscape && !isPiP) {
              return Row(
                children: [
                  Expanded(child: player),
                  SizeTransition(
                    sizeFactor: _panelAnimation,
                    axis: Axis.horizontal,
                    child: SizedBox(
                      width: MediaQuery.of(context).size.width * 0.35,
                      child: EpisodesPanel(
                        panelAnimation: _panelController,
                        mediaId: widget.mediaId,
                      ),
                    ),
                  ),
                ],
              );
            }

            // Mobile / Portrait Mode:
            // 16:9 Player pinned on top, rich interactive details below
            return Column(
              children: [
                SafeArea(
                  bottom: false,
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: player,
                  ),
                ),
                Expanded(
                  child: PortraitPlayerDetails(
                    animeTitle: widget.animeName,
                    animeFormat: widget.animeFormat,
                    animeCover: widget.animeCover,
                    episodeNumber: selectedEp,
                    episodeTitle: currentEpTitle,
                    episodeThumbnail: currentEpThumb,
                    episodeDescription: currentEpDesc,
                    episodes: effectiveEpisodes,
                    mediaId: widget.mediaId,
                    onAllEpisodesPressed: _openEpisodesSheet,
                    onMoreOptionsPressed: _openEpisodesSheet,
                    onToggleFullscreen: _toggleFullscreen,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
