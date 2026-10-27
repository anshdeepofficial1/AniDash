import 'package:ani_dash/core/models/settings/source_model.dart';
import 'package:ani_dash/core/repositories/source_preference_repository.dart';
import 'package:ani_dash/core/services/anime_filler_service.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ani_dash/core/models/anime/episode_model.dart';
import 'package:ani_dash/shared/providers/anime_source_provider.dart';
import 'package:ani_dash/core/repositories/watch_progress_repository.dart';
import 'package:ani_dash/core/utils/app_logger.dart';
import 'package:ani_dash/features/watch/view_model/episode_list_provider.dart';
import 'package:ani_dash/features/watch/view_model/episode_stream_provider.dart';
import 'package:ani_dash/shared/providers/settings/experimental_notifier.dart';
import 'package:ani_dash/shared/providers/settings/source_notifier.dart';
import 'package:ani_dash/helpers/anime_match_search.dart';
import 'package:ani_dash/helpers/navigation.dart';
import 'package:ani_dash/core/models/universal/universal_media.dart';
import 'package:ani_dash/data/hive/models/anime_watch_progress_model.dart';
import 'package:ani_dash/features/details/view_model/details_page_notifier.dart';
import 'package:collection/collection.dart';
import 'package:ani_dash/features/downloads/model/download_item.dart';
import 'package:ani_dash/features/downloads/model/download_status.dart';
import 'package:ani_dash/features/downloads/view_model/downloads_notifier.dart';
import 'package:ani_dash/features/details/view/widgets/episodes/episode_block_item.dart';
import 'package:ani_dash/features/details/view/widgets/episodes/episode_compact_item.dart';
import 'package:ani_dash/features/details/view/widgets/episodes/episode_grid_item.dart';
import 'package:ani_dash/features/details/view/widgets/episodes/episode_list_item.dart';
import 'package:ani_dash/features/details/view/widgets/episodes/episode_banner_item.dart';
import 'package:ani_dash/shared/providers/settings/ui_notifier.dart';
import 'package:ani_dash/shared/providers/settings/download_settings_notifier.dart';
import 'package:ani_dash/shared/providers/settings/player_notifier.dart';
import 'package:ani_dash/features/watch/view/widgets/download_source_selector.dart';
import 'package:go_router/go_router.dart';
import 'package:dartotsu_extension_bridge/dartotsu_extension_bridge.dart';
import 'package:ani_dash/shared/providers/tracker/media_tracker_notifier.dart';
import 'package:ani_dash/features/watch/view_model/watch_sync_notifier.dart';
import 'package:ani_dash/core/services/franchise_service.dart';
import 'package:ani_dash/main.dart';
import 'package:ani_dash/features/episode_groups/model/named_episode_group.dart';
import 'package:ani_dash/features/episode_groups/repository/episode_grouping_repository.dart';
import 'package:ani_dash/features/ai/view/widgets/ask_nia_button.dart';

enum EpisodeViewMode { list, compact, grid, block, banner }

enum EpisodeGroupingMode { ranges, named }

final Map<String, ValueNotifier<Set<int>>> _episodesSelectionStore = {};
ValueNotifier<Set<int>> _getEpisodesSelectionNotifier(String mediaId) {
  return _episodesSelectionStore.putIfAbsent(
    mediaId,
    () => ValueNotifier<Set<int>>({}),
  );
}

class EpisodesTab extends ConsumerStatefulWidget {
  final UniversalMedia? anime;
  final String mediaId;
  final int? malId;
  final UniversalTitle mediaTitle;
  final String mediaFormat;
  final String mediaCover;
  final bool fromHentaiHub;
  final List<UniversalMediaRelation> relations;
  final ValueChanged<UniversalMedia>? onSeasonSelected;

  const EpisodesTab({
    super.key,
    this.anime,
    required this.mediaId,
    this.malId,
    required this.mediaTitle,
    required this.mediaFormat,
    required this.mediaCover,
    this.fromHentaiHub = false,
    this.relations = const [],
    this.onSeasonSelected,
  });

  @override
  ConsumerState<EpisodesTab> createState() => _EpisodesTabState();
}

