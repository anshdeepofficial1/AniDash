import 'dart:async';
import 'dart:io';

import 'package:dartotsu_extension_bridge/dartotsu_extension_bridge.dart';
import 'package:get/instance_manager.dart';
import 'package:get/utils.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:ani_dash/core/models/anime/server_model.dart';
import 'package:ani_dash/core/repositories/source_repository.dart';
import 'package:ani_dash/core/utils/app_logger.dart';
import 'package:ani_dash/core/models/settings/source_model.dart';
import 'package:ani_dash/main.dart';
import 'package:ani_dash/shared/providers/anime_source_provider.dart';

part 'source_notifier.g.dart';

@Riverpod(keepAlive: true)
class SourceNotifier extends _$SourceNotifier {
  final SourceRepository _repo = SourceRepository();

  @override
  SourceState build() {
    ref.onDispose(() {
      _managerSubscription?.cancel();
      for (final sub in _extensionSubscriptions) {
        sub.cancel();
      }
    });
    return const SourceState(isLoading: true);
  }

  StreamSubscription? _managerSubscription;
  final List<StreamSubscription> _extensionSubscriptions = [];

  Future<void> initialize() async {
    try {
      final extensionManager = Get.find<ExtensionManager>();
      // Listen for manager changes (e.g., swapping between Aniyomi/Mangayomi)
      _managerSubscription?.cancel();
      _managerSubscription = extensionManager.currentManagerRx.listen(
        _onManagerChanged,
      );

      // Perform initial setup with the current manager
      await _onManagerChanged(extensionManager.currentManager);
    } catch (e, st) {
      AppLogger.e('Error initializing extensions: $e\n$st');
      state = state.copyWith(isLoading: false);
    }
  }

  List<Extension> _getAllManagers() {
    final List<Extension> managers = [];
    try {
      final m = ExtensionType.mangayomi.getManager();
      managers.add(m);
    } catch (e) {
      AppLogger.w('Failed to get Mangayomi manager: $e');
    }
    if (Platform.isAndroid) {
      try {
        final a = ExtensionType.aniyomi.getManager();
        if (!managers.contains(a)) {
          managers.add(a);
        }
      } catch (e) {
        AppLogger.w('Failed to get Aniyomi manager: $e');
      }
    }
    return managers;
  }

  Future<void> _onManagerChanged(Extension manager) async {
    // Clear old extension subscriptions
    for (final sub in _extensionSubscriptions) {
      sub.cancel();
    }
    _extensionSubscriptions.clear();

    final allManagers = _getAllManagers();

    // Subscribe to installed extension changes from ALL managers (Mangayomi + Aniyomi)
    for (final m in allManagers) {
      _extensionSubscriptions.addAll([
        m.installedAnimeExtensions.listen(
          (_) => _syncCombinedExtensions(ItemType.anime),
        ),
        m.installedMangaExtensions.listen(
          (_) => _syncCombinedExtensions(ItemType.manga),
        ),
        m.installedNovelExtensions.listen(
          (_) => _syncCombinedExtensions(ItemType.novel),
        ),
      ]);
    }

    // Fetch initial repo/store data
    fetchSources(ItemType.anime);
    fetchSources(ItemType.manga);

    // Initial fetch of installed extensions across ALL managers
    for (final type in [ItemType.anime, ItemType.manga]) {
      final Set<String> seen = {};
      final List<Source> extensions = [];

      for (final m in allManagers) {
        try {
          List<Source> list = [];
          switch (type) {
            case ItemType.anime:
              list = await m.getInstalledAnimeExtensions();
              break;
            case ItemType.manga:
              list = await m.getInstalledMangaExtensions();
              break;
            case ItemType.novel:
              list = await m.getInstalledNovelExtensions();
              break;
          }
          for (final s in list) {
            final key = s.id ?? s.name ?? '';
            if (key.isNotEmpty && seen.add(key)) {
              extensions.add(s);
            }
          }
        } catch (e) {
          AppLogger.w('Failed to fetch installed extensions for $type from $m: $e');
        }
      }

      _updateExtensions(type, extensions);
    }

    state = state.copyWith(
      activeAnimeRepo: _repo.getActiveAnimeRepo(),
      activeMangaRepo: _repo.getActiveMangaRepo(),
      activeNovelRepo: _repo.getActiveNovelRepo(),
      isLoading: false,
    );

    _restoreActiveSources();
  }

