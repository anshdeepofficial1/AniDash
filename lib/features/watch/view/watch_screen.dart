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
import 'package:ani_dash/features/watch/view_model/player/player_ui_controller.dart';
import 'package:ani_dash/features/watch/view/widgets/player/sheets/settings_sheet.dart';
import 'package:ani_dash/features/watch/view_model/player/pip_controller.dart';
import 'package:ani_dash/core/repositories/watch_progress_repository.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:window_manager/window_manager.dart';
import 'package:ani_dash/router/desktop/windows_caption_buttons.dart';
import 'package:ani_dash/features/details/view_model/details_page_notifier.dart';

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

      final resolvedFormat = (widget.animeFormat?.trim().isNotEmpty == true)
          ? widget.animeFormat
          : ref.read(detailsPageProvider(widget.mediaId)).details.value?.format ??
              ref.read(watchProgressRepositoryProvider).getProgress(widget.mediaId)?.animeFormat;

      ref
          .read(watchControllerProvider.notifier)
          .initialize(
            animeName: widget.animeName,
            animeId: widget.animeId,
            episodes: widget.episodes ?? [],
            initialEpisode: widget.episode,
            mediaId: widget.mediaId,
            animeFormat: resolvedFormat,
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

  void _openSettingsSheet() {
    final theme = Theme.of(context);
    final sheetHeight = MediaQuery.of(context).size.height * 0.48;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SizedBox(
        height: sheetHeight,
        child: Container(
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.dividerColor.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: SettingsSheetContent(
                  onDismiss: () => Navigator.of(ctx).pop(),
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
      try {
        await windowManager.setFullScreen(target);
      } catch (e) {
        debugPrint('Could not toggle desktop fullscreen: $e');
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

    if (_isLandscapeFullscreen || UIHelper.isFullscreen) {
      // 1. First Back while in Fullscreen:
      // Return to windowed / portrait mode without stopping video playback!
      await _toggleFullscreen();
      return;
    }

    // 2. Second Back (or Back while in windowed mode):
    // Cleanly stop playback and pop back to previous screen.
    _isExiting = true;
    await ref.read(watchControllerProvider.notifier).cleanup();
    await ref.read(playerStateProvider.notifier).stop();
    if (!mounted) return;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      context.go('/');
    }
    _resetSystemUI();
  }

  Future<void> _resetSystemUI() async {
    final isDesktop = !Platform.isAndroid && !Platform.isIOS;
    if (isDesktop) {
      try {
        await windowManager.setFullScreen(false);
      } catch (_) {}
    }
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

  bool _isEditingText() {
    final primaryFocus = FocusManager.instance.primaryFocus;
    return primaryFocus != null &&
        primaryFocus.hasFocus &&
        primaryFocus.context?.widget is EditableText;
  }

  void _adjustVolume(bool isUp) {
    if (_isEditingText()) return;
    final uiState = ref.read(playerUIControllerProvider);
    final newV = (uiState.volume + (isUp ? 0.05 : -0.05)).clamp(0.0, 1.0);
    ref.read(playerUIControllerProvider.notifier).setVolume(newV);
    if (Platform.isAndroid || Platform.isIOS) {
      FlutterVolumeController.setVolume(newV);
      ref
          .read(playerStateProvider.notifier)
          .videoController
          .player
          .setVolume(100.0);
    } else {
      ref
          .read(playerStateProvider.notifier)
          .videoController
          .player
          .setVolume(newV * 100.0);
    }
  }

  @override
  void dispose() {
    if (!_isExiting) {
      unawaited(
        ref
            .read(watchControllerProvider.notifier)
            .cleanup()
            .whenComplete(
              () => ref.read(playerStateProvider.notifier).stop(),
            ),
      );
    }
    final isDesktop = !Platform.isAndroid && !Platform.isIOS;
    if (isDesktop && (_isLandscapeFullscreen || UIHelper.isFullscreen)) {
      try {
        windowManager.setFullScreen(false);
      } catch (_) {}
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

    final savedFormat = ref.watch(watchProgressRepositoryProvider).getProgress(widget.mediaId)?.animeFormat;
    final detailsFormat = ref.watch(detailsPageProvider(widget.mediaId)).details.value?.format;
    final resolvedFormat = (widget.animeFormat?.trim().isNotEmpty == true)
        ? widget.animeFormat
        : (savedFormat?.trim().isNotEmpty == true
            ? savedFormat
            : detailsFormat);

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
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (_panelController.isCompleted || _panelController.value > 0) {
              _panelController.reverse();
              return;
            }
            if (_isLandscapeFullscreen || UIHelper.isFullscreen) {
              _toggleFullscreen();
            } else {
              _handleBack();
            }
          },
          const SingleActivator(LogicalKeyboardKey.space): () {
            if (!_isEditingText()) {
              ref.read(playerStateProvider.notifier).togglePlay();
            }
          },
          const SingleActivator(LogicalKeyboardKey.keyK): () {
            if (!_isEditingText()) {
              ref.read(playerStateProvider.notifier).togglePlay();
            }
          },
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () {
            if (!_isEditingText()) {
              ref.read(playerStateProvider.notifier).rewind(10);
            }
          },
          const SingleActivator(LogicalKeyboardKey.arrowRight): () {
            if (!_isEditingText()) {
              ref.read(playerStateProvider.notifier).forward(10);
            }
          },
          const SingleActivator(LogicalKeyboardKey.keyJ): () {
            if (!_isEditingText()) {
              ref.read(playerStateProvider.notifier).rewind(10);
            }
          },
          const SingleActivator(LogicalKeyboardKey.keyL): () {
            if (!_isEditingText()) {
              ref.read(playerStateProvider.notifier).forward(10);
            }
          },
          const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
              _adjustVolume(true),
          const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
              _adjustVolume(false),
          const SingleActivator(LogicalKeyboardKey.keyM): () {
            if (!_isEditingText()) {
              ref.read(playerStateProvider.notifier).toggleMute();
            }
          },
          const SingleActivator(LogicalKeyboardKey.keyF): () {
            if (!_isEditingText()) {
              _toggleFullscreen();
            }
          },
          const SingleActivator(LogicalKeyboardKey.f11): () {
            _toggleFullscreen();
          },
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: _isLandscapeFullscreen
                ? Colors.black
                : Theme.of(context).scaffoldBackgroundColor,
            body: OrientationBuilder(
              builder: (_, orientation) {
                final isPiP = ref.watch(pipProvider);
                if (isPiP && _panelController.value > 0) {
                  _panelController.reset();
                }

                final isLandscape = orientation == Orientation.landscape ||
                    _isLandscapeFullscreen;

                final player = AniDashVideoPlayer(
                  onEpisodesPressed:
                      isLandscape ? _togglePanel : _openEpisodesSheet,
                  onPanelCloseRequest: () => _panelController.reverse(),
                  screenshotController: _screenshotController,
                  onFullScreenPressed: _toggleFullscreen,
                );

                final isDesktop = !Platform.isAndroid && !Platform.isIOS;
                final screenWidth = MediaQuery.of(context).size.width;

                // Desktop Crunchyroll/YouTube Theater View (when not in full-screen)
                if (isDesktop && !_isLandscapeFullscreen && !isPiP) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _WatchDesktopTopBar(
                        animeName: widget.animeName,
                        episodeNumber: selectedEp,
                        animeFormat: resolvedFormat,
                        onBack: _handleBack,
                        onToggleFullscreen: _toggleFullscreen,
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Top Area: Video Player + Right-Side Episodes Carousel/Panel
                              Container(
                                color: Colors.black,
                                height: (screenWidth * 0.50).clamp(360.0, 560.0),
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 7,
                                      child: player,
                                    ),
                                    Container(
                                      width: (screenWidth * 0.30)
                                          .clamp(280.0, 380.0),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF141416),
                                        border: Border(
                                          left: BorderSide(
                                            color: Colors.white
                                                .withValues(alpha: 0.08),
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
                                color: Theme.of(context).scaffoldBackgroundColor,
                                alignment: Alignment.topCenter,
                                child: ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 1200),
                                  child: PortraitPlayerDetails(
                                    animeTitle: widget.animeName,
                                    animeFormat: resolvedFormat,
                                    animeCover: widget.animeCover,
                                    episodeNumber: selectedEp,
                                    episodeTitle: currentEpTitle,
                                    episodeThumbnail: currentEpThumb,
                                    episodeDescription: currentEpDesc,
                                    episodes: effectiveEpisodes,
                                    mediaId: widget.mediaId,
                                    shrinkWrap: true,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    onAllEpisodesPressed: _openEpisodesSheet,
                                    onMoreOptionsPressed: _openSettingsSheet,
                                    onToggleFullscreen: _toggleFullscreen,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
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

            if (isPiP) {
              return SizedBox.expand(child: player);
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
                    animeFormat: resolvedFormat,
                    animeCover: widget.animeCover,
                    episodeNumber: selectedEp,
                    episodeTitle: currentEpTitle,
                    episodeThumbnail: currentEpThumb,
                    episodeDescription: currentEpDesc,
                    episodes: effectiveEpisodes,
                    mediaId: widget.mediaId,
                    onAllEpisodesPressed: _openEpisodesSheet,
                    onMoreOptionsPressed: _openSettingsSheet,
                    onToggleFullscreen: _toggleFullscreen,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ),
  ),
);
  }
}

class _WatchDesktopTopBar extends StatelessWidget {
  final String animeName;
  final int episodeNumber;
  final String? animeFormat;
  final VoidCallback onBack;
  final VoidCallback? onToggleFullscreen;

  const _WatchDesktopTopBar({
    required this.animeName,
    required this.episodeNumber,
    this.animeFormat,
    required this.onBack,
    this.onToggleFullscreen,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onPanStart: (_) {
        if (!Platform.isAndroid && !Platform.isIOS) {
          windowManager.startDragging();
        }
      },
      onDoubleTap: () async {
        if (!Platform.isAndroid && !Platform.isIOS) {
          final isMax = await windowManager.isMaximized();
          if (isMax) {
            await windowManager.unmaximize();
          } else {
            await windowManager.maximize();
          }
        }
      },
      child: Container(
        height: 42,
        padding: const EdgeInsets.only(
          left: 12,
          right: 0,
        ),
        decoration: const BoxDecoration(
          color: Color(0xFF101216),
          border: Border(
            bottom: BorderSide(
              color: Colors.white10,
              width: 1,
            ),
          ),
        ),
        child: Row(
          children: [
            // Back Button
            IconButton(
              tooltip: 'Go Back (Esc)',
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              color: Colors.white70,
              onPressed: onBack,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
            const SizedBox(width: 8),
            Container(
              height: 16,
              width: 1,
              color: Colors.white24,
            ),
            const SizedBox(width: 10),
            // Title & Episode Badge
            Flexible(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      animeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: theme.colorScheme.primary.withValues(alpha: 0.4),
                        width: 0.5,
                      ),
                    ),
                    child: Text(
                      'EP $episodeNumber',
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (animeFormat != null && animeFormat!.trim().isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white12,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        animeFormat!.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 9,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Spacer(),
            if (onToggleFullscreen != null)
              IconButton(
                tooltip: 'Fullscreen (F / F11)',
                icon: const Icon(Icons.fullscreen_rounded, size: 20),
                color: Colors.white70,
                onPressed: onToggleFullscreen,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
            // Window Caption Controls
            if (!Platform.isAndroid && !Platform.isIOS)
              const WindowsCaptionButtons(height: 42, isDark: true),
          ],
        ),
      ),
    );
  }
}
