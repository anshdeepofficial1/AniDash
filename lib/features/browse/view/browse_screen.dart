import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:ani_dash/core/models/universal/universal_media.dart';
import 'package:ani_dash/core/models/universal/universal_page_response.dart';
import 'package:ani_dash/core/utils/app_logger.dart';

import 'package:ani_dash/shared/ui/cards/anime/anime_card.dart';

import 'package:ani_dash/shared/providers/settings/ui_notifier.dart';
import 'package:ani_dash/shared/ui/shonenx_gridview.dart';
import 'package:ani_dash/helpers/navigation.dart';
import 'package:ani_dash/shared/providers/anime_repo_provider.dart';
import 'package:ani_dash/features/browse/model/search_filter.dart';
import 'package:ani_dash/features/browse/view/widgets/filter_bottom_sheet.dart';
import 'package:ani_dash/features/browse/view/section_screen.dart';
import 'package:ani_dash/main.dart';
import 'package:ani_dash/core/jikan/jikan_service.dart';
import 'package:ani_dash/shared/ui/cards/anime/anime_card_components.dart';
import 'package:ani_dash/features/ai/view/widgets/ask_nia_button.dart';
import 'package:ani_dash/shared/ui/adaptive_media_skeleton.dart';
import 'package:ani_dash/shared/ui/voice_text_button.dart';

class BrowseScreen extends ConsumerStatefulWidget {
  final String? keyword;
  final SearchFilter? initialFilter;

  const BrowseScreen({super.key, this.keyword, this.initialFilter});

