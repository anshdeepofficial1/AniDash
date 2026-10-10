import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:ani_dash/core/models/universal/universal_media.dart';
import 'package:ani_dash/core/repositories/watch_progress_repository.dart';
import 'package:ani_dash/features/details/view_model/details_page_notifier.dart';
import 'package:ani_dash/features/watch/view_model/episode_list_provider.dart';
import 'package:ani_dash/features/details/view/widgets/episodes_tab.dart';
import 'package:ani_dash/features/details/view/widgets/characters_tab.dart';
import 'package:ani_dash/shared/providers/settings/experimental_notifier.dart';
import 'package:ani_dash/helpers/anime_match_search.dart';
import 'widgets/widgets.dart';

class AnimeDetailsScreen extends ConsumerStatefulWidget {
  final UniversalMedia anime;
  final String tag;
  final bool forceFetch;
  final bool fromHentaiHub;
  final int initialTabIndex;

  const AnimeDetailsScreen({
    super.key,
    required this.anime,
    required this.tag,
    this.forceFetch = false,
    this.fromHentaiHub = false,
    this.initialTabIndex = 0,
  });

  @override
  ConsumerState<AnimeDetailsScreen> createState() => _AnimeDetailsScreenState();
}

class _AnimeDetailsScreenState extends ConsumerState<AnimeDetailsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late UniversalMedia _activeMedia;

  @override
  void initState() {
    super.initState();
    _activeMedia = widget.anime;
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 2),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final id = _activeMedia.id;
      ref.read(detailsPageProvider(id).notifier).init(_activeMedia);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _onMediaTap(UniversalMedia media) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => AnimeDetailsScreen(
              anime: media,
              tag: 'tag-${media.id}',
              fromHentaiHub: widget.fromHentaiHub,
            ),
      ),
    );
  }

  void _onSeasonSelected(UniversalMedia media) {
    if (media.id == _activeMedia.id) return;
    // The episode list is shared for playback continuity. Clear it before
    // changing identity so a completed request for the previous season can
    // never be rendered as the newly selected season.
    ref.read(episodeListProvider.notifier).reset();
    setState(() {
      _activeMedia = media;
    });
    ref.read(detailsPageProvider(media.id).notifier).init(media);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final useExtensions = ref.watch(
      experimentalProvider.select((exp) => exp.useExtensions),
    );

    final id = _activeMedia.id;
    final pageState = ref.watch(detailsPageProvider(id));
    final displayedAnime = pageState.details.value ?? _activeMedia;
    final isLoading = pageState.isLoading;
    final isMovie = displayedAnime.format?.toUpperCase() == 'MOVIE';
    final isDesktop = !(Platform.isAndroid || Platform.isIOS);

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      body: SafeArea(
        bottom: false,
        child: NestedScrollView(
          // Give downward drags to the floating cover header before the
          // active tab consumes them. This lets every tab reveal the cover
          // again without first switching back to About.
          floatHeaderSlivers: true,
          headerSliverBuilder: (context, innerBoxIsScrolled) {
            return [
              DetailsHeader(
                key: ValueKey('header-${displayedAnime.id}'),
                anime: displayedAnime,
                tag: widget.tag,
              ),
              if (isDesktop)
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _DetailsTabBarDelegate(
                    tabBar: TabBar(
                      controller: _tabController,
                      labelColor: colorScheme.primary,
                      unselectedLabelColor: colorScheme.onSurface.withValues(
                        alpha: 0.6,
                      ),
                      indicatorColor: colorScheme.primary,
                      indicatorSize: TabBarIndicatorSize.label,
                      indicatorWeight: 3,
                      labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal, fontSize: 14),
                      dividerColor: colorScheme.outlineVariant.withValues(alpha: 0.3),
                      tabs: [
                        const Tab(text: 'About'),
                        Tab(text: isMovie ? 'Movie' : 'Episodes'),
                        const Tab(text: 'Characters'),
                      ],
                    ),
                    backgroundColor: colorScheme.surfaceContainerLowest,
                  ),
                ),
            ];
          },
          body: ScrollConfiguration(
            behavior: ScrollConfiguration.of(
              context,
            ).copyWith(scrollbars: false),
            child: TabBarView(
              controller: _tabController,
              children: [
                _KeepAliveWrapper(
                  key: ValueKey('about-wrap-${displayedAnime.id}'),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(0, 16, 0, 24),
                    child: DetailsContent(
                      key: ValueKey('content-${displayedAnime.id}'),
                      anime: displayedAnime,
                      mediaId: id.toString(),
                      isLoading: isLoading,
                      onMediaTap: _onMediaTap,
                    ),
                  ),
                ),
                _KeepAliveWrapper(
                  key: ValueKey('episodes-wrap-${displayedAnime.id}'),
                  child: EpisodesTab(
                    key: ValueKey('episodes-${displayedAnime.id}'),
                    anime: displayedAnime,
                    mediaId: displayedAnime.id.toString(),
                    malId: int.tryParse(displayedAnime.idMal ?? ''),
                    mediaTitle: displayedAnime.title,
                    mediaFormat: displayedAnime.format ?? '',
                    mediaCover:
                        displayedAnime.coverImage.large ??
                        displayedAnime.coverImage.medium ??
                        '',
                    fromHentaiHub: widget.fromHentaiHub,
                    relations: displayedAnime.relations,
                    onSeasonSelected: _onSeasonSelected,
                  ),
                ),
                _KeepAliveWrapper(
                  key: ValueKey('chars-wrap-${displayedAnime.id}'),
                  child: CharactersTab(
                    key: ValueKey('chars-${displayedAnime.id}'),
                    characters: displayedAnime.characters,
                    isLoading: isLoading,
                    onRetry:
                      () =>
                          ref
                              .read(detailsPageProvider(id).notifier)
                              .fetchDetails(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: isDesktop
          ? null
          : Material(
              color: colorScheme.surface,
              elevation: 8,
              child: SafeArea(
                child: SizedBox(
                  height: 60,
                  child: TabBar(
                    controller: _tabController,
                    labelColor: colorScheme.primary,
                    unselectedLabelColor: colorScheme.onSurface.withValues(
                      alpha: 0.6,
                    ),
                    indicatorColor: colorScheme.primary,
                    indicatorSize: TabBarIndicatorSize.label,
                    dividerColor: Colors.transparent,
                    tabs: [
                      const Tab(text: 'About'),
                      Tab(text: isMovie ? 'Movie' : 'Episodes'),
                      const Tab(text: 'Characters'),
                    ],
                  ),
                ),
              ),
            ),
      floatingActionButton:
          !useExtensions ? _WatchFab(anime: displayedAnime) : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}

class _DetailsTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  final Color backgroundColor;

  _DetailsTabBarDelegate({required this.tabBar, required this.backgroundColor});

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: backgroundColor,
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: tabBar,
      ),
    );
  }

  @override
  double get maxExtent => 48.0;

  @override
  double get minExtent => 48.0;

  @override
  bool shouldRebuild(covariant _DetailsTabBarDelegate oldDelegate) {
    return oldDelegate.tabBar != tabBar || oldDelegate.backgroundColor != backgroundColor;
  }
}

class _WatchFab extends ConsumerStatefulWidget {
  final UniversalMedia anime;
  const _WatchFab({required this.anime});

  @override
  ConsumerState<_WatchFab> createState() => _WatchFabState();
}

class _WatchFabState extends ConsumerState<_WatchFab> {
  bool _isWatchLoading = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final animeIdStr = widget.anime.id.toString();
    final progress =
        ref.watch(animeWatchProgressProvider(animeIdStr)).asData?.value ??
        ref.read(watchProgressRepositoryProvider).getProgress(animeIdStr);

    return FloatingActionButton.extended(
      heroTag: 'watch_btn',
      onPressed:
          _isWatchLoading
              ? null
              : () async {
                setState(() => _isWatchLoading = true);
                await providerAnimeMatchSearch(
                  context: context,
                  ref: ref,
                  animeMedia: widget.anime,
                );
                if (mounted) {
                  setState(() => _isWatchLoading = false);
                }
              },
      backgroundColor: colorScheme.primary,
      foregroundColor: colorScheme.onPrimary,
      elevation: 6,
      icon:
          _isWatchLoading
              ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    colorScheme.onPrimary,
                  ),
                ),
              )
              : const Icon(Iconsax.play_circle, size: 24),
      label: Text(
        _isWatchLoading
            ? 'Loading...'
            : (widget.anime.format?.toUpperCase() == 'MOVIE')
                ? 'Watch Movie'
                : progress?.currentEpisode != null
                ? 'EP ${progress?.currentEpisode}'
                : 'Watch Now',
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _KeepAliveWrapper extends StatefulWidget {
  final Widget child;
  const _KeepAliveWrapper({super.key, required this.child});

  @override
  State<_KeepAliveWrapper> createState() => _KeepAliveWrapperState();
}

class _KeepAliveWrapperState extends State<_KeepAliveWrapper>
    with AutomaticKeepAliveClientMixin {
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }

  @override
  bool get wantKeepAlive => true;
}
