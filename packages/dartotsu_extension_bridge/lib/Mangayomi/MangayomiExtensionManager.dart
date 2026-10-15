import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:isar_community/isar.dart';

import '../dartotsu_extension_bridge.dart';
import 'http/m_client.dart';
import 'lib.dart';

class MangayomiExtensionManager extends GetxController {
  final installedAnimeExtensions = Rx<List<MSource>>([]);
  final availableAnimeExtensions = Rx<List<MSource>>([]);
  final installedMangaExtensions = Rx<List<MSource>>([]);
  final availableMangaExtensions = Rx<List<MSource>>([]);
  final installedNovelExtensions = Rx<List<MSource>>([]);
  final availableNovelExtensions = Rx<List<MSource>>([]);
  final http = MClient.init(reqcopyWith: {'useDartHttpClient': true});

  @override
  void onInit() {
    super.onInit();
    installedAnimeExtensions.bindStream(getExtensionsStream(ItemType.anime));
    installedMangaExtensions.bindStream(getExtensionsStream(ItemType.manga));
    installedNovelExtensions.bindStream(getExtensionsStream(ItemType.novel));
  }

  Stream<List<MSource>> getExtensionsStream(ItemType itemType) async* {
    yield* isar.mSources
        .filter()
        .sourceIdIsNotNull()
        .and()
        .itemTypeEqualTo(itemType)
        .watch(fireImmediately: true)
        .map((rows) {
          // Historic update code inserted a fresh Isar ID every time.
          final unique = <String, MSource>{};
          for (final source in rows) {
            final key = source.sourceId;
            if (key == null || key.isEmpty) continue;
            final current = unique[key];
            if (current == null || (source.id ?? -1) > (current.id ?? -1)) {
              unique[key] = source;
            }
          }
          return unique.values.toList();
        });
  }

  Future<List<MSource>> fetchAvailableExtensionsStream(
    ItemType itemType,
    List<String>? repos,
  ) async {
    var sources = <MSource>[];

    if (repos == null || repos.isEmpty) return sources;

    final seen = <String>{};
    for (final repo in repos) {
      if (repo.trim().isEmpty) continue;
      // A malformed/offline community JSON must not hide all other sources.
      try {
        final response = await http
            .get(Uri.parse(repo.trim()))
            .timeout(const Duration(seconds: 15));
        if (response.statusCode != 200) {
          debugPrint('Failed to fetch $repo: HTTP ${response.statusCode}');
          continue;
        }
        final decoded = jsonDecode(response.body);
        if (decoded is! List) {
          debugPrint('Ignoring non-array source JSON from $repo');
          continue;
        }
        for (final raw in decoded) {
          if (raw is! Map) continue;
          try {
            final e = Map<String, dynamic>.from(raw);
            if (e['id'] == null) continue;
            late MSource source;
            if (e['id'] is String &&
                e['name'] != null &&
                e['site'] != null &&
                e['lang'] != null &&
                e['version'] != null &&
                e['url'] != null &&
                e['iconUrl'] != null) {
              source =
                  MSource.fromJson(e)
                    ..sourceId = e['id'].toString()
                    ..apiUrl = ''
                    ..appMinVerReq = ''
                    ..dateFormat = ''
                    ..dateFormatLocale = ''
                    ..hasCloudflare = false
                    ..headers = ''
                    ..isActive = true
                    ..isAdded = false
                    ..isFullData = false
                    ..isNsfw = false
                    ..isPinned = false
                    ..lastUsed = false
                    ..sourceCode = ''
                    ..typeSource = ''
                    ..versionLast = '0.0.1'
                    ..isObsolete = false
                    ..isLocal = false
                    ..lang = _convertLang(e)
                    ..baseUrl = e['site']
                    ..sourceCodeUrl = e['url']
                    ..sourceCodeLanguage = SourceCodeLanguage.lnreader
                    ..itemType = ItemType.novel
                    ..repo = repo;
            } else {
              source =
                  MSource.fromJson(e)
                    ..sourceId = e['id'].toString()
                    ..repo = repo;
            }
            if (source.itemType != itemType) continue;
            final uniqueKey = '$repo:${source.sourceId}';
            if (seen.add(uniqueKey)) sources.add(source);
          } catch (error) {
            debugPrint('Skipping malformed source in $repo: $error');
          }
        }
      } catch (error) {
        debugPrint('Repository unavailable: $repo ($error)');
      }
    }
    switch (itemType) {
      case ItemType.anime:
        availableAnimeExtensions.value = sources;
        break;
      case ItemType.manga:
        availableMangaExtensions.value = sources;
        break;
      case ItemType.novel:
        availableNovelExtensions.value = sources;
        break;
    }

    return sources;
  }

