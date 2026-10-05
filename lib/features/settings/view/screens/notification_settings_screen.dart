import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import 'package:ani_dash/core/services/notification_service.dart';
import 'package:ani_dash/core/tasks/episode_release_task.dart';
import 'package:ani_dash/features/settings/view/widgets/settings_item.dart';
import 'package:ani_dash/features/settings/view/widgets/settings_section.dart';
import 'package:ani_dash/shared/providers/settings/notification_settings_notifier.dart';

class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(notificationSettingsProvider);
    final notifier = ref.read(notificationSettingsProvider.notifier);
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton.filledTonal(
          onPressed: () => context.pop(),
          icon: const Icon(Iconsax.arrow_left_2),
        ),
        title: const Text('Notifications'),
        forceMaterialTransparency: true,
        actions: [
          IconButton(
            tooltip: 'Send test notification',
            icon: const Icon(Icons.notifications_active_outlined),
            onPressed: () async {
              final allowed =
                  await NotificationService().requestSystemPermission();
              if (!allowed) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Notification permission is disabled in system settings.',
                      ),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
                return;
              }
              await NotificationService().showTestNotification(
                body: 'Notifications are enabled and using your system sound.',
              );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Test notification sent.'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        children: [
          _section(
            colors,
            'Anime News',
            ToggleableSettingsItem(
              icon: Icon(Iconsax.document_text, color: colors.primary),
              accent: colors.primary,
              title: 'News Notifications',
              description: 'Anime news and important announcements',
              value: settings.enableNews,
              onChanged:
                  (value) => notifier.updateSettings(
                    (state) => state.copyWith(enableNews: value),
                  ),
            ),
          ),
          _section(
            colors,
            'Episode Releases',
            ToggleableSettingsItem(
              icon: Icon(Iconsax.translate, color: colors.primary),
              accent: colors.primary,
              title: 'Dub Releases',
              description: 'English dub releases for relevant titles',
              value: settings.enableDubReleases,
              onChanged:
                  (value) => notifier.updateSettings(
                    (state) => state.copyWith(enableDubReleases: value),
                  ),
            ),
            ToggleableSettingsItem(
              icon: Icon(Icons.subtitles_rounded, color: colors.primary),
              accent: colors.primary,
              title: 'Sub Releases',
              description: 'Japanese audio with subtitle releases',
              value: settings.enableSubReleases,
              onChanged:
                  (value) => notifier.updateSettings(
                    (state) => state.copyWith(enableSubReleases: value),
                  ),
            ),
          ),
          _section(
            colors,
            'Reminders & Downloads',
            ToggleableSettingsItem(
              icon: Icon(Iconsax.clock, color: colors.primary),
              accent: colors.primary,
              title: 'Continue Watching',
              description: 'Occasional reminders for unfinished episodes',
              value: settings.enableContinueWatching,
              onChanged:
                  (value) => notifier.updateSettings(
                    (state) => state.copyWith(enableContinueWatching: value),
                  ),
            ),
            ToggleableSettingsItem(
              icon: Icon(Iconsax.document_download, color: colors.primary),
              accent: colors.primary,
              title: 'Download Notifications',
              description: 'Download progress and completion status',
              value: settings.enableDownloads,
              onChanged:
                  (value) => notifier.updateSettings(
                    (state) => state.copyWith(enableDownloads: value),
                  ),
            ),
          ),
          _section(
            colors,
            'Diagnostics',
            NormalSettingsItem(
              icon: Icon(Iconsax.refresh, color: colors.primary),
              accent: colors.primary,
              title: 'Check Releases Now',
              description: 'Manually run episode release check & diagnostics',
              onTap: () async {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Checking latest releases...'),
                    duration: Duration(seconds: 1),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                final res = await EpisodeReleaseTask.performCheck(
                  isManual: true,
                );
                if (context.mounted) {
                  showModalBottomSheet(
                    context: context,
                    backgroundColor: Theme.of(context).colorScheme.surface,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(16),
                      ),
                    ),
                    builder:
                        (ctx) => Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    res.success
                                        ? Icons.check_circle_outline
                                        : Icons.error_outline,
                                    color:
                                        res.success ? Colors.green : Colors.red,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    res.success
                                        ? 'Check Completed'
                                        : 'Check Failed',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                '• AniList Query Status: ${res.success ? "Success" : "Failed"}',
                              ),
                              Text(
                                '• Total Airing Schedules: ${res.schedulesReturned}',
                              ),
                              Text(
                                '• Relevant Watching Titles: ${res.relevantCount}',
                              ),
                              Text('• Notifications Sent: ${res.sentCount}'),
                              Text(
                                '• Duplicates Suppressed: ${res.duplicateSuppressed}',
                              ),
                              const SizedBox(height: 8),
                              Text(
                                res.message,
                                style: TextStyle(
                                  color:
                                      Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
                          ),
                        ),
                  );
                }
              },
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _section(
    ColorScheme colors,
    String title,
    Widget first, [
    Widget? second,
  ]) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SettingsSection(
        title: title,
        titleColor: colors.primary,
        onTap: () {},
        children: [first, if (second != null) second],
      ),
    );
  }
}
