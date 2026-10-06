// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ani_dash/core/network/http_client.dart';
import 'package:ani_dash/core/utils/app_logger.dart';
import 'package:ani_dash/main.dart';
import 'package:ani_dash/core/utils/update_dialog.dart';

enum UpdateType { stable, beta, alpha, hotfix }

Future<void> checkForUpdates(
  BuildContext context, {
  bool debugMode = false,
  bool isManual = false,
  bool includeBeta = false,
  bool includeAlpha = false,
  bool useTestReleases = false,
}) async {
  try {
    final repo =
        useTestReleases
            ? 'anshdeepofficial1/Anidash-test-releases'
            : 'anshdeepofficial1/AniDash';

    final pageSize = (includeBeta || includeAlpha) ? 5 : 1;
    final url = Uri.parse(
      'https://api.github.com/repos/$repo/releases?per_page=$pageSize',
    );

    final response = await UniversalHttpClient.instance.get(
      url,
      headers: {
        'Accept': 'application/vnd.github.v3+json',
        'User-Agent': 'AniDash',
      },
    );

    if (response.statusCode != 200) {
      AppLogger.w('Failed to fetch releases: ${response.statusCode}');
      return;
    }

    final dynamic decoded = jsonDecode(response.body);
    if (decoded is! List || decoded.isEmpty) return;

    final List<dynamic> releases = decoded;

    final latestRelease = releases.firstWhere((rel) {
      final tag = (rel['tag_name'] as String).toLowerCase();
      final isPrerelease = rel['prerelease'] as bool;

      if (!isPrerelease) return true;
      if (tag.contains('hotfix')) return true;
      if (includeBeta && tag.contains('beta')) return true;
      if (includeAlpha && tag.contains('alpha')) return true;
      if (useTestReleases && tag.contains('test')) return true;

      return false;
    }, orElse: () => null);

    if (latestRelease == null) return;

    final tagName = latestRelease['tag_name'] ?? '0.0.0';
    final isPrerelease = latestRelease['prerelease'] ?? false;
    final releaseNotes = latestRelease['body'] ?? '';
    final updateType = _determineUpdateType(tagName, isPrerelease);

    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = '${packageInfo.version}-${packageInfo.buildNumber}';

    if (debugMode) {
      AppLogger.d('Latest: $tagName | Current: $currentVersion');
    }

    bool isNewer = _isNewerVersion(tagName, currentVersion);

    if (!isManual && !debugMode) {
      final preferences = await SharedPreferences.getInstance();
      final cleanLatest = tagName.replaceAll(RegExp(r'^v'), '').trim();
      final remindAfter = preferences.getInt('remind_update_after') ?? 0;
      final remindVersion = preferences.getString('remind_update_version');
      if (remindVersion == cleanLatest &&
          DateTime.now().millisecondsSinceEpoch < remindAfter) {
        return;
      }
    }

    if (debugMode || isNewer) {
      final assets = latestRelease['assets'] as List<dynamic>;
      final selectedAsset = _getPlatformSpecificAsset(assets);

      if (!context.mounted) return;

      showUpdateBottomSheet(
        context,
        tagName,
        currentVersion,
        updateType,
        releaseNotes: releaseNotes,
        apkDownloadUrl: selectedAsset?.url,
        apkSha256: selectedAsset?.sha256,
      );
    } else if (debugMode) {
      showAppSnackBar('No updates', 'You are on the latest allowed version');
    }
  } catch (e) {
    AppLogger.w('Failed to check for updates: $e');
  }
}

