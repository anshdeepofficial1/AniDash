// ignore_for_file: curly_braces_in_flow_control_structures
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ani_dash/core/models/universal/universal_news.dart';
import 'package:ani_dash/data/hive/models/anime_watch_progress_model.dart';
import 'package:ani_dash/core/utils/app_logger.dart';

import 'package:ani_dash/main.dart';
import 'package:ani_dash/core/models/anime/page_model.dart';
import 'package:ani_dash/core/models/universal/universal_media.dart';
import 'package:ani_dash/core/models/universal/universal_page_response.dart';
import 'package:ani_dash/core/repositories/watch_progress_repository.dart';
import 'package:ani_dash/features/home/model/home_section.dart';
import 'package:ani_dash/shared/providers/settings/home_layout_notifier.dart';
import 'package:ani_dash/features/home/view/widget/continue_section.dart';
import 'package:ani_dash/features/home/view_model/homepage_notifier.dart';
import 'package:ani_dash/features/home/view/widget/header_section.dart';
import 'package:ani_dash/features/home/view/widget/home_section.dart';
import 'package:ani_dash/features/home/view/widget/spotlight_section.dart';
import 'package:ani_dash/features/browse/view/section_screen.dart';
import 'package:ani_dash/shared/providers/anime_repo_provider.dart';
import 'package:ani_dash/features/news/view_model/news_provider.dart';
import 'package:ani_dash/features/watchlist/view_model/watchlist_notifier.dart';
import 'package:ani_dash/shared/auth/providers/auth_notifier.dart';
import 'package:ani_dash/shared/providers/continue_watching_dismissed_provider.dart';
import 'package:ani_dash/shared/providers/settings/notification_settings_notifier.dart';
import 'package:go_router/go_router.dart';
import 'package:ani_dash/shared/providers/settings/ui_notifier.dart';
import 'package:ani_dash/shared/ui/adaptive_media_skeleton.dart';
import 'package:ani_dash/features/ai/view/widgets/anidash_ai_emblem.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  late final ProviderSubscription<AsyncValue<List<UniversalNews>>>
  _newsListener;
  late final ProviderSubscription<AuthState> _authListener;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setAppOpenStatus(true);
    _setupAuthListener();
    _setupNewsListener();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showWhatsNew());
    Future.microtask(() {
      if (!mounted) return;
      final auth = ref.read(authProvider);
      if (auth.isAniListAuthenticated || auth.isMalAuthenticated) {
        _syncAccountWatchProgress();
      }
    });
  }

  Future<void> _showWhatsNew() async {
    const version = '1.18.1';
    if (!mounted || sharedPrefs.getString('whats_new_seen') == version) return;
    await sharedPrefs.setString('whats_new_seen', version);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            icon: Container(
              width: 84,
              height: 84,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Theme.of(
                      dialogContext,
                    ).colorScheme.primary.withValues(alpha: 0.22),
                    Theme.of(
                      dialogContext,
                    ).colorScheme.tertiary.withValues(alpha: 0.08),
                  ],
                ),
                border: Border.all(
                  color: Theme.of(
                    dialogContext,
                  ).colorScheme.primary.withValues(alpha: 0.3),
                  width: 1.5,
                ),
              ),
              child: const AniDashAiEmblem(size: 44),
            ),
            title: const Text(
              "Introducing AniDash AI ✨",
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            content: const Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Meet AniDash AI (AnyCore)',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 4),
                Text(
                  'Your smart companion for anime insights, characters, episode summaries, watch order, and personal recommendations.',
                ),
                SizedBox(height: 12),
                Text(
                  'Supercharged Playback & Matching',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 4),
                Text(
                  'Instant stream discovery with direct manual fallback, reliable Continue Watching titles, and auto-scrolling episode panel.',
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Try Later'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  if (mounted) context.push('/ai');
                },
                child: const Text('Explore'),
              ),
            ],
          ),
    );
  }

  void _setupAuthListener() {
    _authListener = ref.listenManual(authProvider, (previous, next) {
      if (!mounted) return;
      final wasAuthed =
          (previous?.isAniListAuthenticated ?? false) ||
          (previous?.isMalAuthenticated ?? false);
      final isAuthed = next.isAniListAuthenticated || next.isMalAuthenticated;
      if (!wasAuthed && isAuthed) {
        AppLogger.i('Auth restored/ready, triggering account sync...');
        _syncAccountWatchProgress();
      }
    });
  }

  void _setupNewsListener() {
    _newsListener = ref.listenManual(newsProvider, (previous, next) {
      if (!ref.read(notificationSettingsProvider).enableNews) return;
      if (previous is AsyncData && next is AsyncData) {
        if (!mounted) return;
        final router = GoRouter.of(context);
        final String currentLocation =
            router.routerDelegate.currentConfiguration.last.matchedLocation;
        const mainTabs = {'/', '/browse', '/downloads', '/watchlist'};

        if (!mainTabs.contains(currentLocation)) return;

        final oldList = previous?.value ?? [];
        final newList = next.value ?? [];
        final oldUrls = oldList.map((e) => e.url).toSet();
        final newItems =
            newList.where((e) => !oldUrls.contains(e.url)).toList();

        if (newItems.isNotEmpty) {
          final count = newItems.length;
          final message =
              count == 1
                  ? 'New Article: ${newItems.first.title ?? "Check it out!"}'
                  : '$count New Articles Available!';

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              action: SnackBarAction(
                label: 'VIEW',
                onPressed: () => context.push('/news'),
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    });
  }

  @override
  void dispose() {
    _setAppOpenStatus(false);
    _authListener.close();
    _newsListener.close();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // let background tasks know if we're actually looking at the app
  Future<void> _setAppOpenStatus(bool isOpen) async {
    await sharedPrefs.setBool('is_app_open', isOpen);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final isOpen = state == AppLifecycleState.resumed;
    _setAppOpenStatus(isOpen);
    if (isOpen) {
      _syncAccountWatchProgress();
    }
  }

  Future<void> _syncAccountWatchProgress() async {
    try {
      final auth = ref.read(authProvider);
      if (!auth.isAniListAuthenticated && !auth.isMalAuthenticated) return;

      final statusQuery = auth.isMalAuthenticated ? 'watching' : 'CURRENT';

      // Also trigger watchlistProvider to fetch watching list in background
      ref.read(watchlistProvider.notifier).fetchListForStatus(statusQuery);

      final repo = ref.read(animeRepositoryProvider);
      final response = await repo.getUserAnimeList(
        type: 'ANIME',
        status: statusQuery,
        page: 1,
        perPage: 50,
      );

      if (response.data.isEmpty) return;

      final progressRepo = ref.read(watchProgressRepositoryProvider);

      for (final entry in response.data) {
        final media = entry.media;
        final mediaId = media.id;
        final targetProgress = entry.progress > 0 ? entry.progress : 1;

        final local = progressRepo.getProgress(mediaId);

        final localEpisode =
            local == null ? null : local.episodesProgress[local.currentEpisode];
        final localDuration = localEpisode?.durationInSeconds ?? 0;
        final localPosition = localEpisode?.progressInSeconds ?? 0;
        final hasUnfinishedLocalEpisode =
            localEpisode != null &&
            localPosition > 0 &&
            !localEpisode.isCompleted &&
            (localDuration <= 0 || localPosition / localDuration < 0.90);
        if (hasUnfinishedLocalEpisode) {
          // A remote tracker stores episode counts, not exact playback time.
          // Never let it skip a locally unfinished episode.
          continue;
        }

        if (local != null && local.currentEpisode > targetProgress) {
          continue;
        }

        final episodesMap = Map<int, EpisodeProgress>.from(
          local?.episodesProgress ?? {},
        );

        for (int i = 1; i <= targetProgress; i++) {
          final existing = episodesMap[i];
          if (existing == null || !existing.isCompleted) {
            episodesMap[i] = EpisodeProgress(
              episodeNumber: i,
              episodeTitle: existing?.episodeTitle ?? 'Episode $i',
              episodeThumbnail: existing?.episodeThumbnail,
              progressInSeconds:
                  existing?.progressInSeconds ??
                  (i == targetProgress && entry.progress == 0 ? 0 : 1440),
              durationInSeconds: existing?.durationInSeconds ?? 1440,
              isCompleted: i < targetProgress,
              watchedAt:
                  existing?.watchedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
            );
          }
        }

        final title =
            media.title.english ??
            media.title.romaji ??
            media.title.native ??
            '';
        final cover = media.coverImage.large ?? media.coverImage.medium ?? '';

        final updated = (local ??
                AnimeWatchProgressEntry(
                  animeId: mediaId,
                  animeTitle: title,
                  animeFormat: media.format,
                  animeCover: cover,
                  totalEpisodes: media.episodes ?? 0,
                  episodesProgress: episodesMap,
                  lastUpdated:
                      local?.lastUpdated ??
                      DateTime.fromMillisecondsSinceEpoch(0),
                  lastPlayedAt: local?.lastPlayedAt,
                  currentEpisode: targetProgress,
                  status: 'watching',
                ))
            .copyWith(
              episodesProgress: episodesMap,
              currentEpisode: targetProgress,
              lastPlayedAt: local?.lastPlayedAt,
              status: 'watching',
              animeTitle: title.isNotEmpty ? title : null,
              animeCover: cover.isNotEmpty ? cover : null,
            );

        await progressRepo.saveProgress(updated);
      }
    } catch (e) {
      AppLogger.e('Error syncing account watch progress: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(homepageProvider);
    final layout = ref.watch(homeLayoutProvider);
    final sections = layout.where((s) => s.enabled).toList();

    if (state.isLoading && state.homePage == null) {
      return Scaffold(
        body: ListView(
          padding: const EdgeInsets.only(top: 10, bottom: 100),
          children: const [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: HeaderSection(isDesktop: false),
            ),
            _HomeLoadingSkeleton(),
          ],
        ),
      );
    }

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([
            ref.read(homepageProvider.notifier).fetchHomePage(),
            _syncAccountWatchProgress(),
          ]);
        },
        child: Stack(
          children: [
            ListView.builder(
              padding: const EdgeInsets.only(top: 10),
              itemCount: sections.length + 2,
              itemBuilder: (context, index) {
                if (index == 0)
                  return const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: HeaderSection(isDesktop: false),
                  );

                // bottom spacer so the nav bar doesn't choke the content
                if (index == sections.length + 1)
                  return const SizedBox(height: 80);

                final section = sections[index - 1];

                // Continue Watching section runs independently from remote homePage API
                if (section.type == HomeSectionType.continueWatching) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: _ContinueWatchingSection(),
                  );
                }

                if (state.error != null)
                  return Center(child: Text('Error: ${state.error}'));

                final home = state.homePage;
                if (home == null) return const SizedBox.shrink();

                return _HomeSectionRenderer(section: section, home: home);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeLoadingSkeleton extends StatelessWidget {
  const _HomeLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(10, 12, 10, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SkeletonBox(height: 210, radius: 20),
          SizedBox(height: 28),
          _SkeletonBox(width: 170, height: 24),
          SizedBox(height: 14),
          _SkeletonCardRow(),
          SizedBox(height: 28),
          _SkeletonBox(width: 140, height: 24),
          SizedBox(height: 14),
          _SkeletonCardRow(),
        ],
      ),
    );
  }
}

class _SkeletonCardRow extends ConsumerWidget {
  const _SkeletonCardRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(uiSettingsProvider).cardStyle;
    final size = mode.getDimensions(context);
    return SizedBox(
      height: size.height,
      child: ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        scrollDirection: Axis.horizontal,
        itemCount: (MediaQuery.sizeOf(context).width / size.width).ceil() + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder:
            (_, index) => SizedBox(
              width: size.width,
              height: size.height,
              child: AdaptiveMediaSkeleton(size: size),
            ),
      ),
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  const _SkeletonBox({this.width, required this.height, this.radius = 8});

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

//  handles the switching logic so the main build isn't a mess
class _HomeSectionRenderer extends ConsumerWidget {
  final HomeSection section;
  final HomePage home;

  const _HomeSectionRenderer({required this.section, required this.home});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (section.type) {
      case HomeSectionType.spotlight:
        final spotlight =
            home.trendingAnime.data.isNotEmpty
                ? home.trendingAnime.data
                : home.popularAnime.data.take(25).toList();
        return SpotlightSection(
          spotlightAnime: spotlight.isEmpty ? null : spotlight,
        );

      case HomeSectionType.continueWatching:
        return const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10),
          child: _ContinueWatchingSection(),
        );

      case HomeSectionType.standard:
        final mediaResponse = _getStandardMedia(section.dataId, home);
        if (mediaResponse == null || mediaResponse.data.isEmpty)
          return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: HomeSectionWidget(
            title: section.title,
            mediaList: mediaResponse.data,
            onTitleTap: () {
              final repo = ref.read(animeRepositoryProvider);
              final fetcher = switch (section.dataId) {
                'trending' => repo.getTrendingAnime,
                'popular' => repo.getPopularAnime,
                'top_rated' => repo.getTopRatedAnime,
                'recently_updated' => repo.getRecentlyUpdatedAnime,
                'upcoming' => repo.getUpcomingAnime,
                'most_favorite' => repo.getMostFavoriteAnime,
                _ => null,
              };
              if (fetcher != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (_) => SectionScreen(
                          title: section.title,
                          fetchItems: fetcher,
                          ranked: section.dataId == 'trending',
                        ),
                  ),
                );
              }
            },
          ),
        );

      case HomeSectionType.watchlist:
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: _WatchlistHomeSection(
            title: section.title,
            status: section.dataId!,
          ),
        );
    }
  }

  // mapping the dynamic data IDs to the actual home page lists
  UniversalPageResponse<UniversalMedia>? _getStandardMedia(
    String? id,
    HomePage home,
  ) {
    return switch (id) {
      'trending' => home.trendingAnime,
      'popular' => home.popularAnime,
      'most_favorite' => home.mostFavoriteAnime,
      'most_watched' => home.mostWatchedAnime,
      'top_rated' => home.topRatedAnime,
      'recently_updated' => home.recentlyUpdated,
      'upcoming' => home.upcomingAnime,
      _ => null,
    };
  }
}

