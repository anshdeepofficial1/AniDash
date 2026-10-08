import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:ani_dash/core/models/universal/universal_media.dart';
import 'package:ani_dash/shared/ui/cards/anime/anime_card.dart';

import 'package:ani_dash/shared/providers/settings/ui_notifier.dart';
import 'package:ani_dash/shared/ui/shonenx_gridview.dart';
import 'package:ani_dash/helpers/navigation.dart';
import 'package:go_router/go_router.dart';

import 'package:ani_dash/core/models/universal/universal_page_response.dart';
import 'package:cached_network_image/cached_network_image.dart';

class SectionScreen extends ConsumerStatefulWidget {
  final String title;
  final Future<UniversalPageResponse<UniversalMedia>> Function({
    int page,
    int perPage,
  })
  fetchItems;
  final bool ranked;

  const SectionScreen({
    super.key,
    required this.title,
    required this.fetchItems,
    this.ranked = false,
  });

  @override
  ConsumerState<SectionScreen> createState() => _SectionScreenState();
}

class _SectionScreenState extends ConsumerState<SectionScreen> {
  final ScrollController _scrollController = ScrollController();
  final List<UniversalMedia> _items = [];
  bool _isLoading = true;
  bool _hasMore = true;
  int _currentPage = 1;

  @override
  void initState() {
    super.initState();
    _fetchData();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoading &&
        _hasMore &&
        !widget.ranked) {
      _fetchData();
    }
  }

  Future<void> _fetchData() async {
    if (!_hasMore) return;

    setState(() => _isLoading = true);

    try {
      // Backend caps perPage at 50, fetch honestly up to 50 per request
      final response = await widget.fetchItems(
        page: _currentPage,
        perPage: widget.ranked ? 50 : 20,
      );
      final newItems = response.data;
      if (mounted) {
        setState(() {
          if (newItems.isEmpty) {
            _hasMore = false;
          } else {
            _items.addAll(newItems);
            _currentPage++;
            if (newItems.length < (widget.ranked ? 50 : 20)) {
              _hasMore = false;
            }
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        // Maybe show snackbar error?
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(uiSettingsProvider).cardStyle;
    final size = mode.getDimensions(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    // Dynamic navigation inset: system bottom inset + custom floating nav height (~64px) + margin
    final navBarPadding = bottomInset + 88.0;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Iconsax.arrow_left_2),
          onPressed: () => context.pop(),
        ),
        title: Text(widget.title),
      ),
      body:
          _items.isEmpty && _isLoading
              ? const Center(child: CircularProgressIndicator())
              : widget.ranked
              ? ListView.separated(
                controller: _scrollController,
                padding: EdgeInsets.fromLTRB(12, 8, 12, navBarPadding),
                itemCount: _items.length + 1,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  if (index == _items.length) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child:
                            _isLoading
                                ? const CircularProgressIndicator()
                                : _hasMore
                                ? FilledButton.tonalIcon(
                                  onPressed: _fetchData,
                                  icon: const Icon(Icons.expand_more_rounded),
                                  label: const Text('Show More'),
                                )
                                : const Text('You reached the end'),
                      ),
                    );
                  }
                  final media = _items[index];
                  final rank = index + 1;
                  final title =
                      media.title.english ??
                      media.title.romaji ??
                      media.title.native ??
                      'Untitled';

                  // Distinct podium treatments
                  Color? rankColor;
                  Color? rankBgColor;
                  BorderSide? rankBorderSide;

                  if (rank == 1) {
                    // Gold
                    rankColor = const Color(0xFFFFD700);
                    rankBgColor = const Color(0xFFFFD700).withValues(alpha: 0.12);
                    rankBorderSide = BorderSide(
                      color: const Color(0xFFFFD700).withValues(alpha: 0.55),
                      width: 1.2,
                    );
                  } else if (rank == 2) {
                    // Silver
                    rankColor = const Color(0xFFD6D6D6);
                    rankBgColor = const Color(0xFFD6D6D6).withValues(alpha: 0.10);
                    rankBorderSide = BorderSide(
                      color: const Color(0xFFD6D6D6).withValues(alpha: 0.45),
                      width: 1.2,
                    );
                  } else if (rank == 3) {
                    // Bronze
                    rankColor = const Color(0xFFCD7F32);
                    rankBgColor = const Color(0xFFCD7F32).withValues(alpha: 0.12);
                    rankBorderSide = BorderSide(
                      color: const Color(0xFFCD7F32).withValues(alpha: 0.50),
                      width: 1.2,
                    );
                  }

                  return Card(
                    elevation: rank <= 3 ? 2 : 0,
                    color: rankBgColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: rankBorderSide ?? BorderSide(
                        color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
                        width: 0.8,
                      ),
                    ),
                    child: ListTile(
                      onTap:
                          () => navigateToDetail(
                            context,
                            media,
                            'trending_${media.id}',
                          ),
                      leading: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 42,
                            alignment: Alignment.center,
                            child: Text(
                              '#$rank',
                              style: Theme.of(
                                context,
                              ).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: rankColor ?? Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: CachedNetworkImage(
                              imageUrl:
                                  media.highResCoverImage.isNotEmpty
                                      ? media.highResCoverImage
                                      : (media.coverImage.large ??
                                          media.coverImage.medium ??
                                          ''),
                              width: 48,
                              height: 64,
                              fit: BoxFit.cover,
                              filterQuality: FilterQuality.high,
                            ),
                          ),
                        ],
                      ),
                      title: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        [
                          if (media.averageScore != null)
                            '★ ${media.averageScore!.toStringAsFixed(1)}',
                          if (media.format != null) media.format!,
                          if (media.episodes != null) '${media.episodes} eps',
                        ].join('  •  '),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                    ),
                  );
                },
              )
              : AniDashGridView(
                padding: EdgeInsets.fromLTRB(10, 10, 10, navBarPadding),
                controller: _scrollController,
                physics: const BouncingScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                crossAxisExtent: size.width,
                childAspectRatio: size.width / size.height,
                itemCount: _items.length + (_isLoading ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == _items.length) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(10.0),
                        child: CircularProgressIndicator(),
                      ),
                    );
                  }
                  final media = _items[index];
                  return GestureDetector(
                    onTap:
                        () => navigateToDetail(
                          context,
                          media,
                          'section_${media.id}',
                        ),
                    child: AnimeCard(
                      anime: media,
                      mode: mode,
                      tag: 'section_${media.id}',
                    ),
                  );
                },
              ),
    );
  }
}