  void _syncCombinedExtensions(ItemType type) {
    final allManagers = _getAllManagers();
    final Set<String> seen = {};
    final List<Source> combined = [];

    for (final m in allManagers) {
      List<Source> list = [];
      switch (type) {
        case ItemType.anime:
          list = m.installedAnimeExtensions.value;
          break;
        case ItemType.manga:
          list = m.installedMangaExtensions.value;
          break;
        case ItemType.novel:
          list = m.installedNovelExtensions.value;
          break;
      }
      for (final s in list) {
        final key = s.id ?? s.name ?? '';
        if (key.isNotEmpty && seen.add(key)) {
          combined.add(s);
        }
      }
    }

    if (combined.isNotEmpty) {
      _updateExtensions(type, combined);
    }
  }

  bool _isAdultSource(Source s) {
    final name = (s.name ?? '').toLowerCase();
    final id = (s.id ?? '').toLowerCase();
    return s.isNsfw == true ||
        name.contains('hanime') ||
        name.contains('hentai') ||
        name.contains('18+') ||
        name.contains('adult') ||
        id.contains('hanime') ||
        id.contains('hentai');
  }

  void _updateExtensions(ItemType type, List<Source> extensions) {
    switch (type) {
      case ItemType.anime:
        final merged = <String, Source>{};
        for (final s in extensions) {
          final key = s.id ?? s.name ?? '';
          if (key.isNotEmpty) merged[key] = s;
        }
        final normal = merged.values.where((s) => !_isAdultSource(s)).toList();
        final adult = merged.values.where((s) => _isAdultSource(s)).toList();
        state = state.copyWith(
          installedAnimeExtensions: normal,
          installedAdultAnimeExtensions: adult,
        );
        break;
      case ItemType.manga:
        final merged = <String, Source>{};
        for (final s in extensions) {
          final key = s.id ?? s.name ?? '';
          if (key.isNotEmpty) merged[key] = s;
        }
        final normal = merged.values.where((s) => !_isAdultSource(s)).toList();
        final adult = merged.values.where((s) => _isAdultSource(s)).toList();
        state = state.copyWith(
          installedMangaExtensions: normal,
          installedAdultMangaExtensions: adult,
        );
        break;
      case ItemType.novel:
        state = state.copyWith(installedNovelExtensions: extensions);
        break;
    }
    _restoreActiveSources();
  }

  void _restoreActiveSources() {
    final savedAnimeId = _repo.getActiveAnimeSourceId();
    final isExplicitExtension = sharedPrefs.getString('selected_playback_source_kind') == 'extension';
    final activeAnime = (savedAnimeId != null || isExplicitExtension)
        ? (state.installedAnimeExtensions.firstWhereOrNull(
            (s) =>
                (s.id == savedAnimeId || s.name == savedAnimeId) &&
                !_isAdultSource(s),
          ) ??
          state.installedAnimeExtensions.firstWhereOrNull(
            (s) => (s.name ?? '').toLowerCase().contains('justanime'),
          ) ??
          (isExplicitExtension ? state.installedAnimeExtensions.firstOrNull : null))
        : null;

    final activeAdult = state.installedAdultAnimeExtensions.firstOrNull;

    state = state.copyWith(
      activeAnimeSource: activeAnime,
      activeAdultAnimeSource: activeAdult,
      activeMangaSource:
          state.installedMangaExtensions.firstWhereOrNull(
            (s) => s.id == _repo.getActiveMangaSourceId() && !_isAdultSource(s),
          ) ??
          state.installedMangaExtensions.firstWhereOrNull(
            (s) => s.name?.toLowerCase().contains('mangasee') == true,
          ) ??
          state.installedMangaExtensions.firstWhereOrNull(
            (s) => s.name?.toLowerCase().contains('mangakakalot') == true,
          ) ??
          state.installedMangaExtensions.firstWhereOrNull(
            (s) => s.name?.toLowerCase().contains('mangabat') == true,
          ) ??
          state.installedMangaExtensions.firstWhereOrNull(
            (s) => s.name?.toLowerCase().contains('manganato') == true,
          ) ??
          state.installedMangaExtensions.firstWhereOrNull(
            (s) => s.name?.toLowerCase().contains('asura') == true,
          ) ??
          state.installedMangaExtensions.firstWhereOrNull(
            (s) => s.name?.toLowerCase().contains('comick') == true,
          ) ??
          state.installedMangaExtensions.firstWhereOrNull(
            (s) => s.name?.toLowerCase().contains('mangadex') == true,
          ) ??
          state.installedMangaExtensions.firstOrNull,
      activeNovelSource:
          state.installedNovelExtensions.firstWhereOrNull(
            (s) => s.id == _repo.getActiveNovelSourceId(),
          ) ??
          state.installedNovelExtensions.firstOrNull,
    );
  }

