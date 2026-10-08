import 'dart:io';
import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ani_dash/shared/providers/anime_source_provider.dart';
import 'package:ani_dash/features/watch/view_model/episode_list_provider.dart';
import 'package:ani_dash/features/watch/view_model/episode_stream_provider.dart';
import 'package:ani_dash/helpers/ui.dart';
import 'package:ani_dash/shared/providers/incognito_provider.dart';
import 'package:ani_dash/features/watch/view_model/player/orientation_lock_provider.dart';
import 'package:ani_dash/router/desktop/windows_caption_buttons.dart';

class TopControls extends ConsumerWidget {
  final VoidCallback onInteraction;
  final VoidCallback? onEpisodesPressed;
  final VoidCallback? onQualityPressed;
  final VoidCallback? onSettingsPressed;
  final VoidCallback? onSubtitlePressed;
  final String? titleOverride;
  final String? sourceOverride;
  final bool isLocal;

  const TopControls({
    super.key,
    required this.onInteraction,
    this.onEpisodesPressed,
    this.onQualityPressed,
    this.onSettingsPressed,
    this.onSubtitlePressed,
    this.titleOverride,
    this.sourceOverride,
    this.isLocal = false,
  });

  VoidCallback? _wrap(VoidCallback? action) {
    if (action == null) return null;
    return () {
      action();
      onInteraction();
    };
  }

