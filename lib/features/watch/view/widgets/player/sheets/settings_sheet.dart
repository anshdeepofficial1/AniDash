// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:ani_dash/features/watch/view_model/player/player_provider.dart';

import 'package:ani_dash/features/watch/view_model/episode_stream_provider.dart';
import 'package:ani_dash/features/watch/view/widgets/player/dialogs/jump_to_time_dialog.dart';
import 'package:ani_dash/shared/providers/settings/player_notifier.dart';
import 'package:ani_dash/features/watch/view_model/player/pip_controller.dart';
import 'package:ani_dash/features/watch/view_model/episode_list_provider.dart';
import 'package:ani_dash/core/services/share_link_service.dart';
import 'package:ani_dash/shared/ui/sponsor/sponsor_dialog.dart';

class SettingsSheetContent extends ConsumerWidget {
  final VoidCallback onDismiss;
  final VoidCallback? onSubtitlesPressed;
  const SettingsSheetContent({
    super.key,
    required this.onDismiss,
    this.onSubtitlesPressed,
  });

  void _showDialog(
    BuildContext context, {
    required Widget Function(BuildContext) builder,
  }) {
    showDialog(context: context, builder: builder).then((_) {
      if (!context.mounted) return;
      if (Navigator.of(context).canPop()) onDismiss();
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final streamData = ref.watch(episodeDataProvider);
    final streamNotifier = ref.read(episodeDataProvider.notifier);
    final playerSettings = ref.watch(playerSettingsProvider);
    final playerNotifier = ref.read(playerSettingsProvider.notifier);
    final episodeList = ref.watch(episodeListProvider);

    final currentQuality =
        streamData.selectedQualityIdx != null &&
                streamData.qualityOptions.isNotEmpty &&
                streamData.selectedQualityIdx! <
                    streamData.qualityOptions.length
            ? streamData
                .qualityOptions[streamData.selectedQualityIdx!]['quality']
                ?.toString()
            : 'Auto';

    final isDub = streamData.selectedServer?.isDub == true;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 12, 8, 10),
        child: ListTileTheme(
          dense: true,
          minVerticalPadding: 2,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("More", style: Theme.of(context).textTheme.headlineSmall),
                if (onSubtitlesPressed != null)
                  ListTile(
                    leading: const Icon(Icons.subtitles_rounded),
                    title: const Text('Subtitles'),
                    onTap: () {
                      Navigator.pop(context);
                      Future<void>.delayed(Duration.zero, onSubtitlesPressed);
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.high_quality_rounded),
                  title: const Text("Quality"),
                  trailing: Text(currentQuality ?? 'Auto'),
                  onTap: () {
                    if (streamData.qualityOptions.isNotEmpty) {
                      _showDialog(
                        context,
                        builder:
                            (ctx) => AlertDialog(
                              title: const Text("Select Quality"),
                              content: SingleChildScrollView(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: List.generate(
                                    streamData.qualityOptions.length,
                                    (index) {
                                      final opt =
                                          streamData.qualityOptions[index];
                                      final isSelected =
                                          streamData.selectedQualityIdx ==
                                          index;
                                      return ListTile(
                                        title: Text(
                                          opt['quality']?.toString() ??
                                              'Option $index',
                                        ),
                                        trailing:
                                            isSelected
                                                ? const Icon(
                                                  Icons.check,
                                                  color: Colors.green,
                                                )
                                                : null,
                                        onTap: () {
                                          Navigator.pop(ctx);
                                          streamNotifier.changeQuality(index);
                                        },
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                      );
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.record_voice_over_rounded),
                  title: const Text("Audio"),
                  trailing: Text(isDub ? 'DUB' : 'SUB'),
                  onTap: () {
                    _showDialog(
                      context,
                      builder:
                          (ctx) => AlertDialog(
                            title: const Text("Select Audio Track"),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ListTile(
                                  title: const Text("Japanese (SUB)"),
                                  trailing:
                                      playerSettings.preferredAudioLanguage ==
                                              'sub'
                                          ? const Icon(
                                            Icons.check,
                                            color: Colors.green,
                                          )
                                          : null,
                                  onTap: () {
                                    Navigator.pop(ctx);
                                    streamNotifier.switchAudioLanguage('sub');
                                  },
                                ),
                                ListTile(
                                  title: const Text("English (DUB)"),
                                  trailing:
                                      playerSettings.preferredAudioLanguage ==
                                              'dub'
                                          ? const Icon(
                                            Icons.check,
                                            color: Colors.green,
                                          )
                                          : null,
                                  onTap: () {
                                    Navigator.pop(ctx);
                                    streamNotifier.switchAudioLanguage('dub');
                                  },
                                ),
                              ],
                            ),
                          ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.dns_rounded),
                  title: const Text("Server"),
                  trailing: Text(
                    streamData.selectedServer?.name ??
                        streamData.selectedServer?.id?.toUpperCase() ??
                        'Auto',
                  ),
                  onTap:
                      streamData.servers.isEmpty
                          ? null
                          : () => _showDialog(
                            context,
                            builder:
                                (ctx) => AlertDialog(
                                  title: const Text("Select Server"),
                                  content: SingleChildScrollView(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children:
                                          streamData.servers
                                              .map(
                                                (server) => ListTile(
                                                  title: Text(
                                                    server.name ??
                                                        (server.id ?? 'Server')
                                                            .toUpperCase(),
                                                  ),
                                                  subtitle: Text(
                                                    server.isDub
                                                        ? 'DUB'
                                                        : 'SUB',
                                                  ),
                                                  onTap: () {
                                                    Navigator.pop(ctx);
                                                    streamNotifier.changeServer(
                                                      server,
                                                    );
                                                  },
                                                ),
                                              )
                                              .toList(),
                                    ),
                                  ),
                                ),
                          ),
                ),
                ListTile(
                  leading: const Icon(Icons.source_rounded),
                  title: const Text("Source"),
                  trailing: Text(
                    streamData.selectedSourceIdx != null &&
                            streamData.selectedSourceIdx! <
                                streamData.sources.length
                        ? (streamData
                                .sources[streamData.selectedSourceIdx!]
                                .quality ??
                            'Auto')
                        : 'Auto',
                  ),
                  onTap:
                      streamData.sources.isEmpty
                          ? null
                          : () => _showDialog(
                            context,
                            builder:
                                (ctx) => AlertDialog(
                                  title: const Text("Select Source"),
                                  content: SingleChildScrollView(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: List.generate(
                                        streamData.sources.length,
                                        (index) => ListTile(
                                          title: Text(
                                            streamData.sources[index].quality ??
                                                'Source ${index + 1}',
                                          ),
                                          trailing:
                                              streamData.selectedSourceIdx ==
                                                      index
                                                  ? const Icon(
                                                    Icons.check,
                                                    color: Colors.green,
                                                  )
                                                  : null,
                                          onTap: () {
                                            Navigator.pop(ctx);
                                            streamNotifier.changeSource(index);
                                          },
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                          ),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.fast_forward_rounded),
                  title: const Text("Auto skip"),
                  value: playerSettings.enableAutoSkip,
                  onChanged: (val) {
                    playerNotifier.updateSettings(
                      (prev) => prev.copyWith(enableAutoSkip: val),
                    );
                  },
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.skip_next_rounded),
                  title: const Text('Skip fillers'),
                  value: playerSettings.skipFillerEpisodes,
                  onChanged: (val) {
                    playerNotifier.updateSettings(
                      (prev) => prev.copyWith(skipFillerEpisodes: val),
                    );
                  },
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.stop_circle_outlined),
                  title: const Text('Stop after episode'),
                  value: playerSettings.stopAfterCurrentEpisode,
                  onChanged: (val) {
                    playerNotifier.updateSettings(
                      (prev) => prev.copyWith(stopAfterCurrentEpisode: val),
                    );
                  },
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.upcoming_rounded),
                  title: const Text('Next episode prompt'),
                  value: playerSettings.showNextEpisodePrompt,
                  onChanged: (val) {
                    playerNotifier.updateSettings(
                      (prev) => prev.copyWith(showNextEpisodePrompt: val),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Iconsax.speedometer),
                  title: const Text("Speed"),
                  trailing: Text(
                    "${ref.watch(playerStateProvider.select((p) => p.playbackSpeed))}x",
                  ),
                  onTap:
                      () => _showDialog(
                        context,
                        builder: (ctx) => const SpeedDialog(),
                      ),
                ),
                ListTile(
                  leading: const Icon(Iconsax.crop),
                  title: const Text("Video Fit"),
                  trailing: Text(
                    ref.watch(
                      playerStateProvider.select((p) => p.fitMode.label),
                    ),
                  ),
                  onTap:
                      () => _showDialog(
                        context,
                        builder: (ctx) => const FitDialog(),
                      ),
                ),
                ListTile(
                  leading: const Icon(Iconsax.timer_1),
                  title: const Text("Jump to time"),
                  trailing: Text(
                    _formatDuration(
                      ref.watch(playerStateProvider.select((p) => p.position)),
                    ),
                  ),
                  onTap: () {
                    final player = ref.read(playerStateProvider);
                    _showDialog(
                      context,
                      builder:
                          (ctx) => JumpToTimeDialog(
                            currentPosition: player.position,
                            totalDuration: player.duration,
                            title: 'Jump to Time',
                            actionLabel: 'Jump',
                            onJump: (targetDuration) {
                              ref
                                  .read(playerStateProvider.notifier)
                                  .seek(targetDuration);
                            },
                          ),
                    );
                  },
                ),
                ListTile(
                  dense: true,
                  leading: Icon(
                    ref.watch(playerStateProvider.select((p) => p.isRepeating))
                        ? Icons.repeat_one_rounded
                        : Icons.repeat_rounded,
                  ),
                  title: const Text('Repeat'),
                  trailing: Text(
                    ref.watch(playerStateProvider.select((p) => p.isRepeating))
                        ? 'Episode'
                        : 'Off',
                  ),
                  onTap:
                      () =>
                          ref.read(playerStateProvider.notifier).toggleRepeat(),
                ),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.picture_in_picture_alt_rounded),
                  title: const Text('Pop-up player'),
                  onTap: () async {
                    Navigator.pop(context);
                    await ref.read(pipProvider.notifier).enterPiP();
                  },
                ),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.share_rounded),
                  title: const Text('Share episode'),
                  onTap:
                      episodeList.mediaId == null ||
                              streamData.selectedEpisode == null
                          ? null
                          : () async {
                            await ShareLinkService.shareEpisode(
                              animeId: episodeList.mediaId!,
                              animeTitle: episodeList.animeTitle ?? 'Anime',
                              episode: streamData.selectedEpisode!,
                            );
                          },
                ),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.info_outline_rounded),
                  title: const Text('Video info'),
                  onTap: () {
                    final player = ref.read(playerStateProvider);
                    _showDialog(
                      context,
                      builder:
                          (ctx) => AlertDialog(
                            title: const Text('Video information'),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Audio: ${isDub ? 'English DUB' : 'Japanese SUB'}',
                                ),
                                Text('Quality: ${currentQuality ?? 'Auto'}'),
                                Text(
                                  'Position: ${_formatDuration(player.position)}',
                                ),
                                Text(
                                  'Duration: ${_formatDuration(player.duration)}',
                                ),
                                Text(
                                  'Buffered: ${_formatDuration(player.buffer)}',
                                ),
                                Text('Speed: ${player.playbackSpeed}x'),
                              ],
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('Close'),
                              ),
                            ],
                          ),
                    );
                  },
                ),
                const Divider(),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.favorite_rounded, color: Colors.pinkAccent),
                  title: const Text('Sponsor AniDash 💖'),
                  subtitle: const Text('Keep AniDash 100% free & ad-free'),
                  onTap: () {
                    Navigator.pop(context);
                    SponsorDialog.show(context);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SpeedDialog extends ConsumerStatefulWidget {
  const SpeedDialog({super.key});

  @override
  ConsumerState<SpeedDialog> createState() => _SpeedDialogState();
}

class _SpeedDialogState extends ConsumerState<SpeedDialog> {
  late double _selectedSpeed;

  @override
  void initState() {
    super.initState();
    _selectedSpeed = ref.read(playerStateProvider).playbackSpeed;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Playback Speed"),
      content: Wrap(
        spacing: 8.0,
        runSpacing: 4.0,
        children:
            [0.5, 1.0, 1.25, 1.5, 2.0, 2.5, 3.0]
                .map(
                  (speed) => ChoiceChip(
                    label: Text("${speed}x"),
                    selected: _selectedSpeed == speed,
                    onSelected: (isSelected) {
                      if (isSelected) setState(() => _selectedSpeed = speed);
                    },
                  ),
                )
                .toList(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel"),
        ),
        TextButton(
          onPressed: () {
            ref.read(playerStateProvider.notifier).setSpeed(_selectedSpeed);
            Navigator.pop(context);
          },
          child: const Text("OK"),
        ),
      ],
    );
  }
}

class FitDialog extends ConsumerStatefulWidget {
  const FitDialog({super.key});

  @override
  ConsumerState<FitDialog> createState() => _FitDialogState();
}

class _FitDialogState extends ConsumerState<FitDialog> {
  late VideoFitMode _selectedFit;
  static const fitModes = VideoFitMode.values;

  @override
  void initState() {
    super.initState();
    _selectedFit = ref.read(playerStateProvider).fitMode;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Video Fit"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children:
            fitModes
                .map(
                  (fit) => RadioListTile<VideoFitMode>(
                    title: Text(fit.label),
                    value: fit,
                    groupValue: _selectedFit,
                    onChanged: (value) {
                      if (value != null) setState(() => _selectedFit = value);
                    },
                  ),
                )
                .toList(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel"),
        ),
        TextButton(
          onPressed: () {
            ref.read(playerStateProvider.notifier).setFitMode(_selectedFit);
            Navigator.pop(context);
          },
          child: const Text("OK"),
        ),
      ],
    );
  }
}

String _formatDuration(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60);
  final seconds = d.inSeconds.remainder(60);
  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}