  void setActiveSource(Source source) {
    if (_isAdultSource(source)) {
      if (source.itemType == ItemType.anime) {
        state = state.copyWith(activeAdultAnimeSource: source);
      }
      return;
    }

    final isAnime = source.itemType == ItemType.anime ||
        state.installedAnimeExtensions.any((s) => s.id == source.id || s.name == source.name);
    if (isAnime) {
      ref.read(selectedProviderKeyProvider.notifier).clear();
      state = state.copyWith(
        activeAnimeSource: source,
        lastUpdatedSourceType: 'ANIME',
      );
      if (source.id != null) {
        _repo.saveActiveAnimeSourceId(source.id!);
      }
      return;
    }

    switch (source.itemType) {
      case ItemType.anime:
        ref.read(selectedProviderKeyProvider.notifier).clear();
        state = state.copyWith(
          activeAnimeSource: source,
          lastUpdatedSourceType: 'ANIME',
        );
        _repo.saveActiveAnimeSourceId(source.id!);
        break;
      case ItemType.manga:
        state = state.copyWith(
          activeMangaSource: source,
          lastUpdatedSourceType: 'MANGA',
        );
        _repo.saveActiveMangaSourceId(source.id!);
        break;
      case ItemType.novel:
        state = state.copyWith(
          activeNovelSource: source,
          lastUpdatedSourceType: 'NOVEL',
        );
        _repo.saveActiveNovelSourceId(source.id!);
        break;
      case null:
        break;
    }
  }

  void setActiveRepo(String repoUrl, ItemType mediaType) {
    switch (mediaType) {
      case ItemType.anime:
        state = state.copyWith(activeAnimeRepo: repoUrl);
        _repo.saveActiveAnimeRepo(repoUrl);
        break;
      case ItemType.manga:
        state = state.copyWith(activeMangaRepo: repoUrl);
        _repo.saveActiveMangaRepo(repoUrl);
        break;
      case ItemType.novel:
        state = state.copyWith(activeNovelRepo: repoUrl);
        _repo.saveActiveNovelRepo(repoUrl);
        break;
    }
  }

