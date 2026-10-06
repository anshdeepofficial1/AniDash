import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:ani_dash/features/settings/view/widgets/settings_item.dart';
import 'package:ani_dash/features/settings/view/widgets/settings_section.dart';
import 'package:ani_dash/shared/providers/permissions_provider.dart';

class PermissionsSettingsScreen extends ConsumerWidget {
  const PermissionsSettingsScreen({super.key});

  void _promptRevoke(BuildContext context) {
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Manage Permissions'),
            content: const Text(
              'Granted system permissions on Android can only be revoked from the device App Settings.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  openAppSettings();
                },
                child: const Text('Open Settings'),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final permissionsState = ref.watch(permissionsProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton.filledTonal(
          onPressed: () => context.pop(),
          icon: const Icon(Iconsax.arrow_left_2),
        ),
        title: const Text('Permissions'),
        forceMaterialTransparency: true,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10.0),
        child: ListView(
          children: [
            SettingsSection(
              title: 'Access Management',
              titleColor: colorScheme.primary,
              onTap: () {},
              children: [
                ToggleableSettingsItem(
                  icon: Icon(Iconsax.folder_open, color: colorScheme.primary),
                  accent: colorScheme.primary,
                  title: 'Storage Access',
                  description: 'Allow access to storage to download anime.',
                  value: permissionsState.storage,
                  onChanged: (val) async {
                    if (val == false) {
                      await ref
                          .read(permissionsProvider.notifier)
                          .revokeStorageAccess();
                      return;
                    }
                    final approved = await showDialog<bool>(
                      context: context,
                      builder:
                          (dialogContext) => AlertDialog(
                            title: const Text('Allow storage access?'),
                            content: const Text(
                              'AniDash will use its private app storage for downloads and extension data. Other apps cannot access these files.',
                            ),
                            actions: [
                              TextButton(
                                onPressed:
                                    () => Navigator.pop(dialogContext, false),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                onPressed:
                                    () => Navigator.pop(dialogContext, true),
                                child: const Text('Allow'),
                              ),
                            ],
                          ),
                    );
                    if (approved != true) return;
                    await ref
                        .read(permissionsProvider.notifier)
                        .requestStoragePermission();
                  },
                ),
                ToggleableSettingsItem(
                  icon: Icon(Iconsax.notification, color: colorScheme.primary),
                  accent: colorScheme.primary,
                  title: 'Notification Access',
                  description:
                      'Allow access to notifications to get notified about new anime news.',
                  value: permissionsState.notification,
                  onChanged: (val) async {
                    if (val == false) {
                      if (Platform.isAndroid) {
                        _promptRevoke(context);
                      } else {
                        ref
                            .read(permissionsProvider.notifier)
                            .setNotificationAccess(false);
                      }
                      return;
                    }
                    await ref
                        .read(permissionsProvider.notifier)
                        .requestNotificationPermission();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
