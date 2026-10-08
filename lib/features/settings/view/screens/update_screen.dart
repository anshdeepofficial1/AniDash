import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:ani_dash/features/settings/view/widgets/settings_item.dart';
import 'package:ani_dash/features/settings/view/widgets/settings_section.dart';
import 'package:ani_dash/shared/providers/settings/update_settings_notifier.dart';
import 'package:ani_dash/shared/providers/permissions_provider.dart';
import 'package:ani_dash/core/models/settings/update_settings_model.dart';
import 'package:ani_dash/core/services/update_service.dart';
import 'package:ani_dash/core/services/notification_service.dart';
import 'package:ani_dash/core/utils/updater.dart';
import 'package:ani_dash/shared/ui/brand_logo.dart';

class UpdateScreen extends ConsumerStatefulWidget {
  const UpdateScreen({super.key});

  @override
  ConsumerState<UpdateScreen> createState() => _UpdateScreenState();
}

class _UpdateScreenState extends ConsumerState<UpdateScreen> {
  final UpdateService _updateService = UpdateService();
  bool _isChecking = false;
  UpdateInfo? _availableUpdate;
  DateTime? _lastCheckedTime;
  String _currentVersion = '...';

  @override
  void initState() {
    super.initState();
    _loadCurrentVersion();
  }

