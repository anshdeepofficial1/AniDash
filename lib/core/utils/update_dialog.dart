import 'dart:io';
import 'package:http/http.dart' as http;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'package:ani_dash/core/utils/updater.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateDialog extends StatefulWidget {
  final String latestVersion;
  final String currentVersion;
  final UpdateType type;
  final String? releaseNotes;
  final String? apkDownloadUrl;
  final String? apkSha256;

  const UpdateDialog({
    super.key,
    required this.latestVersion,
    required this.currentVersion,
    required this.type,
    this.releaseNotes,
    this.apkDownloadUrl,
    this.apkSha256,
  });

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog>
    with WidgetsBindingObserver {
  static const _installer = MethodChannel('anidash/updater');
  double _progress = 0.0;
  bool _downloading = false;
  String? _statusMessage;
  bool _error = false;
  String? _downloadedApkPath;
  bool _awaitingInstallPermission = false;

  final String _linuxCmd =
      'bash <(curl -fsSL https://raw.githubusercontent.com/anshdeepofficial1/AniDash/main/install.sh)';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _awaitingInstallPermission) {
      _awaitingInstallPermission = false;
      if (_downloadedApkPath != null && Platform.isAndroid) {
        _checkAndInstallAfterPermission();
      }
    }
  }

  Future<void> _checkAndInstallAfterPermission() async {
    final canInstall =
        await _installer.invokeMethod<bool>('canInstallPackages') ?? false;
    if (canInstall && _downloadedApkPath != null) {
      _launchInstaller(_downloadedApkPath!);
    }
  }

  String get _effectiveApkUrl {
    if (widget.apkDownloadUrl != null && widget.apkDownloadUrl!.isNotEmpty) {
      return widget.apkDownloadUrl!;
    }
    final tag =
        widget.latestVersion.startsWith('v')
            ? widget.latestVersion
            : 'v${widget.latestVersion}';
    final isBeta = tag.toLowerCase().contains('beta');
    if (Platform.isWindows) {
      return 'https://github.com/anshdeepofficial1/AniDash/releases/download/$tag/AniDash-$tag-Setup.exe';
    }
    if (Platform.isMacOS) {
      return 'https://github.com/anshdeepofficial1/AniDash/releases/download/$tag/AniDash-$tag.dmg';
    }
    final apkName =
        isBeta
            ? 'AniDash-Beta-$tag-Universal.apk'
            : 'AniDash-$tag-Universal.apk';
    return 'https://github.com/anshdeepofficial1/AniDash/releases/download/$tag/$apkName';
  }

  Future<void> _handleUpdateAction() async {
    if (Platform.isAndroid || Platform.isWindows || Platform.isMacOS) {
      final url = _effectiveApkUrl;
      await _downloadAndInstall(url);
    } else if (Platform.isLinux) {
      await Clipboard.setData(ClipboardData(text: _linuxCmd));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('Command copied! Paste it in your terminal.'),
          ),
        );
      }
    }
  }

  Future<void> _downloadAndInstall(String downloadUrl) async {
    setState(() {
      _downloading = true;
      _progress = 0;
      _statusMessage = "Starting download...";
      _error = false;
    });

    final client = http.Client();
    try {
      Directory? dir;
      if (Platform.isAndroid) {
        try {
          dir = await getExternalStorageDirectory();
        } catch (_) {}
      }
      dir ??= await getTemporaryDirectory();
      final ext = Platform.isWindows ? 'exe' : (Platform.isMacOS ? 'dmg' : 'apk');
      final savePath = '${dir.path}/AniDash-Update.$ext';
      final file = File(savePath);
      if (await file.exists()) await file.delete();

      final request = http.Request('GET', Uri.parse(downloadUrl));
      request.headers['User-Agent'] = 'AniDash';
      final response = await client.send(request);

      if (response.statusCode >= 400) {
        throw Exception('HTTP Error: ${response.statusCode}');
      }

      final contentLength = response.contentLength ?? -1;
      int received = 0;

      final sink = file.openWrite();

      try {
        await response.stream.forEach((chunk) {
          sink.add(chunk);
          received += chunk.length;

          if (mounted) {
            setState(() {
              if (contentLength > 0) {
                _progress = received / contentLength;
                final receivedMB = (received / (1024 * 1024)).toStringAsFixed(
                  1,
                );
                final totalMB = (contentLength / (1024 * 1024)).toStringAsFixed(
                  1,
                );
                _statusMessage =
                    "Downloading... ${(_progress * 100).toInt()}% ($receivedMB MB / $totalMB MB)";
              } else {
                final receivedMB = (received / (1024 * 1024)).toStringAsFixed(
                  1,
                );
                _statusMessage = "Downloading... $receivedMB MB";
              }
            });
          }
        });
        await sink.flush();
      } finally {
        await sink.close();
      }

      _downloadedApkPath = savePath;
      if (Platform.isAndroid) {
        final expected = widget.apkSha256?.trim().toLowerCase();
        if (expected == null || expected.isEmpty) {
          await file.delete();
          throw const FormatException(
            'This release has no verifiable APK SHA-256 digest.',
          );
        }
        final actual = sha256.convert(await file.readAsBytes()).toString();
        if (actual != expected) {
          await file.delete();
          throw const FormatException('APK integrity verification failed.');
        }
      }
      await _launchInstaller(savePath);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = true;
          _statusMessage = "Download failed. Check your connection.";
          _downloading = false;
        });
      }
    } finally {
      client.close();
    }
  }

  Future<void> _launchInstaller(String savePath) async {
    try {
      if (Platform.isWindows) {
        if (mounted) {
          setState(() {
            _downloading = false;
            _statusMessage = 'Launching Windows installer...';
          });
        }
        // Launch installer detached so it stays running after AniDash exits
        await Process.start(
          savePath,
          [],
          mode: ProcessStartMode.detached,
        );
        // Allow the installer process to spawn, then exit AniDash cleanly so files are not locked
        await Future.delayed(const Duration(milliseconds: 600));
        exit(0);
      }

      if (Platform.isMacOS) {
        if (mounted) {
          setState(() {
            _downloading = false;
            _statusMessage = 'Opening macOS update image...';
          });
        }
        await Process.run('open', [savePath]);
        if (mounted) {
          Navigator.of(context).pop();
        }
        return;
      }

      final canInstall =
          await _installer.invokeMethod<bool>('canInstallPackages') ?? false;
      if (!canInstall) {
        _awaitingInstallPermission = true;
        await _installer.invokeMethod<bool>('openInstallPermission');
        if (!mounted) return;
        setState(() {
          _downloading = false;
          _statusMessage =
              'Allow installs from AniDash, return here, then tap Install Update.';
        });
        return;
      }

      if (mounted) {
        setState(() {
          _downloading = false;
          _statusMessage = 'Opening Android installer...';
        });
      }
      final success = await _installer.invokeMethod<bool>('installApk', {
        'path': savePath,
      });
      if (success != true && mounted) {
        setState(() {
          _statusMessage =
              'Could not open installer. Tap Install Update again.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = true;
          _downloading = false;
          _statusMessage = 'Installer error: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isLinux = Platform.isLinux;

    final statusColor =
        widget.type == UpdateType.stable
            ? colorScheme.primary
            : widget.type == UpdateType.hotfix
            ? colorScheme.error
            : colorScheme.tertiary;

    final isDesktop = MediaQuery.sizeOf(context).width > 700 ||
        Platform.isWindows ||
        Platform.isMacOS ||
        Platform.isLinux;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 32 : 16,
        vertical: 24,
      ),
      child: Container(
        constraints: BoxConstraints(maxWidth: isDesktop ? 620 : 500),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
          border: isDesktop
              ? Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                  width: 1.2,
                )
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    onPressed:
                        () => launchUrl(
                          Uri.parse(
                            'https://github.com/anshdeepofficial1/AniDash/releases',
                          ),
                        ),
                    icon: const Icon(Icons.code_rounded, size: 18),
                    label: const Text('GitHub'),
                    style: TextButton.styleFrom(
                      foregroundColor: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),

            if (isDesktop) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: statusColor.withValues(alpha: 0.3),
                          width: 1.2,
                        ),
                      ),
                      child: Icon(
                        isLinux
                            ? Icons.terminal_rounded
                            : (Platform.isMacOS
                                ? Icons.apple_rounded
                                : Icons.desktop_windows_rounded),
                        size: 30,
                        color: statusColor,
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
                                'Software Update Available',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                              const SizedBox(width: 10),
                              _VersionBadge(
                                current: widget.currentVersion,
                                latest: widget.latestVersion,
                                type: widget.type,
                                color: statusColor,
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            Platform.isMacOS
                                ? 'A new native macOS DMG build is ready to install.'
                                : (Platform.isWindows
                                    ? 'A new Windows Setup installer is ready to update your app.'
                                    : 'A new official release is ready on GitHub.'),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isLinux
                            ? Icons.terminal_rounded
                            : Icons.rocket_launch_rounded,
                        size: 40,
                        color: statusColor,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      isLinux ? 'Update via Terminal' : 'Update Available',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _VersionBadge(
                      current: widget.currentVersion,
                      latest: widget.latestVersion,
                      type: widget.type,
                      color: statusColor,
                    ),
                  ],
                ),
              ),
            ],

            Flexible(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                  ),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isLinux) ...[
                        Text(
                          "Run this command:",
                          style: theme.textTheme.labelLarge,
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: colorScheme.outlineVariant),
                          ),
                          child: Text(
                            _linuxCmd,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                      Text(
                        "Release Notes & Changes",
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      MarkdownBody(
                        data:
                            widget.releaseNotes ?? "No release notes available.",
                        styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                          p: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurface,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  if (_statusMessage != null || _error) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            _statusMessage ?? "",
                            style: theme.textTheme.bodySmall?.copyWith(
                              color:
                                  _error
                                      ? colorScheme.error
                                      : colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        if (_downloading)
                          Text(
                            "${(_progress * 100).toInt()}%",
                            style: theme.textTheme.labelMedium,
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_downloading)
                      LinearProgressIndicator(
                        value: _progress,
                        borderRadius: BorderRadius.circular(8),
                        minHeight: 8,
                      ),
                    const SizedBox(height: 16),
                  ],
                  if (isDesktop) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        if (!_downloading && _downloadedApkPath == null)
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Remind Me Later'),
                          )
                        else
                          const SizedBox.shrink(),
                        Row(
                          children: [
                            OutlinedButton.icon(
                              onPressed: () => launchUrl(
                                Uri.parse(
                                  'https://github.com/anshdeepofficial1/AniDash/releases',
                                ),
                              ),
                              icon: const Icon(Icons.code_rounded, size: 16),
                              label: const Text('GitHub'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            FilledButton.icon(
                              icon: Icon(
                                isLinux
                                    ? Icons.content_copy_rounded
                                    : Icons.download_rounded,
                                size: 16,
                              ),
                              label: Text(
                                isLinux
                                    ? 'Copy Command'
                                    : (_downloading
                                        ? 'Downloading...'
                                        : (_downloadedApkPath != null
                                            ? 'Install Update'
                                            : (Platform.isWindows
                                                ? 'Download & Install Windows .exe'
                                                : (Platform.isMacOS
                                                    ? 'Download & Install macOS DMG'
                                                    : 'Update Now')))),
                              ),
                              onPressed:
                                  _downloading
                                      ? null
                                      : (_downloadedApkPath != null &&
                                              Platform.isAndroid
                                          ? () => _launchInstaller(
                                              _downloadedApkPath!,
                                            )
                                          : _handleUpdateAction),
                              style: FilledButton.styleFrom(
                                backgroundColor: statusColor,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ] else ...[
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        icon: Icon(
                          isLinux
                              ? Icons.content_copy_rounded
                              : Icons.download_rounded,
                        ),
                        label: Text(
                          isLinux
                              ? 'Copy Command'
                              : (_downloading
                                  ? 'Downloading...'
                                  : (_downloadedApkPath != null
                                      ? 'Install Update'
                                      : (Platform.isWindows
                                          ? 'Download & Install Windows .exe'
                                          : (Platform.isMacOS
                                              ? 'Download macOS .dmg'
                                              : 'Update Now')))),
                        ),
                        onPressed:
                            _downloading
                                ? null
                                : (_downloadedApkPath != null &&
                                        Platform.isAndroid
                                    ? () => _launchInstaller(_downloadedApkPath!)
                                    : _handleUpdateAction),
                        style: FilledButton.styleFrom(
                          backgroundColor: statusColor,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                    if (!_downloading && _downloadedApkPath == null) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.snooze_rounded, size: 16),
                              label: const Text('Remind in 1h'),
                              onPressed: () async {
                                final prefs =
                                    await SharedPreferences.getInstance();
                                await prefs.setInt(
                                  'remind_update_after',
                                  DateTime.now()
                                      .add(const Duration(hours: 1))
                                      .millisecondsSinceEpoch,
                                );
                                await prefs.setString(
                                  'remind_update_version',
                                  widget.latestVersion.replaceAll('v', '').trim(),
                                );
                                if (context.mounted) Navigator.pop(context);
                              },
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.today_rounded, size: 16),
                              label: const Text('Skip for today'),
                              onPressed: () async {
                                final prefs =
                                    await SharedPreferences.getInstance();
                                await prefs.setInt(
                                  'remind_update_after',
                                  DateTime.now()
                                      .add(const Duration(hours: 24))
                                      .millisecondsSinceEpoch,
                                );
                                await prefs.setString(
                                  'remind_update_version',
                                  widget.latestVersion.replaceAll('v', '').trim(),
                                );
                                if (context.mounted) Navigator.pop(context);
                              },
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VersionBadge extends StatelessWidget {
  final String current;
  final String latest;
  final UpdateType type;
  final Color color;

  const _VersionBadge({
    required this.current,
    required this.latest,
    required this.type,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final platformTag = Platform.isWindows
        ? 'Windows .exe'
        : (Platform.isMacOS
            ? 'macOS .dmg'
            : (Platform.isLinux ? 'Linux' : 'Android'));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        '${type.name.toUpperCase()} • $platformTag • $current → $latest',
        style: theme.textTheme.labelMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
