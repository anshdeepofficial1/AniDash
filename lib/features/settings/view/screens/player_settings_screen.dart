import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:go_router/go_router.dart';
import 'package:ani_dash/shared/providers/settings/player_notifier.dart';
import 'package:ani_dash/features/settings/view/widgets/settings_item.dart';
import 'package:ani_dash/features/settings/view/widgets/settings_section.dart';

class PlayerSettingsScreen extends ConsumerWidget {
  const PlayerSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final playerSettings = ref.watch(playerSettingsProvider);
    final playerNotifier = ref.read(playerSettingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton.filledTonal(
          onPressed: () => context.pop(),
          icon: const Icon(Iconsax.arrow_left_2),
        ),
        title: const Text('Video Player'),
        forceMaterialTransparency: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(10.0),
        child: ListView(
          children: [
            SettingsSection(
              title: 'Quality',
              titleColor: colorScheme.primary,
              children: [
                DropdownSettingsItem(
                  icon: Icon(Iconsax.video_tick, color: colorScheme.primary),
                  accent: colorScheme.primary,
                  title: 'Video Quality',
                  description: 'Current: ${playerSettings.defaultQuality}',
                  value: playerSettings.defaultQuality,
                  items: const [
                    DropdownMenuItem(value: 'Auto', child: Text('Auto')),
                    DropdownMenuItem(value: '1080p', child: Text('1080p')),
                    DropdownMenuItem(value: '720p', child: Text('720p')),
                    DropdownMenuItem(value: '480p', child: Text('480p')),
                    DropdownMenuItem(value: '360p', child: Text('360p')),
                  ],
                  onChanged: (value) => playerNotifier.updateSettings(
                    (prev) => prev.copyWith(defaultQuality: value!),
                  ),
                ),
                DropdownSettingsItem(
                  icon: Icon(Iconsax.microphone, color: colorScheme.primary),
                  accent: colorScheme.primary,
                  title: 'Preferred Audio Track',
                  description:
                      (playerSettings.preferredAudioLanguage == 'sub'
                              ? 'Subtitled / Original (SUB)'
                              : 'Dubbed (DUB)'),
                  value: playerSettings.preferredAudioLanguage,
                  items: const [
                    DropdownMenuItem(
                      value: 'sub',
                      child: Text('Subtitled / Original (SUB)'),
                    ),
                    DropdownMenuItem(
                      value: 'dub',
                      child: Text('Dubbed (DUB)'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      playerNotifier.setPreferredAudioLanguage(value);
                    }
                  },
                ),
              ],
            ),
            SettingsSection(
              title: 'AniSkip',
              titleColor: colorScheme.primary,
              children: [
                ToggleableSettingsItem(
                  icon: Icon(Iconsax.timer_1, color: colorScheme.primary),
                  accent: colorScheme.primary,
                  title: 'Enable AniSkip',
                  description: 'Skip intro and outro automatically or manually',
                  value: playerSettings.enableAniSkip,
                  onChanged: (value) => playerNotifier.updateSettings(
                    (prev) => prev.copyWith(enableAniSkip: value),
                  ),
                ),
                ToggleableSettingsItem(
                  icon: Icon(
                    Iconsax.autobrightness,
                    color: colorScheme.primary,
                  ),
                  accent: colorScheme.primary,
                  title: 'Auto Skip',
                  description: 'Automatically skip intro/outro without asking',
                  value: playerSettings.enableAutoSkip,
                  onChanged: (value) {
                    if (playerSettings.enableAniSkip) {
                      playerNotifier.updateSettings(
                        (prev) => prev.copyWith(enableAutoSkip: value),
                      );
                    }
                  },
                ),
                ToggleableSettingsItem(
                  icon: Icon(
                    Iconsax.forward_5_seconds,
                    color: colorScheme.primary,
                  ),
                  accent: colorScheme.primary,
                  title: 'Manual Op Skip Button',
                  description:
                      'Show a one-tap skip button during opening intros',
                  value: playerSettings.showManualSkip,
                  onChanged: (value) => playerNotifier.updateSettings(
                    (prev) => prev.copyWith(showManualSkip: value),
                  ),
                ),
                if (playerSettings.showManualSkip)
                  SliderSettingsItem(
                    icon: Icon(Iconsax.timer, color: colorScheme.primary),
                    accent: colorScheme.primary,
                    title: 'Manual Skip Duration',
                    description:
                        'Skip ${playerSettings.manualSkipDuration} seconds (standard anime intro: 85s)',
                    value: playerSettings.manualSkipDuration.toDouble(),
                    min: 30,
                    max: 120,
                    divisions: 18,
                    onChanged: (value) => playerNotifier.updateSettings(
                      (prev) => prev.copyWith(manualSkipDuration: value.toInt()),
                    ),
                  ),
              ],
            ),
            SettingsSection(
              title: 'Playback & Flow',
              titleColor: colorScheme.primary,
              children: [
                ToggleableSettingsItem(
                  icon: Icon(Iconsax.flash_1, color: colorScheme.primary),
                  accent: colorScheme.primary,
                  title: 'Pre-load Next Episode at 85%',
                  description:
                      'Pre-fetches stream servers and URLs in memory for instant switching with zero lag',
                  value: playerSettings.prefetchNextEpisode,
                  onChanged: (value) => playerNotifier.updateSettings(
                    (prev) => prev.copyWith(prefetchNextEpisode: value),
                  ),
                ),
                ToggleableSettingsItem(
                  icon: Icon(Iconsax.play_add, color: colorScheme.primary),
                  accent: colorScheme.primary,
                  title: 'Next Episode Prompt at 95%',
                  description:
                      'Show floating Netflix-style next episode card during outro/credits',
                  value: playerSettings.showNextEpisodePrompt,
                  onChanged: (value) => playerNotifier.updateSettings(
                    (prev) => prev.copyWith(showNextEpisodePrompt: value),
                  ),
                ),
              ],
            ),
            SettingsSection(
              title: 'Subtitle',
              titleColor: colorScheme.primary,
              children: [
                ToggleableSettingsItem(
                  icon: Icon(Iconsax.subtitle, color: colorScheme.primary),
                  accent: colorScheme.primary,
                  title: 'Auto-Enable Subtitles',
                  description:
                      'Automatically show subtitles when video playback starts',
                  value: playerSettings.autoEnableSubtitles,
                  onChanged: (value) => playerNotifier.updateSettings(
                    (prev) => prev.copyWith(autoEnableSubtitles: value),
                  ),
                ),
                NormalSettingsItem(
                  icon: Icon(Iconsax.colorfilter, color: colorScheme.primary),
                  accent: colorScheme.primary,
                  title: 'Subtitle Customization',
                  description: 'Customize subtitle appearance',
                  onTap: () => context.push('/settings/player/subtitles'),
                ),
              ],
            ),
            SettingsSection(
              title: 'Controls Overlay',
              titleColor: colorScheme.primary,
              children: [
                SliderSettingsItem(
                  icon: Icon(
                    Iconsax.forward_10_seconds,
                    color: colorScheme.primary,
                  ),
                  accent: colorScheme.primary,
                  title: 'Seek Duration',
                  description: '${playerSettings.seekDuration}s',
                  value: playerSettings.seekDuration.toDouble(),
                  min: 5,
                  max: 30,
                  divisions: 5,
                  onChanged: (val) => playerNotifier.updateSettings(
                    (prev) => prev.copyWith(seekDuration: val.toInt()),
                  ),
                ),
                SliderSettingsItem(
                  icon: Icon(Iconsax.timer_pause, color: colorScheme.primary),
                  accent: colorScheme.primary,
                  title: 'Auto Hide Timeout',
                  description: '${playerSettings.autoHideDuration}s',
                  value: playerSettings.autoHideDuration.toDouble(),
                  min: 2,
                  max: 10,
                  onChanged: (val) => playerNotifier.updateSettings(
                    (prev) => prev.copyWith(autoHideDuration: val.toInt()),
                  ),
                ),
                SliderSettingsItem(
                  icon: Icon(Icons.lock_clock_outlined, color: colorScheme.primary),
                  accent: colorScheme.primary,
                  title: 'Lock Button Auto Hide',
                  description: '${playerSettings.lockAutoHideDuration}s',
                  value: playerSettings.lockAutoHideDuration.toDouble().clamp(2.0, 30.0),
                  min: 2,
                  max: 30,
                  divisions: 28,
                  onChanged: (val) => playerNotifier.updateSettings(
                    (prev) => prev.copyWith(lockAutoHideDuration: val.toInt()),
                  ),
                ),
              ],
            ),
            SettingsSection(
              title: 'Advanced',
              titleColor: colorScheme.primary,
              children: [
                NormalSettingsItem(
                  icon: Icon(
                    Icons.settings_applications,
                    color: colorScheme.primary,
                  ),
                  title: 'Advanced Video Settings',
                  description: 'Configure hardware acceleration and MPV flags',
                  onTap: () => context.push('/settings/player/advanced'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