class _WatchlistHomeSection extends ConsumerStatefulWidget {
  final String title;
  final String status;

  const _WatchlistHomeSection({required this.title, required this.status});

  @override
  ConsumerState<_WatchlistHomeSection> createState() =>
      _WatchlistHomeSectionState();
}

class _WatchlistHomeSectionState extends ConsumerState<_WatchlistHomeSection> {
  @override
  void initState() {
    super.initState();
    _fetchListIfNeeded();
  }

  @override
  void didUpdateWidget(covariant _WatchlistHomeSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != widget.status) {
      _fetchListIfNeeded();
    }
  }

  void _fetchListIfNeeded() {
    final state = ref.read(watchlistProvider);
    final list = state.listFor(widget.status);

    if (list.isEmpty && !state.loadingStatuses.contains(widget.status)) {
      ref.read(watchlistProvider.notifier).fetchListForStatus(widget.status);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(
      watchlistProvider.select((state) => state.listFor(widget.status)),
    );

    if (list.isEmpty) {
      return const SizedBox.shrink();
    }

    return HomeSectionWidget(
      title: widget.title,
      mediaList: list.map((e) => e.media).toList(),
    );
  }
}

final sortedWatchProgressProvider =
    Provider<AsyncValue<List<AnimeWatchProgressEntry>>>((ref) {
      return ref.watch(watchProgressStreamProvider).whenData((list) {
        if (list.isEmpty) return [];
        return list
            .whereType<AnimeWatchProgressEntry>()
            .where((e) => !e.isAdult)
            .toList()
          ..sort(AnimeWatchProgressEntry.compareByRecency);
      });
    });