  Future<void> _loadCurrentVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _currentVersion = packageInfo.version;
      });
    }
  }

  Future<void> _checkForUpdate() async {
    setState(() {
      _isChecking = true;
    });

    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version;
    final updateInfo = await _updateService.checkForUpdate();

    if (!mounted) return;
    setState(() {
      _isChecking = false;
      _currentVersion = currentVersion;
      _lastCheckedTime = DateTime.now();
      _availableUpdate = updateInfo;
    });

    if (updateInfo != null) {
      try {
        await NotificationService().showUpdateAvailableNotification(
          updateInfo.version,
        );
      } catch (_) {}
      if (!mounted) return;
      showUpdateBottomSheet(
        context,
        updateInfo.version,
        currentVersion,
        UpdateType.stable,
        releaseNotes: updateInfo.releaseNotes,
        apkDownloadUrl: updateInfo.downloadUrl,
        apkSha256: updateInfo.sha256,
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('AniDash is completely up to date!'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  String _getPlatformName() {
    if (Platform.isWindows) return 'Windows (x64)';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isLinux) return 'Linux';
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    return 'Desktop';
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(updateSettingsProvider);
    final notifier = ref.read(updateSettingsProvider.notifier);
    final permissionsState = ref.watch(permissionsProvider);
    final permissionsNotifier = ref.read(permissionsProvider.notifier);
    final colorScheme = Theme.of(context).colorScheme;
    final isDesktop = MediaQuery.sizeOf(context).width > 700 ||
        Platform.isWindows ||
        Platform.isMacOS ||
        Platform.isLinux;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        leading: IconButton.filledTonal(
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/');
            }
          },
          icon: const Icon(Iconsax.arrow_left_2),
        ),
        title: const Text('Check for Updates'),
        forceMaterialTransparency: true,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: isDesktop ? 860 : 600),
          child: ListView(
            padding: EdgeInsets.symmetric(
              horizontal: isDesktop ? 20 : 12,
              vertical: 8,
            ),
            children: [
              // 1. Desktop-grade Hero Card
              _buildDesktopHeroCard(context, colorScheme, isDesktop),

              const SizedBox(height: 18),

              // 2. Available Update Card (if one was discovered)
              if (_availableUpdate != null) ...[
                _buildAvailableUpdateCard(context, colorScheme),
                const SizedBox(height: 18),
              ],

              // Mobile-only Android permission banner
              if (Platform.isAndroid && !permissionsState.notification) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Iconsax.warning_2, color: Colors.amber, size: 28),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Notification Permission Needed',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Allow notifications so AniDash can alert you when updates are ready.',
                              style: TextStyle(fontSize: 11, color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.tonal(
                        onPressed: () async {
                          await permissionsNotifier.requestNotificationPermission();
                        },
                        child: const Text('Allow'),
                      ),
                    ],
                  ),
                ),
              ],

              // 3. Automation and Schedule Section
              SettingsSection(
                title: 'Background Update Automation',
                titleColor: colorScheme.primary,
                children: [
                  ToggleableSettingsItem(
                    icon: Icon(Iconsax.refresh_2, color: colorScheme.primary),
                    accent: colorScheme.primary,
                    title: 'Auto-Check for Updates',
                    description: isDesktop
                        ? 'Silently check GitHub releases in the background while running'
                        : 'Periodically check GitHub releases for new updates',
                    value: settings.autoCheckEnabled,
                    onChanged: (value) async {
                      if (value && Platform.isAndroid && !permissionsState.notification) {
                        await permissionsNotifier.requestNotificationPermission();
                      }
                      notifier.updateSettings(
                        (state) => state.copyWith(autoCheckEnabled: value),
                      );
                    },
                  ),
                  if (settings.autoCheckEnabled) ...[
                    ToggleableSettingsItem(
                      icon: Icon(Iconsax.clock, color: colorScheme.primary),
                      accent: colorScheme.primary,
                      title: 'Run 24 Hours',
                      description: settings.fullDay
                          ? 'Checking continuously throughout the day (Custom window disabled)'
                          : 'Continuously check for updates round the clock',
                      value: settings.fullDay,
                      onChanged: (value) {
                        notifier.updateSettings(
                          (state) => state.copyWith(
                            fullDay: value,
                            startHour:
                                state.startHour == state.endHour
                                    ? 20
                                    : state.startHour,
                            endHour:
                                state.startHour == state.endHour
                                    ? 6
                                    : state.endHour,
                          ),
                        );
                      },
                    ),
                    SliderSettingsItem(
                      icon: Icon(Iconsax.timer_1, color: colorScheme.primary),
                      accent: colorScheme.primary,
                      title: 'Check Interval',
                      description:
                          'Checks approximately every ${settings.checkIntervalMinutes} minutes',
                      value: settings.checkIntervalMinutes.toDouble(),
                      min: 5,
                      max: 60,
                      divisions: 11,
                      onChanged: (value) {
                        notifier.updateSettings(
                          (state) =>
                              state.copyWith(checkIntervalMinutes: value.toInt()),
                        );
                      },
                    ),
                    _buildCustomTimeItem(
                      context: context,
                      colorScheme: colorScheme,
                      title: 'Custom Window: Start Hour',
                      hour: settings.startHour,
                      is24HourMode: settings.fullDay,
                      onTap: () => _pickStartHour(context, settings, notifier),
                    ),
                    _buildCustomTimeItem(
                      context: context,
                      colorScheme: colorScheme,
                      title: 'Custom Window: End Hour',
                      hour: settings.endHour,
                      is24HourMode: settings.fullDay,
                      onTap: () => _pickEndHour(context, settings, notifier),
                    ),
                  ],
                ],
              ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopHeroCard(
    BuildContext context,
    ColorScheme colorScheme,
    bool isDesktop,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: EdgeInsets.all(isDesktop ? 22 : 16),
      decoration: BoxDecoration(
        color: isDark
            ? colorScheme.surfaceContainerHigh.withValues(alpha: 0.6)
            : colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.05),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: colorScheme.primary.withValues(alpha: 0.3),
                    width: 1.5,
                  ),
                ),
                child: Center(
                  child: BrandLogo(size: 48, borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'AniDash for ${_getPlatformName()}',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: isDesktop ? 18 : 16,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: colorScheme.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Stable Channel',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Installed Version: v$_currentVersion • Native Release',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: _availableUpdate != null
                                ? Colors.amber
                                : Colors.greenAccent.shade700,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _availableUpdate != null
                              ? 'Update available (v${_availableUpdate!.version})'
                              : 'System is up to date',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: _availableUpdate != null
                                ? Colors.amber
                                : Colors.greenAccent.shade700,
                          ),
                        ),
                        if (_lastCheckedTime != null) ...[
                          Text(
                            ' • Checked ${_lastCheckedTime!.hour}:${_lastCheckedTime!.minute.toString().padLeft(2, '0')}',
                            style: TextStyle(
                              fontSize: 11,
                              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Divider(height: 1),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton.icon(
                onPressed: () => launchUrl(
                  Uri.parse('https://github.com/anshdeepofficial1/AniDash/releases'),
                ),
                icon: const Icon(Icons.code_rounded, size: 16),
                label: const Text('View Releases on GitHub'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: _isChecking ? null : _checkForUpdate,
                icon: _isChecking
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Iconsax.refresh_2, size: 16),
                label: Text(_isChecking ? 'Checking...' : 'Check for Updates'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAvailableUpdateCard(BuildContext context, ColorScheme colorScheme) {
    final theme = Theme.of(context);
    final update = _availableUpdate!;
    final isWindows = Platform.isWindows;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.4),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Iconsax.direct_up, color: colorScheme.primary, size: 24),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'AniDash ${update.version} Ready for Installation',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isWindows ? 'Windows .exe verified' : 'Official Update',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            "What's New in this Release:",
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            constraints: const BoxConstraints(maxHeight: 180),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surface.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
            child: SingleChildScrollView(
              child: MarkdownBody(
                data: update.releaseNotes.isNotEmpty
                    ? update.releaseNotes
                    : 'Performance improvements and bug fixes.',
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              FilledButton.icon(
                onPressed: () {
                  showUpdateBottomSheet(
                    context,
                    update.version,
                    _currentVersion,
                    UpdateType.stable,
                    releaseNotes: update.releaseNotes,
                    apkDownloadUrl: update.downloadUrl,
                    apkSha256: update.sha256,
                  );
                },
                icon: const Icon(Icons.download_rounded, size: 18),
                label: Text(
                  isWindows
                      ? 'Download & Install Windows .exe'
                      : 'Install Update Now',
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatHour(int hour) {
    final period = hour >= 12 ? 'PM' : 'AM';
    final h = hour % 12 == 0 ? 12 : hour % 12;
    return '$h:00 $period (${hour.toString().padLeft(2, '0')}:00)';
  }

  Widget _buildCustomTimeItem({
    required BuildContext context,
    required ColorScheme colorScheme,
    required String title,
    required int hour,
    required bool is24HourMode,
    required VoidCallback? onTap,
  }) {
    final timeStr = _formatHour(hour);
    final desc = is24HourMode ? '$timeStr • Disabled in 24-Hour mode' : timeStr;

    return Opacity(
      opacity: is24HourMode ? 0.45 : 1.0,
      child: IgnorePointer(
        ignoring: is24HourMode,
        child: NormalSettingsItem(
          icon: Icon(
            Iconsax.clock,
            color: is24HourMode ? Colors.grey : colorScheme.primary,
          ),
          accent: is24HourMode ? Colors.grey : colorScheme.primary,
          title: title,
          description: desc,
          onTap: is24HourMode ? null : onTap,
        ),
      ),
    );
  }

  Future<void> _pickStartHour(
    BuildContext context,
    UpdateSettingsModel settings,
    UpdateSettingsNotifier notifier,
  ) async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: settings.startHour, minute: 0),
      helpText: 'SELECT AUTO-CHECK START HOUR',
    );
    if (time == null || !context.mounted) return;

    if (time.hour == settings.endHour) {
      notifier.updateSettings(
        (state) => state.copyWith(fullDay: true, startHour: 20, endHour: 6),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '24-Hour schedule selected. Switched to 24-Hour Checking mode.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      notifier.updateSettings(
        (state) => state.copyWith(startHour: time.hour, fullDay: false),
      );
    }
  }

  Future<void> _pickEndHour(
    BuildContext context,
    UpdateSettingsModel settings,
    UpdateSettingsNotifier notifier,
  ) async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: settings.endHour, minute: 0),
      helpText: 'SELECT AUTO-CHECK END HOUR',
    );
    if (time == null || !context.mounted) return;

    if (time.hour == settings.startHour) {
      notifier.updateSettings(
        (state) => state.copyWith(fullDay: true, startHour: 20, endHour: 6),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '24-Hour schedule selected. Switched to 24-Hour Checking mode.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      notifier.updateSettings(
        (state) => state.copyWith(endHour: time.hour, fullDay: false),
      );
    }
  }
}
