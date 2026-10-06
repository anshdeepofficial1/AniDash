import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:go_router/go_router.dart';
import 'package:ani_dash/features/settings/view/widgets/settings_item.dart';
import 'package:ani_dash/features/settings/view/widgets/settings_section.dart';
import 'package:ani_dash/shared/providers/settings/download_settings_notifier.dart';

class DownloadSettingsScreen extends ConsumerWidget {
  const DownloadSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(downloadSettingsProvider);
    final notifier = ref.read(downloadSettingsProvider.notifier);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton.filledTonal(
          onPressed: () => context.pop(),
          icon: const Icon(Iconsax.arrow_left_2),
        ),
        title: const Text('Download Settings'),
        forceMaterialTransparency: true,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        children: [
          SettingsSection(
            title: 'Storage',
            titleColor: colorScheme.primary,
            onTap: () {},
            children: [
              Consumer(
                builder: (context, ref, child) {
                  return ToggleableSettingsItem(
                    icon: Icon(Iconsax.folder_open, color: colorScheme.primary),
                    accent: colorScheme.primary,
                    title: 'Custom Download Path',
                    description: 'Use a custom directory for downloads',
                    value: settings.useCustomPath,
                    onChanged: (val) => notifier.toggleUseCustomPath(val),
                  );
                },
              ),
              if (settings.useCustomPath)
                NormalSettingsItem(
                  icon: Icon(Iconsax.folder, color: colorScheme.primary),
                  accent: colorScheme.primary,
                  title: 'Select Path',
                  description:
                      settings.customDownloadPath ?? 'Tap to select...',
                  onTap: () async {
                    String? selectedDirectory =
                        await FilePicker.getDirectoryPath();
                    if (selectedDirectory != null) {
                      bool isWritable = false;
                      try {
                        final dir = Directory(selectedDirectory);
                        if (!dir.existsSync()) {
                          dir.createSync(recursive: true);
                        }
                        final testFile = File('${dir.path}/.shonenx_test');
                        testFile.writeAsStringSync('write_ok');
                        testFile.deleteSync();
                        isWritable = true;
                      } catch (_) {
                        isWritable = false;
                      }

                      if (isWritable) {
                        notifier.setCustomPath(selectedDirectory);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Download directory set to $selectedDirectory',
                              ),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                        return;
                      }

                      // Attempt to resolve app-specific writable directory on SD card
                      String? sdCardPath;
                      if (Platform.isAndroid) {
                        try {
                          final extDirs = await getExternalStorageDirectories();
                          if (extDirs != null) {
                            final match = RegExp(r'/storage/([A-Fa-f0-9]{4}-[A-Fa-f0-9]{4})')
                                .firstMatch(selectedDirectory);
                            if (match != null) {
                              final sdId = match.group(1)!;
                              final sdDir = extDirs.where((d) => d.path.contains(sdId)).firstOrNull;
                              if (sdDir != null) {
                                final appSdTarget = '${sdDir.path}/AniDash';
                                final targetDir = Directory(appSdTarget);
                                if (!targetDir.existsSync()) targetDir.createSync(recursive: true);
                                final test = File('$appSdTarget/.shonenx_test');
                                test.writeAsStringSync('ok');
                                test.deleteSync();
                                sdCardPath = appSdTarget;
                              }
                            }
                          }
                        } catch (_) {}
                      }

                      if (sdCardPath != null) {
                        notifier.setCustomPath(sdCardPath);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Set to writable SD Card folder: $sdCardPath',
                              ),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      } else {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Selected directory is not writable. Please pick an accessible folder.',
                              ),
                              backgroundColor: Colors.red,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      }
                    }
                  },
                ),
              DropdownSettingsItem(
                icon: Icon(Iconsax.sort),
                accent: colorScheme.primary,
                title: 'Folder Structure',
                description: 'Organize downloaded files',
                value: settings.folderStructure,
                items:
                    ['Anime/Episode', 'Anime', 'Flat']
                        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                        .toList(),
                onChanged: (val) {
                  if (val != null) notifier.setFolderStructure(val);
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          SettingsSection(
            title: 'Performance',
            titleColor: colorScheme.primary,
            onTap: () {},
            children: [
              SliderSettingsItem(
                accent: colorScheme.primary,
                title: 'Number of Downloads',
                description:
                    '${settings.parallelDownloads} downloads at the same time',
                value: settings.parallelDownloads.toDouble(),
                min: 1,
                max: 10,
                divisions: 9,
                onChanged: (val) => notifier.setParallelDownloads(val.toInt()),
                icon: Icon(Iconsax.flash_1, color: colorScheme.primary),
              ),
              SliderSettingsItem(
                accent: colorScheme.primary,
                title: 'Speed Limit',
                description:
                    settings.speedLimitKBps == 0
                        ? 'Unlimited'
                        : '${settings.speedLimitKBps} KB/s',
                value: settings.speedLimitKBps.toDouble(),
                min: 0,
                max: 10000,
                divisions: 100,
                onChanged: (val) => notifier.setSpeedLimit(val.toInt()),
                icon: Icon(Iconsax.timer_1, color: colorScheme.primary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SettingsSection(
            title: 'Network',
            titleColor: colorScheme.primary,
            onTap: () {},
            children: [
              ToggleableSettingsItem(
                icon: Icon(Iconsax.wifi, color: colorScheme.primary),
                accent: colorScheme.primary,
                title: 'Wi-Fi Only',
                description: 'Only download when connected to Wi-Fi',
                value: settings.wifiOnly,
                onChanged: (val) => notifier.toggleWifiOnly(val),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SettingsSection(
            title: 'Download Preferences',
            titleColor: colorScheme.primary,
            onTap: () {},
            children: [
              ToggleableSettingsItem(
                icon: Icon(Iconsax.tick_circle, color: colorScheme.primary),
                accent: colorScheme.primary,
                title: 'Remember Preferences',
                description:
                    settings.rememberDownloadPreferences
                        ? 'Downloads auto-start with saved server, audio & quality'
                        : 'Show these saved defaults before every download',
                value: settings.rememberDownloadPreferences,
                onChanged: (val) {
                  notifier.updateSettings(
                    (s) => s.copyWith(rememberDownloadPreferences: val),
                  );
                },
              ),
              ...[
                DropdownSettingsItem(
                  icon: const Icon(Icons.dns_rounded),
                  accent: colorScheme.primary,
                  title: 'Default Server',
                  description:
                      'Used when this server is available for the episode',
                  value: settings.preferredServerId,
                  items: const [
                    DropdownMenuItem(value: 'auto', child: Text('Automatic')),
                    DropdownMenuItem(value: 'megaplay', child: Text('Momo')),
                    DropdownMenuItem(value: 'zokoanime', child: Text('Zoko')),
                    DropdownMenuItem(value: 'animegg', child: Text('Gigi')),
                    DropdownMenuItem(value: 'anineko', child: Text('Neko')),
                    DropdownMenuItem(
                      value: 'megacloud',
                      child: Text('Megacloud'),
                    ),
                    DropdownMenuItem(value: 'hd-1', child: Text('HD-1')),
                    DropdownMenuItem(value: 'hd-2', child: Text('HD-2')),
                    DropdownMenuItem(value: 'anikoto', child: Text('Anikoto')),
                    DropdownMenuItem(
                      value: 'animepahe',
                      child: Text('AnimePahe'),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) notifier.setPreferredServer(val);
                  },
                ),
                DropdownSettingsItem(
                  icon: Icon(Iconsax.translate),
                  accent: colorScheme.primary,
                  title: 'Default Language',
                  description: 'Preferred audio / subtitle language',
                  value: settings.preferredLanguage,
                  items: const [
                    DropdownMenuItem(
                      value: 'sub',
                      child: Text('Japanese (Sub)'),
                    ),
                    DropdownMenuItem(
                      value: 'dub',
                      child: Text('English (Dub)'),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      notifier.updateSettings(
                        (s) => s.copyWith(preferredLanguage: val),
                      );
                    }
                  },
                ),
                DropdownSettingsItem(
                  icon: Icon(Iconsax.video),
                  accent: colorScheme.primary,
                  title: 'Default Quality',
                  description: 'Preferred video resolution',
                  value: settings.preferredQuality,
                  items: const [
                    DropdownMenuItem(
                      value: '1080p',
                      child: Text('1080p (FHD)'),
                    ),
                    DropdownMenuItem(value: '720p', child: Text('720p (HD)')),
                    DropdownMenuItem(value: '480p', child: Text('480p (SD)')),
                    DropdownMenuItem(
                      value: '360p',
                      child: Text('360p (Data Saver)'),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      notifier.updateSettings(
                        (s) => s.copyWith(preferredQuality: val),
                      );
                    }
                  },
                ),
              ],
            ],
          ),
          const SizedBox(height: 50),
        ],
      ),
    );
  }
}
