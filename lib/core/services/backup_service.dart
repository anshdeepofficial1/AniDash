import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:dartotsu_extension_bridge/dartotsu_extension_bridge.dart' as bridge;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:ani_dash/core/utils/app_logger.dart';
import 'package:ani_dash/core/repositories/watch_progress_repository.dart';
import 'package:ani_dash/data/hive/models/anime_watch_progress_model.dart';
import 'package:ani_dash/core/models/settings/content_settings_model.dart';
import 'package:ani_dash/core/models/settings/download_settings_model.dart';
import 'package:ani_dash/core/models/settings/experimental_model.dart';
import 'package:ani_dash/core/models/settings/player_model.dart';
import 'package:ani_dash/core/models/settings/theme_model.dart';
import 'package:ani_dash/core/models/settings/ui_model.dart';
import 'package:ani_dash/main.dart';
import 'package:ani_dash/shared/providers/permissions_provider.dart';
import 'package:ani_dash/storage_provider.dart';

final backupServiceProvider = Provider<BackupService>((ref) {
  return BackupService(ref);
});

class BackupService {
  final Ref _ref;

  BackupService(this._ref);

  static const String _progressBox = 'anime_watch_progress';

  Future<void> exportData({
    required bool includeWatchlist,
    required bool includeSettings,
  }) async {
    try {
      final Map<String, dynamic> dataPayload = {};

      if (includeWatchlist) {
        final progressBox = Hive.box<AnimeWatchProgressEntry>(_progressBox);
        dataPayload['watchlist'] = progressBox.toMap().map(
          (key, value) => MapEntry(key.toString(), value.toMap()),
        );
      }

      if (includeSettings) {
        final settingsData = <String, dynamic>{};

        void addSetting<T>(
          String key,
          String prefKey,
          Map<String, dynamic> Function(String) parser,
        ) {
          final jsonStr = sharedPrefs.getString(prefKey);
          if (jsonStr != null) {
            try {
              settingsData[key] = parser(jsonStr);
            } catch (_) {}
          }
        }

        addSetting(
          'theme',
          'theme_settings',
          (j) => ThemeModel.fromJson(j).toMap(),
        );
        addSetting(
          'download',
          'download_settings',
          (j) => DownloadSettingsModel.fromJson(j).toMap(),
        );
        addSetting(
          'player',
          'player_settings',
          (j) => PlayerModel.fromJson(j).toMap(),
        );
        addSetting('ui', 'ui_settings', (j) => UiSettings.fromJson(j).toMap());
        addSetting(
          'experimental',
          'experimental_settings',
          (j) => ExperimentalFeaturesModel.fromJson(j).toMap(),
        );
        addSetting(
          'content',
          'content_settings',
          (j) => ContentSettingsModel.fromJson(j).toMap(),
        );

        dataPayload['settings'] = settingsData;
        // Export repository indexes and source identities, not executable code
        // or downloaded APK files. Each source can be re-fetched safely.
        final sourceAssignments = <String, String>{};
        for (final key in sharedPrefs.getKeys()) {
          if (key.startsWith('extension_source_repo_')) {
            final repo = sharedPrefs.getString(key);
            if (repo != null) sourceAssignments[key] = repo;
          }
        }
        dataPayload['extensions'] = {
          'animeRepositories':
              sharedPrefs.getStringList('saved_anime_repos') ?? <String>[],
          'mangaRepositories':
              sharedPrefs.getStringList('saved_manga_repos') ?? <String>[],
          'sourceAssignments': sourceAssignments,
          'installedMangayomi': bridge.isar.mSources
              .where()
              .findAllSync()
              .where((source) => source.sourceId?.isNotEmpty == true)
              .map((source) => {
                    'id': source.sourceId,
                    'type': source.itemType.index,
                    'repo': source.repo,
                  })
              .toList(),
        };
      }

      final Map<String, dynamic> backupData = {
        'version': 1,
        'timestamp': DateTime.now().toIso8601String(),
        'data': dataPayload,
      };

      final jsonString = jsonEncode(backupData);
      final fileName =
          'AniDash_backup_${DateTime.now().millisecondsSinceEpoch}.json';

      if (Platform.isAndroid) {
        bool saved = false;
        try {
          final hasPermission =
              await _ref
                  .read(permissionsProvider.notifier)
                  .requestStoragePermission();

          if (hasPermission) {
            final dir = await StorageProvider.getDefaultDirectory();
            if (dir != null) {
              final file = File('${dir.path}/$fileName');
              await file.writeAsString(jsonString);
              AppLogger.i('Backup saved to ${file.path}');
              saved = true;
              return;
            }
          }
        } catch (err) {
          AppLogger.w(
            'Storage permission check failed or denied, sharing backup file: $err',
          );
        }

        if (!saved) {
          final tempDir = await getTemporaryDirectory();
          final file = File('${tempDir.path}/$fileName');
          await file.writeAsString(jsonString);
          await SharePlus.instance.share(
            ShareParams(files: [XFile(file.path)], text: 'AniDash Backup'),
          );
        }
      } else {
        final result = await FilePicker.saveFile(
          dialogTitle: 'Save Backup',
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: ['json'],
        );

        if (result != null) {
          final file = File(result);
          await file.writeAsString(jsonString);
          AppLogger.i('Backup saved to ${file.path}');
        }
      }
    } catch (e, s) {
      AppLogger.e('Failed to export data', e, s);
      rethrow;
    }
  }