({String url, String? sha256})? _getPlatformSpecificAsset(
  List<dynamic> assets,
) {
  ({String url, String? sha256}) value(dynamic asset) {
    final digest = asset['digest']?.toString();
    return (
      url: asset['browser_download_url'] as String,
      sha256:
          digest?.startsWith('sha256:') == true
              ? digest!.substring('sha256:'.length).toLowerCase()
              : null,
    );
  }

  if (Platform.isAndroid) {
    // 1. First look for arm64-v8a specific apk if available
    for (final a in assets) {
      final name = (a['name'] as String).toLowerCase();
      if (name.contains('arm64') && name.endsWith('.apk')) return value(a);
    }
    // 2. Fallback to any apk (such as app-release.apk)
    for (final a in assets) {
      final name = (a['name'] as String).toLowerCase();
      if (name.endsWith('.apk')) return value(a);
    }
  }

  if (Platform.isWindows) {
    // 1. Prefer Setup installer exe
    for (final a in assets) {
      final name = (a['name'] as String).toLowerCase();
      if (name.endsWith('-setup.exe') || (name.endsWith('.exe') && !name.contains('portable'))) {
        return value(a);
      }
    }
    // 2. Fallback to any windows asset
    for (final a in assets) {
      final name = (a['name'] as String).toLowerCase();
      if (name.endsWith('.exe') || name.endsWith('.zip')) {
        return value(a);
      }
    }
  }

  for (final a in assets) {
    final name = (a['name'] as String).toLowerCase();
    if (Platform.isLinux && name.contains('linux.zip')) return value(a);
    if (Platform.isMacOS &&
        (name.endsWith('.dmg') ||
            name.contains('macos.zip') ||
            name.contains('darwin.zip') ||
            name.endsWith('.zip'))) {
      return value(a);
    }
  }
  return null;
}

UpdateType _determineUpdateType(String tag, bool prerelease) {
  final lowerTag = tag.toLowerCase();
  if (lowerTag.contains('hotfix')) return UpdateType.hotfix;
  if (lowerTag.contains('beta')) return UpdateType.beta;
  if (lowerTag.contains('alpha') || lowerTag.contains('test'))
    return UpdateType.alpha;
  return UpdateType.stable;
}

bool _isNewerVersion(String latestTag, String currentVersion) {
  final cleanLatest =
      latestTag
          .replaceAll(RegExp(r'^v'), '')
          .split('+')
          .first
          .split('-')
          .first
          .trim();
  final cleanCurrent =
      currentVersion
          .replaceAll(RegExp(r'^v'), '')
          .split('+')
          .first
          .split('-')
          .first
          .trim();

  final lParts =
      cleanLatest.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  final cParts =
      cleanCurrent.split('.').map((e) => int.tryParse(e) ?? 0).toList();

  while (lParts.length < 3) lParts.add(0);
  while (cParts.length < 3) cParts.add(0);

  for (int i = 0; i < 3; i++) {
    if (lParts[i] > cParts[i]) return true;
    if (lParts[i] < cParts[i]) return false;
  }

  // If major.minor.patch are identical, check build numbers if available
  int getBuild(String s) {
    if (s.contains('+')) return int.tryParse(s.split('+').last) ?? 0;
    if (s.contains('-')) return int.tryParse(s.split('-').last) ?? 0;
    return 0;
  }

  final lBuild = getBuild(latestTag);
  final cBuild = getBuild(currentVersion);
  if (lBuild > 0 && cBuild > 0) {
    return lBuild > cBuild;
  }

  return false;
}

Future<void> showUpdateBottomSheet(
  BuildContext context,
  String latestVersion,
  String currentVersion,
  UpdateType type, {
  String? releaseNotes,
  String? apkDownloadUrl,
  String? apkSha256,
}) {
  return showGeneralDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder:
        (context, animation, secondaryAnimation) => UpdateDialog(
          latestVersion: latestVersion,
          currentVersion: currentVersion,
          type: type,
          releaseNotes: releaseNotes,
          apkDownloadUrl: apkDownloadUrl,
          apkSha256: apkSha256,
        ),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curvedAnimation = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );

      return FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.05),
            end: Offset.zero,
          ).animate(curvedAnimation),
          child: child,
        ),
      );
    },
  );
}