  @override
  ConsumerState<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends ConsumerState<BrowseScreen>
    with SingleTickerProviderStateMixin {
  // Services and controllers
  late final _repo = ref.read(animeRepositoryProvider);
  late final _searchController = TextEditingController(text: widget.keyword);
  late final _scrollController = ScrollController()..addListener(_onScroll);
  late final _animationController = AnimationController(
    duration: const Duration(milliseconds: 400),
    vsync: this,
  );
  Timer? _debounce;
  static const _historyKey = 'anime_search_history';
  List<String> _searchHistory = [];
  List<String> _remoteSuggestions = [];
  int _suggestionGeneration = 0;

  // State variables
  List<UniversalMedia> _results = [];
  List<UniversalMedia> _trending = [];
  List<UniversalMedia> _popular = [];
  List<UniversalMedia> _upcoming = [];
  late SearchFilter _currentFilter =
      widget.initialFilter ?? const SearchFilter();

  var _currentPage = 1;
  var _isLoading = false;
  var _hasMore = true;
  var _isSearchFocused = false;
  var _isExploreLoading = true;
  var _isSearchSubmitted = false;
  String? _fuzzySuggestion;
  int _searchGeneration = 0;

  @override
  void initState() {
    super.initState();
    _animationController.forward();
    _searchHistory = sharedPrefs.getStringList(_historyKey) ?? [];
    if (widget.keyword?.isNotEmpty == true || !_currentFilter.isEmpty) {
      _isSearchSubmitted = true;
      _search();
    } else {
      _fetchExploreData();
    }
  }

  @override
  void didUpdateWidget(covariant BrowseScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.keyword != oldWidget.keyword) {
      _searchController.text = widget.keyword ?? '';
      _isSearchSubmitted = widget.keyword?.isNotEmpty == true;
      _search();
    }
    if (widget.initialFilter != oldWidget.initialFilter) {
      setState(() {
        _currentFilter = widget.initialFilter ?? const SearchFilter();
        _isSearchSubmitted = !_currentFilter.isEmpty;
      });
      _search();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _fetchExploreData() async {
    if (mounted) setState(() => _isExploreLoading = true);
    try {
      Future<UniversalPageResponse<UniversalMedia>> safeRepo(
        Future<UniversalPageResponse<UniversalMedia>> Function() request,
      ) async {
        try {
          return await request();
        } catch (_) {
          return UniversalPageResponse<UniversalMedia>.empty();
        }
      }

      final results = await Future.wait([
        safeRepo(_repo.getTrendingAnime),
        safeRepo(_repo.getPopularAnime),
        safeRepo(_repo.getUpcomingAnime),
      ]);

      if (results.every((result) => result.data.isEmpty)) {
        final jikan = JikanService();
        final fallback = await Future.wait([
          jikan.getTopUniversal(),
          jikan.getPopularUniversal(),
          jikan.getUpcomingUniversal(),
        ]);
        if (mounted) {
          setState(() {
            _trending = fallback[0];
            _popular = fallback[1];
            _upcoming = fallback[2];
            _isExploreLoading = false;
          });
        }
        return;
      }

      if (mounted) {
        setState(() {
          _trending = results[0].data;
          _popular = results[1].data;
          _upcoming = results[2].data;
          _isExploreLoading = false;
        });
      }
    } catch (e, s) {
      AppLogger.e("Failed to fetch explore data", e, s);
      final jikan = JikanService();
      final fallback = await Future.wait([
        jikan.getTopUniversal(),
        jikan.getPopularUniversal(),
        jikan.getUpcomingUniversal(),
      ]);
      if (mounted) {
        setState(() {
          _trending = fallback[0];
          _popular = fallback[1];
          _upcoming = fallback[2];
          _isExploreLoading = false;
        });
      }
    }
  }

  Future<bool> _fetchResults(String keyword, int page, int generation) async {
    // A page-one search intentionally supersedes an older request. Pagination
    // is still serial so a fast scroll cannot skip pages.
    if ((_isLoading && page > 1) ||
        !_hasMore ||
        generation != _searchGeneration) {
      return false;
    }
    // Allow search if keyword is empty BUT filter is present
    if (keyword.isEmpty && _currentFilter.isEmpty) return false;

    setState(() => _isLoading = true);

    try {
      var searchWord = keyword;
      var results = await _repo.searchAnime(
        searchWord,
        page: page,
        perPage: 20,
        filter: _currentFilter,
      );

      var effectiveResults = List<UniversalMedia>.from(
        page == 1 && results.isEmpty
            ? await JikanService().searchUniversal(searchWord)
            : results,
      );

      // Typo-tolerant / Fuzzy fallback: If 0 results found on page 1, try fuzzy correction
      if (page == 1 &&
          effectiveResults.isEmpty &&
          searchWord.trim().isNotEmpty) {
        final fuzzyCorrection = _findFuzzyCorrection(searchWord);
        if (fuzzyCorrection != null &&
            fuzzyCorrection.toLowerCase() != searchWord.trim().toLowerCase()) {
          AppLogger.d(
            "Fuzzy search correcting '$searchWord' -> '$fuzzyCorrection'",
          );
          final fuzzyRes = await _repo.searchAnime(
            fuzzyCorrection,
            page: 1,
            perPage: 20,
            filter: _currentFilter,
          );
          if (fuzzyRes.isNotEmpty) {
            effectiveResults = List<UniversalMedia>.from(fuzzyRes);
            if (mounted && generation == _searchGeneration) {
              setState(() => _fuzzySuggestion = fuzzyCorrection);
            }
          } else {
            final jikanFuzzy = await JikanService().searchUniversal(
              fuzzyCorrection,
            );
            if (jikanFuzzy.isNotEmpty) {
              effectiveResults = List<UniversalMedia>.from(jikanFuzzy);
              if (mounted && generation == _searchGeneration) {
                setState(() => _fuzzySuggestion = fuzzyCorrection);
              }
            }
          }
        }
      }

      if (page == 1) {
        _sortSearchResults(effectiveResults, searchWord);
      }

      if (mounted && generation == _searchGeneration) {
        setState(() {
          if (page == 1) {
            _results = effectiveResults;
          } else {
            _results.addAll(effectiveResults);
          }
          _hasMore = results.isNotEmpty;
          _isLoading = false;
        });
        return true;
      }
    } catch (e, stackTrace) {
      AppLogger.e("Search error", e, stackTrace);
      final fallback = List<UniversalMedia>.from(
        await JikanService().searchUniversal(keyword),
      );
      _sortSearchResults(fallback, keyword);
      if (mounted && generation == _searchGeneration) {
        setState(() {
          if (page == 1) _results = fallback;
          _hasMore = false;
          _isLoading = false;
        });
        return true;
      }
    }
    return false;
  }

  String? _findFuzzyCorrection(String query) {
    final cleanQuery = query.trim().toLowerCase();
    if (cleanQuery.isEmpty) return null;

    // Check pre-populated popular titles
    final candidateTitles = <String>{
      ..._trending.map((a) => a.title.userPreferred),
      ..._popular.map((a) => a.title.userPreferred),
      ..._upcoming.map((a) => a.title.userPreferred),
      ..._searchHistory,
      ..._remoteSuggestions,
      // Well-known popular anime to handle common user typos
      'One Piece',
      'Naruto',
      'Naruto Shippuden',
      'Bleach',
      'Demon Slayer: Kimetsu no Yaiba',
      'Jujutsu Kaisen',
      'Attack on Titan',
      'Solo Leveling',
      'Lord of the Mysteries',
      'Dragon Ball',
      'Dragon Ball Z',
      'Dragon Ball Super',
      'Death Note',
      'Fullmetal Alchemist: Brotherhood',
      'Hunter x Hunter',
      'My Hero Academia',
      'Black Clover',
      'Chainsaw Man',
      'Tokyo Ghoul',
      'Sword Art Online',
      'Frieren: Beyond Journey\'s End',
      'Vinland Saga',
      'Spy x Family',
      'Mob Psycho 100',
      'Bungo Stray Dogs',
      'Re:Zero - Starting Life in Another World',
      'Steins;Gate',
      'Cowboy Bebop',
      'Code Geass',
      'Haikyu!!',
      'Blue Lock',
      'Dr. Stone',
      'Fire Force',
      'Wind Breaker',
      'Kaiju No. 8',
      'Mashle: Magic and Muscles',
      'Mushoku Tensei: Jobless Reincarnation',
      'That Time I Got Reincarnated as a Slime',
      'Overlord',
      'Classroom of the Elite',
      'Oshi no Ko',
      'Baki',
      'Kengan Ashura',
      'JoJo\'s Bizarre Adventure',
    };

    String? bestTitle;
    double highestScore = 0.0;

    for (final title in candidateTitles) {
      if (title.isEmpty) continue;
      final t = title.toLowerCase();
      // If query is close substring or vice-versa
      if (t.contains(cleanQuery) || cleanQuery.contains(t)) {
        return title;
      }
      final sim = _levenshteinSimilarity(cleanQuery, t);
      if (sim > highestScore && sim >= 0.45) {
        highestScore = sim;
        bestTitle = title;
      }
    }

    return bestTitle;
  }

  double _levenshteinSimilarity(String s, String t) {
    if (s == t) return 1.0;
    if (s.isEmpty || t.isEmpty) return 0.0;
    final d = _levenshteinDistance(s, t);
    final maxLen = s.length > t.length ? s.length : t.length;
    return 1.0 - (d / maxLen);
  }

  int _levenshteinDistance(String s, String t) {
    if (s == t) return 0;
    if (s.isEmpty) return t.length;
    if (t.isEmpty) return s.length;

    var v0 = List<int>.generate(t.length + 1, (i) => i);
    var v1 = List<int>.filled(t.length + 1, 0);

    for (var i = 0; i < s.length; i++) {
      v1[0] = i + 1;
      for (var j = 0; j < t.length; j++) {
        final cost = s[i] == t[j] ? 0 : 1;
        v1[j + 1] = [
          v1[j] + 1,
          v0[j + 1] + 1,
          v0[j] + cost,
        ].reduce((a, b) => a < b ? a : b);
      }
      final temp = v0;
      v0 = v1;
      v1 = temp;
    }
    return v0[t.length];
  }

  void _sortSearchResults(List<UniversalMedia> results, String keyword) {
    final query = keyword.trim().toLowerCase();
    results.sort((a, b) {
      final aTitle = a.title.userPreferred.toLowerCase();
      final bTitle = b.title.userPreferred.toLowerCase();
      final relevance = (aTitle.contains(query) ? 0 : 1).compareTo(
        bTitle.contains(query) ? 0 : 1,
      );
      if (relevance != 0) return relevance;
      final season = animeSeasonSortKey(a).compareTo(animeSeasonSortKey(b));
      return season != 0 ? season : aTitle.compareTo(bTitle);
    });
  }

  Future<void> _onScroll() async {
    if (_results.isNotEmpty &&
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200) {
      final generation = _searchGeneration;
      final nextPage = _currentPage + 1;
      final loaded = await _fetchResults(
        _searchController.text,
        nextPage,
        generation,
      );
      if (loaded && mounted && generation == _searchGeneration) {
        _currentPage = nextPage;
      }
    }
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    if (query.isEmpty && _currentFilter.isEmpty) {
      setState(() {
        _isSearchSubmitted = false;
        _results.clear();
        _remoteSuggestions.clear();
      });
    } else {
      setState(() {});
      final normalized = query.trim();
      if (normalized.length >= 2) {
        _debounce = Timer(
          const Duration(milliseconds: 300),
          () => _fetchSearchSuggestions(normalized),
        );
      } else {
        _suggestionGeneration++;
        _remoteSuggestions.clear();
      }
    }
  }

  Future<void> _fetchSearchSuggestions(String query) async {
    final generation = ++_suggestionGeneration;
    try {
      var results = await _repo.searchAnime(query, page: 1, perPage: 12);
      if (results.isEmpty) {
        results = await JikanService().searchUniversal(query);
      }
      if (!mounted || generation != _suggestionGeneration) return;
      setState(() {
        _remoteSuggestions =
            results
                .map((anime) => anime.title.userPreferred)
                .where((title) => title.isNotEmpty)
                .toList();
      });
    } catch (_) {
      if (mounted && generation == _suggestionGeneration) {
        setState(() => _remoteSuggestions = []);
      }
    }
  }

  Future<void> _submitSearch() async {
    FocusScope.of(context).unfocus();
    final query = _searchController.text.trim();
    if (query.isEmpty && _currentFilter.isEmpty) {
      setState(() {
        _isSearchSubmitted = false;
        _isSearchFocused = false;
        _results.clear();
      });
      return;
    }
    setState(() {
      _isSearchSubmitted = true;
      _isSearchFocused = false;
    });
    if (query.isNotEmpty) {
      _searchHistory =
          [
            query,
            ..._searchHistory.where(
              (item) => item.toLowerCase() != query.toLowerCase(),
            ),
          ].take(10).toList();
      await sharedPrefs.setStringList(_historyKey, _searchHistory);
    }
    await _search();
  }

  void _selectSuggestion(String value) {
    _searchController.text = value;
    _searchController.selection = TextSelection.collapsed(offset: value.length);
    _submitSearch();
  }

  List<String> get _suggestions {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _searchHistory.take(8).toList();
    final titles = [..._trending, ..._popular, ..._upcoming]
        .map((anime) => anime.title.userPreferred)
        .where((title) => title.isNotEmpty);
    final candidates = <String>[
      ..._searchHistory,
      ..._remoteSuggestions,
      ...titles,
    ];
    final seen = <String>{};
    return candidates
        .where((title) {
          final key = title.toLowerCase();
          return seen.add(key) && key.contains(query);
        })
        .take(8)
        .toList();
  }

  Future<void> _search() async {
    final generation = ++_searchGeneration;
    if (_searchController.text.isEmpty && _currentFilter.isEmpty) {
      setState(() {
        _results.clear();
        _isExploreLoading = false; // Show explore content
      });
      return;
    }

    setState(() {
      _currentPage = 1;
      _results.clear();
      _hasMore = true;
    });

    await _fetchResults(_searchController.text, _currentPage, generation);
  }

  void _openFilter() async {
    final result = await showModalBottomSheet<SearchFilter>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (context) => FilterBottomSheet(initialFilter: _currentFilter),
    );

    if (result != null) {
      setState(() {
        _currentFilter = result;
        if (!_currentFilter.isEmpty || _searchController.text.isNotEmpty) {
          _isSearchSubmitted = true;
        }
      });

      if (_searchController.text.isEmpty && !_currentFilter.isEmpty) {
        _searchController.text = _searchController.text; // no-op
        _search();
      } else if (_searchController.text.isNotEmpty) {
        _search();
      }
    }
  }

  int _getColumnCount() {
    final width = MediaQuery.sizeOf(context).width;
    return width >= 1400
        ? 6
        : width >= 1100
        ? 5
        : width >= 800
        ? 4
        : width >= 420
        ? 3
        : 2;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_isSearchSubmitted ||
            _searchController.text.isNotEmpty ||
            !_currentFilter.isEmpty) {
          setState(() {
            _searchController.clear();
            _currentFilter = const SearchFilter();
            _isSearchSubmitted = false;
            _results.clear();
          });
          _fetchExploreData();
        } else {
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          } else {
            context.go('/');
          }
        }
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: Column(
          children: [
            _Header(
              controller: _searchController,
              animation: _animationController,
              onSearch: _submitSearch,
              onFocusChange:
                  (focused) => setState(() => _isSearchFocused = focused),
              isSearchFocused: _isSearchFocused,
              onSearchChanged: _onSearchChanged,
              onFilter: _openFilter,
              hasFilter: !_currentFilter.isEmpty,
            ),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child:
                        (!_isSearchSubmitted && _currentFilter.isEmpty)
                            ? _ExploreView(
                              trending: _trending,
                              popular: _popular,
                              upcoming: _upcoming,
                              isLoading: _isExploreLoading,
                              onRetry: _fetchExploreData,
                            )
                            : _results.isEmpty && !_isLoading
                            ? _EmptyState(fuzzySuggestion: _fuzzySuggestion)
                            : _results.isEmpty && _isLoading
                            ? const _BrowseLoadingSkeleton()
                            : _ResultsGrid(
                              results: _results,
                              scrollController: _scrollController,
                              columnCount: _getColumnCount(),
                              isLoading: _isLoading,
                              animation: _animationController,
                              fuzzySuggestion: _fuzzySuggestion,
                              onApplySuggestion: (suggested) {
                                _searchController.text = suggested;
                                _submitSearch();
                              },
                            ),
                  ),
                  if (_isSearchFocused && _suggestions.isNotEmpty)
                    Positioned(
                      top: 0,
                      left: 10,
                      right: 10,
                      child: Material(
                        elevation: 8,
                        shadowColor: Colors.black54,
                        borderRadius: BorderRadius.circular(16),
                        color:
                            Theme.of(context).colorScheme.surfaceContainerHigh,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 320),
                            child: _SearchSuggestions(
                              items: _suggestions,
                              history: _searchHistory.toSet(),
                              onSelected: _selectSuggestion,
                              onClear: () async {
                                await sharedPrefs.setStringList(
                                  _historyKey,
                                  [],
                                );
                                setState(() => _searchHistory = []);
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchSuggestions extends StatelessWidget {
  final List<String> items;
  final Set<String> history;
  final ValueChanged<String> onSelected;
  final VoidCallback onClear;

  const _SearchSuggestions({
    required this.items,
    required this.history,
    required this.onSelected,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      children: [
        if (history.isNotEmpty)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onClear,
              child: const Text('Clear history'),
            ),
          ),
        ...items.map(
          (item) => ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            leading: Icon(
              history.contains(item) ? Icons.history : Icons.search,
              size: 20,
            ),
            title: Text(item, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: const Icon(Icons.north_west_rounded, size: 16),
            onTap: () => onSelected(item),
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  final TextEditingController controller;
  final AnimationController animation;
  final VoidCallback onSearch;
  final ValueChanged<bool> onFocusChange;
  final bool isSearchFocused;
  final Function(String) onSearchChanged;
  final VoidCallback onFilter;
  final bool hasFilter;

  const _Header({
    required this.controller,
    required this.animation,
    required this.onSearch,
    required this.onFocusChange,
    required this.isSearchFocused,
    required this.onSearchChanged,
    required this.onFilter,
    required this.hasFilter,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            return Opacity(
              opacity: animation.value,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Discover Anime',
                          style: Theme.of(context).textTheme.headlineLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      const AskNiaButton(compact: true),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Find your next favorite series',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _SearchBar(
                    controller: controller,
                    onSearch: onSearch,
                    onFocusChange: onFocusChange,
                    isSearchFocused: isSearchFocused,
                    onSearchChanged: onSearchChanged,
                    onFilter: onFilter,
                    hasFilter: hasFilter,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSearch;
  final ValueChanged<bool> onFocusChange;
  final bool isSearchFocused;
  final Function(String) onSearchChanged;
  final VoidCallback onFilter;
  final bool hasFilter;

  const _SearchBar({
    required this.controller,
    required this.onSearch,
    required this.onFocusChange,
    required this.isSearchFocused,
    required this.onSearchChanged,
    required this.onFilter,
    required this.hasFilter,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color:
              isSearchFocused
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(
                    context,
                  ).colorScheme.outline.withValues(alpha: 0.2),
          width: isSearchFocused ? 2 : 1,
        ),
      ),
      child: Focus(
        onFocusChange: onFocusChange,
        child: TextField(
          controller: controller,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => onSearch(),
          onChanged: onSearchChanged,
          decoration: InputDecoration(
            hintText: 'Search anime titles...',
            hintStyle: TextStyle(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.5),
            ),
            prefixIcon: IconButton(
              icon: Icon(
                Iconsax.search_normal,
                color:
                    isSearchFocused
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.5),
              ),
              onPressed: onSearch,
            ),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                VoiceTextButton(
                  controller: controller,
                  onChanged: onSearchChanged,
                  tooltip: 'Speak an anime name',
                ),
                if (controller.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      controller.clear();
                      onSearchChanged('');
                    },
                  ),
                IconButton(
                  icon: Icon(
                    Iconsax.setting_4,
                    color:
                        hasFilter
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                  onPressed: onFilter,
                ),
                const SizedBox(width: 8),
              ],
            ),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 16,
            ),
          ),
        ),
      ),
    );
  }
}

class _ResultsGrid extends ConsumerWidget {
  final List<UniversalMedia> results;
  final ScrollController scrollController;
  final int columnCount;
  final bool isLoading;
  final AnimationController animation;
  final String? fuzzySuggestion;
  final ValueChanged<String>? onApplySuggestion;

  const _ResultsGrid({
    required this.results,
    required this.scrollController,
    required this.columnCount,
    required this.isLoading,
    required this.animation,
    this.fuzzySuggestion,
    this.onApplySuggestion,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(uiSettingsProvider).cardStyle;
    final size = mode.getDimensions(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedBuilder(
                animation: animation,
                builder: (context, child) {
                  return Opacity(
                    opacity: animation.value,
                    child: Text(
                      '${results.length} Results',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                },
              ),
              if (fuzzySuggestion != null) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.auto_fix_high_rounded,
                        size: 16,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Showing results for: ',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        fuzzySuggestion!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: AnimatedBuilder(
            animation: animation,
            builder: (context, child) {
              return FadeTransition(
                opacity: animation,
                child: AniDashGridView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 100),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  crossAxisExtent: size.width,
                  childAspectRatio: size.width / size.height,
                  itemCount: results.length + (isLoading ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == results.length) {
                      return const _LoadingIndicator();
                    }
                    final anime = results[index];
                    return GestureDetector(
                      onTap:
                          () => navigateToDetail(
                            context,
                            anime,
                            'browse_grid_${anime.id}',
                          ),
                      child: AnimeCard(
                        anime: anime,
                        mode: mode,
                        tag: 'browse_grid_${anime.id}',
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String? fuzzySuggestion;

  const _EmptyState({this.fuzzySuggestion});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.search_off,
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No Anime Found',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Try another title or adjust your filters',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _BrowseLoadingSkeleton extends ConsumerWidget {
  const _BrowseLoadingSkeleton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(uiSettingsProvider).cardStyle;
    final size = mode.getDimensions(context);
    return AniDashGridView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 100),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      crossAxisExtent: size.width,
      childAspectRatio: size.width / size.height,
      itemCount: 8,
      itemBuilder: (_, index) => AdaptiveMediaSkeleton(size: size),
    );
  }
}

class _LoadingIndicator extends StatelessWidget {
  const _LoadingIndicator();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(
                Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Loading more...',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExploreView extends StatelessWidget {
  final List<UniversalMedia> trending;
  final List<UniversalMedia> popular;
  final List<UniversalMedia> upcoming;
  final bool isLoading;
  final VoidCallback onRetry;

  const _ExploreView({
    required this.trending,
    required this.popular,
    required this.upcoming,
    required this.isLoading,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const _BrowseLoadingSkeleton();
    }

    if (trending.isEmpty && popular.isEmpty && upcoming.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 48),
            const SizedBox(height: 12),
            const Text('Could not load anime right now'),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HorizontalSection(title: 'Trending Now', items: trending),
          _HorizontalSection(title: 'All Time Popular', items: popular),
          _HorizontalSection(title: 'Upcoming Seasons', items: upcoming),
        ],
      ),
    );
  }
}

class _HorizontalSection extends ConsumerWidget {
  final String title;
  final List<UniversalMedia> items;

  const _HorizontalSection({required this.title, required this.items});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (items.isEmpty) return const SizedBox.shrink();

    final mode = ref.watch(uiSettingsProvider).cardStyle;
    final size = mode.getDimensions(context);
    final isDesktop = MediaQuery.sizeOf(context).width >= 1000;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: Icon(
                  Iconsax.arrow_right_3,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                onPressed: () {
                  final repo = ref.read(animeRepositoryProvider);
                  Future<UniversalPageResponse<UniversalMedia>> Function({
                    int page,
                    int perPage,
                  })?
                  fetcher;

                  if (title == 'Trending Now') {
                    fetcher = repo.getTrendingAnime;
                  } else if (title == 'All Time Popular') {
                    fetcher = repo.getPopularAnime;
                  } else if (title == 'Upcoming Seasons') {
                    fetcher = repo.getUpcomingAnime;
                  }

                  if (fetcher != null) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder:
                            (_) => SectionScreen(
                              title: title,
                              fetchItems: fetcher!,
                            ),
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        ),
        if (isDesktop)
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = (constraints.maxWidth / (size.width + 12))
                  .floor()
                  .clamp(4, 8);
              final visibleItems = items.take(columns).toList();
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (
                      var index = 0;
                      index < visibleItems.length;
                      index++
                    ) ...[
                      Expanded(
                        child: AspectRatio(
                          aspectRatio: size.width / size.height,
                          child: GestureDetector(
                            onTap: () {
                              final anime = visibleItems[index];
                              navigateToDetail(
                                context,
                                anime,
                                'browse-$title-${anime.id}',
                              );
                            },
                            child: AnimeCard(
                              anime: visibleItems[index],
                              mode: mode,
                              tag: 'browse-$title-${visibleItems[index].id}',
                            ),
                          ),
                        ),
                      ),
                      if (index != visibleItems.length - 1)
                        const SizedBox(width: 12),
                    ],
                  ],
                ),
              );
            },
          )
        else
          SizedBox(
            height: size.height,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final anime = items[index];
                final tag = 'browse-$title-${anime.id}';
                return SizedBox(
                  width: size.width,
                  child: GestureDetector(
                    onTap: () => navigateToDetail(context, anime, tag),
                    child: AnimeCard(anime: anime, mode: mode, tag: tag),
                  ),
                );
              },
            ),
          ),
        const SizedBox(height: 16),
      ],
    );
  }
}
