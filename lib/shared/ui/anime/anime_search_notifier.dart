import 'dart:async';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:ani_dash/core/models/anime/anime_model.dep.dart';
import 'package:ani_dash/core/models/universal/universal_media.dart';
import 'package:ani_dash/core/repositories/source_preference_repository.dart';
import 'package:ani_dash/data/isar/isar_source_preference.dart';
import 'package:ani_dash/shared/providers/anime_match_service.dart';
import 'package:ani_dash/shared/providers/anime_source_provider.dart';
import 'package:ani_dash/shared/providers/settings/content_settings_notifier.dart';
import 'package:ani_dash/shared/providers/settings/experimental_notifier.dart';
import 'package:ani_dash/shared/providers/settings/source_notifier.dart';

part 'anime_search_notifier.g.dart';

class AnimeSearchState {
  final List<BaseAnimeModel> results;
  final bool isLoading;

  AnimeSearchState({this.results = const [], this.isLoading = true});

  AnimeSearchState copyWith({List<BaseAnimeModel>? results, bool? isLoading}) {
    return AnimeSearchState(
      results: results ?? this.results,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

@riverpod
class AnimeSearchNotifier extends _$AnimeSearchNotifier {
  Timer? _debounce;
  int _searchGeneration = 0;

  @override
  AnimeSearchState build() {
    ref.onDispose(() {
      _debounce?.cancel();
    });
    return AnimeSearchState();
  }

  void tryAutoResolve(
    UniversalMedia media,
    bool autoMatch,
    Function(BaseAnimeModel) onMatch,
  ) async {
    final title = media.title.userPreferred;
    performSearch(title);

    if (autoMatch) {
      final match = await ref
          .read(animeMatchServiceProvider)
          .findBestMatch(
            media.title,
            mediaId: media.id.toString(),
            malId: media.idMal,
          );
      if (match != null) {
        onMatch(match);
      }
    }
  }

  Future<void> performSearch(String query) async {
    final generation = ++_searchGeneration;
    state = state.copyWith(isLoading: true);
    try {
      final results = await ref.read(animeMatchServiceProvider).search(query);
      if (!ref.mounted || generation != _searchGeneration) return;
      state = state.copyWith(results: results, isLoading: false);
    } catch (e) {
      if (!ref.mounted || generation != _searchGeneration) return;
      state = state.copyWith(results: [], isLoading: false);
    }
  }

  void onSearchChanged(String query) {
    _debounce?.cancel();
    if (query.trim().length < 2) {
      _searchGeneration++;
      state = state.copyWith(results: const [], isLoading: false);
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 600), () {
      performSearch(query);
    });
  }

  void saveSelection(UniversalMedia media, BaseAnimeModel anime) {
    if (ref.read(contentSettingsProvider).smartSourceEnabled) {
      final useExtensions = ref.read(experimentalProvider).useExtensions;

      if (useExtensions) {
        final activeSource = ref.read(sourceProvider).activeAnimeSource;
        if (activeSource != null) {
          final selection = IsarSourcePreference(
            animeId: media.id.toString(),
            sourceId: activeSource.id.toString(),
            sourceType: 'mangayomi',
            matchedAnimeId: anime.id,
            matchedAnimeTitle: anime.name,
          );

          ref
              .read(sourcePreferenceRepositoryProvider)
              .saveSourcePreference(
                media.id.toString(),
                media.highResCoverImage,
                selection,
              );
        }
      } else {
        final sourceId = ref.read(selectedProviderKeyProvider);
        if (sourceId != null) {
          final selection = IsarSourcePreference(
            animeId: media.id.toString(),
            sourceId: sourceId,
            sourceType: 'legacy',
            matchedAnimeId: anime.id,
            matchedAnimeTitle: anime.name,
          );

          ref
              .read(sourcePreferenceRepositoryProvider)
              .saveSourcePreference(
                media.id.toString(),
                media.highResCoverImage,
                selection,
              );
        }
      }
    }
  }
}
