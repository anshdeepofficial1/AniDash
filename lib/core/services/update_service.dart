import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:install_plugin/install_plugin.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:ani_dash/core/network/http_client.dart';
import 'package:ani_dash/core/utils/app_logger.dart';

class UpdateInfo {
  final String version;
  final String downloadUrl;
  final String releaseNotes;
  final DateTime publishedAt;
  final String? sha256;

  UpdateInfo({
    required this.version,
    required this.downloadUrl,
    required this.releaseNotes,
    required this.publishedAt,
    this.sha256,
  });
}

class UpdateService {
  final UniversalHttpClient _httpClient = UniversalHttpClient.instance;

  Future<UpdateInfo?> checkForUpdate() async {
    try {
      final response = await _httpClient.get(
        Uri.parse(
          'https://api.github.com/repos/anshdeepofficial1/AniDash/releases/latest',
        ),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final tagName = data['tag_name'] as String;
        final releaseNotes = data['body'] as String;
        final publishedAt = DateTime.parse(data['published_at']);

        final assets = data['assets'] as List;
        if (assets.isEmpty) return null;

        dynamic matchedAsset;
        if (Platform.isAndroid) {
          matchedAsset = assets.firstWhere(
            (asset) => asset['name'].toString().toLowerCase().endsWith('.apk'),
            orElse: () => null,
          );
        } else if (Platform.isWindows) {
          matchedAsset = assets.firstWhere(
            (asset) {
              final name = asset['name'].toString().toLowerCase();
              return name.endsWith('.exe') ||
                  name.contains('windows-portable.zip') ||
                  name.endsWith('.zip');
            },
            orElse: () => null,
          );
        } else if (Platform.isMacOS) {
          matchedAsset = assets.firstWhere(
            (asset) {
              final name = asset['name'].toString().toLowerCase();
              return name.endsWith('.dmg') ||
                  name.contains('macos.zip') ||
                  name.endsWith('.zip');
            },
            orElse: () => null,
          );
        } else if (Platform.isLinux) {
          matchedAsset = assets.firstWhere(
            (asset) =>
                asset['name'].toString().toLowerCase().contains('linux.zip'),
            orElse: () => null,
          );
        }

        if (matchedAsset == null) return null;
        final downloadUrl = matchedAsset['browser_download_url'] as String;
        final digest = matchedAsset['digest']?.toString();

        final packageInfo = await PackageInfo.fromPlatform();
        final currentVersion = packageInfo.version;

        final cleanTagName = tagName.replaceAll('v', '');

        if (_isNewerVersion(currentVersion, cleanTagName)) {
          return UpdateInfo(
            version: cleanTagName,
            downloadUrl: downloadUrl,
            releaseNotes: releaseNotes,
            publishedAt: publishedAt,
            sha256:
                digest?.startsWith('sha256:') == true
                    ? digest!.substring('sha256:'.length).toLowerCase()
                    : null,
          );
        }
      }
    } catch (e) {
      AppLogger.e('Error checking for update: $e');
    }
    return null;
  }

  bool _isNewerVersion(String current, String latest) {
    final cleanCurrent =
        current
            .replaceAll(RegExp(r'^v'), '')
            .split('+')
            .first
            .split('-')
            .first
            .trim();
    final cleanLatest =
        latest
            .replaceAll(RegExp(r'^v'), '')
            .split('+')
            .first
            .split('-')
            .first
            .trim();

    final currentParts =
        cleanCurrent.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final latestParts =
        cleanLatest.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    while (currentParts.length < 3) {
      currentParts.add(0);
    }
    while (latestParts.length < 3) {
      latestParts.add(0);
    }

    for (int i = 0; i < 3; i++) {
      final c = currentParts[i];
      final l = latestParts[i];
      if (l > c) return true;
      if (l < c) return false;
    }

    int getBuild(String s) {
      if (s.contains('+')) return int.tryParse(s.split('+').last) ?? 0;
      if (s.contains('-')) return int.tryParse(s.split('-').last) ?? 0;
      return 0;
    }

    final lBuild = getBuild(latest);
    final cBuild = getBuild(current);
    if (lBuild > 0 && cBuild > 0) {
      return lBuild > cBuild;
    }

    return false;
  }

  Future<void> downloadAndInstallUpdate(
    String url, {
    String? expectedSha256,
    void Function(int receivedBytes, int totalBytes)? onProgress,
  }) async {
    if (!Platform.isAndroid) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      return;
    }

    final client = http.Client();
    try {
      final tempDir = await getTemporaryDirectory();
      final savePath = '${tempDir.path}/update.apk';
      final file = File(savePath);
      if (await file.exists()) {
        await file.delete();
      }

      final request = http.Request('GET', Uri.parse(url));
      request.headers['User-Agent'] =
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';
      final streamedResponse = await client.send(request);

      if (streamedResponse.statusCode >= 200 &&
          streamedResponse.statusCode < 300) {
        final totalBytes = streamedResponse.contentLength ?? 0;
        int receivedBytes = 0;

        final sink = file.openWrite();
        await for (final chunk in streamedResponse.stream) {
          sink.add(chunk);
          receivedBytes += chunk.length;
          onProgress?.call(receivedBytes, totalBytes);
        }

        await sink.flush();
        await sink.close();

        if (expectedSha256 == null || expectedSha256.trim().isEmpty) {
          await file.delete();
          throw const FormatException(
            'The release does not provide an APK SHA-256 digest.',
          );
        }
        final actualSha256 =
            sha256.convert(await file.readAsBytes()).toString();
        if (actualSha256.toLowerCase() != expectedSha256.toLowerCase()) {
          await file.delete();
          throw const FormatException('Downloaded APK integrity check failed.');
        }

        await InstallPlugin.install(savePath);
      } else {
        throw 'HTTP status ${streamedResponse.statusCode}';
      }
    } catch (e) {
      AppLogger.e('Error downloading/installing update: $e');
      rethrow;
    } finally {
      client.close();
    }
  }
}
