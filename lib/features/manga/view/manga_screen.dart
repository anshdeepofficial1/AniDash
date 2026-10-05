import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:dartotsu_extension_bridge/dartotsu_extension_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:ani_dash/main.dart';
import 'package:ani_dash/core/models/manga/manga_reading_progress_model.dart';
import 'package:ani_dash/core/repositories/manga_reading_progress_repository.dart';
import 'package:ani_dash/core/services/auth_provider_enum.dart';
import 'package:ani_dash/core/utils/greeting_methods.dart';
import 'package:ani_dash/features/manga/utils/manga_helpers.dart';
import 'package:ani_dash/shared/auth/providers/auth_notifier.dart';
import 'package:ani_dash/shared/providers/settings/source_notifier.dart';
import 'package:ani_dash/features/ai/view/widgets/ask_nia_button.dart';
import 'manga_details_screen.dart';
import 'manga_reader_screen.dart';
import 'manga_section_screen.dart';

class _MangaChapterResolver {
  static final List<({DMedia item, Source source, VoidCallback onResolved})>
  _queue = [];
  static int _activeRequests = 0;
  static const int _maxConcurrency = 2;
  static final Set<String> _pendingKeys = {};

  static void enqueue(DMedia item, Source source, VoidCallback onResolved) {
    final key = item.url ?? item.title;
    if (key == null || key.isEmpty) return;
    if (_pendingKeys.contains(key)) return;
    _pendingKeys.add(key);

    _queue.add((item: item, source: source, onResolved: onResolved));
    _drainQueue();
  }

  static void _drainQueue() {
    while (_activeRequests < _maxConcurrency && _queue.isNotEmpty) {
      final next = _queue.removeAt(0);
      final key = next.item.url ?? next.item.title;
      if (key == null) continue;

      _activeRequests++;
      next.source.methods
          .getDetail(next.item)
          .timeout(const Duration(seconds: 4))
          .then((detail) {
            if (detail.episodes != null && detail.episodes!.isNotEmpty) {
              sharedPrefs.setInt(
                'manga_ch_count_$key',
                detail.episodes!.length,
              );
              next.onResolved();
            }
          })
          .catchError((_) {})
          .whenComplete(() {
            _activeRequests--;
            _drainQueue();
          });
    }
  }
}

class MangaScreen extends ConsumerStatefulWidget {
  const MangaScreen({super.key});

  @override
  ConsumerState<MangaScreen> createState() => _MangaScreenState();
}

