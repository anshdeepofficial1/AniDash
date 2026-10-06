import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:ani_dash/core/models/anime/page_model.dart';
import 'package:ani_dash/core/models/universal/universal_media.dart';
import 'package:ani_dash/core/models/universal/universal_page_response.dart';
import 'package:ani_dash/core/repositories/anime_repository.dart';
import 'package:ani_dash/core/utils/app_logger.dart';
import 'package:ani_dash/features/home/model/home_page.dart';
import 'package:ani_dash/shared/providers/anime_repo_provider.dart';

class HomepageState {
  final HomePage? homePage;
  final DateTime lastUpdated;
  final bool isLoading;
  final String? error;

  const HomepageState({
    this.homePage,
    required this.lastUpdated,
    this.isLoading = true,
    this.error,
  });

  HomepageState copyWith({
    HomePage? homePage,
    DateTime? lastUpdated,
    bool? isLoading,
    String? error,
  }) {
    return HomepageState(
      homePage: homePage ?? this.homePage,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class HomepageNotifier extends Notifier<HomepageState> {
  AnimeRepository get _repo => ref.read(animeRepositoryProvider);
  static const _boxName = 'home_page';
  Box<HomePageModel>? get _box =>
      Hive.isBoxOpen(_boxName) ? Hive.box<HomePageModel>(_boxName) : null;

  @override
  HomepageState build() {
    HomePageModel? cachedModel;
    try {
      cachedModel = _box?.get(0);
    } catch (_) {}

    final hasData = cachedModel != null;
    return HomepageState(
      homePage: cachedModel?.toHomePage(),
      lastUpdated: cachedModel?.lastUpdated ?? DateTime.now(),
      isLoading: !hasData,
    );
  }

  Future<HomepageState> initialize({bool forceRefresh = false}) async {
    if (!Hive.isBoxOpen(_boxName)) {
      try {
        await Hive.openBox<HomePageModel>(_boxName);
      } catch (_) {}
    }

    final shouldRefresh =
        forceRefresh ||
        state.homePage == null ||
        state.homePage!.trendingAnime.data.isEmpty ||
        state.homePage!.popularAnime.data.isEmpty ||
        state.homePage!.upcomingAnime.data.isEmpty ||
        state.homePage!.recentlyUpdated.data.isEmpty ||
        state.homePage!.topRatedAnime.data.isEmpty ||
        state.lastUpdated.isBefore(
          DateTime.now().subtract(const Duration(hours: 6)),
        );

    return shouldRefresh ? await fetchHomePage() : state;
  }

  void clearCache() {
    try {
      if (Hive.isBoxOpen(_boxName)) {
        Hive.box<HomePageModel>(_boxName).clear();
      }
    } catch (_) {}
    state = HomepageState(lastUpdated: DateTime.now(), isLoading: false);
  }

  Future<HomepageState> fetchHomePage() async {
    // Only show loading if we don't have data yet
    if (state.homePage == null) {
      state = state.copyWith(isLoading: true, error: null);
    }
    try {
      final previous = state.homePage;
      Future<UniversalPageResponse<UniversalMedia>> safe(
        Future<UniversalPageResponse<UniversalMedia>> Function() request,
        UniversalPageResponse<UniversalMedia>? fallback,
      ) async {
        try {
          final result = await request().timeout(const Duration(seconds: 15));
          return result.data.isEmpty && fallback != null ? fallback : result;
        } catch (error) {
          AppLogger.w(
            'Home section refresh failed; keeping cached row: $error',
          );
          return fallback ?? UniversalPageResponse.empty();
        }
      }

      final futures = await Future.wait([
        safe(_repo.getTrendingAnime, previous?.trendingAnime),
        safe(_repo.getPopularAnime, previous?.popularAnime),
        safe(_repo.getUpcomingAnime, previous?.upcomingAnime),
        safe(_repo.getRecentlyUpdatedAnime, previous?.recentlyUpdated),
        safe(_repo.getTopRatedAnime, previous?.topRatedAnime),
        safe(_repo.getMostFavoriteAnime, previous?.mostFavoriteAnime),
      ]);

      final homePage = HomePage(
        trendingAnime: futures[0],
        popularAnime: futures[1],
        upcomingAnime: futures[2],
        recentlyUpdated: futures[3],
        topRatedAnime: futures[4],
        mostFavoriteAnime: futures[5],
        mostWatchedAnime:
            previous?.mostWatchedAnime.data.isNotEmpty == true
                ? previous!.mostWatchedAnime
                : futures[1],
      );

      AppLogger.d('✅ Successfully fetched homepage data concurrently');
      _saveToHive(homePage);
      return state.copyWith(homePage: homePage, isLoading: false);
    } catch (err, stackTrace) {
      AppLogger.e('❌ Error fetching homepage data', err, stackTrace);
      return state.copyWith(error: err.toString(), isLoading: false);
    }
  }

  void _saveToHive(HomePage page) {
    final model = HomePageModel.fromHomePage(page);
    try {
      if (Hive.isBoxOpen(_boxName)) {
        Hive.box<HomePageModel>(_boxName).put(0, model);
      }
    } catch (_) {}
    state = state.copyWith(
      homePage: page,
      lastUpdated: model.lastUpdated,
      isLoading: false,
    );
  }
}

final homepageProvider = NotifierProvider<HomepageNotifier, HomepageState>(
  HomepageNotifier.new,
);