  String _convertLang(dynamic e) {
    final lang = e['lang'];

    if (lang is String) {
      switch (lang) {
        case "‎العربية":
          return "ar";

        case "中文, 汉语, 漢語":
          return "zh";

        case "English":
          return "en";

        case "Français":
          return "fr";

        case "Bahasa Indonesia":
          return "id";

        case "日本語":
          return "ja";

        case "조선말, 한국어":
          return "ko";

        case "Polski":
          return "pl";

        case "Português":
          return "pt";

        case "Русский":
          return "ru";

        case "Español":
          return "es";

        case "ไทย":
          return "th";

        case "Türkçe":
          return "tr";

        case "Українська":
          return "uk";

        case "Tiếng Việt":
          return "vi";

        default:
          return "all";
      }
    }

    return "all";
  }

  Future<void> installSource(Source source) async {
    try {
      await _saveSource(source);
    } catch (e) {
      debugPrint('Error installing source: $e');
      return Future.error(e);
    }
  }

  // Source IDs, not Isar's auto-increment IDs, identify installed extensions.
  // Preserve the existing database record while installing/updating code.
  Future<void> _saveSource(Source source) async {
    final candidate = await getAvailable(source.itemType!, source.id);
    final codeUrl = candidate.sourceCodeUrl;
    if (codeUrl == null || codeUrl.isEmpty) {
      throw StateError('Extension has no source-code URL');
    }
    final response = await http.get(Uri.parse(codeUrl));
    if (response.statusCode != 200 || response.body.trim().isEmpty) {
      throw StateError(
        'Could not download extension: HTTP ${response.statusCode}',
      );
    }

    final installed =
        isar.mSources
            .where()
            .findAllSync()
            .where(
              (row) =>
                  row.sourceId == candidate.sourceId &&
                  row.itemType == source.itemType,
            )
            .toList();
    final existing = installed.isEmpty ? null : installed.last;
    candidate.id = existing?.id;
    candidate.sourceCode = response.body;
    candidate.headers = jsonEncode(getExtensionService(candidate).getHeaders());
    isar.writeTxnSync(() {
      isar.mSources.putSync(candidate);
      // Remove clones made by previous versions without losing the valid row.
      for (final duplicate in installed) {
        if (duplicate.id != null && duplicate.id != candidate.id) {
          isar.mSources.deleteSync(duplicate.id!);
        }
      }
    });
  }

  Future<void> uninstallSource(Source source) async {
    try {
      var mSource = await getInstalled(source.itemType!, source.id);
      isar.writeTxnSync(() => isar.mSources.deleteSync(mSource.id!));
    } catch (e) {
      debugPrint("Error uninstalling source: $e");
      return Future.error(e);
    }
  }

  Future<void> updateSource(Source source) async {
    try {
      await _saveSource(source);
    } catch (e) {
      debugPrint('Error updating source: $e');
      return Future.error(e);
    }
  }

  Future<MSource> getAvailable(ItemType itemType, String? id) async {
    switch (itemType) {
      case ItemType.anime:
        return availableAnimeExtensions.value.firstWhere(
          (source) => source.sourceId == id,
          orElse: () => throw Exception('Source not found'),
        );
      case ItemType.manga:
        return availableMangaExtensions.value.firstWhere(
          (source) => source.sourceId == id,
          orElse: () => throw Exception('Source not found'),
        );
      case ItemType.novel:
        return availableNovelExtensions.value.firstWhere(
          (source) => source.sourceId == id,
          orElse: () => throw Exception('Source not found'),
        );
    }
  }

  Future<MSource> getInstalled(ItemType itemType, String? id) async {
    switch (itemType) {
      case ItemType.anime:
        return installedAnimeExtensions.value.firstWhere(
          (source) => source.sourceId == id,
          orElse: () => throw Exception('Source not found'),
        );
      case ItemType.manga:
        return installedMangaExtensions.value.firstWhere(
          (source) => source.sourceId == id,
          orElse: () => throw Exception('Source not found'),
        );
      case ItemType.novel:
        return installedNovelExtensions.value.firstWhere(
          (source) => source.sourceId == id,
          orElse: () => throw Exception('Source not found'),
        );
    }
  }
}