class _MangaScreenState extends ConsumerState<MangaScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<DMedia> _spotlightList = [];
  List<DMedia> _latestList = [];
  List<DMedia> _popularList = [];
  List<DMedia> _searchList = [];

  bool _isLoading = false;
  bool _isSearching = false;
  bool _showSearchBar = false;
  String? _error;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadMangaContent();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Source? _getActiveMangaSource() {
    final sourceState = ref.read(sourceProvider);
    return sourceState.activeMangaSource ??
        sourceState.installedMangaExtensions.firstOrNull ??
        sourceState.installedAdultMangaExtensions.firstOrNull;
  }

  Future<void> _loadMangaContent() async {
    final source = _getActiveMangaSource();
    if (source == null) {
      if (mounted) {
        setState(() {
          _error =
              'No Manga extension installed yet.\nPlease install MangaDex or add an extension repository in settings.';
          _isLoading = false;
        });
      }
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      Pages? latestPages;
      Pages? popularPages;

      await Future.wait([
        source.methods
            .getLatestUpdates(1)
            .timeout(const Duration(seconds: 15))
            .then((res) {
              latestPages = res;
            })
            .catchError((_) {}),
        source.methods
            .getPopular(1)
            .timeout(const Duration(seconds: 15))
            .then((res) {
              popularPages = res;
            })
            .catchError((_) {}),
      ]);

      final latest = latestPages?.list ?? <DMedia>[];
      final popular = popularPages?.list ?? <DMedia>[];

      // Fallbacks if one is empty
      final finalLatest = latest.isNotEmpty ? latest : popular;
      final finalPopular = popular.isNotEmpty ? popular : latest;

      final spotlightCandidates =
          finalPopular.isNotEmpty ? finalPopular : finalLatest;
      final spotlight = spotlightCandidates.take(6).toList();

      if (mounted) {
        setState(() {
          _latestList = finalLatest;
          _popularList = finalPopular;
          _spotlightList = spotlight;
          _isLoading = false;
          if (_latestList.isEmpty && _popularList.isEmpty) {
            _error = 'No manga found from ${source.name ?? "this extension"}.';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load manga: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _searchManga(String query) async {
    final source = _getActiveMangaSource();
    if (source == null || query.trim().isEmpty) {
      if (mounted) {
        setState(() {
          _searchList = [];
          _isSearching = false;
        });
      }
      return;
    }

    setState(() {
      _isSearching = true;
      _error = null;
    });

    try {
      final pages = await source.methods
          .search(query.trim(), 1, [])
          .timeout(const Duration(seconds: 15));
      if (mounted) {
        setState(() {
          _searchList = pages.list;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _searchList = [];
          _isSearching = false;
        });
      }
    }
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (query.trim().isNotEmpty) {
        _searchManga(query.trim());
      } else {
        if (mounted) {
          setState(() {
            _searchList = [];
            _isSearching = false;
          });
        }
      }
    });
  }

  void _showSourceSelector(BuildContext context) {
    final sourceState = ref.read(sourceProvider);
    final installedManga = sourceState.installedMangaExtensions;
    final installedAdultManga = sourceState.installedAdultMangaExtensions;
    final activeSource = _getActiveMangaSource();

    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final colorScheme = theme.colorScheme;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 16, 0, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Select Manga Source',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          context.push('/settings/extensions');
                        },
                        icon: const Icon(Icons.extension_outlined, size: 18),
                        label: const Text('Manage'),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                if (installedManga.isEmpty && installedAdultManga.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24.0),
                    child: Center(
                      child: Text(
                        'No Manga extensions installed yet.\nPlease install MangaDex or add a repository in settings.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                else
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        if (installedManga.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 6,
                            ),
                            child: Text(
                              'Manga Sources',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          ...installedManga.map((src) {
                            final isSelected = activeSource?.id == src.id;
                            return ListTile(
                              leading: const Icon(Iconsax.book),
                              title: Text(src.name ?? 'Unknown'),
                              subtitle: Text(
                                'v${src.version ?? '0.0.1'} • ${src.lang?.toUpperCase() ?? 'EN'}',
                              ),
                              trailing:
                                  isSelected
                                      ? Icon(
                                        Icons.check_circle,
                                        color: colorScheme.primary,
                                      )
                                      : null,
                              onTap: () {
                                ref
                                    .read(sourceProvider.notifier)
                                    .setActiveSource(src);
                                Navigator.pop(ctx);
                                _searchController.clear();
                                _searchList = [];
                                _loadMangaContent();
                              },
                            );
                          }),
                        ],
                        if (installedAdultManga.isNotEmpty) ...[
                          ...installedAdultManga.map((src) {
                            final isSelected = activeSource?.id == src.id;
                            return ListTile(
                              leading: const Icon(
                                Iconsax.book_1,
                                color: Colors.redAccent,
                              ),
                              title: Row(
                                children: [
                                  Text(src.name ?? 'Unknown'),
                                  const SizedBox(width: 8),
                                  build18PlusBadge(fontSize: 8),
                                ],
                              ),
                              subtitle: Text(
                                'v${src.version ?? '0.0.1'} • ${src.lang?.toUpperCase() ?? 'EN'}',
                              ),
                              trailing:
                                  isSelected
                                      ? Icon(
                                        Icons.check_circle,
                                        color: colorScheme.primary,
                                      )
                                      : null,
                              onTap: () {
                                ref
                                    .read(sourceProvider.notifier)
                                    .setActiveSource(src);
                                Navigator.pop(ctx);
                                _searchController.clear();
                                _searchList = [];
                                _loadMangaContent();
                              },
                            );
                          }),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openMangaDetails(DMedia item) {
    final activeSource = _getActiveMangaSource();
    if (activeSource != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder:
              (_) => MangaDetailsScreen(manga: item, mangaSource: activeSource),
        ),
      );
    }
  }

  int? _getChapterCount(DMedia item) {
    if (item.episodes != null && item.episodes!.isNotEmpty) {
      return item.episodes!.length;
    }
    final key = item.url ?? item.title;
    if (key != null && key.isNotEmpty) {
      try {
        final cached = sharedPrefs.getInt('manga_ch_count_$key');
        if (cached != null) return cached;

        final source = _getActiveMangaSource();
        if (source != null) {
          _MangaChapterResolver.enqueue(item, source, () {
            if (mounted) setState(() {});
          });
        }
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  Widget _buildChapterBadge(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.25),
          width: 0.5,
        ),
      ),
      child: Text(
        'Ch. $count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 1. Header Section (exact parity with HomeScreen Header)
  // ---------------------------------------------------------------------------
  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final activePlatform = ref.watch(
      authProvider.select((s) => s.activePlatform),
    );
    final user = ref.watch(
      authProvider.select(
        (s) =>
            activePlatform == AuthPlatform.anilist ? s.anilistUser : s.malUser,
      ),
    );
    final activeSource = _getActiveMangaSource();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // User Avatar
              GestureDetector(
                onTap:
                    () => context.push(
                      user != null
                          ? '/settings/account/profile'
                          : '/settings/account',
                    ),
                child: Hero(
                  tag: 'manga-user-avatar',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child:
                        user?.avatarUrl != null && user!.avatarUrl!.isNotEmpty
                            ? CachedNetworkImage(
                              imageUrl: user.avatarUrl!,
                              width: 44,
                              height: 44,
                              fit: BoxFit.cover,
                              errorWidget:
                                  (_, __, ___) => Container(
                                    width: 44,
                                    height: 44,
                                    color: colorScheme.surfaceContainerHighest,
                                    child: const Icon(Icons.person),
                                  ),
                            )
                            : Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Iconsax.book,
                                color: colorScheme.primary,
                              ),
                            ),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Greeting & Title
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      getGreeting(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      user?.name ?? 'Manga Reader',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              const AskNiaButton(compact: true),
              const SizedBox(width: 8),

              // Action 2: Toggle Search
              Material(
                color: colorScheme.secondaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _showSearchBar = !_showSearchBar;
                      if (!_showSearchBar) {
                        _searchController.clear();
                        _searchList = [];
                        _isSearching = false;
                      }
                    });
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Icon(
                      _showSearchBar ? Icons.close : Iconsax.search_normal,
                      size: 18,
                      color: colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Action 3: Settings shortcut
              Material(
                color: colorScheme.secondaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: () => context.push('/settings'),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Icon(
                      Icons.settings_outlined,
                      size: 18,
                      color: colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Source Switcher Chip bar
          Row(
            children: [
              ActionChip(
                avatar: const Icon(Iconsax.book, size: 15),
                label: Text(
                  activeSource?.name ?? 'Select Source',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onPressed: () => _showSourceSelector(context),
              ),
              if (activeSource?.isNsfw == true) ...[
                const SizedBox(width: 8),
                build18PlusBadge(fontSize: 8),
              ],
              const Spacer(),
            ],
          ),

          // Search Bar if expanded
          if (_showSearchBar) ...[
            const SizedBox(height: 10),
            SearchBar(
              controller: _searchController,
              hintText: 'Search manga (e.g. Naruto, Berserk, Solo Leveling)...',
              leading: const Icon(Iconsax.search_normal, size: 18),
              trailing: [
                if (_searchController.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () {
                      _searchController.clear();
                      setState(() {
                        _searchList = [];
                        _isSearching = false;
                      });
                    },
                  ),
              ],
              onChanged: _onSearchChanged,
              elevation: const WidgetStatePropertyAll(1.0),
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 2. Spotlight Hero Banner Carousel
  // ---------------------------------------------------------------------------
  Widget _buildSpotlightBanner(BuildContext context, ColorScheme colorScheme) {
    if (_spotlightList.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 0, 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: colorScheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(30),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Iconsax.star5,
                    size: 16,
                    color: colorScheme.onTertiaryContainer,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Spotlight Manga',
                    style: TextStyle(
                      color: colorScheme.onTertiaryContainer,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
          CarouselSlider.builder(
            options: CarouselOptions(
              height: 200,
              autoPlay: _spotlightList.length > 1,
              autoPlayInterval: const Duration(seconds: 5),
              enableInfiniteScroll: _spotlightList.length > 1,
              enlargeCenterPage: true,
              viewportFraction: 0.92,
              enlargeStrategy: CenterPageEnlargeStrategy.scale,
            ),
            itemCount: _spotlightList.length,
            itemBuilder: (context, index, realIndex) {
              final item = _spotlightList[index];
              final isAdult = isMangaAdult(
                item,
                source: _getActiveMangaSource(),
              );

              return GestureDetector(
                onTap: () => _openMangaDetails(item),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 10,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Backdrop Cover
                      if (item.cover != null && item.cover!.isNotEmpty)
                        CachedNetworkImage(
                          imageUrl: item.cover!,
                          fit: BoxFit.cover,
                          errorWidget:
                              (_, __, ___) => Container(
                                color: colorScheme.surfaceContainerHighest,
                                child: const Icon(Iconsax.book, size: 40),
                              ),
                        )
                      else
                        Container(
                          color: colorScheme.surfaceContainerHighest,
                          child: const Icon(Iconsax.book, size: 40),
                        ),

                      // Gradient Overlay
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.4),
                              Colors.black.withValues(alpha: 0.92),
                            ],
                          ),
                        ),
                      ),

                      // Poster + Info + Read Button
                      Positioned(
                        left: 14,
                        right: 14,
                        bottom: 14,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            // Thumbnail Poster with 18+ tag
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Stack(
                                children: [
                                  SizedBox(
                                    width: 65,
                                    height: 90,
                                    child: CachedNetworkImage(
                                      imageUrl: item.cover ?? '',
                                      fit: BoxFit.cover,
                                      errorWidget:
                                          (_, __, ___) => Container(
                                            color: Colors.black45,
                                            child: const Icon(
                                              Iconsax.book,
                                              color: Colors.white70,
                                            ),
                                          ),
                                    ),
                                  ),
                                  if (isAdult)
                                    Positioned(
                                      top: 4,
                                      left: 4,
                                      child: build18PlusBadge(fontSize: 8),
                                    ),
                                  if (_getChapterCount(item) != null &&
                                      _getChapterCount(item)! > 0)
                                    Positioned(
                                      bottom: 4,
                                      right: 4,
                                      child: _buildChapterBadge(
                                        _getChapterCount(item)!,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),

                            // Manga Titles & Badges
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Wrap(
                                    spacing: 6,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: colorScheme.primary,
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: const Text(
                                          'TRENDING',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ),
                                      if (isAdult)
                                        build18PlusBadge(fontSize: 8),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    item.title ?? 'Unknown Title',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      height: 1.2,
                                    ),
                                  ),
                                  if (item.author != null &&
                                      item.author!.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      item.author!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.8,
                                        ),
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),

                            // Read Action Button
                            FilledButton.icon(
                              onPressed: () => _openMangaDetails(item),
                              icon: const Icon(Iconsax.book, size: 16),
                              label: const Text('Read'),
                              style: FilledButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
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
            },
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 3. Continue Reading Section (matching Continue Watching on HomeScreen)
  // ---------------------------------------------------------------------------
  Widget _buildContinueReadingSection(BuildContext context, ThemeData theme) {
    final progressList = ref.watch(mangaReadingProgressProvider);
    final activeSource = _getActiveMangaSource();

    final validEntries = progressList;

    if (validEntries.isEmpty) return const SizedBox.shrink();

    final colorScheme = theme.colorScheme;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final itemWidth = (screenWidth * 0.6).clamp(180.0, 280.0);
    final imageHeight = itemWidth * (9 / 16);
    final listHeight = imageHeight + 62.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Continue Reading',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '${validEntries.length} In Progress',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: listHeight,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            scrollDirection: Axis.horizontal,
            itemCount: validEntries.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final entry = validEntries[index];

              return RepaintBoundary(
                child: SizedBox(
                  width: itemWidth,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onLongPress: () => _showContinueReadingMenu(context, entry),
                    onTap: () {
                      final targetSource =
                          activeSource ??
                          Source(
                            id: entry.sourceId ?? 'mangadex',
                            name: entry.sourceName ?? 'MangaDex',
                            isNsfw: entry.isAdult,
                          );

                      final chapter =
                          entry.chapterJson != null
                              ? DEpisode.fromJson(entry.chapterJson!)
                              : DEpisode(
                                url: entry.chapterUrl,
                                name: entry.chapterTitle,
                                episodeNumber: entry.chapterNumber,
                              );

                      final manga =
                          entry.mangaJson != null
                              ? DMedia.fromJson(entry.mangaJson!)
                              : DMedia(
                                title: entry.mangaTitle,
                                url: entry.mangaUrl,
                                cover: entry.mangaCover,
                              );

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder:
                              (_) => MangaReaderScreen(
                                chapter: chapter,
                                mangaTitle: entry.mangaTitle,
                                mangaSource: targetSource,
                                manga: manga,
                                mangaCover: entry.mangaCover,
                                mangaUrl: entry.mangaUrl,
                                initialPage: entry.pageIndex,
                                isAdult: entry.isAdult,
                              ),
                        ),
                      );
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: AspectRatio(
                            aspectRatio: 16 / 9,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                // Cover
                                if (entry.mangaCover != null &&
                                    entry.mangaCover!.isNotEmpty)
                                  CachedNetworkImage(
                                    imageUrl: entry.mangaCover!,
                                    fit: BoxFit.cover,
                                    errorWidget:
                                        (_, __, ___) => Container(
                                          color:
                                              colorScheme
                                                  .surfaceContainerHighest,
                                          child: const Icon(Iconsax.book),
                                        ),
                                  )
                                else
                                  Container(
                                    color: colorScheme.surfaceContainerHighest,
                                    child: const Icon(Iconsax.book),
                                  ),

                                // Dark Overlay
                                Container(
                                  color: Colors.black.withValues(alpha: 0.25),
                                ),

                                // Center Read Icon
                                Center(
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: colorScheme.primaryContainer
                                          .withValues(alpha: 0.85),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Iconsax.book_1,
                                      color: colorScheme.onPrimaryContainer,
                                      size: 18,
                                    ),
                                  ),
                                ),

                                // 18+ Tag on Top-Left
                                if (entry.isAdult)
                                  Positioned(
                                    top: 6,
                                    left: 6,
                                    child: build18PlusBadge(fontSize: 8),
                                  ),

                                // Chapter Tag on Top-Right
                                Positioned(
                                  top: 6,
                                  right: 6,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: colorScheme.primaryContainer,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'CH ${entry.chapterNumber}',
                                      style: TextStyle(
                                        color: colorScheme.onPrimaryContainer,
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),

                                // Reading Progress Bar at Bottom
                                Positioned(
                                  bottom: 0,
                                  left: 0,
                                  right: 0,
                                  child: LinearProgressIndicator(
                                    value: entry.progressValue,
                                    minHeight: 3.5,
                                    backgroundColor: Colors.white24,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      colorScheme.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          entry.mangaTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            fontSize: 12.5,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          '${entry.chapterTitle} • Page ${entry.pageIndex}/${entry.totalPages}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  void _showContinueReadingMenu(
    BuildContext context,
    MangaReadingProgressEntry entry,
  ) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final colorScheme = theme.colorScheme;
        final activeSource = _getActiveMangaSource();

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.dividerColor.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  entry.mangaTitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${entry.chapterTitle} • Page ${entry.pageIndex}/${entry.totalPages}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const Divider(height: 20),

                // 1. Resume Reading
                ListTile(
                  leading: Icon(Iconsax.book_1, color: colorScheme.primary),
                  title: const Text('Resume Reading'),
                  subtitle: Text('Continue from page ${entry.pageIndex}'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    final targetSource =
                        activeSource ??
                        Source(
                          id: entry.sourceId ?? 'mangadex',
                          name: entry.sourceName ?? 'MangaDex',
                          isNsfw: entry.isAdult,
                        );

                    final chapter =
                        entry.chapterJson != null
                            ? DEpisode.fromJson(entry.chapterJson!)
                            : DEpisode(
                              url: entry.chapterUrl,
                              name: entry.chapterTitle,
                              episodeNumber: entry.chapterNumber,
                            );

                    final manga =
                        entry.mangaJson != null
                            ? DMedia.fromJson(entry.mangaJson!)
                            : DMedia(
                              title: entry.mangaTitle,
                              url: entry.mangaUrl,
                              cover: entry.mangaCover,
                            );

                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder:
                            (_) => MangaReaderScreen(
                              chapter: chapter,
                              mangaTitle: entry.mangaTitle,
                              mangaSource: targetSource,
                              manga: manga,
                              mangaCover: entry.mangaCover,
                              mangaUrl: entry.mangaUrl,
                              initialPage: entry.pageIndex,
                              isAdult: entry.isAdult,
                            ),
                      ),
                    );
                  },
                ),

                // 2. View Manga Details
                ListTile(
                  leading: Icon(
                    Iconsax.info_circle,
                    color: colorScheme.primary,
                  ),
                  title: const Text('View Manga Details'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    final targetSource =
                        activeSource ??
                        Source(
                          id: entry.sourceId ?? 'mangadex',
                          name: entry.sourceName ?? 'MangaDex',
                          isNsfw: entry.isAdult,
                        );

                    final manga =
                        entry.mangaJson != null
                            ? DMedia.fromJson(entry.mangaJson!)
                            : DMedia(
                              title: entry.mangaTitle,
                              url: entry.mangaUrl,
                              cover: entry.mangaCover,
                            );

                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder:
                            (_) => MangaDetailsScreen(
                              manga: manga,
                              mangaSource: targetSource,
                            ),
                      ),
                    );
                  },
                ),

                // 3. Mark as Read
                ListTile(
                  leading: const Icon(
                    Icons.check_circle_outline,
                    color: Colors.green,
                  ),
                  title: const Text('Mark as Completed'),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await ref
                        .read(mangaReadingProgressRepositoryProvider)
                        .markCompleted(entry.mangaUrl);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Marked as completed'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                ),

                // 4. Remove from Continue Reading
                ListTile(
                  leading: Icon(Iconsax.close_circle, color: colorScheme.error),
                  title: const Text('Remove from Continue Reading'),
                  subtitle: const Text('Clears your reading progress'),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    final repo = ref.read(
                      mangaReadingProgressRepositoryProvider,
                    );
                    await repo.removeProgress(entry.mangaUrl);

                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Removed "${entry.mangaTitle}"'),
                          action: SnackBarAction(
                            label: 'UNDO',
                            onPressed: () => repo.saveProgress(entry),
                          ),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // 4. Horizontal Manga Section (matching HomeSectionWidget on HomeScreen)
  // ---------------------------------------------------------------------------
  Widget _buildHorizontalSection({
    required BuildContext context,
    required String title,
    required List<DMedia> list,
    bool isAdultSection = false,
  }) {
    if (list.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final activeSource = _getActiveMangaSource();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: InkWell(
            onTap: () {
              if (activeSource != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (_) => MangaSectionScreen(
                          title: title,
                          mangaList: list,
                          mangaSource: activeSource,
                        ),
                  ),
                );
              }
            },
            borderRadius: BorderRadius.circular(8),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (isAdultSection) ...[
                        const SizedBox(width: 8),
                        build18PlusBadge(fontSize: 9),
                      ],
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 225,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final item = list[index];
              final isAdult =
                  isAdultSection || isMangaAdult(item, source: activeSource);
              final chCount = _getChapterCount(item);

              return GestureDetector(
                onTap: () => _openMangaDetails(item),
                child: SizedBox(
                  width: 125,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Card Cover
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              CachedNetworkImage(
                                imageUrl: item.cover ?? '',
                                fit: BoxFit.cover,
                                placeholder:
                                    (_, __) => Container(
                                      color:
                                          theme
                                              .colorScheme
                                              .surfaceContainerHighest,
                                      child: const Center(
                                        child: SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      ),
                                    ),
                                errorWidget:
                                    (_, __, ___) => Container(
                                      color:
                                          theme
                                              .colorScheme
                                              .surfaceContainerHighest,
                                      child: const Icon(Iconsax.book, size: 30),
                                    ),
                              ),
                              // 18+ Badge
                              if (isAdult)
                                Positioned(
                                  top: 6,
                                  left: 6,
                                  child: build18PlusBadge(fontSize: 8.5),
                                ),
                              // Chapter Badge
                              if (chCount != null && chCount > 0)
                                Positioned(
                                  bottom: 6,
                                  right: 6,
                                  child: _buildChapterBadge(chCount),
                                ),
                              // Bottom subtle gradient
                              Positioned(
                                bottom: 0,
                                left: 0,
                                right: 0,
                                height: 35,
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Colors.transparent,
                                        Colors.black.withValues(alpha: 0.65),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        item.title ?? 'Unknown',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 22),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 5. Search Results Grid
  // ---------------------------------------------------------------------------
  Widget _buildSearchResultsGrid(ColorScheme colorScheme) {
    if (_isSearching) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_searchList.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Text(
            'No manga found for "${_searchController.text}"',
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Search Results (${_searchList.length})',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: colorScheme.primary,
                fontSize: 14,
              ),
            ),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 0.58,
              crossAxisSpacing: 10,
              mainAxisSpacing: 14,
            ),
            itemCount: _searchList.length,
            itemBuilder: (context, index) {
              final item = _searchList[index];
              final isAdult = isMangaAdult(
                item,
                source: _getActiveMangaSource(),
              );
              final chCount = _getChapterCount(item);

              return InkWell(
                onTap: () => _openMangaDetails(item),
                borderRadius: BorderRadius.circular(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CachedNetworkImage(
                              imageUrl: item.cover ?? '',
                              fit: BoxFit.cover,
                              errorWidget:
                                  (_, __, ___) => Container(
                                    color: colorScheme.surfaceContainerHighest,
                                    child: const Icon(Iconsax.book, size: 30),
                                  ),
                            ),
                            if (isAdult)
                              Positioned(
                                top: 5,
                                left: 5,
                                child: build18PlusBadge(fontSize: 8.5),
                              ),
                            if (chCount != null && chCount > 0)
                              Positioned(
                                bottom: 5,
                                right: 5,
                                child: _buildChapterBadge(chCount),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      item.title ?? 'Unknown',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        height: 1.15,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasSearchQuery = _searchController.text.trim().isNotEmpty;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Top Header (exact parity with HomeScreen)
            _buildHeader(context),

            // Content Area
            Expanded(
              child:
                  hasSearchQuery
                      ? _buildSearchResultsGrid(colorScheme)
                      : _isLoading
                      ? const _MangaHomeSkeleton()
                      : _error != null
                      ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Iconsax.book,
                                size: 48,
                                color: Colors.grey,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _error!,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Wrap(
                                spacing: 12,
                                runSpacing: 8,
                                alignment: WrapAlignment.center,
                                children: [
                                  FilledButton.tonalIcon(
                                    onPressed:
                                        () => context.push(
                                          '/settings/extensions',
                                        ),
                                    icon: const Icon(Icons.extension_outlined),
                                    label: const Text('Install Extensions'),
                                  ),
                                  ElevatedButton.icon(
                                    onPressed: _loadMangaContent,
                                    icon: const Icon(Icons.refresh),
                                    label: const Text('Retry'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      )
                      : RefreshIndicator(
                        onRefresh: _loadMangaContent,
                        child: SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 1. Spotlight Hero Banner
                              _buildSpotlightBanner(context, colorScheme),

                              // 2. Continue Reading Section
                              _buildContinueReadingSection(context, theme),

                              // 3. Popular Manga Section
                              _buildHorizontalSection(
                                context: context,
                                title: 'Popular Manga',
                                list: _popularList,
                              ),

                              // 4. Latest Updates Section
                              _buildHorizontalSection(
                                context: context,
                                title: 'Latest Updates',
                                list: _latestList,
                              ),

                              // Bottom Navigation clearance padding
                              const SizedBox(height: 80),
                            ],
                          ),
                        ),
                      ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MangaHomeSkeleton extends StatelessWidget {
  const _MangaHomeSkeleton();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(
      context,
    ).colorScheme.surfaceContainerHighest.withValues(alpha: .65);
    Widget block({double? width, required double height, double radius = 12}) =>
        Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(radius),
          ),
        );

    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 100),
      children: [
        block(height: 205, radius: 20),
        const SizedBox(height: 24),
        block(width: 150, height: 20),
        const SizedBox(height: 12),
        SizedBox(
          height: 190,
          child: Row(
            children: List.generate(
              3,
              (index) => Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: index == 2 ? 0 : 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: block(height: 150)),
                      const SizedBox(height: 8),
                      block(height: 10),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        block(width: 130, height: 20),
        const SizedBox(height: 12),
        SizedBox(
          height: 190,
          child: Row(
            children: List.generate(
              3,
              (index) => Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: index == 2 ? 0 : 10),
                  child: block(height: 190),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