class _EpisodesTabState extends ConsumerState<EpisodesTab>
    with AutomaticKeepAliveClientMixin<EpisodesTab> {
  @override
  bool get wantKeepAlive => true;

  late final ValueNotifier<Set<int>> _selectionNotifier;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _chipsScrollController = ScrollController();
  final GlobalKey _selectedChipKey = GlobalKey();
  bool _showSearch = false;
  bool _isSelecting = false;
  final GlobalKey _currentEpisodeKey = GlobalKey();
  int? _autoScrollEpisode;
  String? _lastAutoScrollToken;
  EpisodeGroupingMode _groupingMode = EpisodeGroupingMode.ranges;
  List<NamedEpisodeGroup> _namedGroups = const [];
  NamedEpisodeGroup? _selectedNamedGroup;
  bool _userManuallySelectedGroup = false;
  bool _userManuallySelectedRange = false;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _selectionNotifier = _getEpisodesSelectionNotifier(widget.mediaId);
    _selectionNotifier.addListener(_onSelectionChanged);
    _restoreGroupingPreference();
    _loadNamedGroups();
    WidgetsBinding.instance.addPostFrameCallback((_) {});
  }

  Future<void> _restoreGroupingPreference() async {
    final stored = sharedPrefs.getString('episode_grouping_mode');
    if (!mounted || stored == null) return;
    setState(() {
      _groupingMode =
          stored == EpisodeGroupingMode.named.name
              ? EpisodeGroupingMode.named
              : EpisodeGroupingMode.ranges;
    });
    _selectCurrentNamedGroup();
  }

  Future<void> _loadNamedGroups() async {
    final title = widget.mediaTitle.english ?? widget.mediaTitle.romaji;
    final groups = await const VerifiedEpisodeGroupingRepository()
        .getNamedGroups(
          animeId: widget.mediaId,
          malId: widget.malId?.toString(),
          title: title,
        );
    if (!mounted) return;
    final stored = sharedPrefs.getString('episode_grouping_mode');
    setState(() {
      _namedGroups = groups;
      // Default to named story arcs when available, unless user specifically configured ranges
      if (groups.isNotEmpty &&
          (stored == null || stored == EpisodeGroupingMode.named.name)) {
        _groupingMode = EpisodeGroupingMode.named;
      } else if (groups.isEmpty) {
        _groupingMode = EpisodeGroupingMode.ranges;
      }
    });
    _selectCurrentNamedGroup();
    _scheduleSelectedChipScroll();
  }

  void _selectCurrentNamedGroup([int? preferredEpisode]) {
    if (!mounted ||
        _groupingMode != EpisodeGroupingMode.named ||
        _namedGroups.isEmpty) {
      return;
    }
    int currentEpisode = preferredEpisode ?? 1;
    if (preferredEpisode == null) {
      var progress = ref
          .read(watchProgressRepositoryProvider)
          .getProgress(widget.mediaId);
      if (progress == null) {
        final title =
            (widget.mediaTitle.english ??
                    widget.mediaTitle.romaji ??
                    widget.mediaTitle.userPreferred)
                .trim()
                .toLowerCase();
        if (title.isNotEmpty) {
          progress =
              ref
                  .read(watchProgressRepositoryProvider)
                  .getAllProgress()
                  .where((p) => p.animeTitle.trim().toLowerCase() == title)
                  .firstOrNull;
        }
      }
      currentEpisode = progress?.currentEpisode ?? 1;
    }
    final matching = _namedGroups.cast<NamedEpisodeGroup?>().firstWhere(
      (group) => group?.contains(currentEpisode) ?? false,
      orElse: () => _namedGroups.first,
    );
    if (_selectedNamedGroup?.id == matching?.id) return;
    setState(() => _selectedNamedGroup = matching);
    _scheduleSelectedChipScroll();
  }

  void _scheduleSelectedChipScroll() {
    // Avoid Scrollable.ensureVisible which causes parent TabBarView horizontal switches
  }

  Future<void> _setGroupingMode(EpisodeGroupingMode mode) async {
    if (mode == EpisodeGroupingMode.named && _namedGroups.isEmpty) return;
    setState(() {
      _groupingMode = mode;
      _selectedNamedGroup = null;
      _userManuallySelectedGroup = false;
      _userManuallySelectedRange = false;
    });
    if (mode == EpisodeGroupingMode.named) {
      _selectCurrentNamedGroup();
    }
    await sharedPrefs.setString('episode_grouping_mode', mode.name);
    _scheduleSelectedChipScroll();
  }

  @override
  void dispose() {
    _selectionNotifier.removeListener(_onSelectionChanged);
    _searchController.dispose();
    _chipsScrollController.dispose();
    super.dispose();
  }

  void _scheduleCurrentEpisodeScroll({
    required int episodeNumber,
    required List<EpisodeDataModel> visibleEpisodes,
    required String selectedRange,
    required EpisodeViewMode viewMode,
  }) {
    // Disabled to prevent unwanted jumping to bottom of page
    return;
    if (_isRefreshing) return;
    final targetIndex = visibleEpisodes.indexWhere(
      (episode) => episode.number == episodeNumber,
    );
    if (targetIndex < 0 || visibleEpisodes.isEmpty) return;

    final token = '${widget.mediaId}:$selectedRange:$episodeNumber';
    if (_lastAutoScrollToken == token) return;
    _lastAutoScrollToken = token;
    _autoScrollEpisode = episodeNumber;

    double estimatedRowHeight;
    switch (viewMode) {
      case EpisodeViewMode.compact:
        estimatedRowHeight = 64.0;
        break;
      case EpisodeViewMode.banner:
        estimatedRowHeight = 150.0;
        break;
      case EpisodeViewMode.grid:
        estimatedRowHeight = 120.0;
        break;
      case EpisodeViewMode.block:
        estimatedRowHeight = 22.0;
        break;
      case EpisodeViewMode.list:
        estimatedRowHeight = 88.0;
        break;
    }

    void performEpisodeScroll() async {
      if (!mounted) return;
      final scrollController = PrimaryScrollController.maybeOf(context);
      if (scrollController == null || !scrollController.hasClients) return;

      final positions =
          scrollController.positions
              .where((position) => position.hasContentDimensions)
              .toList();
      if (positions.isEmpty) return;
      final position = positions.reduce(
        (current, candidate) =>
            candidate.maxScrollExtent > current.maxScrollExtent
                ? candidate
                : current,
      );
      final maxExtent = position.maxScrollExtent;
      if (maxExtent > 0) {
        final estimatedOffset = (targetIndex * estimatedRowHeight);
        final targetOffset = estimatedOffset.clamp(0.0, maxExtent);
        if ((position.pixels - targetOffset).abs() > 40) {
          await position.animateTo(
            targetOffset,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
          );
        }
      }

      if (!mounted) return;
      final targetContext = _currentEpisodeKey.currentContext;
      if (targetContext != null && targetContext.mounted) {
        await Scrollable.ensureVisible(
          targetContext,
          alignment: 0.35,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
        );
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => performEpisodeScroll());
    Future.delayed(const Duration(milliseconds: 120), performEpisodeScroll);
    Future.delayed(const Duration(milliseconds: 280), performEpisodeScroll);
  }

  void _onSelectionChanged() {
    if (mounted) setState(() {});
  }

  Set<int> get _selectedEpisodes => _selectionNotifier.value;
  bool get _isSelectionMode => _isSelecting || _selectedEpisodes.isNotEmpty;

  void _enterSelectionMode([int? epNum]) {
    _isSelecting = true;
    if (epNum != null) {
      _selectionNotifier.value = {..._selectionNotifier.value, epNum};
    } else {
      if (mounted) setState(() {});
    }
  }

  void _toggleSelection(int epNum) {
    _isSelecting = true;
    final s = _selectionNotifier.value;
    _selectionNotifier.value =
        s.contains(epNum)
            ? (Set<int>.from(s)..remove(epNum))
            : (Set<int>.from(s)..add(epNum));
  }

  void _exitSelectionMode() {
    _isSelecting = false;
    _selectionNotifier.value = {};
    if (mounted) setState(() {});
  }

  void _toggleSelectAll(List<EpisodeDataModel> visibleEpisodes) {
    final visibleNums =
        visibleEpisodes.map((e) => e.number).whereType<int>().toSet();
    final s = _selectionNotifier.value;
    _selectionNotifier.value =
        s.length >= visibleNums.length ? {} : visibleNums;
  }

  Future<void> _markSelectedAsWatched({required bool watched}) async {
    if (_selectedEpisodes.isEmpty) return;

    final repo = ref.read(watchProgressRepositoryProvider);
    final animeId = widget.mediaId;
    final animeTitle =
        ref.read(detailsPageProvider(widget.mediaId)).bestMatchName ??
        widget.mediaTitle.english ??
        widget.mediaTitle.romaji ??
        'Anime';

    final currentEntry = repo.getProgress(animeId);
    final episodesMap = Map<int, EpisodeProgress>.from(
      currentEntry?.episodesProgress ?? {},
    );

    for (final epNum in _selectedEpisodes) {
      final existing = episodesMap[epNum];
      episodesMap[epNum] = EpisodeProgress(
        episodeNumber: epNum,
        episodeTitle: existing?.episodeTitle ?? 'Episode $epNum',
        episodeThumbnail: existing?.episodeThumbnail,
        progressInSeconds: watched ? (existing?.durationInSeconds ?? 1440) : 0,
        durationInSeconds: existing?.durationInSeconds ?? 1440,
        isCompleted: watched,
        watchedAt: DateTime.now(),
      );
    }

    final totalEps =
        (widget.anime?.episodes != null && widget.anime!.episodes! > 0)
            ? widget.anime!.episodes!
            : (currentEntry?.totalEpisodes ?? 0);
    final updatedEntry = (currentEntry ??
            AnimeWatchProgressEntry(
              animeId: animeId,
              animeTitle: animeTitle,
              animeCover: widget.mediaCover,
              animeFormat: widget.mediaFormat,
              totalEpisodes: totalEps,
            ))
        .copyWith(
          episodesProgress: episodesMap,
          totalEpisodes: totalEps > 0 ? totalEps : null,
          lastUpdated: DateTime.now(),
          currentEpisode: _selectedEpisodes.reduce((a, b) => a > b ? a : b),
        );

    final maxEp = _selectedEpisodes.reduce((a, b) => a > b ? a : b);
    final isAllWatched = totalEps > 0 && maxEp >= totalEps && watched;
    final finalUpdatedEntry = updatedEntry.copyWith(
      status:
          isAllWatched
              ? 'completed'
              : (watched ? 'watching' : updatedEntry.status),
    );

    await repo.saveProgress(finalUpdatedEntry);

    if (watched && _selectedEpisodes.isNotEmpty) {
      final maxEp = _selectedEpisodes.reduce((a, b) => a > b ? a : b);
      ref
          .read(watchSyncProvider.notifier)
          .handleTrackingUpdate(mediaId: widget.mediaId, episodeNum: maxEp);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            watched
                ? 'Marked ${_selectedEpisodes.length} episodes as watched'
                : 'Marked ${_selectedEpisodes.length} episodes as unwatched',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handleBatchDownload(
    BuildContext context,
    WidgetRef ref,
    List<EpisodeDataModel> visibleEpisodes,
  ) async {
    final selectedNums = _selectedEpisodes.toList()..sort();
    if (selectedNums.isEmpty) return;

    if (selectedNums.length == 1) {
      final epNum = selectedNums.first;
      _exitSelectionMode();
      ref.read(episodeDataProvider.notifier).downloadEpisode(context, epNum);
      return;
    }

    final downloadSettings = ref.read(downloadSettingsProvider);
    final animeTitle =
        ref.read(detailsPageProvider(widget.mediaId)).bestMatchName ??
        widget.mediaTitle.english ??
        widget.mediaTitle.romaji ??
        'Anime';

    if (downloadSettings.rememberDownloadPreferences) {
      _exitSelectionMode();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Starting batch download for ${selectedNums.length} episodes (${downloadSettings.preferredLanguage.toUpperCase()}, ${downloadSettings.preferredQuality})...',
          ),
          duration: const Duration(seconds: 3),
        ),
      );

      await ref
          .read(episodeDataProvider.notifier)
          .downloadBatchEpisodes(
            context,
            selectedNums,
            preferredLanguage: downloadSettings.preferredLanguage,
            preferredQuality: downloadSettings.preferredQuality,
          );
      return;
    }

    _exitSelectionMode();

    if (!context.mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder:
          (sheetContext) => ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.85,
            ),
            child: DownloadSourceSelector(
              animeTitle: animeTitle,
              animeCover: widget.mediaCover,
              episodeCount: selectedNums.length,
              isAdult: widget.fromHentaiHub,
              genres: widget.anime?.genres,
              onConfirmBatchDownload: (lang, quality, doNotAskAgain) async {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Queueing ${selectedNums.length} episodes ($lang, $quality)...',
                    ),
                    behavior: SnackBarBehavior.floating,
                    action: SnackBarAction(
                      label: 'View Downloads',
                      onPressed: () => context.push('/downloads'),
                    ),
                  ),
                );
                await ref
                    .read(episodeDataProvider.notifier)
                    .downloadBatchEpisodes(
                      context,
                      selectedNums,
                      preferredLanguage: lang,
                      preferredQuality: quality,
                    );
              },
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // Automatically sync watched progress from AniList / Tracker
    ref.watch(mediaTrackerProvider(widget.mediaId));

    final notifier = ref.read(detailsPageProvider(widget.mediaId).notifier);
    final state = ref.watch(detailsPageProvider(widget.mediaId));
    final episodeListState = ref.watch(episodeListProvider);
    if (widget.malId != null &&
        episodeListState.episodes.isNotEmpty &&
        episodeListState.malId != widget.malId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(episodeListProvider.notifier).attachMalId(widget.malId!);
        }
      });
    }

    final isMatchingAnime =
        episodeListState.mediaId == widget.mediaId &&
        ((state.animeIdForSource != null &&
                episodeListState.animeId == state.animeIdForSource) ||
            (state.bestMatchName != null &&
                episodeListState.animeTitle == state.bestMatchName &&
                episodeListState.episodes.isNotEmpty));
    final hasSourceMatch = state.animeIdForSource != null;

    if (!_isRefreshing &&
        !isMatchingAnime &&
        hasSourceMatch &&
        !state.isSearchingMatch &&
        !episodeListState.isLoading &&
        state.error == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final titleForSearch =
            state.bestMatchName ??
            widget.mediaTitle.english ??
            widget.mediaTitle.romaji ??
            '';
        AnimeFillerService().getFillerInfo(
          title: titleForSearch,
          malId: widget.malId,
        );
        ref
            .read(episodeListProvider.notifier)
            .fetchEpisodes(
              animeTitle: titleForSearch,
              animeId: state.animeIdForSource,
              mediaId: widget.mediaId,
              force: false,
              malId: widget.malId,
              media: DMedia(
                title: titleForSearch,
                url: state.animeIdForSource,
                cover: widget.mediaCover,
              ),
              isAdult: widget.fromHentaiHub,
              isMovie: widget.mediaFormat.toUpperCase() == 'MOVIE',
            );
      });
    }

    final episodes =
        isMatchingAnime ? episodeListState.episodes : <EpisodeDataModel>[];
    final loading =
        state.isLoading ||
        episodeListState.isLoading ||
        state.isSearchingMatch ||
        (!isMatchingAnime &&
            episodes.isEmpty &&
            episodeListState.error == null &&
            state.error == null);
    final error =
        state.error ?? (isMatchingAnime ? episodeListState.error : null);

    final franchiseOrder =
        widget.anime != null
            ? ref
                .watch(franchiseWatchOrderProvider(widget.anime!))
                .asData
                ?.value
            : null;
    final franchiseEntries = franchiseOrder?.navigationItems ?? [];

    final rawExposed = state.bestMatchName?.trim();
    final exposedName = (rawExposed == null ||
            rawExposed.isEmpty ||
            rawExposed.toLowerCase() == 'none')
        ? null
        : rawExposed;
    final theme = Theme.of(context);
    final seasonRelations =
        widget.relations.where((relation) {
            final relationType = relation.relationType.toUpperCase();
            final format = relation.media.format?.toUpperCase() ?? '';
            const excludedFormats = {'MUSIC', 'MANGA', 'NOVEL', 'ONE_SHOT'};
            const relevantRelations = {
              'SEQUEL',
              'PREQUEL',
              'PARENT',
              'SIDE_STORY',
              'SUMMARY',
              'SPIN_OFF',
              'OTHER',
            };
            return relevantRelations.contains(relationType) &&
                !excludedFormats.contains(format);
          }).toList()
          ..sort(
            (a, b) => (a.media.seasonYear ?? 9999).compareTo(
              b.media.seasonYear ?? 9999,
            ),
          );

    final totalEpisodes = episodes.length;

    EpisodeDataModel? continueEpisode;
    EpisodeProgress? continueEpProgress;
    final watchProgress =
        ref.watch(animeWatchProgressProvider(widget.mediaId)).asData?.value ??
        ref.read(watchProgressRepositoryProvider).getProgress(widget.mediaId);

    int targetEpNum = 1;

    if (episodes.isNotEmpty && watchProgress != null) {
      final unfinished =
          watchProgress.episodesProgress.values.where((item) {
              final progress = item.progressInSeconds ?? 0;
              return progress > 0 &&
                  !isEpisodeProgressEffectivelyComplete(item);
            }).toList()
            ..sort((a, b) {
              final aTime = a.watchedAt ?? DateTime(0);
              final bTime = b.watchedAt ?? DateTime(0);
              return bTime.compareTo(aTime);
            });

      final currentEp =
          unfinished.firstOrNull ??
          watchProgress.episodesProgress[watchProgress.currentEpisode];

      final isCurrentCompleted =
          currentEp != null &&
          isEpisodeProgressEffectivelyComplete(currentEp);

      final baseEp =
          currentEp?.episodeNumber ??
          (watchProgress.currentEpisode > 0 ? watchProgress.currentEpisode : 1);

      targetEpNum =
          isCurrentCompleted &&
                  (totalEpisodes == 0 || baseEp < totalEpisodes)
              ? baseEp + 1
              : baseEp;

      continueEpisode = episodes.firstWhereOrNull(
        (e) => e.number == targetEpNum,
      ) ?? episodes.firstWhereOrNull(
        (e) => e.number == baseEp,
      );
      continueEpProgress =
          watchProgress.episodesProgress[continueEpisode?.number];
    } else if (watchProgress != null) {
      targetEpNum = watchProgress.currentEpisode > 0 ? watchProgress.currentEpisode : 1;
    }

    // Auto-select Arc if user has not manually picked one
    if (!_userManuallySelectedGroup && _namedGroups.isNotEmpty) {
      final matching = _namedGroups.firstWhereOrNull(
        (group) => group.contains(targetEpNum),
      ) ?? _namedGroups.first;
      if (_selectedNamedGroup?.id != matching.id) {
        _selectedNamedGroup = matching;
        _scheduleSelectedChipScroll();
      }
    }

    // Auto-select Range if user is in ranges mode and hasn't manually picked one
    if (!_isRefreshing &&
        !_userManuallySelectedRange &&
        _groupingMode == EpisodeGroupingMode.ranges &&
        state.rangeOptions.length > 1 &&
        state.selectedRange == 'All') {
      for (final r in state.rangeOptions) {
        if (r == 'All') continue;
        final parts = r.split('–');
        if (parts.length == 2) {
          final s = int.tryParse(parts[0]) ?? 1;
          final e = int.tryParse(parts[1]) ?? totalEpisodes;
          if (targetEpNum >= s && targetEpNum <= e) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                ref.read(detailsPageProvider(widget.mediaId).notifier).updateRange(r);
                _scheduleSelectedChipScroll();
              }
            });
            break;
          }
        }
      }
    }

    List<EpisodeDataModel> visibleEpisodes = episodes;
    if (_groupingMode == EpisodeGroupingMode.named &&
        _selectedNamedGroup != null) {
      final group = _selectedNamedGroup!;
      visibleEpisodes =
          episodes
              .where(
                (episode) =>
                    episode.number != null && group.contains(episode.number!),
              )
              .toList();
    } else if (state.selectedRange != 'All') {
      final parts = state.selectedRange.split('–');
      if (parts.length == 2) {
        final start = int.tryParse(parts[0]) ?? 1;
        final end = int.tryParse(parts[1]) ?? episodes.length;
        visibleEpisodes = episodes.sublist(
          (start - 1).clamp(0, episodes.length),
          end.clamp(0, episodes.length),
        );
      }
    }
    if (state.isSortedDescending) {
      visibleEpisodes = visibleEpisodes.reversed.toList();
    }

    if (_searchQuery.trim().isNotEmpty) {
      final query = _searchQuery.trim().toLowerCase();
      final queryNum = int.tryParse(query);
      visibleEpisodes =
          episodes.where((e) {
            if (queryNum != null && e.number == queryNum) return true;
            if (e.number?.toString().contains(query) == true) return true;
            if (e.title?.toLowerCase().contains(query) == true) return true;
            return false;
          }).toList();
      if (state.isSortedDescending) {
        visibleEpisodes = visibleEpisodes.reversed.toList();
      }
    }

    if (ref.watch(playerSettingsProvider).skipFillerEpisodes) {
      visibleEpisodes =
          visibleEpisodes.where((e) => e.isFiller != true).toList();
    }

    final experimentalSettings = ref.watch(experimentalProvider);
    final viewMode =
        experimentalSettings.useEpisodeBannerStyle
            ? EpisodeViewMode.banner
            : EpisodeViewMode.values.firstWhere(
              (e) => e.name == ref.watch(uiSettingsProvider).episodeViewMode,
              orElse: () => EpisodeViewMode.list,
            );

    // Auto-scroll disabled to prevent disruptive jumping to bottom or switching tabs

    return RefreshIndicator(
      onRefresh: () async {
        _isRefreshing = true;
        try {
          await notifier.refresh();
        } finally {
          if (mounted) {
            setState(() => _isRefreshing = false);
          }
        }
      },
      child: CustomScrollView(
        primary: true,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          () {
                            final useExt = ref.watch(experimentalProvider).useExtensions;
                            final activeExt = ref.watch(sourceProvider).activeAnimeSource;
                            final nativeKey = ref.watch(selectedProviderKeyProvider)?.toLowerCase();
                            final selectedNative = ref.watch(selectedAnimeProvider);

                            String rawName;
                            if (nativeKey == 'justanime' || nativeKey == 'hianime' || nativeKey == 'anikoto') {
                              rawName = nativeKey!;
                            } else if (useExt && activeExt != null) {
                              rawName = activeExt.name ?? 'Unknown';
                            } else {
                              rawName = selectedNative?.providerName ?? nativeKey ?? 'JustAnime';
                            }

                            String formatName(String? name) {
                              if (name == null || name.isEmpty) {
                                return 'JustAnime';
                              }
                              final l = name.toLowerCase();
                              if (l.contains('justanime')) return 'JustAnime';
                              if (l.contains('hianime')) return 'HiAnime';
                              if (l.contains('anikoto')) return 'AniKoto';
                              if (l.contains('toonstream')) return 'Toonstream';
                              if (l.contains('animedub')) return 'AnimeDubHindi';
                              if (l.contains('moviebox')) return 'MovieBox';
                              return name.substring(0, 1).toUpperCase() +
                                  name.substring(1);
                            }

                            final formatted = formatName(rawName);

                            if (state.isSearchingMatch) {
                              return 'SEARCHING ( via  )';
                            }
                            if (exposedName == null) {
                              return 'SOURCE: ';
                            }
                            return 'MATCHED ( by  )';
                          }(),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        InkWell(
                          onTap: exposedName == null ? () => _handleWrongMatch(context, ref, notifier) : null,
                          borderRadius: BorderRadius.circular(6),
                          child: Text(
                            exposedName ?? (state.isSearchingMatch ? 'Searching for match...' : 'Tap to select match manually'),
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: exposedName == null ? theme.colorScheme.primary : null,
                              fontStyle: exposedName == null ? FontStyle.italic : FontStyle.normal,
                              decoration: exposedName == null ? TextDecoration.underline : null,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.swap_horiz_rounded,
                      color: theme.hintColor,
                    ),
                    tooltip: 'Change Source',
                    onPressed:
                        () =>
                            _showSourceSelectionDialog(context, ref, notifier),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.help_outline_rounded,
                      color: theme.hintColor,
                    ),
                    tooltip: 'Wrong match?',
                    onPressed: () => _handleWrongMatch(context, ref, notifier),
                  ),
                  AskNiaButton(
                    compact: true,
                    animeId: widget.mediaId,
                    animeTitle:
                        widget.mediaTitle.english ?? widget.mediaTitle.romaji,
                    currentEpisode: watchProgress?.currentEpisode,
                  ),
                ],
              ),
            ),
          ),

          // Hindi Quick Switch Banner
          if (_hasHindiExtension(ref.watch(sourceProvider)) && !_isCurrentSourceHindi(ref))
            SliverToBoxAdapter(
              child: _buildHindiAvailabilityBanner(context, ref, notifier, ref.watch(sourceProvider)),
            ),

          if (franchiseEntries.length > 1)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Seasons & Specials',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 38,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: franchiseEntries.length,
                        itemBuilder: (context, index) {
                          final seasonItem = franchiseEntries[index];
                          final isCurrent =
                              seasonItem.isCurrent ||
                              seasonItem.id.toString() == widget.mediaId;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(seasonItem.chipLabel),
                              selected: isCurrent,
                              onSelected:
                                  isCurrent
                                      ? null
                                      : (selected) {
                                        if (widget.onSeasonSelected != null) {
                                          widget.onSeasonSelected!(
                                            seasonItem.media,
                                          );
                                        }
                                      },
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (seasonRelations.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Seasons & Specials',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 38,
                      child: Builder(
                        builder: (context) {
                          final allItemsMap = <String, UniversalMedia>{};
                          if (widget.anime != null) {
                            allItemsMap[widget.anime!.id] = widget.anime!;
                          }
                          for (final rel in seasonRelations) {
                            allItemsMap.putIfAbsent(rel.media.id, () => rel.media);
                          }
                          final sortedEntries = allItemsMap.values.toList()
                            ..sort((a, b) {
                              final aDate = a.startDate;
                              final bDate = b.startDate;
                              final aKey =
                                  (aDate?.year ?? a.seasonYear ?? 9999) * 10000 +
                                  (aDate?.month ?? 1) * 100 +
                                  (aDate?.day ?? 1);
                              final bKey =
                                  (bDate?.year ?? b.seasonYear ?? 9999) * 10000 +
                                  (bDate?.month ?? 1) * 100 +
                                  (bDate?.day ?? 1);
                              if (aKey != bKey) return aKey.compareTo(bKey);
                              return (a.title.userPreferred).compareTo(b.title.userPreferred);
                            });

                          return ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: sortedEntries.length,
                            itemBuilder: (context, index) {
                              final item = sortedEntries[index];
                              final isCurrent = item.id == widget.mediaId;
                              final chipLabel =
                                  FranchiseService.deriveCleanSeasonChipLabel(
                                    item,
                                    index + 1,
                                  );

                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(chipLabel),
                                  selected: isCurrent,
                                  onSelected:
                                      isCurrent
                                          ? null
                                          : (selected) {
                                            if (widget.onSeasonSelected != null) {
                                              widget.onSeasonSelected!(item);
                                            }
                                          },
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),

          if (continueEpisode != null && !loading && episodes.isNotEmpty)
            SliverToBoxAdapter(
              child: _buildContinueWatchingBanner(
                context,
                continueEpisode,
                continueEpProgress,
                episodes,
                state.animeIdForSource ?? '',
              ),
            ),

          if (state.isSearchingMatch)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24.0,
                    vertical: 20.0,
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: theme.colorScheme.primary.withValues(
                          alpha: 0.25,
                        ),
                        width: 1.2,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 44,
                          height: 44,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Searching for best match…',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Resolving stream sources for ${widget.mediaTitle.english ?? widget.mediaTitle.romaji ?? "anime"}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 20),
                        Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: [
                            OutlinedButton.icon(
                              onPressed:
                                  () =>
                                      _handleWrongMatch(context, ref, notifier),
                              icon: const Icon(
                                Icons.touch_app_rounded,
                                size: 18,
                              ),
                              label: const Text('Manual Selection'),
                            ),
                            TextButton.icon(
                              onPressed:
                                  () => _showSourceSelectionDialog(
                                    context,
                                    ref,
                                    notifier,
                                  ),
                              icon: const Icon(
                                Icons.swap_horiz_rounded,
                                size: 18,
                              ),
                              label: const Text('Change Source'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          else if (loading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            )
          else if ((error != null || state.error != null) && episodes.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(10.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        state.error ?? error ?? 'Unknown Error',
                        style: const TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        children: [
                          ElevatedButton.icon(
                            onPressed:
                                () => _handleWrongMatch(context, ref, notifier),
                            icon: const Icon(Icons.search),
                            label: const Text('Manual Selection'),
                          ),
                          ElevatedButton.icon(
                            onPressed: () => notifier.refresh(),
                            icon: const Icon(Icons.refresh),
                            label: const Text('Retry'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            )
          else if (episodes.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _buildEmptyEpisodesView(context, theme),
            )
          else ...[
            SliverPersistentHeader(
              pinned: true,
              delegate: _SliverToolbarDelegate(
                minHeight: 110.0,
                maxHeight: 110.0,
                child: Container(
                  color: theme.scaffoldBackgroundColor,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10.0),
                        child:
                            _isSelectionMode
                                ? Row(
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.close),
                                      onPressed: _exitSelectionMode,
                                      tooltip: 'Cancel',
                                    ),
                                    Text(
                                      '${_selectedEpisodes.length}',
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            color: theme.colorScheme.primary,
                                          ),
                                    ),
                                    const Spacer(),
                                    IconButton(
                                      icon: Icon(
                                        visibleEpisodes.isNotEmpty &&
                                                _selectedEpisodes.length >=
                                                    visibleEpisodes.length
                                            ? Icons.select_all_rounded
                                            : Icons.checklist_rtl_rounded,
                                      ),
                                      tooltip:
                                          visibleEpisodes.isNotEmpty &&
                                                  _selectedEpisodes.length >=
                                                      visibleEpisodes.length
                                              ? 'Deselect All'
                                              : 'Select All',
                                      color: theme.colorScheme.primary,
                                      onPressed:
                                          () =>
                                              _toggleSelectAll(visibleEpisodes),
                                    ),
                                    PopupMenuButton<String>(
                                      icon: const Icon(Icons.more_vert),
                                      tooltip: 'More actions',
                                      onSelected: (val) {
                                        if (val == 'watch') {
                                          _markSelectedAsWatched(watched: true);
                                        } else if (val == 'unwatch') {
                                          _markSelectedAsWatched(
                                            watched: false,
                                          );
                                        }
                                      },
                                      itemBuilder:
                                          (context) => [
                                            const PopupMenuItem(
                                              value: 'watch',
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    Icons.check_circle_outline,
                                                    size: 18,
                                                  ),
                                                  SizedBox(width: 8),
                                                  Text('Mark as Watched'),
                                                ],
                                              ),
                                            ),
                                            const PopupMenuItem(
                                              value: 'unwatch',
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    Icons.remove_done_rounded,
                                                    size: 18,
                                                  ),
                                                  SizedBox(width: 8),
                                                  Text('Mark as Unwatched'),
                                                ],
                                              ),
                                            ),
                                          ],
                                    ),
                                    FilledButton.icon(
                                      onPressed:
                                          _selectedEpisodes.isEmpty
                                              ? null
                                              : () => _handleBatchDownload(
                                                context,
                                                ref,
                                                visibleEpisodes,
                                              ),
                                      icon: const Icon(
                                        Icons.download_rounded,
                                        size: 18,
                                      ),
                                      label: Text(
                                        'Download (${_selectedEpisodes.length})',
                                      ),
                                      style: FilledButton.styleFrom(
                                        visualDensity: VisualDensity.compact,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                                : Row(
                                  children: [
                                    if (_showSearch)
                                      Expanded(
                                        child: SizedBox(
                                          height: 36,
                                          child: TextField(
                                            controller: _searchController,
                                            autofocus: true,
                                            decoration: InputDecoration(
                                              hintText:
                                                  'Jump to episode (e.g. 50)...',
                                              hintStyle: TextStyle(
                                                fontSize: 12,
                                                color: theme.hintColor,
                                              ),
                                              isDense: true,
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 8,
                                                  ),
                                              border: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                borderSide: BorderSide.none,
                                              ),
                                              filled: true,
                                              fillColor:
                                                  theme
                                                      .colorScheme
                                                      .surfaceContainerHighest,
                                              prefixIcon: const Icon(
                                                Icons.search_rounded,
                                                size: 16,
                                              ),
                                              suffixIcon:
                                                  _searchQuery.isNotEmpty
                                                      ? IconButton(
                                                        icon: const Icon(
                                                          Icons.clear,
                                                          size: 14,
                                                        ),
                                                        onPressed: () {
                                                          setState(() {
                                                            _searchQuery = '';
                                                            _searchController
                                                                .clear();
                                                          });
                                                        },
                                                      )
                                                      : null,
                                            ),
                                            keyboardType: TextInputType.text,
                                            onChanged: (val) {
                                              setState(() {
                                                _searchQuery = val;
                                              });
                                            },
                                          ),
                                        ),
                                      )
                                    else
                                      Text(
                                        (widget.mediaFormat.toUpperCase() ==
                                                    'MOVIE' ||
                                                widget.anime?.format
                                                        ?.toUpperCase() ==
                                                    'MOVIE')
                                            ? 'Movie'
                                            : '$totalEpisodes Episodes',
                                        style: theme.textTheme.titleSmall,
                                      ),
                                    if (!_showSearch) const Spacer(),
                                    IconButton(
                                      icon: Icon(
                                        _showSearch
                                            ? Icons.close
                                            : Icons.search_rounded,
                                        size: 20,
                                      ),
                                      tooltip:
                                          _showSearch
                                              ? 'Close Search'
                                              : 'Search / Jump to Episode',
                                      onPressed: () {
                                        setState(() {
                                          _showSearch = !_showSearch;
                                          if (!_showSearch) {
                                            _searchQuery = '';
                                            _searchController.clear();
                                          }
                                        });
                                      },
                                    ),
                                    if (!_showSearch) ...[
                                      IconButton(
                                        icon: const Icon(Icons.sync_rounded),
                                        tooltip: 'Sync with AniList',
                                        onPressed: () async {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Syncing watched episodes from AniList...',
                                              ),
                                              duration: Duration(seconds: 1),
                                              behavior:
                                                  SnackBarBehavior.floating,
                                            ),
                                          );
                                          await ref
                                              .read(
                                                mediaTrackerProvider(
                                                  widget.mediaId,
                                                ).notifier,
                                              )
                                              .fetchRemoteEntries();
                                        },
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.checklist_rounded,
                                        ),
                                        tooltip: 'Select Episodes',
                                        onPressed: () {
                                          _enterSelectionMode();
                                        },
                                      ),
                                      PopupMenuButton<Object>(
                                        icon: const Icon(Icons.more_vert),
                                        tooltip: 'Episode display',
                                        onSelected: (value) {
                                          if (value is EpisodeViewMode) {
                                            final mode = value;
                                            if (mode ==
                                                EpisodeViewMode.banner) {
                                              ref
                                                  .read(
                                                    experimentalProvider
                                                        .notifier,
                                                  )
                                                  .updateSettings(
                                                    (s) => s.copyWith(
                                                      useEpisodeBannerStyle:
                                                          true,
                                                    ),
                                                  );
                                            } else {
                                              ref
                                                  .read(
                                                    experimentalProvider
                                                        .notifier,
                                                  )
                                                  .updateSettings(
                                                    (s) => s.copyWith(
                                                      useEpisodeBannerStyle:
                                                          false,
                                                    ),
                                                  );
                                            }
                                            ref
                                                .read(
                                                  uiSettingsProvider.notifier,
                                                )
                                                .updateSettings(
                                                  (s) => s.copyWith(
                                                    episodeViewMode: mode.name,
                                                  ),
                                                );
                                          } else if (value
                                              is EpisodeGroupingMode) {
                                            _setGroupingMode(value);
                                          } else if (value == 'toggle_filler') {
                                            final current =
                                                ref
                                                    .read(
                                                      playerSettingsProvider,
                                                    )
                                                    .skipFillerEpisodes;
                                            ref
                                                .read(
                                                  playerSettingsProvider
                                                      .notifier,
                                                )
                                                .updateSettings(
                                                  (s) => s.copyWith(
                                                    skipFillerEpisodes:
                                                        !current,
                                                  ),
                                                );
                                          }
                                        },
                                        itemBuilder:
                                            (context) => [
                                              const PopupMenuItem<Object>(
                                                enabled: false,
                                                child: Text(
                                                  'Episode style',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                              const PopupMenuItem(
                                                value: EpisodeViewMode.list,
                                                child: Row(
                                                  children: [
                                                    Icon(Icons.view_list),
                                                    SizedBox(width: 8),
                                                    Text('List'),
                                                  ],
                                                ),
                                              ),
                                              const PopupMenuItem(
                                                value: EpisodeViewMode.grid,
                                                child: Row(
                                                  children: [
                                                    Icon(Icons.grid_view),
                                                    SizedBox(width: 8),
                                                    Text('Grid'),
                                                  ],
                                                ),
                                              ),
                                              const PopupMenuItem(
                                                value: EpisodeViewMode.compact,
                                                child: Row(
                                                  children: [
                                                    Icon(Icons.view_headline),
                                                    SizedBox(width: 8),
                                                    Text('Compact'),
                                                  ],
                                                ),
                                              ),
                                              const PopupMenuItem(
                                                value: EpisodeViewMode.block,
                                                child: Row(
                                                  children: [
                                                    Icon(Icons.view_module),
                                                    SizedBox(width: 8),
                                                    Text('Block'),
                                                  ],
                                                ),
                                              ),
                                              const PopupMenuItem(
                                                value: EpisodeViewMode.banner,
                                                child: Row(
                                                  children: [
                                                    Icon(Icons.video_library),
                                                    SizedBox(width: 8),
                                                    Text('Banner'),
                                                  ],
                                                ),
                                              ),
                                              if (_namedGroups.isNotEmpty) ...[
                                                const PopupMenuDivider(),
                                                const PopupMenuItem<Object>(
                                                  enabled: false,
                                                  child: Text(
                                                    'Grouping',
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                                CheckedPopupMenuItem<Object>(
                                                  value:
                                                      EpisodeGroupingMode
                                                          .ranges,
                                                  checked:
                                                      _groupingMode ==
                                                      EpisodeGroupingMode
                                                          .ranges,
                                                  child: const Text(
                                                    'Episode ranges',
                                                  ),
                                                ),
                                                CheckedPopupMenuItem<Object>(
                                                  value:
                                                      EpisodeGroupingMode.named,
                                                  checked:
                                                      _groupingMode ==
                                                      EpisodeGroupingMode.named,
                                                  child: const Text(
                                                    'Story arcs',
                                                  ),
                                                ),
                                              ],
                                              const PopupMenuDivider(),
                                              CheckedPopupMenuItem<Object>(
                                                value: 'toggle_filler',
                                                checked:
                                                    ref
                                                        .read(
                                                          playerSettingsProvider,
                                                        )
                                                        .skipFillerEpisodes,
                                                child: const Text(
                                                  'Hide filler episodes',
                                                ),
                                              ),
                                            ],
                                      ),
                                      IconButton(
                                        icon: Icon(
                                          state.isSortedDescending
                                              ? Icons.arrow_downward_rounded
                                              : Icons.arrow_upward_rounded,
                                        ),
                                        tooltip:
                                            state.isSortedDescending
                                                ? 'Sort Ascending'
                                                : 'Sort Descending',
                                        onPressed: () => notifier.toggleSort(),
                                      ),
                                    ],
                                  ],
                                ),
                      ),
                      if (widget.mediaFormat.toUpperCase() != 'MOVIE' &&
                          widget.anime?.format?.toUpperCase() != 'MOVIE' &&
                          (state.rangeOptions.length > 1 ||
                              _namedGroups.isNotEmpty ||
                              totalEpisodes > 25))
                        SizedBox(
                          height: 50,
                          child: ListView(
                            controller: _chipsScrollController,
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            children: [
                              if (_groupingMode == EpisodeGroupingMode.ranges)
                                ...state.rangeOptions.map((range) {
                                  final isSelected = state.selectedRange == range;
                                  Widget chip = Center(
                                    child: ChoiceChip(
                                      label: Text(range),
                                      selected: isSelected,
                                      onSelected: (isSelected) {
                                        if (isSelected) {
                                          _userManuallySelectedRange = true;
                                          notifier.updateRange(range);
                                          _scheduleSelectedChipScroll();
                                        }
                                      },
                                    ),
                                  );
                                  if (isSelected) {
                                    chip = KeyedSubtree(
                                      key: _selectedChipKey,
                                      child: chip,
                                    );
                                  }
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4.0,
                                    ),
                                    child: chip,
                                  );
                                })
                              else ...[
                                ..._namedGroups.map(
                                  (group) {
                                    final isSelected =
                                        _selectedNamedGroup?.id == group.id;
                                    Widget chip = Center(
                                      child: ChoiceChip(
                                        label: Text(
                                          '${group.title} (${group.rangeLabel})',
                                        ),
                                        selected: isSelected,
                                        onSelected: (_) {
                                          _userManuallySelectedGroup = true;
                                          setState(
                                            () => _selectedNamedGroup = group,
                                          );
                                          _scheduleSelectedChipScroll();
                                        },
                                      ),
                                    );
                                    if (isSelected) {
                                      chip = KeyedSubtree(
                                        key: _selectedChipKey,
                                        child: chip,
                                      );
                                    }
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                      ),
                                      child: chip,
                                    );
                                  },
                                ),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),

            _buildEpisodeSliver(
              context,
              ref,
              visibleEpisodes,
              episodeListState.animeTitle,
              episodes,
              state.animeIdForSource,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEpisodeSliver(
    BuildContext context,
    WidgetRef ref,
    List<EpisodeDataModel> visibleEpisodes,
    String? animeTitle,
    List<EpisodeDataModel> allEpisodes,
    String? animeIdForSource,
  ) {
    final experimentalSettings = ref.watch(experimentalProvider);
    final viewMode =
        experimentalSettings.useEpisodeBannerStyle
            ? EpisodeViewMode.banner
            : EpisodeViewMode.values.firstWhere(
              (e) => e.name == ref.watch(uiSettingsProvider).episodeViewMode,
              orElse: () => EpisodeViewMode.list,
            );

    Widget buildItem(BuildContext context, int index) {
      final ep = visibleEpisodes[index];
      final epNum = ep.number ?? index + 1;
      final isSelected = _selectedEpisodes.contains(epNum);
      final progressAsync = ref.watch(
        animeWatchProgressProvider(widget.mediaId),
      );
      final progress = progressAsync.asData?.value;

      final epProgress = progress?.episodesProgress[ep.number ?? -1];
      final isWatched = epProgress?.isCompleted ?? false;
      final duration = epProgress?.durationInSeconds ?? 0;
      final progressSec = epProgress?.progressInSeconds ?? 0;
      final watchProgress =
          (duration > 0) ? (progressSec / duration).clamp(0.0, 1.0) : 0.0;

      final downloadState = ref.watch(downloadsProvider);
      final download = downloadState.downloads.firstWhereOrNull(
        (d) => d.animeTitle == animeTitle && d.episodeNumber == ep.number,
      );
      final isDownloaded = download?.state == DownloadStatus.downloaded;

      final fallbackCover = widget.mediaCover;

      void onDownloadItem() {
        ref.read(episodeDataProvider.notifier).downloadEpisode(context, epNum);
      }

      void onLongPressItem() {
        if (_isSelectionMode) {
          _toggleSelection(epNum);
        } else {
          _showEpisodeMenu(context, ep, isWatched, download: download);
        }
      }

      void onItemTap() {
        if (_isSelectionMode) {
          _toggleSelection(epNum);
        } else {
          _navigateToWatch(ep, allEpisodes, animeIdForSource ?? '');
        }
      }

      final Widget itemWidget = switch (viewMode) {
        EpisodeViewMode.grid => EpisodeGridItem(
          episode: ep,
          index: index,
          isWatched: isWatched,
          watchProgress: watchProgress,
          download: download,
          episodeProgress: epProgress,
          fallbackCover: fallbackCover,
          onTap: onItemTap,
          onLongPress: onLongPressItem,
          onDownload: isDownloaded ? null : onDownloadItem,
          onMoreOptions:
              () =>
                  _showEpisodeMenu(context, ep, isWatched, download: download),
          isSelected: isSelected,
          isSelectionMode: _isSelectionMode,
        ),
        EpisodeViewMode.compact => EpisodeCompactItem(
          episode: ep,
          index: index,
          isWatched: isWatched,
          watchProgress: watchProgress,
          download: download,
          episodeProgress: epProgress,
          onTap: onItemTap,
          onMoreOptions:
              () =>
                  _showEpisodeMenu(context, ep, isWatched, download: download),
          onDownload: isDownloaded ? null : onDownloadItem,
          onLongPress: onLongPressItem,
          isSelected: isSelected,
          isSelectionMode: _isSelectionMode,
          isHindi: _isCurrentSourceHindi(ref),
        ),
        EpisodeViewMode.block => EpisodeBlockItem(
          episode: ep,
          index: index,
          isWatched: isWatched,
          watchProgress: watchProgress,
          download: download,
          onTap: onItemTap,
          onLongPress: onLongPressItem,
          onDownload: isDownloaded ? null : onDownloadItem,
          isSelected: isSelected,
          isSelectionMode: _isSelectionMode,
        ),
        EpisodeViewMode.banner => EpisodeBannerItem(
          episode: ep,
          index: index,
          isWatched: isWatched,
          watchProgress: watchProgress,
          download: download,
          episodeProgress: epProgress,
          fallbackCover: fallbackCover,
          onTap: onItemTap,
          onMoreOptions:
              () =>
                  _showEpisodeMenu(context, ep, isWatched, download: download),
          onDownload: isDownloaded ? null : onDownloadItem,
          onLongPress: onLongPressItem,
          isSelected: isSelected,
          isSelectionMode: _isSelectionMode,
        ),
        EpisodeViewMode.list => EpisodeListItem(
          episode: ep,
          index: index,
          isWatched: isWatched,
          watchProgress: watchProgress,
          download: download,
          episodeProgress: epProgress,
          fallbackCover: fallbackCover,
          onTap: onItemTap,
          onMoreOptions:
              () =>
                  _showEpisodeMenu(context, ep, isWatched, download: download),
          onDownload: isDownloaded ? null : onDownloadItem,
          onLongPress: onLongPressItem,
          isSelected: isSelected,
          isSelectionMode: _isSelectionMode,
          isHindi: _isCurrentSourceHindi(ref),
          isMovie:
              widget.mediaFormat.toUpperCase() == 'MOVIE' ||
              widget.anime?.format?.toUpperCase() == 'MOVIE',
        ),
      };
      if (epNum == _autoScrollEpisode) {
        return KeyedSubtree(key: _currentEpisodeKey, child: itemWidget);
      }
      return itemWidget;
    }

    if (viewMode == EpisodeViewMode.grid) {
      return SliverPadding(
        padding: const EdgeInsets.all(12),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 180,
            childAspectRatio: 0.75,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) => buildItem(context, index),
            childCount: visibleEpisodes.length,
          ),
        ),
      );
    } else if (viewMode == EpisodeViewMode.block) {
      return SliverPadding(
        padding: const EdgeInsets.all(12),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 80,
            childAspectRatio: 1.0,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) => buildItem(context, index),
            childCount: visibleEpisodes.length,
          ),
        ),
      );
    } else if (viewMode == EpisodeViewMode.banner) {
      return SliverPadding(
        padding: const EdgeInsets.fromLTRB(0, 6, 0, 100),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => buildItem(context, index),
            childCount: visibleEpisodes.length,
          ),
        ),
      );
    } else if (viewMode == EpisodeViewMode.list) {
      return SliverPadding(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 100),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => buildItem(context, index),
            childCount: visibleEpisodes.length,
          ),
        ),
      );
    } else {
      return SliverPadding(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 100),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => buildItem(context, index),
            childCount: visibleEpisodes.length,
          ),
        ),
      );
    }
  }

  void _navigateToWatch(
    EpisodeDataModel ep,
    List<EpisodeDataModel> episodes,
    String animeIdForSource,
  ) {
    final savedProgress = ref
        .read(watchProgressRepositoryProvider)
        .getEpisodeProgress(widget.mediaId, ep.number ?? 1);
    final savedSeconds = savedProgress?.progressInSeconds ?? 0;
    final savedDuration = savedProgress?.durationInSeconds ?? 0;
    final shouldResume =
        savedSeconds > 0 &&
        !(savedDuration > 0 && savedSeconds >= savedDuration - 20);

    navigateToWatch(
      mediaId: widget.mediaId,
      animeId: animeIdForSource,
      animeName:
          (widget.mediaTitle.english ??
              widget.mediaTitle.romaji ??
              widget.mediaTitle.native)!,
      animeFormat: widget.mediaFormat,
      animeCover: widget.mediaCover,
      context: context,
      episodes: episodes,
      currentEpisode: ep.number ?? 1,
      startAtPosition: shouldResume ? savedSeconds : null,
      malId: widget.malId,
      fromHentaiHub: widget.fromHentaiHub,
    );
  }

  void _showSourceSelectionDialog(
    BuildContext context,
    WidgetRef ref,
    DetailsPageNotifier notifier,
  ) {
    final theme = Theme.of(context);

    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: theme.scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            String searchQuery = '';
            return StatefulBuilder(
              builder: (context, setState) {
                return Consumer(
                  builder: (context, ref, _) {
                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16.0),
                          child: Center(
                            child: Container(
                              width: 40,
                              height: 4,
                              decoration: BoxDecoration(
                                color: theme.dividerColor.withValues(
                                  alpha: 0.5,
                                ),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Select Source',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                decoration: InputDecoration(
                                  hintText: 'Search sources...',
                                  prefixIcon: const Icon(Icons.search),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                  fillColor:
                                      theme.colorScheme.surfaceContainerHighest,
                                  filled: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                ),
                                onChanged: (value) {
                                  setState(() => searchQuery = value);
                                },
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: _buildUnifiedSourceList(
                            ref,
                            scrollController,
                            notifier,
                            searchQuery,
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  bool _hasHindiExtension(SourceState state) {
    return state.installedAnimeExtensions.any((s) =>
        s.lang == 'hi' ||
        s.lang == 'hin' ||
        (s.name ?? '').toLowerCase().contains('toonstream') ||
        (s.name ?? '').toLowerCase().contains('animedub') ||
        (s.name ?? '').toLowerCase().contains('moviebox'));
  }

  bool _isCurrentSourceHindi(WidgetRef ref) {
    final nativeKey = ref.watch(selectedProviderKeyProvider)?.toLowerCase();
    if (nativeKey == 'justanime' || nativeKey == 'hianime' || nativeKey == 'anikoto') {
      return false;
    }
    final useExt = ref.watch(experimentalProvider).useExtensions;
    if (!useExt) return false;
    final active = ref.watch(sourceProvider).activeAnimeSource;
    if (active == null) return false;
    final name = (active.name ?? '').toLowerCase();
    final lang = (active.lang ?? '').toLowerCase();
    if (name.contains('justanime') || name.contains('hianime') || name.contains('anikoto')) {
      return false;
    }
    return lang == 'hi' ||
        lang == 'hin' ||
        name.contains('toonstream') ||
        name.contains('animedub') ||
        name.contains('moviebox');
  }

  Widget _buildHindiAvailabilityBanner(
    BuildContext context,
    WidgetRef ref,
    DetailsPageNotifier notifier,
    SourceState sourceState,
  ) {
    final theme = Theme.of(context);
    // Priority: Toonstream > AnimeDub > hi/hin > Moviebox
    Source? hindiSource = sourceState.installedAnimeExtensions.firstWhereOrNull(
      (s) => (s.name ?? '').toLowerCase().contains('toonstream'),
    );
    hindiSource ??= sourceState.installedAnimeExtensions.firstWhereOrNull(
      (s) => (s.name ?? '').toLowerCase().contains('animedub'),
    );
    hindiSource ??= sourceState.installedAnimeExtensions.firstWhereOrNull(
      (s) => (s.lang ?? '').toLowerCase() == 'hi' || (s.lang ?? '').toLowerCase() == 'hin',
    );
    hindiSource ??= sourceState.installedAnimeExtensions.firstWhereOrNull(
      (s) => (s.name ?? '').toLowerCase().contains('moviebox'),
    );
    if (hindiSource == null) return const SizedBox.shrink();
    final targetSource = hindiSource;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.orange.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.translate_rounded, color: Colors.orange, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Also in Hindi (हिन्दी डब उपलब्ध)',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.orange.shade800,
                  ),
                ),
                Text(
                  'Switch to ${hindiSource.name} for Hindi audio',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.8),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () {
              ref.read(selectedProviderKeyProvider.notifier).clear();
              ref.read(sourceProvider.notifier).setActiveSource(targetSource);
              ref.read(experimentalProvider.notifier).toggleExtensions(true);
              ref.read(sourcePreferenceRepositoryProvider).clearSourcePreference(widget.mediaId);
              notifier.refresh();
            },
            child: const Text(
              'Switch',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnifiedSourceList(
    WidgetRef ref,
    ScrollController scrollController,
    DetailsPageNotifier notifier,
    String query,
  ) {
    final theme = Theme.of(ref.context);
    final sourceState = ref.watch(sourceProvider);
    final useExtensions = ref.watch(experimentalProvider).useExtensions;
    final activeId =
        sourceState.activeAdultAnimeSource?.id ??
        sourceState.activeAnimeSource?.id;
    final currentNativeKey =
        ref.watch(selectedProviderKeyProvider)?.toLowerCase() ?? 'justanime';

    final allAvailable = <Source>[
      ...sourceState.installedAdultAnimeExtensions,
      ...sourceState.installedAnimeExtensions,
    ];
    final seenIds = <String>{};
    final uniqueAvailable =
        allAvailable.where((s) {
          final key = (s.id?.toString() ?? s.name ?? '').trim();
          if (key.isEmpty) return true;
          return seenIds.add(key);
        }).toList();

    final q = query.trim().toLowerCase();

    // 1. Native Built-in servers
    final nativeServers = [
      (
        key: 'justanime',
        name: 'JustAnime',
        subtitle: 'Official Global Server • Multi-Quality SUB/DUB',
        icon: Icons.play_circle_fill_rounded,
      ),
      (
        key: 'hianime',
        name: 'HiAnime',
        subtitle: 'Official Fast Server • High Speed Sub & Dub',
        icon: Icons.bolt_rounded,
      ),
      (
        key: 'anikoto',
        name: 'AniKoto',
        subtitle: 'Official Alternative Fast Server',
        icon: Icons.video_library_rounded,
      ),
    ].where((n) => q.isEmpty || n.name.toLowerCase().contains(q)).toList();

    // 2. Installed Extensions
    final filteredExtensions = uniqueAvailable.where((s) {
      if (q.isEmpty) return true;
      return (s.name ?? '').toLowerCase().contains(q);
    }).toList()..sort((a, b) => (a.name ?? '').compareTo(b.name ?? ''));

    bool isHindi(Source s) {
      final name = (s.name ?? '').toLowerCase();
      final lang = (s.lang ?? '').toLowerCase();
      return lang == 'hi' ||
          lang == 'hin' ||
          name.contains('toonstream') ||
          name.contains('animedub') ||
          name.contains('moviebox');
    }

    bool isOfficialServer(Source s) {
      final name = (s.name ?? '').toLowerCase();
      final id = (s.id ?? '').toLowerCase();
      return name.contains('justanime') ||
          name.contains('hianime') ||
          name.contains('anikoto') ||
          id.contains('justanime') ||
          id.contains('hianime') ||
          id.contains('anikoto');
    }

    final hindiExtensions = filteredExtensions.where(isHindi).toList();
    final otherExtensions = filteredExtensions
        .where((s) => !isHindi(s) && !isOfficialServer(s))
        .toList();

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      children: [
        // Built-in section
        if (nativeServers.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Text(
              '⭐ OFFICIAL SERVERS',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.6,
              ),
            ),
          ),
          for (final server in nativeServers) ...[
            () {
              final matchingExt = uniqueAvailable.firstWhereOrNull((s) {
                final name = (s.name ?? '').toLowerCase();
                final id = (s.id ?? '').toLowerCase();
                return name.contains(server.key) || id.contains(server.key);
              });
              final fallbackIcon = {
                'justanime':
                    'https://raw.githubusercontent.com/m2k3a/mangayomi-extensions/main/anime/icon/en.justanime.png',
                'hianime':
                    'https://raw.githubusercontent.com/m2k3a/mangayomi-extensions/main/anime/icon/en.hianime.png',
                'anikoto':
                    'https://raw.githubusercontent.com/m2k3a/mangayomi-extensions/main/anime/icon/en.anikoto.png',
              }[server.key];
              final iconUrl =
                  (matchingExt?.iconUrl != null &&
                          matchingExt!.iconUrl!.isNotEmpty)
                      ? matchingExt.iconUrl
                      : fallbackIcon;

              final activeSourceName = (sourceState.activeAdultAnimeSource?.name ??
                      sourceState.activeAnimeSource?.name ??
                      '')
                  .toLowerCase();
              final isSelected = currentNativeKey == server.key;

              return ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: theme.colorScheme.surfaceContainerHighest,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: (iconUrl != null && iconUrl.isNotEmpty)
                      ? CachedNetworkImage(
                          imageUrl: iconUrl,
                          fit: BoxFit.cover,
                          placeholder: (_, _) => Container(
                            color: theme.colorScheme.primary.withValues(alpha: 0.1),
                            child: Icon(
                              server.icon,
                              color: theme.colorScheme.primary,
                              size: 20,
                            ),
                          ),
                          errorWidget: (_, _, _) => Image.asset(
                            'assets/icons/anidash_logo.png',
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Icon(
                              server.icon,
                              color: theme.colorScheme.primary,
                              size: 20,
                            ),
                          ),
                        )
                      : Image.asset(
                          'assets/icons/anidash_logo.png',
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Icon(
                            server.icon,
                            color: theme.colorScheme.primary,
                            size: 20,
                          ),
                        ),
                ),
                title: Row(
                  children: [
                    Text(
                      server.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'OFFICIAL',
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 9,
                        ),
                      ),
                    ),
                  ],
                ),
                subtitle: Text(
                  server.subtitle,
                  style: const TextStyle(fontSize: 12),
                ),
                selected: isSelected,
                trailing: isSelected
                    ? Icon(
                        Icons.check_circle_rounded,
                        color: theme.colorScheme.primary,
                      )
                    : null,
                onTap: () {
                  ref.read(selectedProviderKeyProvider.notifier).select(server.key);
                  if (matchingExt != null) {
                    ref.read(sourceProvider.notifier).setActiveSource(matchingExt);
                    ref.read(experimentalProvider.notifier).toggleExtensions(true);
                  } else {
                    ref.read(experimentalProvider.notifier).toggleExtensions(false);
                  }
                  ref
                      .read(sourcePreferenceRepositoryProvider)
                      .clearSourcePreference(widget.mediaId);
                  Navigator.pop(ref.context);
                  notifier.refresh();
                },
              );
            }(),
          ],
        ],

        // Hindi section
        if (hindiExtensions.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
            child: Row(
              children: [
                const Text('🇮🇳 ', style: TextStyle(fontSize: 14)),
                Text(
                  'HINDI ANIME SOURCES (हिन्दी डब)',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: Colors.orange.shade700,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
          ),
          for (final source in hindiExtensions) ...[
            ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: Colors.orange.withValues(alpha: 0.15),
                ),
                clipBehavior: Clip.antiAlias,
                child: source.iconUrl != null
                    ? CachedNetworkImage(
                        imageUrl: source.iconUrl!,
                        fit: BoxFit.cover,
                        errorWidget: (_, _, _) =>
                            const Icon(Icons.translate_rounded, color: Colors.orange, size: 20),
                      )
                    : const Icon(Icons.translate_rounded, color: Colors.orange, size: 20),
              ),
              title: Row(
                children: [
                  Text(
                    source.name ?? 'Hindi Source',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'HINDI',
                      style: TextStyle(
                        color: Colors.orange,
                        fontWeight: FontWeight.bold,
                        fontSize: 9,
                      ),
                    ),
                  ),
                ],
              ),
              subtitle: Text(
                'हिन्दी Audio Dub & Sub • Extension',
                style: TextStyle(fontSize: 12, color: theme.hintColor),
              ),
              selected: useExtensions && source.id == activeId,
              trailing: (useExtensions && source.id == activeId)
                  ? const Icon(Icons.check_circle_rounded, color: Colors.orange)
                  : null,
              onTap: () {
                ref.read(selectedProviderKeyProvider.notifier).clear();
                ref.read(sourceProvider.notifier).setActiveSource(source);
                ref.read(experimentalProvider.notifier).toggleExtensions(true);
                ref.read(sourcePreferenceRepositoryProvider).clearSourcePreference(widget.mediaId);
                Navigator.pop(ref.context);
                notifier.refresh();
              },
            ),
          ],
        ],

        // Other extensions section
        if (otherExtensions.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
            child: Text(
              '🧩 OTHER EXTENSIONS',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.6,
              ),
            ),
          ),
          for (final source in otherExtensions) ...[
            ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: theme.colorScheme.surfaceContainerHighest,
                ),
                clipBehavior: Clip.antiAlias,
                child: source.iconUrl != null
                    ? CachedNetworkImage(
                        imageUrl: source.iconUrl!,
                        fit: BoxFit.cover,
                        errorWidget: (_, _, _) => const Icon(Icons.extension, size: 20),
                      )
                    : const Icon(Icons.extension, size: 20),
              ),
              title: Text(source.name ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(source.lang?.toUpperCase() ?? 'Extension', style: const TextStyle(fontSize: 12)),
              selected: useExtensions && source.id == activeId,
              trailing: (useExtensions && source.id == activeId)
                  ? Icon(Icons.check_circle_rounded, color: theme.colorScheme.primary)
                  : null,
              onTap: () {
                ref.read(selectedProviderKeyProvider.notifier).clear();
                ref.read(sourceProvider.notifier).setActiveSource(source);
                ref.read(experimentalProvider.notifier).toggleExtensions(true);
                ref.read(sourcePreferenceRepositoryProvider).clearSourcePreference(widget.mediaId);
                Navigator.pop(ref.context);
                notifier.refresh();
              },
            ),
          ],
        ],
      ],
    );
  }

  Future<void> _handleWrongMatch(
    BuildContext context,
    WidgetRef ref,
    DetailsPageNotifier notifier,
  ) async {
    final currentState = ref.read(detailsPageProvider(widget.mediaId));
    AppLogger.i(
      'User reported a wrong match. Best match was: ${currentState.bestMatchName}',
    );

    final anime = await providerAnimeMatchSearch(
      withAnimeMatch: false,
      beforeSearchCallback: () => null,
      afterSearchCallback: () => null,
      context: context,
      ref: ref,
      animeMedia: UniversalMedia(
        title: widget.mediaTitle,
        id: widget.mediaId,
        format: widget.mediaFormat,
        coverImage: UniversalCoverImage(
          large: widget.mediaCover,
          medium: widget.mediaCover,
        ),
      ),
    );

    if (!mounted) return;
    if (anime != null) {
      AppLogger.d('Selected anime: ${anime.id}');
      notifier.setManualMatch(anime.id!, anime.name!);
    }
  }

  void _showEpisodeMenu(
    BuildContext context,
    EpisodeDataModel episode,
    bool isWatched, {
    DownloadItem? download,
  }) {
    final repo = ref.read(watchProgressRepositoryProvider);
    final epNum = episode.number ?? 1;
    final isDownloaded =
        download != null && download.state == DownloadStatus.downloaded;
    final animeTitle =
        widget.mediaTitle.english ??
        widget.mediaTitle.romaji ??
        widget.mediaTitle.native ??
        'Unknown';

    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 12.0,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  episode.title ?? 'Episode $epNum',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (episode.isFiller == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Text(
                      'FILLER',
                      style: TextStyle(
                        color: Colors.orange.shade700,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                const Divider(height: 20),
                FutureBuilder<({bool sub, bool dub})>(
                  future: ref
                      .read(episodeDataProvider.notifier)
                      .checkLanguageAvailability(episode),
                  builder: (context, snapshot) {
                    final availability = snapshot.data;
                    return ListTile(
                      leading: const Icon(Icons.info_outline_rounded),
                      title: const Text('Audio availability'),
                      subtitle:
                          snapshot.connectionState == ConnectionState.waiting
                              ? const Text(
                                'Checking SUB and DUB availability…',
                              )
                              : Text(
                                'SUB: ${availability?.sub == true ? "Available" : "Unavailable"}\n'
                                'DUB: ${availability?.dub == true ? "Available" : "Unavailable"}',
                              ),
                    );
                  },
                ),
                ListTile(
                  leading: Icon(
                    isWatched
                        ? Icons.remove_red_eye_outlined
                        : Icons.check_circle_outline_rounded,
                    color: isWatched ? Colors.orange : Colors.green,
                  ),
                  title: Text(
                    isWatched ? 'Mark as Unwatched' : 'Mark as Watched',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  onTap: () async {
                    final newWatched = !isWatched;
                    final existing = repo.getProgress(widget.mediaId);
                    final totalEpisodes =
                        (widget.anime?.episodes ?? 0) > 0
                            ? widget.anime!.episodes!
                            : (widget.mediaFormat.toUpperCase() == 'MOVIE'
                                ? 1
                                : ref
                                    .read(episodeListProvider)
                                    .episodes
                                    .length);
                    final episodesMap = Map<int, EpisodeProgress>.from(
                      existing?.episodesProgress ?? const {},
                    );
                    episodesMap[epNum] = EpisodeProgress(
                      episodeNumber: epNum,
                      episodeTitle:
                          episode.title ??
                          (widget.mediaFormat.toUpperCase() == 'MOVIE'
                              ? animeTitle
                              : 'Episode $epNum'),
                      episodeThumbnail: episode.thumbnail ?? widget.mediaCover,
                      progressInSeconds: newWatched ? 1440 : 0,
                      durationInSeconds: 1440,
                      isCompleted: newWatched,
                      watchedAt: DateTime.now(),
                    );
                    final isComplete =
                        newWatched &&
                        totalEpisodes > 0 &&
                        epNum >= totalEpisodes;
                    final updated = (existing ??
                            AnimeWatchProgressEntry(
                              animeId: widget.mediaId,
                              animeTitle: animeTitle,
                              animeCover: widget.mediaCover,
                              animeFormat: widget.mediaFormat,
                              totalEpisodes: totalEpisodes,
                            ))
                        .copyWith(
                          animeTitle: animeTitle,
                          animeCover: widget.mediaCover,
                          animeFormat: widget.mediaFormat,
                          totalEpisodes: totalEpisodes,
                          currentEpisode: epNum,
                          episodesProgress: episodesMap,
                          status: isComplete ? 'completed' : 'watching',
                          lastUpdated: DateTime.now(),
                          lastPlayedAt: existing?.lastPlayedAt,
                        );
                    // Save the complete state atomically. Previously the empty
                    // shell entry and episode update raced, which could leave
                    // a one-part movie as a fake "EP 2" Continue card.
                    await repo.saveProgress(updated);
                    if (newWatched) {
                      await ref
                          .read(watchSyncProvider.notifier)
                          .handleTrackingUpdate(
                            mediaId: widget.mediaId,
                            episodeNum: epNum,
                          );
                    }
                    if (!sheetContext.mounted) return;
                    Navigator.pop(sheetContext);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          newWatched
                              ? 'Marked Episode $epNum as watched'
                              : 'Marked Episode $epNum as unwatched',
                        ),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(
                    Icons.checklist_rounded,
                    color: Colors.purpleAccent,
                  ),
                  title: const Text(
                    'Select Episodes',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text('Enter multi-selection mode'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _enterSelectionMode(epNum);
                  },
                ),
                ListTile(
                  leading: const Icon(
                    Icons.done_all_rounded,
                    color: Colors.blueAccent,
                  ),
                  title: Text(
                    'Mark All Previous Episodes (1–$epNum)',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'Marks all previous episodes as watched',
                  ),
                  onTap: () async {
                    final totalEps =
                        (widget.anime?.episodes != null &&
                                widget.anime!.episodes! > 0)
                            ? widget.anime!.episodes!
                            : ref.read(episodeListProvider).episodes.length;
                    await repo.markPreviousEpisodesWatched(
                      animeId: widget.mediaId,
                      animeTitle: animeTitle,
                      animeCover: widget.mediaCover,
                      animeFormat: widget.mediaFormat,
                      upToEpisodeNumber: epNum,
                      totalEpisodes: totalEps > 0 ? totalEps : null,
                    );
                    ref
                        .read(watchSyncProvider.notifier)
                        .handleTrackingUpdate(
                          mediaId: widget.mediaId,
                          episodeNum: epNum,
                        );
                    if (sheetContext.mounted) {
                      Navigator.pop(sheetContext);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Marked episodes 1 to $epNum as watched',
                          ),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                ),
                if (isDownloaded)
                  ListTile(
                    leading: const Icon(
                      Icons.delete_outline_rounded,
                      color: Colors.red,
                    ),
                    title: const Text(
                      'Remove Download',
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onTap: () {
                      ref
                          .read(downloadsProvider.notifier)
                          .deleteDownload(download);
                      Navigator.pop(sheetContext);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Removed download for Episode $epNum'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildContinueWatchingBanner(
    BuildContext context,
    EpisodeDataModel ep,
    EpisodeProgress? progress,
    List<EpisodeDataModel> allEpisodes,
    String animeIdForSource,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final epNum = ep.number ?? 1;
    final watchedSeconds = progress?.progressInSeconds ?? 0;
    final totalSeconds = progress?.durationInSeconds ?? 0;
    final inProgress =
        progress != null &&
        !progress.isCompleted &&
        watchedSeconds > 0 &&
        totalSeconds > 0;
    final progressFraction =
        inProgress ? (watchedSeconds / totalSeconds).clamp(0.0, 1.0) : 0.0;

    final remainingSeconds =
        totalSeconds > watchedSeconds ? totalSeconds - watchedSeconds : 0;
    final resumeText =
        inProgress
            ? '${_formatDuration(watchedSeconds)} watched · ${_formatDuration(remainingSeconds)} left'
            : (progress?.isCompleted == true ? 'Completed' : 'Next to play');

    final thumbUrl =
        ep.thumbnail?.isNotEmpty == true ? ep.thumbnail! : widget.mediaCover;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Material(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _navigateToWatch(ep, allEpisodes, animeIdForSource),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 105,
                    height: 64,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CachedNetworkImage(
                          imageUrl: thumbUrl,
                          fit: BoxFit.cover,
                          errorWidget:
                              (_, __, ___) => Container(
                                color: colorScheme.surfaceContainer,
                                child: Icon(
                                  Icons.movie_outlined,
                                  color: theme.hintColor,
                                ),
                              ),
                        ),
                        Container(
                          color: Colors.black38,
                          child: const Center(
                            child: Icon(
                              Icons.play_circle_fill_rounded,
                              color: Colors.white,
                              size: 32,
                            ),
                          ),
                        ),
                        if (inProgress)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: LinearProgressIndicator(
                              value: progressFraction,
                              minHeight: 3.5,
                              backgroundColor: Colors.black54,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                colorScheme.primary,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              inProgress ? 'CONTINUE' : 'NEXT UP',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.w800,
                                fontSize: 9.5,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            (widget.mediaFormat.toUpperCase() == 'MOVIE' ||
                                    widget.anime?.format?.toUpperCase() ==
                                        'MOVIE')
                                ? 'MOVIE'
                                : 'EP $epNum',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        ep.title?.isNotEmpty == true
                            ? ep.title!
                            : ((widget.mediaFormat.toUpperCase() == 'MOVIE' ||
                                    widget.anime?.format?.toUpperCase() ==
                                        'MOVIE')
                                ? (widget.mediaTitle.english ??
                                    widget.mediaTitle.romaji ??
                                    'Movie')
                                : 'Episode $epNum'),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        resumeText,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.hintColor,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                IconButton.filledTonal(
                  onPressed:
                      () => _navigateToWatch(ep, allEpisodes, animeIdForSource),
                  icon: const Icon(Icons.play_arrow_rounded, size: 24),
                ),
                IconButton(
                  icon: const Icon(Icons.more_vert),
                  tooltip: 'Options',
                  onPressed:
                      () => _showEpisodeMenu(
                        context,
                        ep,
                        progress?.isCompleted == true,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Widget _buildEmptyEpisodesView(BuildContext context, ThemeData theme) {
    final anime = widget.anime;
    final isUnreleased = anime?.isUnreleased ?? false;
    final colors = theme.colorScheme;

    if (isUnreleased) {
      String dateText = 'Coming Soon';
      String countdownText = '';
      if (anime?.nextAiringEpisode?.airingAt != null) {
        final airDate = DateTime.fromMillisecondsSinceEpoch(
          anime!.nextAiringEpisode!.airingAt! * 1000,
        );
        final diff = airDate.difference(DateTime.now());
        if (diff.isNegative) {
          dateText = 'Airing Soon';
        } else if (diff.inDays > 0) {
          countdownText = 'Airs in ${diff.inDays}d ${diff.inHours % 24}h';
          dateText =
              'Episode ${anime.nextAiringEpisode?.episode ?? 1} on ${airDate.day}/${airDate.month}/${airDate.year}';
        } else {
          countdownText = 'Airs in ${diff.inHours}h ${diff.inMinutes % 60}m';
          dateText = 'Episode ${anime.nextAiringEpisode?.episode ?? 1} today';
        }
      } else if (anime?.startDate != null && anime!.startDate!.year != null) {
        final d = anime.startDate!;
        dateText = 'Release: ${d.month != null ? "${d.month}/" : ""}${d.year}';
      }

      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.schedule_rounded,
                  size: 32,
                  color: colors.primary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Not Yet Released',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colors.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                dateText,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (countdownText.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  countdownText,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                'Episodes will automatically appear here once broadcast begins.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.movie_filter_outlined, size: 48, color: colors.outline),
            const SizedBox(height: 12),
            Text(
              'No episodes found on this provider',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => ref.read(detailsPageProvider(widget.mediaId).notifier).refresh(),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SliverToolbarDelegate extends SliverPersistentHeaderDelegate {
  _SliverToolbarDelegate({
    required this.minHeight,
    required this.maxHeight,
    required this.child,
  });

  final double minHeight;
  final double maxHeight;
  final Widget child;

  @override
  double get minExtent => minHeight;
  @override
  double get maxExtent => maxHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return SizedBox.expand(child: child);
  }

  @override
  bool shouldRebuild(_SliverToolbarDelegate oldDelegate) {
    return maxHeight != oldDelegate.maxHeight ||
        minHeight != oldDelegate.minHeight ||
        child != oldDelegate.child;
  }
}
