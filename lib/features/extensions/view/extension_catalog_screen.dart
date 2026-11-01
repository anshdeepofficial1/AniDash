import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dartotsu_extension_bridge/dartotsu_extension_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:ani_dash/core/models/universal/universal_media.dart';
import 'package:ani_dash/features/manga/view/manga_details_screen.dart';
import 'package:ani_dash/shared/providers/settings/experimental_notifier.dart';
import 'package:ani_dash/shared/providers/settings/source_notifier.dart';

class ExtensionCatalogScreen extends ConsumerStatefulWidget {
  final Source source;

  const ExtensionCatalogScreen({
    super.key,
    required this.source,
  });

  @override
  ConsumerState<ExtensionCatalogScreen> createState() =>
      _ExtensionCatalogScreenState();
}

class _ExtensionCatalogScreenState
    extends ConsumerState<ExtensionCatalogScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  int _selectedTabIndex = 0; // 0: Popular, 1: Latest
  bool _isLoading = false;
  bool _isSearching = false;
  String? _error;

  List<DMedia> _popularList = [];
  List<DMedia> _latestList = [];
  List<DMedia> _searchList = [];

  int _popularPage = 1;
  int _latestPage = 1;
  int _searchPage = 1;

  bool _hasMorePopular = true;
  bool _hasMoreLatest = true;
  bool _hasMoreSearch = true;
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadContent();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadContent() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      Pages? popularPages;
      Pages? latestPages;

      await Future.wait([
        () async {
          try {
            popularPages = await widget.source.methods
                .getPopular(1)
                .timeout(const Duration(seconds: 15));
          } catch (_) {}
        }(),
        () async {
          try {
            latestPages = await widget.source.methods
                .getLatestUpdates(1)
                .timeout(const Duration(seconds: 15));
          } catch (_) {}
        }(),
      ]);

      final popular = popularPages?.list ?? <DMedia>[];
      final latest = latestPages?.list ?? <DMedia>[];

      final finalPopular = popular.isNotEmpty ? popular : latest;
      final finalLatest = latest.isNotEmpty ? latest : popular;

      if (mounted) {
        setState(() {
          _popularList = finalPopular;
          _latestList = finalLatest;
          _hasMorePopular = popularPages?.hasNextPage ?? (finalPopular.length >= 10);
          _hasMoreLatest = latestPages?.hasNextPage ?? (finalLatest.length >= 10);
          _isLoading = false;
          if (_popularList.isEmpty && _latestList.isEmpty) {
            _error =
                'No content found for ${widget.source.name ?? "this extension"}. Check your network or extension settings.';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load catalog: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore) return;
    setState(() => _isLoadingMore = true);

    try {
      final isSearchActive = _searchController.text.trim().isNotEmpty;
      if (isSearchActive) {
        if (!_hasMoreSearch) return;
        final next = _searchPage + 1;
        final res = await widget.source.methods
            .search(_searchController.text.trim(), next, [])
            .timeout(const Duration(seconds: 15));
        if (mounted) {
          setState(() {
            _searchPage = next;
            _searchList.addAll(res.list);
            _hasMoreSearch = res.hasNextPage;
          });
        }
      } else if (_selectedTabIndex == 0) {
        if (!_hasMorePopular) return;
        final next = _popularPage + 1;
        final res = await widget.source.methods
            .getPopular(next)
            .timeout(const Duration(seconds: 15));
        if (mounted) {
          setState(() {
            _popularPage = next;
            _popularList.addAll(res.list);
            _hasMorePopular = res.hasNextPage;
          });
        }
      } else {
        if (!_hasMoreLatest) return;
        final next = _latestPage + 1;
        final res = await widget.source.methods
            .getLatestUpdates(next)
            .timeout(const Duration(seconds: 15));
        if (mounted) {
          setState(() {
            _latestPage = next;
            _latestList.addAll(res.list);
            _hasMoreLatest = res.hasNextPage;
          });
        }
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _executeSearch(query);
    });
  }

  Future<void> _executeSearch(String query) async {
    if (query.trim().isEmpty) {
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
      _searchPage = 1;
    });

    try {
      final res = await widget.source.methods
          .search(query.trim(), 1, [])
          .timeout(const Duration(seconds: 15));
      if (mounted) {
        setState(() {
          _searchList = res.list;
          _hasMoreSearch = res.hasNextPage;
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

  void _openDetails(DMedia item) {
    if (widget.source.itemType == ItemType.manga) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MangaDetailsScreen(
            manga: item,
            mangaSource: widget.source,
          ),
        ),
      );
    } else {
      // Set this extension as active anime source
      ref.read(sourceProvider.notifier).setActiveSource(widget.source);
      ref.read(experimentalProvider.notifier).toggleExtensions(true);

      final media = UniversalMedia(
        id: item.url ?? item.title ?? '0',
        title: UniversalTitle(
          english: item.title,
          romaji: item.title,
          native: item.title,
        ),
        coverImage: UniversalCoverImage(
          large: item.cover,
          medium: item.cover,
        ),
        description: item.description,
        format: 'TV',
      );

      context.push('/details', extra: media);
    }
  }

  void _toggleActiveProvider() {
    final activeSource = ref.read(sourceProvider).activeAnimeSource;
    final isAlreadyActive =
        activeSource?.id == widget.source.id ||
        activeSource?.name == widget.source.name;

    if (isAlreadyActive) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${widget.source.name ?? "Extension"} is already active provider.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    ref.read(sourceProvider.notifier).setActiveSource(widget.source);
    ref.read(experimentalProvider.notifier).toggleExtensions(true);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Set ${widget.source.name ?? "Extension"} as active anime provider!'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final activeSource = ref.watch(sourceProvider).activeAnimeSource;
    final isActiveProvider =
        activeSource?.id == widget.source.id ||
        activeSource?.name == widget.source.name;

    final isSearchActive = _searchController.text.trim().isNotEmpty;
    final currentList = isSearchActive
        ? _searchList
        : (_selectedTabIndex == 0 ? _popularList : _latestList);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton.filledTonal(
          onPressed: () => context.pop(),
          icon: const Icon(Iconsax.arrow_left_2),
        ),
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: widget.source.iconUrl?.isNotEmpty == true
                  ? CachedNetworkImage(
                      imageUrl: widget.source.iconUrl!,
                      width: 28,
                      height: 28,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => const Icon(
                        Icons.extension,
                        size: 20,
                      ),
                    )
                  : const Icon(Icons.extension, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.source.name ?? 'Extension Catalog',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'v${widget.source.version ?? "1.0"} • ${widget.source.lang ?? "en"}',
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: isActiveProvider
                ? 'Active Content Provider'
                : 'Set as Active Provider',
            icon: Icon(
              isActiveProvider ? Icons.check_circle : Icons.radio_button_off,
              color: isActiveProvider ? colorScheme.primary : null,
            ),
            onPressed: _toggleActiveProvider,
          ),
          IconButton(
            tooltip: 'Extension Settings',
            icon: const Icon(Iconsax.setting_2),
            onPressed: () => context.push(
              '/settings/extensions/extension-preference',
              extra: widget.source,
            ),
          ),
        ],
        forceMaterialTransparency: true,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          if (isSearchActive) {
            await _executeSearch(_searchController.text.trim());
          } else {
            await _loadContent();
          }
        },
        child: Column(
          children: [
            // Search Input
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: 'Search ${widget.source.name ?? "Extension"}...',
                  prefixIcon: const Icon(Iconsax.search_normal),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            _executeSearch('');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ),

            // Tab Filter (Popular vs Latest) when not searching
            if (!isSearchActive)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    FilterChip(
                      label: const Text('Popular'),
                      selected: _selectedTabIndex == 0,
                      onSelected: (val) {
                        if (val) setState(() => _selectedTabIndex = 0);
                      },
                      avatar: const Icon(Iconsax.star, size: 16),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Text('Latest Updates'),
                      selected: _selectedTabIndex == 1,
                      onSelected: (val) {
                        if (val) setState(() => _selectedTabIndex = 1);
                      },
                      avatar: const Icon(Iconsax.clock, size: 16),
                    ),
                    const Spacer(),
                    Text(
                      '${currentList.length} items',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),

            // Body Content
            Expanded(
              child: _isLoading || _isSearching
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null && currentList.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.error_outline, size: 48, color: colorScheme.error),
                                const SizedBox(height: 12),
                                Text(
                                  _error!,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: colorScheme.onSurface),
                                ),
                                const SizedBox(height: 16),
                                FilledButton.tonalIcon(
                                  onPressed: _loadContent,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Retry'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : currentList.isEmpty
                          ? Center(
                              child: Text(
                                isSearchActive
                                    ? 'No results found for "${_searchController.text.trim()}"'
                                    : 'No items available in this category.',
                                style: TextStyle(color: colorScheme.onSurfaceVariant),
                              ),
                            )
                          : NotificationListener<ScrollNotification>(
                              onNotification: (scrollInfo) {
                                if (scrollInfo.metrics.pixels >=
                                        scrollInfo.metrics.maxScrollExtent - 200 &&
                                    !_isLoadingMore) {
                                  _loadMore();
                                }
                                return false;
                              },
                              child: GridView.builder(
                                padding: const EdgeInsets.all(16),
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  childAspectRatio: 0.62,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                ),
                                itemCount: currentList.length + (_isLoadingMore ? 1 : 0),
                                itemBuilder: (context, index) {
                                  if (index >= currentList.length) {
                                    return const Center(
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    );
                                  }

                                  final item = currentList[index];
                                  final title = item.title ?? 'Unknown';
                                  final coverUrl = item.cover ?? '';

                                  return InkWell(
                                    onTap: () => _openDetails(item),
                                    borderRadius: BorderRadius.circular(12),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(12),
                                            child: Container(
                                              color: colorScheme.surfaceContainerHighest,
                                              width: double.infinity,
                                              child: coverUrl.isNotEmpty
                                                  ? CachedNetworkImage(
                                                      imageUrl: coverUrl,
                                                      fit: BoxFit.cover,
                                                      errorWidget: (_, __, ___) =>
                                                          const Center(
                                                        child: Icon(
                                                          Icons.movie_creation_outlined,
                                                          size: 32,
                                                        ),
                                                      ),
                                                    )
                                                  : const Center(
                                                      child: Icon(
                                                        Icons.movie_creation_outlined,
                                                        size: 32,
                                                      ),
                                                    ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          title,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            fontWeight: FontWeight.w600,
                                            height: 1.2,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }
}
