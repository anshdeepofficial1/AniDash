import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ani_dash/features/watch/view_model/episode_list_provider.dart';
import 'package:ani_dash/features/watch/view_model/episode_stream_provider.dart';
import 'package:ani_dash/features/watch/view_model/player/player_provider.dart';
import 'package:ani_dash/shared/providers/settings/player_notifier.dart';

class CenterControls extends ConsumerWidget {
  final VoidCallback onInteraction;
  const CenterControls({super.key, required this.onInteraction});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (isPlaying, isBusyPlayer) = ref.watch(
      playerStateProvider.select(
        (p) => (p.isPlaying, p.isBuffering || p.isSeeking || p.isOpening),
      ),
    );
    final episodeStates = ref.watch(
      episodeDataProvider.select((episode) => episode.states),
    );
    final episodesLoading = ref.watch(
      episodeListProvider.select((episodes) => episodes.isLoading),
    );
    final isBusy = isBusyPlayer || episodesLoading || episodeStates.isNotEmpty;

    final playerNotifier = ref.read(playerStateProvider.notifier);
    final settings = ref.watch(playerSettingsProvider);
    final isMovie = ref.watch(episodeListProvider.select((s) => s.isMovie));

    return Center(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (settings.showNextPrevButtons && !isMovie) ...[
            _ShadowIconButton(
              icon: Icons.skip_previous_rounded,
              size: 56,
              onTap: () {
                onInteraction();
                ref
                    .read(episodeDataProvider.notifier)
                    .changeEpisode(null, by: -1);
              },
            ),
            const SizedBox(width: 48),
          ],

          // Core Center Action (Buffer or Play/Pause)
          SizedBox(
            width: 80,
            height: 80,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              switchInCurve: Curves.easeOutBack,
              switchOutCurve: Curves.easeInBack,
              transitionBuilder: (child, animation) {
                return ScaleTransition(
                  scale: animation,
                  child: FadeTransition(opacity: animation, child: child),
                );
              },
              child: isPlaying
                  ? _ShadowIconButton(
                      key: const ValueKey('pause'),
                      icon: Icons.pause_rounded,
                      size: 80,
                      onTap: () {
                        onInteraction();
                        playerNotifier.togglePlay();
                      },
                    )
                  : isBusy
                      ? const Center(
                          key: ValueKey('loading'),
                          child: SizedBox(
                            width: 50,
                            height: 50,
                            child: CircularProgressIndicator(
                              strokeWidth: 3.5,
                              color: Colors.white,
                            ),
                          ),
                        )
                      : _ShadowIconButton(
                          key: const ValueKey('play'),
                          icon: Icons.play_arrow_rounded,
                          size: 80,
                          onTap: () {
                            onInteraction();
                            playerNotifier.togglePlay();
                          },
                        ),
            ),
          ),

          if (settings.showNextPrevButtons && !isMovie) ...[
            const SizedBox(width: 48),
            _ShadowIconButton(
              icon: Icons.skip_next_rounded,
              size: 56,
              onTap: () {
                onInteraction();
                ref
                    .read(episodeDataProvider.notifier)
                    .changeEpisode(null, by: 1);
              },
            ),
          ],
        ],
      ),
    );
  }
}

// --- Borderless Premium Components ---

class _ShadowIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double size;

  const _ShadowIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Icon(
        icon,
        color: Colors.white,
        size: size,
        shadows: const [
          Shadow(color: Colors.black26, blurRadius: 12, offset: Offset(0, 4)),
          Shadow(color: Colors.black26, blurRadius: 24, offset: Offset(0, 2)),
        ],
      ),
    );
  }
}
