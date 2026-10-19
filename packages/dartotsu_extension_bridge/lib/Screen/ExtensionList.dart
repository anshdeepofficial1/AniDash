import 'package:dartotsu_extension_bridge/Settings/Settings.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../ExtensionManager.dart';
import '../Models/Source.dart';
import '../extension_bridge.dart';

abstract class ExtensionConfig {
  ItemType get itemType;

  bool get isInstalled;

  /// Null shows all repositories; a URL scopes this list to one JSON index.
  String? get repositoryFilter;

  String? assignedRepoFor(String sourceId);

  String get searchQuery;

  String get selectedLanguage;
}

abstract class ExtensionList<T extends StatefulWidget> extends State<T> {
  final controller = ScrollController();
  var sortedList = <String>[];

  var manager = Get.find<ExtensionManager>().currentManager;

  ExtensionConfig get config => widget as ExtensionConfig;

  ItemType get itemType => config.itemType;

  bool get isInstalled => config.isInstalled;

  String get searchQuery => config.searchQuery;

  String get selectedLanguage => config.selectedLanguage;

  @override
  void initState() {
    super.initState();
    var settings = isar.bridgeSettings.getSync(26) ?? BridgeSettings();
    switch (itemType) {
      case ItemType.anime:
        sortedList = settings.sortedAnimeExtensions;
      case ItemType.manga:
        sortedList = settings.sortedMangaExtensions;
      case ItemType.novel:
        sortedList = settings.sortedNovelExtensions;
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _refreshData() async {
    final settings = isar.bridgeSettings.getSync(26) ?? BridgeSettings();
    final aniyomi = ExtensionType.fromManager(manager) == ExtensionType.aniyomi;
    switch (itemType) {
      case ItemType.anime:
        await manager.fetchAvailableAnimeExtensions(
          aniyomi
              ? settings.aniyomiAnimeExtensions
              : settings.mangayomiAnimeExtensions,
        );
        break;
      case ItemType.manga:
        await manager.fetchAvailableMangaExtensions(
          aniyomi
              ? settings.aniyomiMangaExtensions
              : settings.mangayomiMangaExtensions,
        );
        break;
      case ItemType.novel:
        await manager.fetchAvailableNovelExtensions(
          settings.mangayomiNovelExtensions,
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final fullList = switch (itemType) {
        ItemType.anime =>
          isInstalled
              ? manager.installedAnimeExtensions.value
              : manager.availableAnimeExtensions.value,
        ItemType.manga =>
          isInstalled
              ? manager.installedMangaExtensions.value
              : manager.availableMangaExtensions.value,
        ItemType.novel =>
          isInstalled
              ? manager.installedNovelExtensions.value
              : manager.availableNovelExtensions.value,
      };

      final search = searchQuery.trim().toLowerCase();
      final searchTerms =
          search == 'hnm' ? const ['hnm', 'hanime'] : <String>[search];
      final filterLang =
          selectedLanguage == 'All' || selectedLanguage == 'all'
              ? null
              : selectedLanguage;

      final Map<String, List<Source>> grouped = {};
      final seenSourceIds = <String>{};
      for (final source in fullList) {
        final repoFilter = isInstalled ? null : config.repositoryFilter;
        if (repoFilter != null &&
            (source.repo ?? config.assignedRepoFor(source.id ?? '')) !=
                repoFilter) {
          continue;
        }
        final lang = source.lang ?? 'Unknown';
        if (filterLang != null && lang != filterLang) continue;
        if (search.isNotEmpty &&
            !searchTerms.any(
              (term) => source.name?.toLowerCase().contains(term) ?? false,
            )) {
          continue;
        }

        // Merge overlapping catalogs in All view without hiding genuine
        // sources filtered by language or search.
        final uniqueKey = '${source.extensionType?.index}:${source.id}';
        if (source.id?.isNotEmpty == true && !seenSourceIds.add(uniqueKey)) {
          continue;
        }
        grouped.putIfAbsent(lang, () => []).add(source);
      }

      final sortedEntries =
          grouped.entries.toList()..sort((a, b) {
            if (a.key == 'all') return -1;
            if (b.key == 'all') return 1;
            if (a.key == 'en') return -1;
            if (b.key == 'en') return 1;
            return a.key.compareTo(b.key);
          });

      final flattenedList = <({bool isHeader, String lang, Source? source})>[];
      for (final entry in sortedEntries) {
        flattenedList.add((isHeader: true, lang: entry.key, source: null));
        for (final source in entry.value) {
          flattenedList.add((isHeader: false, lang: entry.key, source: source));
        }
      }

      if (flattenedList.isEmpty) {
        return RefreshIndicator(
          onRefresh: _refreshData,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.extension_off_outlined,
                          size: 48,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No extensions found',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          config.repositoryFilter == null
                              ? 'Add a JSON repository or pull down to refresh.'
                              : 'No sources in this JSON. Pull down to refresh '
                                  'or choose another repository from the menu.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      }

      return RefreshIndicator(
        onRefresh: _refreshData,
        child: CustomScrollView(
          controller: controller,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(8.0),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  childCount: flattenedList.length,
                  (context, index) {
                    final item = flattenedList[index];
                    return extensionItem(item.isHeader, item.lang, item.source);
                  },
                ),
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget extensionItem(bool isHeader, String lang, Source? source);
}
