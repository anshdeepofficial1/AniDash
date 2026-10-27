import 'dart:io';

import 'package:dartotsu_extension_bridge/Settings/Settings.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'Aniyomi/AniyomiExtensions.dart';
import 'ExtensionManager.dart';
import 'Mangayomi/Eval/dart/model/source_preference.dart';
import 'Mangayomi/MangayomiExtensions.dart';
import 'Mangayomi/Models/Source.dart';

late Isar isar;
WebViewEnvironment? webViewEnvironment;

class DartotsuExtensionBridge {
  Future<void> init(Isar? isarInstance, String dirName) async {
    var document = await getDatabaseDirectory(dirName);
    if (isarInstance == null) {
      isar = Isar.openSync([
        MSourceSchema,
        SourcePreferenceSchema,
        SourcePreferenceStringValueSchema,
        BridgeSettingsSchema,
      ], directory: p.join(document.path, 'isar'));
    } else {
      isar = isarInstance;
    }
    final settings =
        await isar.bridgeSettings.filter().idEqualTo(26).findFirst();
    if (settings == null) {
      isar.writeTxnSync(
        () => isar.bridgeSettings.putSync(BridgeSettings()..id = 26),
      );
    }

    // Ensure default extension repos are present
    final currentSettings = isar.bridgeSettings.getSync(26)!;
    bool needsUpdate = false;
    const defaultAnimeRepos = [
      'https://raw.githubusercontent.com/Mallyd11/mangayomi-anime-extensions/main/anime_index.json',
      'https://raw.githubusercontent.com/m2k3a/mangayomi-extensions/main/anime_index.json',
    ];
    for (final repo in defaultAnimeRepos) {
      if (!currentSettings.mangayomiAnimeExtensions.contains(repo)) {
        currentSettings.mangayomiAnimeExtensions = [
          ...currentSettings.mangayomiAnimeExtensions,
          repo,
        ];
        needsUpdate = true;
      }
    }
    const defaultAniyomiRepos = [
      'https://raw.githubusercontent.com/msrofficial/anime-repo/repo/index.min.json',
      'https://kohiden.xyz/Kohi-den/extensions/raw/branch/main/index.min.json',
      'https://raw.githubusercontent.com/yuzono/anime-repo/repo/index.min.json',
      'https://raw.githubusercontent.com/Secozzi/aniyomi-extensions/refs/heads/repo/index.min.json',
    ];
    for (final repo in defaultAniyomiRepos) {
      if (!currentSettings.aniyomiAnimeExtensions.contains(repo)) {
        currentSettings.aniyomiAnimeExtensions = [
          ...currentSettings.aniyomiAnimeExtensions,
          repo,
        ];
        needsUpdate = true;
      }
    }
    const defaultAniyomiMangaRepos = [
      'https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json',
    ];
    for (final repo in defaultAniyomiMangaRepos) {
      if (!currentSettings.aniyomiMangaExtensions.contains(repo)) {
        currentSettings.aniyomiMangaExtensions = [
          ...currentSettings.aniyomiMangaExtensions,
          repo,
        ];
        needsUpdate = true;
      }
    }
    if (!currentSettings.mangayomiMangaExtensions.contains(
      'https://raw.githubusercontent.com/kodjodevf/mangayomi-extensions/main/index.json',
    )) {
      currentSettings.mangayomiMangaExtensions = [
        ...currentSettings.mangayomiMangaExtensions,
        'https://raw.githubusercontent.com/kodjodevf/mangayomi-extensions/main/index.json',
      ];
      needsUpdate = true;
    }
    if (needsUpdate) {
      isar.writeTxnSync(() => isar.bridgeSettings.putSync(currentSettings));
    }

    if (Platform.isAndroid) {
      Get.put(AniyomiExtensions(), tag: 'AniyomiExtensions');
    }
    Get.put(MangayomiExtensions(), tag: 'MangayomiExtensions');
    Get.put(ExtensionManager());
    if (Platform.isWindows) {
      final availableVersion = await WebViewEnvironment.getAvailableVersion();
      if (availableVersion != null) {
        webViewEnvironment = await WebViewEnvironment.create(
          settings: WebViewEnvironmentSettings(
            userDataFolder: p.join(document.path, 'flutter_inappwebview'),
          ),
        );
      }
    }
  }
}

Future<Directory> getDatabaseDirectory(String dirName) async {
  final dir = await getApplicationDocumentsDirectory();
  if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
    return dir;
  } else {
    String dbDir = p.join(dir.path, dirName, 'databases');
    await Directory(dbDir).create(recursive: true);
    return Directory(dbDir);
  }
}
