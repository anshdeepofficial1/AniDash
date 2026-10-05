import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:ani_dash/core/network/http_client.dart';
import 'package:ani_dash/core/services/backup_service.dart';
import 'package:ani_dash/features/settings/view/widgets/settings_item.dart';
import 'package:ani_dash/features/settings/view/widgets/settings_section.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DataSettingsScreen extends ConsumerStatefulWidget {
  const DataSettingsScreen({super.key});

  @override
  ConsumerState<DataSettingsScreen> createState() => _DataSettingsScreenState();
}

class _DataSettingsScreenState extends ConsumerState<DataSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton.filledTonal(
          onPressed: () => context.pop(),
          icon: const Icon(Iconsax.arrow_left_2),
        ),
        title: const Text('Data & Storage'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          SettingsSection(
            title: 'Cache',
            titleColor: colorScheme.primary,
            onTap: () {},
            children: [
              NormalSettingsItem(
                icon: Icon(Iconsax.image, color: colorScheme.primary),
                accent: colorScheme.primary,
                title: 'Clear Image Cache',
                description: 'Free up space by clearing cached images',
                onTap: () async {
                  await CachedNetworkImage.evictFromCache('');
                  imageCache.clear();
                  imageCache.clearLiveImages();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Image cache cleared')),
                    );
                  }
                },
              ),
              NormalSettingsItem(
                icon: Icon(Iconsax.refresh, color: colorScheme.error),
                accent: colorScheme.error,
                title: 'Clear Everything & Rebuild',
                description:
                    'Remove images, API responses and old episode metadata, then fetch fresh data',
                onTap: () => _clearAndRebuild(context),
              ),
              NormalSettingsItem(
                icon: Icon(Iconsax.global, color: colorScheme.primary),
                accent: colorScheme.primary,
                title: 'Clear API Cache',
                description: 'Clear cached network responses',
                onTap: () async {
                  await UniversalHttpClient.instance.wipeCache();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('API cache cleared')),
                    );
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          SettingsSection(
            title: 'Backup & Restore',
            titleColor: colorScheme.primary,
            onTap: () {},
            children: [
              NormalSettingsItem(
                icon: Icon(Iconsax.export, color: colorScheme.primary),
                accent: colorScheme.primary,
                title: 'Export Data',
                description: 'Create a backup of your data',
                onTap: () => _showExportDialog(context),
              ),
              NormalSettingsItem(
                icon: Icon(Iconsax.import, color: colorScheme.primary),
                accent: colorScheme.primary,
                title: 'Import Data',
                description: 'Restore data from a backup file',
                onTap: () => _importData(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _clearAndRebuild(BuildContext context) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder:
              (dialogContext) => AlertDialog(
                title: const Text('Clear and rebuild data?'),
                content: const Text(
                  'Downloaded videos, watch progress and accounts will stay safe. Cached images, network data and saved episode corrections will be rebuilt.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('Clear & Rebuild'),
                  ),
                ],
              ),
        ) ??
        false;
    if (!confirmed) return;

    imageCache.clear();
    imageCache.clearLiveImages();
    await UniversalHttpClient.instance.wipeCache();
    final prefs = await SharedPreferences.getInstance();
    final staleKeys = prefs
        .getKeys()
        .where(
          (key) =>
              key.startsWith('corrected_episode_titles_') ||
              key.startsWith('named_episode_groups_') ||
              key.startsWith('episode_thumbnail_'),
        )
        .toList(growable: false);
    for (final key in staleKeys) {
      await prefs.remove(key);
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Old cached data cleared. Pages will now rebuild fresh.'),
      ),
    );
  }

  void _showExportDialog(BuildContext context) {
    bool includeWatchlist = true;
    bool includeSettings = true;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Export Data'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CheckboxListTile(
                    value: includeWatchlist,
                    onChanged: (v) => setState(() => includeWatchlist = v!),
                    title: const Text('Watchlist & Progress'),
                    activeColor: Theme.of(context).colorScheme.primary,
                  ),
                  CheckboxListTile(
                    value: includeSettings,
                    onChanged: (v) => setState(() => includeSettings = v!),
                    title: const Text('App Settings'),
                    activeColor: Theme.of(context).colorScheme.primary,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _exportData(context, includeWatchlist, includeSettings);
                  },
                  child: const Text('Export'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _exportData(
    BuildContext context,
    bool watchlist,
    bool settings,
  ) async {
    try {
      await ref
          .read(backupServiceProvider)
          .exportData(includeWatchlist: watchlist, includeSettings: settings);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Export completed successfully')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: ${e.toString()}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _importData(BuildContext context) async {
    try {
      await ref.read(backupServiceProvider).importData();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Import completed. Please restart app.'),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import failed: ${e.toString()}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }
}
