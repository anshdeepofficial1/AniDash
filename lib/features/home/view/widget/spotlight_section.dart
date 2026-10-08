import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:iconsax/iconsax.dart';
import 'package:ani_dash/core/models/universal/universal_media.dart';
import 'package:ani_dash/shared/ui/cards/spotlight/anime_spotlight_card.dart';

import 'package:ani_dash/shared/providers/settings/ui_notifier.dart';
import 'package:ani_dash/helpers/navigation.dart';

class SpotlightSection extends ConsumerStatefulWidget {
  final List<UniversalMedia>? spotlightAnime;

  const SpotlightSection({super.key, required this.spotlightAnime});

  @override
  ConsumerState<SpotlightSection> createState() => _SpotlightSectionState();
}

class _SpotlightSectionState extends ConsumerState<SpotlightSection> {
  bool _isHovered = false;
  final CarouselSliderController _carouselController = CarouselSliderController();

  @override
  Widget build(BuildContext context) {
    final trendingAnimes =
        (widget.spotlightAnime != null && widget.spotlightAnime!.isNotEmpty)
            ? widget.spotlightAnime!
            : List<UniversalMedia?>.filled(25, null);
    final cardMode = ref.watch(
      uiSettingsProvider.select((ui) => ui.spotlightCardStyle),
    );
    final carouselHeight = cardMode.getDimensions(context).height;
    final isDesktop = MediaQuery.of(context).size.width > 900;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SpotlightHeader(spotlightAnime: widget.spotlightAnime),
        MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: Stack(
            alignment: Alignment.center,
            children: [
              ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(
                  dragDevices: {
                    PointerDeviceKind.touch,
                    PointerDeviceKind.mouse,
                    PointerDeviceKind.trackpad,
                    PointerDeviceKind.stylus,
                  },
                ),
                child: CarouselSlider.builder(
                  carouselController: _carouselController,
                  options: CarouselOptions(
                    height: carouselHeight,
                    autoPlay: !_isHovered,
                    autoPlayInterval: const Duration(seconds: 2),
                    autoPlayAnimationDuration: const Duration(milliseconds: 600),
                    autoPlayCurve: Curves.easeInOutCubic,
                    pauseAutoPlayOnTouch: true,
                    pauseAutoPlayOnManualNavigate: true,
                    enableInfiniteScroll: true,
                    enlargeCenterPage: true,
                    enlargeStrategy: CenterPageEnlargeStrategy.height,
                    viewportFraction: isDesktop ? 0.8 : 0.9,
                    pageSnapping: true,
                  ),
                  itemCount: trendingAnimes.length,
                  itemBuilder: (context, index, realIndex) {
                    final anime = trendingAnimes[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 5),
                      child: AnimeSpotlightCard(
                        onTap:
                            (media) =>
                                anime?.id != null
                                    ? navigateToDetail(
                                      context,
                                      media,
                                      anime?.id.toString() ?? '',
                                      forceFetch: true,
                                    )
                                    : null,
                        anime: anime,
                        mode: cardMode,
                        heroTag: 'spotlight_${anime?.id ?? 'loading_$index'}',
                      ),
                    );
                  },
                ),
              ),
              // Optional subtle desktop quick navigation arrows on hover
              if (isDesktop && _isHovered) ...[
                Positioned(
                  left: 12,
                  child: IconButton.filledTonal(
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black.withValues(alpha: 0.65),
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Iconsax.arrow_left_2, size: 20),
                    tooltip: 'Previous Anime',
                    onPressed: () => _carouselController.previousPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                    ),
                  ),
                ),
                Positioned(
                  right: 12,
                  child: IconButton.filledTonal(
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black.withValues(alpha: 0.65),
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Iconsax.arrow_right_3, size: 20),
                    tooltip: 'Next Anime',
                    onPressed: () => _carouselController.nextPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }
}

class _SpotlightHeader extends StatelessWidget {
  final List<UniversalMedia>? spotlightAnime;

  const _SpotlightHeader({required this.spotlightAnime});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(15, 0, 0, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.tertiaryContainer,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Iconsax.star5,
              size: 18,
              color: theme.colorScheme.onTertiaryContainer,
            ),
            const SizedBox(width: 8),
            Text(
              'Trending ${spotlightAnime?.length ?? 25}',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onTertiaryContainer,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