  Future<void> fetchSources(ItemType mediaType) async {
    final extensionManager = Get.find<ExtensionManager>();
    // Loading available repositories must not change the user's selected
    // AniYomi/MangaYomi engine as a side effect.
    final manager = extensionManager.currentManager;
    final isAniyomi =
        ExtensionType.fromManager(manager) == ExtensionType.aniyomi;
    if (mediaType == ItemType.anime) {
      final savedList = sharedPrefs.getStringList('saved_anime_repos') ?? [];
      final repos =
          <String>{
            if (!isAniyomi) ...[
              'https://raw.githubusercontent.com/Mallyd11/mangayomi-anime-extensions/main/anime_index.json',
              'https://raw.githubusercontent.com/m2k3a/mangayomi-extensions/main/anime_index.json',
            ] else ...[
              'https://raw.githubusercontent.com/msrofficial/anime-repo/repo/index.min.json',
              'https://kohiden.xyz/Kohi-den/extensions/raw/branch/main/index.min.json',
            ],
            ...savedList.where(
              (url) =>
                  isAniyomi
                      ? url.contains('index.min.json')
                      : !url.contains('index.min.json'),
            ),
          }.toList();
      await manager.fetchAvailableAnimeExtensions(repos);
    } else if (mediaType == ItemType.manga) {
      final repos =
          <String>{
            if (!isAniyomi)
              'https://raw.githubusercontent.com/kodjodevf/mangayomi-extensions/main/index.json'
            else
              'https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json',
            ...?sharedPrefs
                .getStringList('saved_manga_repos')
                ?.where(
                  (url) =>
                      isAniyomi
                          ? url.contains('index.min.json')
                          : !url.contains('index.min.json'),
                ),
          }.toList();
      await manager.fetchAvailableMangaExtensions(repos);
    } else {
      if (state.activeNovelRepo.isEmpty) return;
      await manager.fetchAvailableNovelExtensions([state.activeNovelRepo]);
    }
  }

  Future<Pages> search(
    String query, {
    int page = 1,
    List filters = const [],
  }) async {
    try {
      if (state.activeAnimeSource == null) {
        // Auto-select first installed extension if available
        final firstSource = state.installedAnimeExtensions.firstOrNull;
        if (firstSource != null) {
          AppLogger.d('Auto-selecting extension source: ${firstSource.name}');
          setActiveSource(firstSource);
        } else {
          AppLogger.w('Search: No installed anime extensions available');
          return Pages(list: []);
        }
      }
      AppLogger.d(
        'Search: Using source "${state.activeAnimeSource!.name}" (id: ${state.activeAnimeSource!.id}, itemType: ${state.activeAnimeSource!.itemType}) for query "$query"',
      );
      final result = await state.activeAnimeSource!.methods
          .search(query, page, filters)
          .timeout(const Duration(seconds: 25));
      AppLogger.d('Search: Got ${result.list.length} results');
      return result;
    } catch (err, st) {
      AppLogger.e(
        'Search failed for query "$query" with source "${state.activeAnimeSource?.name}" (id: ${state.activeAnimeSource?.id})',
        err,
        st,
      );
      return Pages(list: []);
    }
  }

  Future<DMedia?> getDetails(DMedia media) async {
    try {
      if (state.activeAnimeSource == null) {
        final firstSource = state.installedAnimeExtensions.firstOrNull;
        if (firstSource != null) {
          setActiveSource(firstSource);
        } else {
          return null;
        }
      }
      return await state.activeAnimeSource!.methods
          .getDetail(media)
          .timeout(const Duration(seconds: 25));
    } catch (err) {
      AppLogger.e(err);
      return null;
    }
  }

  Future<List<Video?>> getSources(DEpisode episode) async {
    try {
      if (state.activeAnimeSource == null) {
        final firstSource = state.installedAnimeExtensions.firstOrNull;
        if (firstSource != null) {
          setActiveSource(firstSource);
        } else {
          return [];
        }
      }
      return await state.activeAnimeSource!.methods
          .getVideoList(episode)
          .timeout(const Duration(seconds: 30));
    } catch (err) {
      AppLogger.e(err);
      return [];
    }
  }

  Future<List<ServerData?>> getServers(
    String animeId,
    String episodeId,
    String episodeNumber,
  ) async {
    return [];
    //   try {
    //     if (state.activeAnimeSource == null) return [];
    //     final anilist = ref.read(anilistServiceProvider);
    //     final service = _getService(anilist);
    //     return state.activeAnimeSource!.isForAniDash ?? false
    //         ? await service.getSupportedServers(animeId, episodeId, episodeNumber)
    //         : [] as List<ServerData?>;
    //   } catch (err) {
    //     AppLogger.e(err);
    //     return [];
    //   }
    // }
  }
}