  String? _cleanEpisodeTitle(String? rawTitle) {
    final title =
        (rawTitle ?? '')
            .trim()
            .replaceFirst(
              RegExp(
                r'^(?:(?:episode|ep)|e)\s*#?\s*\d+(?:\.\d+)?\s*(?:[-:—|/]+\s*)?',
                caseSensitive: false,
              ),
              '',
            )
            .trim();
    return title.isEmpty ? null : title;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedEp = ref.watch(
      episodeDataProvider.select((e) => e.selectedEpisode),
    );
    final sources = ref.watch(episodeDataProvider.select((e) => e.sources));

    final rawEpisodeTitle = ref.watch(
      episodeListProvider.select((s) {
        if (selectedEp == null) return null;
        return s.episodes
            .firstWhereOrNull((i) => i.number == selectedEp)
            ?.title;
      }),
    );
    final episodeTitle = _cleanEpisodeTitle(rawEpisodeTitle);

    final animeId = ref.watch(episodeListProvider.select((s) => s.animeId));
    final isIncognito =
        animeId != null && ref.watch(incognitoProvider(animeId));

    final animeTitle = ref.watch(
      episodeListProvider.select((s) => s.animeTitle),
    );
    final epListState = ref.watch(episodeListProvider);
    final isMovie = epListState.isMovie ||
        (animeTitle?.toLowerCase().contains('the very final') == true) ||
        (animeTitle?.toLowerCase().contains('movie') == true) ||
        (animeTitle?.toLowerCase().contains('film') == true) ||
        (epListState.episodes.length <= 1 &&
            (rawEpisodeTitle?.toLowerCase().contains('movie') == true ||
                rawEpisodeTitle?.toLowerCase().contains('the very final') == true));

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black87, Colors.black54, Colors.transparent],
          stops: [0.0, 0.5, 1.0],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _wrap(() {
                    Navigator.of(context).maybePop();
                  }),
                  customBorder: const CircleBorder(),
                  child: const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Icon(
                      Icons.arrow_back_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          sourceOverride ?? _getSourceName(ref).toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.0,
                          ),
                        ),
                        if (isIncognito) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.purple.shade900.withValues(
                                alpha: 0.9,
                              ),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: Colors.purpleAccent,
                                width: 0.8,
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.visibility_off_rounded,
                                  size: 11,
                                  color: Colors.purpleAccent,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    'INCOGNITO',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (titleOverride != null ||
                          (selectedEp != null && sources.isNotEmpty))
                        Text(
                          titleOverride ??
                              (isMovie
                                  ? (animeTitle != null && animeTitle.isNotEmpty
                                      ? animeTitle
                                      : (episodeTitle?.isNotEmpty == true
                                          ? episodeTitle!
                                          : 'Movie'))
                                  : (episodeTitle?.trim().isNotEmpty == true
                                      ? 'E$selectedEp — $episodeTitle'
                                      : 'Episode $selectedEp')),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),

                const SizedBox(width: 12),

                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (Platform.isAndroid || Platform.isIOS)
                      Consumer(
                        builder: (context, ref, _) {
                          final lockMode = ref.watch(orientationLockProvider);
                          IconData lockIcon = Icons.screen_rotation_rounded;
                          Color iconColor = Colors.white;
                          String tooltipText =
                              'Auto-Rotate Landscape (Tap to lock)';

                          if (lockMode == OrientationLockMode.lockedLandscape) {
                            lockIcon = Icons.screen_lock_landscape_rounded;
                            iconColor = Theme.of(context).colorScheme.primary;
                            tooltipText = 'Landscape Locked (Tap to unlock)';
                          }

                          return _TopIconButton(
                            icon: lockIcon,
                            color: iconColor,
                            tooltip: tooltipText,
                            onTap: () async {
                              await ref
                                  .read(orientationLockProvider.notifier)
                                  .toggle();
                              onInteraction();
                            },
                            onLongPress: () {
                              _showRotationSheet(context, ref);
                              onInteraction();
                            },
                          );
                        },
                      ),

                    if (!isMovie)
                      _TopIconButton(
                        icon: Icons.view_list_rounded,
                        onTap: _wrap(onEpisodesPressed),
                      ),

                    if (!Platform.isAndroid && !Platform.isIOS) ...[
                      const SizedBox(width: 8),
                      const WindowsCaptionButtons(height: 36, isDark: true),
                    ],
                  ],
                ),
              ],
            ),
        ),
      ),
    );
  }

  void _showRotationSheet(BuildContext context, WidgetRef ref) {
    final currentMode = ref.read(orientationLockProvider);
    final scheme = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder:
          (ctx) => Container(
            decoration: const BoxDecoration(
              color: Color(0xFF1E1E1E),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.screen_rotation_rounded,
                          color: scheme.primary,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'Landscape Screen Rotation',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildRotationOption(
                    context: ctx,
                    ref: ref,
                    mode: OrientationLockMode.unlocked,
                    title: 'Auto-Rotate Landscape (Sensor)',
                    subtitle:
                        'Screen freely flips between both landscape sides following sensor',
                    icon: Icons.screen_rotation_rounded,
                    isSelected: currentMode == OrientationLockMode.unlocked,
                  ),
                  _buildRotationOption(
                    context: ctx,
                    ref: ref,
                    mode: OrientationLockMode.lockedLandscape,
                    title: 'Lock Landscape',
                    subtitle:
                        'Screen remains strictly locked in current landscape direction',
                    icon: Icons.stay_current_landscape_rounded,
                    isSelected:
                        currentMode == OrientationLockMode.lockedLandscape,
                  ),
                ],
              ),
            ),
          ),
    );
  }

  Widget _buildRotationOption({
    required BuildContext context,
    required WidgetRef ref,
    required OrientationLockMode mode,
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: isSelected ? scheme.primary : Colors.white70),
      title: Text(
        title,
        style: TextStyle(
          color: isSelected ? scheme.primary : Colors.white,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: Colors.white54, fontSize: 12),
      ),
      trailing:
          isSelected
              ? Icon(
                Icons.check_circle_rounded,
                color: scheme.primary,
                size: 22,
              )
              : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onTap: () async {
        Navigator.pop(context);
        await ref.read(orientationLockProvider.notifier).setMode(mode);
        onInteraction();
      },
    );
  }

  String _getSourceName(WidgetRef ref) {
    return ref.watch(selectedAnimeProvider)?.providerName ?? 'AniDash';
  }
}

class _TopIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? tooltip;
  final Color color;

  const _TopIconButton({
    required this.icon,
    this.onTap,
    this.onLongPress,
    this.tooltip,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    Widget button = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Icon(icon, color: color, size: 24),
        ),
      ),
    );

    if (tooltip != null) {
      button = Tooltip(message: tooltip!, preferBelow: false, child: button);
    }

    return button;
  }
}
