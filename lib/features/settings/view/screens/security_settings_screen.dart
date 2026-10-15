import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:go_router/go_router.dart';
import 'package:ani_dash/features/settings/view/widgets/settings_item.dart';
import 'package:ani_dash/features/settings/view/widgets/settings_section.dart';
import 'package:ani_dash/shared/providers/settings/security_notifier.dart';
import 'package:ani_dash/shared/ui/pin_lock_dialog.dart';
import 'package:ani_dash/core/services/biometric_service.dart';

class SecuritySettingsScreen extends ConsumerWidget {
  const SecuritySettingsScreen({super.key});

  int _length(String type) => type == 'pin6' ? 6 : 4;
  bool _letters(String type) => type == 'password';
  String _typeLabel(String type) => switch (type) {
    'pin6' => '6-digit PIN',
    'password' => 'Alphanumeric password',
    'pattern' => 'Pattern (4 points)',
    _ => '4-digit PIN',
  };

  String _delayLabel(int seconds) => switch (seconds) {
    10 => 'After 10 seconds',
    20 => 'After 20 seconds',
    30 => 'After 30 seconds',
    300 => 'After 5 minutes',
    600 => 'After 10 minutes',
    _ => 'Immediately',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final security = ref.watch(securityProvider);
    final notifier = ref.read(securityProvider.notifier);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton.filledTonal(
          onPressed: () => context.pop(),
          icon: const Icon(Iconsax.arrow_left_2),
        ),
        title: const Text('Security & Privacy'),
        forceMaterialTransparency: true,
      ),
      body: SafeArea(
        top: true,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          children: [
            SettingsSection(
              title: 'App Lock',
              titleColor: colorScheme.primary,
              onTap: () {},
              children: [
                ToggleableSettingsItem(
                  icon: Icon(
                    Icons.lock_outline_rounded,
                    color: colorScheme.primary,
                  ),
                  accent: colorScheme.primary,
                  title: 'Lock AniDash App',
                  description: 'Require PIN to open the AniDash application',
                  value: security.appLockEnabled,
                  onChanged: (val) async {
                    if (val) {
                      final type = await showDialog<String>(
                        context: context,
                        builder:
                            (dialogContext) => SimpleDialog(
                              title: const Text('Choose lock method'),
                              children:
                                  ['pin4', 'pin6', 'password', 'pattern']
                                      .map(
                                        (method) => SimpleDialogOption(
                                          onPressed:
                                              () => Navigator.pop(
                                                dialogContext,
                                                method,
                                              ),
                                          child: Text(_typeLabel(method)),
                                        ),
                                      )
                                      .toList(),
                            ),
                      );
                      if (type == null || !context.mounted) return;
                      notifier.setPreferredAppLockType(type);
                      final pin = await PinLockDialog.showSetup(
                        context: context,
                        title: 'Set ${_typeLabel(type)}',
                        credentialLength: _length(type),
                        allowLetters: _letters(type),
                      );
                      if (pin != null && pin.isNotEmpty) {
                        notifier.setAppLock(true, pin);
                      }
                    } else {
                      final verified = await PinLockDialog.showUnlock(
                        context: context,
                        title: 'Verify App PIN',
                        onVerify: (pin) => notifier.verifyAppPin(pin),
                        credentialLength: _length(security.appLockType),
                        allowLetters: _letters(security.appLockType),
                      );
                      if (verified) {
                        notifier.setAppLock(false);
                      }
                    }
                  },
                ),
                if (security.appLockEnabled) ...[
                  NormalSettingsItem(
                    icon: Icon(
                      Icons.security_rounded,
                      color: colorScheme.primary,
                    ),
                    accent: colorScheme.primary,
                    title: 'Lock Method',
                    description: _typeLabel(security.appLockType),
                    onTap: () async {
                      final type = await showDialog<String>(
                        context: context,
                        builder:
                            (dialogContext) => SimpleDialog(
                              title: const Text('Choose lock method'),
                              children:
                                  ['pin4', 'pin6', 'password', 'pattern']
                                      .map(
                                        (type) => SimpleDialogOption(
                                          onPressed:
                                              () => Navigator.pop(
                                                dialogContext,
                                                type,
                                              ),
                                          child: Text(_typeLabel(type)),
                                        ),
                                      )
                                      .toList(),
                            ),
                      );
                      if (type == null || !context.mounted) return;
                      final credential = await PinLockDialog.showSetup(
                        context: context,
                        title: 'Set ${_typeLabel(type)}',
                        credentialLength: _length(type),
                        allowLetters: _letters(type),
                      );
                      if (credential != null && credential.isNotEmpty) {
                        notifier.setAppLockType(type, credential);
                      }
                    },
                  ),
                  NormalSettingsItem(
                    icon: Icon(Icons.fingerprint, color: colorScheme.primary),
                    accent: colorScheme.primary,
                    title: 'Forgot App Lock',
                    description:
                        'Verify your fingerprint or face to set a new lock',
                    onTap: () async {
                      final authenticated = await BiometricService.authenticate(
                        reason:
                            'Verify your identity to reset the AniDash lock',
                      );
                      if (!authenticated || !context.mounted) return;
                      final newPin = await PinLockDialog.showSetup(
                        context: context,
                        title: 'Set New ${_typeLabel(security.appLockType)}',
                        credentialLength: _length(security.appLockType),
                        allowLetters: _letters(security.appLockType),
                      );
                      if (newPin != null && newPin.isNotEmpty) {
                        notifier.setAppLock(true, newPin);
                      }
                    },
                  ),
                  NormalSettingsItem(
                    icon: Icon(
                      Icons.timer_outlined,
                      color: colorScheme.primary,
                    ),
                    accent: colorScheme.primary,
                    title: 'Auto-lock',
                    description: _delayLabel(security.appLockDelaySeconds),
                    onTap: () async {
                      const delays = [0, 10, 20, 30, 300, 600];
                      final delay = await showDialog<int>(
                        context: context,
                        builder:
                            (dialogContext) => SimpleDialog(
                              title: const Text('Auto-lock after leaving app'),
                              children:
                                  delays
                                      .map(
                                        (seconds) => SimpleDialogOption(
                                          onPressed:
                                              () => Navigator.pop(
                                                dialogContext,
                                                seconds,
                                              ),
                                          child: Text(_delayLabel(seconds)),
                                        ),
                                      )
                                      .toList(),
                            ),
                      );
                      if (delay != null) notifier.setAppLockDelay(delay);
                    },
                  ),
                  ToggleableSettingsItem(
                    icon: Icon(
                      Icons.fingerprint_rounded,
                      color: colorScheme.primary,
                    ),
                    accent: colorScheme.primary,
                    title: 'Biometric Unlock',
                    description:
                        'Unlock AniDash using Fingerprint or Face Lock',
                    value: security.appLockBiometrics,
                    onChanged: (val) => notifier.toggleAppLockBiometrics(val),
                  ),
                  NormalSettingsItem(
                    icon: Icon(
                      Icons.password_rounded,
                      color: colorScheme.primary,
                    ),
                    accent: colorScheme.primary,
                    title: 'Change App PIN',
                    description: 'Update your 4-digit AniDash PIN',
                    onTap: () async {
                      final verified = await PinLockDialog.showUnlock(
                        context: context,
                        title: 'Verify Current PIN',
                        onVerify: (pin) => notifier.verifyAppPin(pin),
                        credentialLength: _length(security.appLockType),
                        allowLetters: _letters(security.appLockType),
                      );
                      if (verified && context.mounted) {
                        final newPin = await PinLockDialog.showSetup(
                          context: context,
                          title: 'Set New App PIN',
                          credentialLength: _length(security.appLockType),
                          allowLetters: _letters(security.appLockType),
                        );
                        if (newPin != null && newPin.isNotEmpty) {
                          notifier.setAppLock(true, newPin);
                        }
                      }
                    },
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            SettingsSection(
              title: 'Privacy Protection',
              titleColor: colorScheme.primary,
              onTap: () {},
              children: [
                ToggleableSettingsItem(
                  icon: Icon(Icons.blur_on_rounded, color: colorScheme.primary),
                  accent: colorScheme.primary,
                  title: 'Recent Apps Privacy',
                  description:
                      'Hides the Android Recents preview while the app is in background',
                  value: security.recentAppsPrivacy,
                  onChanged: notifier.toggleRecentAppsPrivacy,
                ),
                ToggleableSettingsItem(
                  icon: Icon(
                    Icons.no_photography_outlined,
                    color: colorScheme.primary,
                  ),
                  accent: colorScheme.primary,
                  title: 'Screenshot Privacy',
                  description:
                      'Block screenshots & device screen capture. (Wi-Fi TV casting remains fully functional)',
                  value: security.screenshotPrivacy,
                  onChanged: notifier.toggleScreenshotPrivacy,
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
