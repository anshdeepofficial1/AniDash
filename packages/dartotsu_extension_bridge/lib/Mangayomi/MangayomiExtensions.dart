import 'package:dartotsu_extension_bridge/dartotsu_extension_bridge.dart';
import 'package:get/get.dart';
import 'package:flutter/foundation.dart';

import 'MangayomiExtensionManager.dart';

class MangayomiExtensions extends Extension {
  MangayomiExtensions() {
    initialize();
  }

  final _manager = Get.put(MangayomiExtensionManager());

  @override
  Future<void> initialize() async {
    if (isInitialized.value) return;
    isInitialized.value = true;

    final settings = isar.bridgeSettings.getSync(26)!;

    await Future.wait([
      getInstalledAnimeExtensions(),
      getInstalledMangaExtensions(),
      getInstalledNovelExtensions(),
      fetchAvailableAnimeExtensions(settings.mangayomiAnimeExtensions),
      fetchAvailableMangaExtensions(settings.mangayomiMangaExtensions),
      fetchAvailableNovelExtensions(settings.mangayomiNovelExtensions),
    ]);

    _autoInstallDefaults();
  }

  Future<void> _autoInstallDefaults() async {
    try {
      final installedNames =
          getInstalledRx(ItemType.anime).value
              .map(
                (e) => (e.name ?? '').toLowerCase().replaceAll(
                  RegExp(r'[^a-z0-9]'),
                  '',
                ),
              )
              .toSet();
      final available = getAvailableRx(ItemType.anime).value;
      const targetNames = ['justanime', 'hianime', 'anikoto'];

      for (final target in targetNames) {
        if (!installedNames.any(
          (name) => name == target || name.startsWith(target),
        )) {
          final match =
              available.firstWhereOrNull(
                (s) =>
                    (s.name
                            ?.toLowerCase()
                            .replaceAll(RegExp(r'[^a-z0-9]'), '')
                            .startsWith(target) ==
                        true) &&
                    (target != 'hianime' ||
                        s.version == '0.4.11' ||
                        (s.version != null &&
                            s.version!.compareTo('0.4') >= 0)),
              ) ??
              available.firstWhereOrNull(
                (s) =>
                    s.name?.toLowerCase().replaceAll(
                          RegExp(r'[^a-z0-9]'),
                          '',
                        ) ==
                        target ||
                    (s.name
                            ?.toLowerCase()
                            .replaceAll(RegExp(r'[^a-z0-9]'), '')
                            .startsWith(target) ==
                        true),
              );

          if (match != null) {
            match.itemType = ItemType.anime;
            debugPrint(
              '[EXT_AUTO_INSTALL] Installing default anime extension: ${match.name} (${match.version})',
            );
            await installSource(match);
          }
        }
      }

      // Auto-install default verified Manga extensions
      final installedManga =
          getInstalledRx(
            ItemType.manga,
          ).value.map((e) => e.name?.toLowerCase() ?? '').toSet();
      final availableManga = getAvailableRx(ItemType.manga).value;
      const targetManga = ['mangadex'];

      for (final target in targetManga) {
        if (!installedManga.contains(target)) {
          final match =
              availableManga.firstWhereOrNull(
                (s) =>
                    s.name?.toLowerCase() == target &&
                    (s.lang == 'en' || s.lang == 'all'),
              ) ??
              availableManga.firstWhereOrNull(
                (s) => s.name?.toLowerCase() == target,
              );

          if (match != null) {
            match.itemType = ItemType.manga;
            debugPrint(
              '[EXT_AUTO_INSTALL] Installing default manga extension: ${match.name} (${match.version})',
            );
            await installSource(match);
          }
        }
      }
    } catch (e) {
      debugPrint('[EXT_AUTO_INSTALL] Error installing defaults: $e');
    }
  }

  @override
  Future<List<Source>> fetchAvailableAnimeExtensions(List<String>? repos) =>
      _fetchAvailable(ItemType.anime, repos);

  @override
  Future<List<Source>> fetchAvailableMangaExtensions(List<String>? repos) =>
      _fetchAvailable(ItemType.manga, repos);