  Future<void> importData() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result == null || result.files.single.path == null) return;

      final file = File(result.files.single.path!);
      final jsonString = await file.readAsString();
      final Map<String, dynamic> backupData = jsonDecode(jsonString);

      if (backupData['version'] != 1) {
        throw Exception('Unsupported backup version');
      }

      final data = backupData['data'] as Map<String, dynamic>? ?? {};

      if (data.containsKey('watchlist')) {
        final watchlistData = data['watchlist'] as Map<String, dynamic>;

        final Map<String, AnimeWatchProgressEntry> entries = {};
        for (var entry in watchlistData.entries) {
          try {
            entries[entry.key] = AnimeWatchProgressEntry.fromMap(
              Map<String, dynamic>.from(entry.value),
            );
          } catch (_) {}
        }
        // Isar is the live source of truth. Restoring Hive alone makes a
        // successful import appear empty until a later migration.
        await _ref
            .read(watchProgressRepositoryProvider)
            .replaceAllProgress(entries.values);
      }

      if (data.containsKey('settings')) {
        final settingsData = data['settings'] as Map<String, dynamic>;

        Future<void> restoreSetting(
          String key,
          String prefKey,
          dynamic Function(Map<String, dynamic>) parser,
        ) async {
          if (settingsData.containsKey(key)) {
            try {
              final model = parser(settingsData[key]);
              await sharedPrefs.setString(prefKey, model.toJson());
            } catch (_) {}
          }
        }

        await restoreSetting(
          'theme',
          'theme_settings',
          (m) => ThemeModel.fromMap(m),
        );
        await restoreSetting(
          'download',
          'download_settings',
          (m) => DownloadSettingsModel.fromMap(m),
        );
        await restoreSetting(
          'player',
          'player_settings',
          (m) => PlayerModel.fromMap(m),
        );
        await restoreSetting('ui', 'ui_settings', (m) => UiSettings.fromMap(m));
        await restoreSetting(
          'experimental',
          'experimental_settings',
          (m) => ExperimentalFeaturesModel.fromMap(m),
        );
        await restoreSetting(
          'content',
          'content_settings',
          (m) => ContentSettingsModel.fromMap(m),
        );
      }

      if (data['extensions'] is Map) {
        final extensionData =
            Map<String, dynamic>.from(data['extensions'] as Map);
        List<String> validRepositories(dynamic value) {
          if (value is! List) return [];
          return value.whereType<String>().where((url) {
            final uri = Uri.tryParse(url);
            return uri != null && uri.hasAuthority &&
                (uri.scheme == 'http' || uri.scheme == 'https');
          }).toSet().take(100).toList();
        }
        final animeRepos = <String>{
          'https://raw.githubusercontent.com/Mallyd11/mangayomi-anime-extensions/main/anime_index.json',
          'https://raw.githubusercontent.com/m2k3a/mangayomi-extensions/main/anime_index.json',
          ...validRepositories(extensionData['animeRepositories'])
        }.toList();
        final mangaRepos = <String>{
          'https://raw.githubusercontent.com/kodjodevf/mangayomi-extensions/main/index.json',
          ...validRepositories(extensionData['mangaRepositories'])
        }.toList();
        await sharedPrefs.setStringList('saved_anime_repos', animeRepos);
        await sharedPrefs.setStringList('saved_manga_repos', mangaRepos);
        if (extensionData['sourceAssignments'] is Map) {
          for (final pair in
              (extensionData['sourceAssignments'] as Map).entries) {
            final key = pair.key.toString();
            final value = pair.value.toString();
            if (key.startsWith('extension_source_repo_') &&
                Uri.tryParse(value)?.hasAuthority == true) {
              await sharedPrefs.setString(key, value);
            }
          }
        }

        // MangaYomi extensions run inside the app and can be restored from
        // their repository JSON. AniYomi APKs need the Android installer
        // confirmation and are intentionally never side-loaded from backup.
        final pending = <Map<String, dynamic>>[];
        final installedData = extensionData['installedMangayomi'];
        if (installedData is List) {
          try {
            final manager = bridge.ExtensionType.mangayomi.getManager();
            final installedAnime =
                await manager.getInstalledAnimeExtensions();
            final installedManga =
                await manager.getInstalledMangaExtensions();
            final availableAnime =
                await manager.fetchAvailableAnimeExtensions(animeRepos);
            final availableManga =
                await manager.fetchAvailableMangaExtensions(mangaRepos);
            for (final entry in installedData) {
              if (entry is! Map) continue;
              final id = entry['id']?.toString();
              final kind = entry['type'];
              if (id == null || id.isEmpty) continue;
              final manga = kind == bridge.ItemType.manga.index;
              final installed = manga ? installedManga : installedAnime;
              if (installed.any((source) => source.id == id)) continue;
              final available = manga ? availableManga : availableAnime;
              final match = available.where((source) => source.id == id);
              if (match.isEmpty) {
                pending.add(Map<String, dynamic>.from(entry));
                continue;
              }
              try {
                await manager.installSource(match.first);
              } catch (error) {
                pending.add(Map<String, dynamic>.from(entry));
                AppLogger.w('Could not restore extension $id: $error');
              }
            }
          } catch (error) {
            AppLogger.w('Extension restore deferred: $error');
            for (final entry in installedData) {
              if (entry is Map) pending.add(Map<String, dynamic>.from(entry));
            }
          }
        }
        await sharedPrefs.setString(
          'pending_extension_restore', jsonEncode(pending),
        );
      }
    } catch (e, s) {
      AppLogger.e('Failed to import data', e, s);
      rethrow;
    }
  }
}