class _ContinueWatchingSection extends ConsumerWidget {
  const _ContinueWatchingSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final sortedAsync = ref.watch(sortedWatchProgressProvider);
    final watchlist = ref.watch(watchlistProvider);
    final watchingStatus = auth.isMalAuthenticated ? 'watching' : 'CURRENT';
    final dismissedIds = ref.watch(continueWatchingDismissedProvider);
    final cloudWatching =
        watchlist
            .listFor(watchingStatus)
            .where((c) => !dismissedIds.contains(c.media.id))
            .toList();

    return sortedAsync.when(
      data: (sorted) {
        final Map<String, AnimeWatchProgressEntry> merged = {};
        for (final entry in sorted) {
          if (!dismissedIds.contains(entry.animeId)) {
            merged[entry.animeId] = entry;
          }
        }

        // Merge cloud watching items
        for (final cloudItem in cloudWatching) {
          final media = cloudItem.media;
          if (!merged.containsKey(media.id)) {
            final targetProgress =
                cloudItem.progress > 0 ? cloudItem.progress : 1;
            merged[media.id] = AnimeWatchProgressEntry(
              animeId: media.id,
              animeTitle:
                  media.title.english ??
                  media.title.romaji ??
                  media.title.native ??
                  '',
              animeFormat: media.format,
              animeCover:
                  media.coverImage.large ?? media.coverImage.medium ?? '',
              totalEpisodes: media.episodes ?? 0,
              episodesProgress: {
                targetProgress: EpisodeProgress(
                  episodeNumber: targetProgress,
                  episodeTitle: 'Episode $targetProgress',
                  episodeThumbnail:
                      media.coverImage.large ?? media.coverImage.medium,
                  progressInSeconds: 0,
                  durationInSeconds: 1440,
                  isCompleted: false,
                  watchedAt: DateTime.fromMillisecondsSinceEpoch(0),
                ),
              },
              lastUpdated: DateTime.fromMillisecondsSinceEpoch(0),
              currentEpisode: targetProgress,
              status: 'watching',
            );
          }
        }

        final combinedList =
            merged.values.toList()
              ..sort(AnimeWatchProgressEntry.compareByRecency);

        if (combinedList.isEmpty) return const SizedBox.shrink();
        return ContinueSection(allProgress: combinedList.take(15).toList());
      },
      loading: () {
        List<AnimeWatchProgressEntry> syncList = [];
        try {
          syncList =
              ref
                  .read(watchProgressRepositoryProvider)
                  .getAllProgress()
                  .where((e) => !dismissedIds.contains(e.animeId))
                  .toList()
                ..sort(AnimeWatchProgressEntry.compareByRecency);
        } catch (_) {}
        if (syncList.isNotEmpty) {
          return ContinueSection(allProgress: syncList.take(15).toList());
        }

        if (cloudWatching.isNotEmpty) {
          final synthetic =
              cloudWatching.map((c) {
                final media = c.media;
                final ep = c.progress > 0 ? c.progress : 1;
                return AnimeWatchProgressEntry(
                  animeId: media.id,
                  animeTitle: media.title.english ?? media.title.romaji ?? '',
                  animeFormat: media.format,
                  animeCover:
                      media.coverImage.large ?? media.coverImage.medium ?? '',
                  totalEpisodes: media.episodes ?? 0,
                  episodesProgress: {
                    ep: EpisodeProgress(
                      episodeNumber: ep,
                      episodeTitle: 'Episode $ep',
                      episodeThumbnail:
                          media.coverImage.large ?? media.coverImage.medium,
                      progressInSeconds: 0,
                      durationInSeconds: 1440,
                      isCompleted: false,
                      watchedAt: DateTime.fromMillisecondsSinceEpoch(0),
                    ),
                  },
                  currentEpisode: ep,
                  lastUpdated: DateTime.fromMillisecondsSinceEpoch(0),
                  status: 'watching',
                );
              }).toList();
          return ContinueSection(allProgress: synthetic.take(15).toList());
        }
        return const SizedBox.shrink();
      },
      error: (_, _) {
        List<AnimeWatchProgressEntry> syncList = [];
        try {
          syncList =
              ref
                  .read(watchProgressRepositoryProvider)
                  .getAllProgress()
                  .where((e) => !dismissedIds.contains(e.animeId))
                  .toList()
                ..sort(AnimeWatchProgressEntry.compareByRecency);
        } catch (_) {}
        if (syncList.isNotEmpty) {
          return ContinueSection(allProgress: syncList.take(15).toList());
        }

        if (cloudWatching.isNotEmpty) {
          final synthetic =
              cloudWatching.map((c) {
                final media = c.media;
                final ep = c.progress > 0 ? c.progress : 1;
                return AnimeWatchProgressEntry(
                  animeId: media.id,
                  animeTitle: media.title.english ?? media.title.romaji ?? '',
                  animeFormat: media.format,
                  animeCover:
                      media.coverImage.large ?? media.coverImage.medium ?? '',
                  totalEpisodes: media.episodes ?? 0,
                  episodesProgress: {
                    ep: EpisodeProgress(
                      episodeNumber: ep,
                      episodeTitle: 'Episode $ep',
                      episodeThumbnail:
                          media.coverImage.large ?? media.coverImage.medium,
                      progressInSeconds: 0,
                      durationInSeconds: 1440,
                      isCompleted: false,
                      watchedAt: DateTime.fromMillisecondsSinceEpoch(0),
                    ),
                  },
                  currentEpisode: ep,
                  lastUpdated: DateTime.fromMillisecondsSinceEpoch(0),
                  status: 'watching',
                );
              }).toList();
          return ContinueSection(allProgress: synthetic.take(15).toList());
        }
        return const SizedBox.shrink();
      },
    );
  }
}