  @override
  Future<List<Source>> fetchAvailableNovelExtensions(List<String>? repos) =>
      _fetchAvailable(ItemType.novel, repos);

  Future<List<Source>> _fetchAvailable(
    ItemType type,
    List<String>? repos,
  ) async {
    final settings = isar.bridgeSettings.getSync(26)!;

    switch (type) {
      case ItemType.anime:
        settings.mangayomiAnimeExtensions = repos ?? [];
        break;
      case ItemType.manga:
        settings.mangayomiMangaExtensions = repos ?? [];
        break;
      case ItemType.novel:
        settings.mangayomiNovelExtensions = repos ?? [];
        break;
    }
    isar.writeTxnSync(() => isar.bridgeSettings.putSync(settings));

    final sources = await _manager.fetchAvailableExtensionsStream(type, repos);
    final installedIds = getInstalledRx(type).value.map((e) => e.id).toSet();

    final list =
        sources
            .map((e) {
              var map = e.toJson();
              map['extensionType'] = 0;
              map["id"] = e.sourceId;
              return Source.fromJson(map);
            })
            .where((s) => !installedIds.contains(s.id))
            .toList();

    getAvailableRx(type).value = list;
    checkForUpdates(type);
    return list;
  }

  @override
  Future<List<Source>> getInstalledAnimeExtensions() =>
      _getInstalled(ItemType.anime);

  @override
  Future<List<Source>> getInstalledMangaExtensions() =>
      _getInstalled(ItemType.manga);

  @override
  Future<List<Source>> getInstalledNovelExtensions() =>
      _getInstalled(ItemType.novel);

  Future<List<Source>> _getInstalled(ItemType type) async {
    final stream =
        _manager
            .getExtensionsStream(type)
            .map(
              (sources) =>
                  sources.map((s) {
                    var map = s.toJson();
                    map['extensionType'] = 0;
                    map["id"] = s.sourceId;
                    return Source.fromJson(map);
                  }).toList(),
            )
            .asBroadcastStream();

    getInstalledRx(type).bindStream(stream);
    return stream.first;
  }

  @override
  Future<void> installSource(Source source) async {
    if (source.id?.isEmpty ?? true) {
      return Future.error('Source ID is required for installation.');
    }

    await _manager.installSource(source);

    switch (source.itemType!) {
      case ItemType.anime:
        await getInstalledAnimeExtensions();
        break;
      case ItemType.manga:
        await getInstalledMangaExtensions();
        break;
      case ItemType.novel:
        break;
    }

    final rx = getAvailableRx(source.itemType!);
    rx.value = rx.value.where((s) => s.id != source.id).toList();
  }

  @override
  Future<void> uninstallSource(Source source) async {
    if (source.id?.isEmpty ?? true) {
      return Future.error('Source ID is required for uninstallation.');
    }

    await _manager.uninstallSource(source);

    final availableList = _getAvailableList(source.itemType!);
    if (availableList.any((s) => s.sourceId == source.id)) {
      getAvailableRx(source.itemType!).update((list) => list?.add(source));
    }
  }

  @override
  Future<void> updateSource(Source source) async {
    if (source.id?.isEmpty ?? true) {
      return Future.error('Source ID is required for update.');
    }
    await _manager.updateSource(source);
  }

  Future<void> checkForUpdates(ItemType type) async {
    final availableMap = {for (var s in _getAvailableList(type)) s.sourceId: s};

    final updated =
        getInstalledRx(type).value.map((installed) {
          final avail = availableMap[installed.id];
          if (avail != null &&
              installed.version != null &&
              avail.version != null &&
              compareVersions(installed.version!, avail.version!) < 0) {
            return installed
              ..hasUpdate = true
              ..versionLast = avail.version;
          }
          return installed;
        }).toList();

    getInstalledRx(type).value = updated;
  }

  List<MSource> _getAvailableList(ItemType type) {
    switch (type) {
      case ItemType.anime:
        return _manager.availableAnimeExtensions.value;
      case ItemType.manga:
        return _manager.availableMangaExtensions.value;
      case ItemType.novel:
        return _manager.availableNovelExtensions.value;
    }
  }
}
