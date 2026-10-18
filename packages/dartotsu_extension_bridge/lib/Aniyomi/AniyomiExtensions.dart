import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dartotsu_extension_bridge/dartotsu_extension_bridge.dart';
import 'package:device_apps/device_apps.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get/get_rx/src/rx_types/rx_types.dart';
import 'package:http/http.dart' as http;
import 'package:install_plugin/install_plugin.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class AniyomiExtensions extends Extension {
  static const int _maxApkBytes = 50 * 1024 * 1024;
  AniyomiExtensions() {
    initialize();
  }

  static const platform = MethodChannel('aniyomiExtensionBridge');
  final Rx<List<Source>> availableAnimeExtensionsUnmodified = Rx([]);
  final Rx<List<Source>> availableMangaExtensionsUnmodified = Rx([]);
  final Rx<List<Source>> availableNovelExtensionsUnmodified = Rx([]);

  @override
  bool get supportsNovel => false;

  @override
  Future<void> initialize() async {
    if (isInitialized.value) return;
    isInitialized.value = true;
    var settings = isar.bridgeSettings.getSync(26)!;
    getInstalledAnimeExtensions();
    getInstalledMangaExtensions();
    getInstalledNovelExtensions();
    fetchAvailableAnimeExtensions(settings.aniyomiAnimeExtensions);
    fetchAvailableMangaExtensions(settings.aniyomiMangaExtensions);
  }

  @override
  Future<List<Source>> fetchAvailableAnimeExtensions(List<String>? repos) =>
      _fetchAvailable('fetchAnimeExtensions', ItemType.anime, repos);

  @override
  Future<List<Source>> fetchAvailableMangaExtensions(List<String>? repos) =>
      _fetchAvailable('fetchMangaExtensions', ItemType.manga, repos);

  Future<List<Source>> _fetchAvailable(
    String method,
    ItemType type,
    List<String>? repos,
  ) async {
    final settings = isar.bridgeSettings.getSync(26)!;

    switch (type) {
      case ItemType.anime:
        settings.aniyomiAnimeExtensions = repos ?? [];
        break;
      case ItemType.manga:
        settings.aniyomiMangaExtensions = repos ?? [];
        break;
      case ItemType.novel:
        break;
    }
    isar.writeTxnSync(() => isar.bridgeSettings.putSync(settings));

    // Native AniYomi bridge returns sources from multiple JSON indexes as
    // one list, losing which repository each item came from. Fetch each index
    // separately so the repository drawer can correctly filter its children.
    final sources = <Source>[];
    for (final repo in (repos ?? <String>[]).toSet()) {
      if (repo.trim().isEmpty) continue;
      try {
        final loaded = await _loadExtensions(method, repos: [repo]);
        for (final source in loaded) {
          source.repo = repo;
          if (source.apkUrl == null || source.apkUrl!.isEmpty) {
            final cleanRepo = repo
                .replaceAll('/index.min.json', '')
                .replaceAll('index.min.json', '')
                .trimRight();
            final apkName = source.apkName;
            if (apkName != null && apkName.isNotEmpty) {
              source.apkUrl = '$cleanRepo/apk/$apkName';
            }
          }
          sources.add(source);
        }
      } catch (error) {
        debugPrint('Could not load AniYomi repository $repo: $error');
      }
    }
    final installedIds = getInstalledRx(type).value.map((e) => e.id).toSet();

    final unmodifiedList =
        sources.map((e) {
          var map = e.toJson();
          map['extensionType'] = 1;
          return Source.fromJson(map);
        }).toList();
    final list =
        unmodifiedList.where((s) => !installedIds.contains(s.id)).toList();
    getAvailableRx(type).value = list;
    getAvailableUnmodified(type).value = unmodifiedList;
    checkForUpdates(type);
    return list;
  }

  @override
  Future<List<Source>> getInstalledAnimeExtensions() {
    return _getInstalled('getInstalledAnimeExtensions', ItemType.anime);
  }

  @override
  Future<List<Source>> getInstalledMangaExtensions() {
    return _getInstalled('getInstalledMangaExtensions', ItemType.manga);
  }

  Future<List<Source>> _getInstalled(String method, ItemType type) async {
    final sources = await _loadExtensions(method);
    getInstalledRx(type).value = sources;
    checkForUpdates(type);
    return sources;
  }

  Future<List<Source>> _loadExtensions(
    String method, {
    List<String>? repos,
  }) async {
    try {
      final List<dynamic> result = await platform.invokeMethod(method, repos);
      final parsed = await compute(_parseSources, result);
      return parsed;
    } catch (e) {
      return [];
    }
  }

  static List<Source> _parseSources(List<dynamic> data) {
    return data.map((e) {
      final map = Map<String, dynamic>.from(e);
      map['apkUrl'] = getAnimeApkUrl(
        map['iconUrl'] ?? '',
        map['apkName'] ?? '',
      );
      map['extensionType'] = 1;
      return Source.fromJson(map);
    }).toList();
  }

  @override
  Future<void> installSource(Source source) async {
    String? apkUrl = source.apkUrl;
    if (apkUrl == null || apkUrl.isEmpty) {
      if (source.repo != null &&
          source.apkName != null &&
          source.apkName!.isNotEmpty) {
        final cleanRepo = source.repo!
            .replaceAll('/index.min.json', '')
            .replaceAll('index.min.json', '')
            .trimRight();
        apkUrl = '$cleanRepo/apk/${source.apkName}';
        source.apkUrl = apkUrl;
      }
    }
    if (apkUrl == null || apkUrl.isEmpty) {
      return Future.error('Source APK URL is required for installation.');
    }

    try {
      final apkName = apkUrl.split('/').last;
      final packageName =
          source.id?.trim().isNotEmpty == true
              ? source.id!
              : apkName.replaceAll('.apk', '');

      final tempDir = await getTemporaryDirectory();
      final apkFileName = apkName.endsWith('.apk') ? apkName : '$apkName.apk';
      final apkFile = File(path.join(tempDir.path, apkFileName));
      await _downloadVerifiedApk(source, apkFile);

      final result = await InstallPlugin.installApk(
        apkFile.path,
        appId: packageName,
      );

      // Keep APK temporarily on disk so the system PackageInstaller can read it
      Future.delayed(const Duration(minutes: 5), () async {
        try {
          if (await apkFile.exists()) {
            await apkFile.delete();
          }
        } catch (_) {}
      });

      if (result['isSuccess'] != true) {
        throw Exception(
          'Installation failed: ${result['errorMessage'] ?? 'Unknown error'}',
        );
      }
      final rx = getAvailableRx(source.itemType!);
      rx.value = rx.value.where((s) => s.id != source.id).toList();
      switch (source.itemType) {
        case ItemType.anime:
          await getInstalledAnimeExtensions();
          break;
        case ItemType.manga:
          await getInstalledMangaExtensions();
          break;
        case ItemType.novel:
          break;
        default:
          throw Exception('Unsupported item type: ${source.itemType}');
      }
      debugPrint('Successfully initiated install for package: $packageName');
    } catch (e) {
      if (kDebugMode) {
        print('Error installing source: $e');
      }
      rethrow;
    }
  }

  @override
  Future<void> uninstallSource(Source source) async {
    final packageName = source.id;
    if (packageName == null || packageName.isEmpty) {
      throw Exception('Source ID is required for uninstallation.');
    }

    try {
      final isInstalled = await DeviceApps.isAppInstalled(packageName);
      if (!isInstalled) {
        _removeFromInstalledList(source);
        return;
      }

      final success = await DeviceApps.uninstallApp(packageName);
      if (!success) {
        throw Exception('Failed to initiate uninstallation for: $packageName');
      }

      final timeout = const Duration(seconds: 10);
      final start = DateTime.now();

      while (DateTime.now().difference(start) < timeout) {
        final stillInstalled = await DeviceApps.isAppInstalled(packageName);
        if (!stillInstalled) break;
        await Future.delayed(const Duration(milliseconds: 500));
      }

      final finalCheck = await DeviceApps.isAppInstalled(packageName);
      if (finalCheck) {
        throw Exception('Uninstallation timed out or was cancelled by user.');
      }

      _removeFromInstalledList(source);

      final itemType = source.itemType;
      if (itemType != null) {
        final availableList = getAvailableUnmodified(itemType).value;
        if (availableList.any((s) => s.id == packageName)) {
          getAvailableRx(itemType).update((list) => list?..add(source));
        }
      }

      debugPrint('Successfully uninstalled package: $packageName');
    } catch (e) {
      debugPrint('Error uninstalling $packageName: $e');
      rethrow;
    }
  }

  @override
  Future<void> updateSource(Source source) async {
    String? apkUrl = source.apkUrl;
    if (apkUrl == null || apkUrl.isEmpty) {
      if (source.repo != null &&
          source.apkName != null &&
          source.apkName!.isNotEmpty) {
        final cleanRepo = source.repo!
            .replaceAll('/index.min.json', '')
            .replaceAll('index.min.json', '')
            .trimRight();
        apkUrl = '$cleanRepo/apk/${source.apkName}';
        source.apkUrl = apkUrl;
      }
    }
    if (apkUrl == null || apkUrl.isEmpty) {
      return Future.error('Source APK URL is required for installation.');
    }

    try {
      final apkName = apkUrl.split('/').last;
      final packageName =
          source.id?.trim().isNotEmpty == true
              ? source.id!
              : apkName.replaceAll('.apk', '');

      final tempDir = await getTemporaryDirectory();
      final apkFileName = '$packageName.apk';
      final apkFile = File(path.join(tempDir.path, apkFileName));

      await _downloadVerifiedApk(source, apkFile);

      final result = await InstallPlugin.installApk(
        apkFile.path,
        appId: packageName,
      );
      if (result['isSuccess'] != true) {
        debugPrint(
          'Installation failed: ${result['errorMessage'] ?? 'Unknown error'}',
        );
      }
      Future.delayed(const Duration(minutes: 5), () async {
        try {
          if (await apkFile.exists()) {
            await apkFile.delete();
          }
        } catch (_) {}
      });

      switch (source.itemType) {
        case ItemType.anime:
          getInstalledAnimeExtensions(); // because it also update extension on kotlin side
          break;
        case ItemType.manga:
          getInstalledMangaExtensions();
          break;
        case ItemType.novel:
          break;
        default:
          throw Exception('Unsupported item type: ${source.itemType}');
      }
      debugPrint('Successfully update package: $packageName');
    } catch (e) {
      if (kDebugMode) {
        print('Error installing source: $e');
      }
      rethrow;
    }
  }

  Future<void> _downloadVerifiedApk(Source source, File destination) async {
    final expected = source.apkSha256?.trim().toLowerCase();
    final hasExpectedChecksum = expected != null && expected.isNotEmpty;
    if (hasExpectedChecksum && !RegExp(r'^[a-f0-9]{64}$').hasMatch(expected)) {
      throw StateError(
        'This external extension published an invalid SHA-256 checksum format.',
      );
    }

    final client = http.Client();
    IOSink? sink;
    try {
      final uri = Uri.tryParse(source.apkUrl ?? '');
      if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https'))) {
        throw StateError('Invalid APK download URL: ${source.apkUrl}');
      }
      final request = http.Request('GET', uri);
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 40));
      if (response.statusCode != 200) {
        throw HttpException(
          'APK download returned HTTP ${response.statusCode}',
        );
      }
      final declaredLength = response.contentLength;
      if (declaredLength != null && declaredLength > _maxApkBytes) {
        throw StateError('Extension APK exceeds the 50 MB safety limit.');
      }

      var received = 0;
      sink = destination.openWrite();
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 40),
      )) {
        received += chunk.length;
        if (received > _maxApkBytes) {
          throw StateError('Extension APK exceeds the 50 MB safety limit.');
        }
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();
      sink = null;

      if (hasExpectedChecksum) {
        final actual =
            (await sha256.bind(destination.openRead()).first).toString();
        if (actual.toLowerCase() != expected.toLowerCase()) {
          throw StateError('Extension APK checksum verification failed.');
        }
      }
    } finally {
      await sink?.close();
      client.close();
      if (destination.existsSync() && destination.lengthSync() == 0) {
        await destination.delete();
      }
    }
  }

  void _removeFromInstalledList(Source source) {
    switch (source.itemType) {
      case ItemType.anime:
        installedAnimeExtensions.value =
            installedAnimeExtensions.value
                .where((e) => e.name != source.name)
                .toList();
        break;
      case ItemType.manga:
        installedMangaExtensions.value =
            installedMangaExtensions.value
                .where((e) => e.name != source.name)
                .toList();
        break;
      case ItemType.novel:
        installedNovelExtensions.value =
            installedNovelExtensions.value
                .where((e) => e.name != source.name)
                .toList();
        break;
      case null:
        break;
    }
  }

  Rx<List<Source>> getAvailableUnmodified(ItemType type) {
    switch (type) {
      case ItemType.anime:
        return availableAnimeExtensionsUnmodified;
      case ItemType.manga:
        return availableMangaExtensionsUnmodified;
      case ItemType.novel:
        return availableNovelExtensionsUnmodified;
    }
  }

  Future<void> checkForUpdates(ItemType type) async {
    final availableMap = {
      for (var s in getAvailableUnmodified(type).value) s.id: s,
    };

    final updated =
        getInstalledRx(type).value.map((installed) {
          final avail = availableMap[installed.id ?? ''];
          if (avail != null &&
              installed.version != null &&
              avail.version != null &&
              compareVersions(installed.version!, avail.version!) < 0) {
            return installed
              ..hasUpdate = true
              ..apkUrl = avail.apkUrl
              ..versionLast = avail.version;
          }
          return installed;
        }).toList();

    getInstalledRx(type).value = updated;
  }

  static String getAnimeApkUrl(String iconUrl, String apkName) {
    if (iconUrl.isEmpty || apkName.isEmpty) return "";

    final baseUrl = iconUrl.replaceFirst('icon/', 'apk/');
    final lastSlash = baseUrl.lastIndexOf('/');
    if (lastSlash == -1) return "";

    final cleanedUrl = baseUrl.substring(0, lastSlash);
    return '$cleanedUrl/$apkName';
  }
}
