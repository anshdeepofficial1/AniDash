import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ani_dash/core/models/universal/universal_media.dart';

import 'package:ani_dash/shared/ui/cards/anime/anime_card.dart';

import 'package:ani_dash/shared/providers/settings/ui_notifier.dart';
import 'package:ani_dash/helpers/navigation.dart';

class HomeSectionWidget extends ConsumerWidget {
  final String title;
  final List<UniversalMedia> mediaList;
  final VoidCallback? onTitleTap;
  final bool fromHentaiHub;

  const HomeSectionWidget({
    super.key,
    required this.title,
    required this.mediaList,
    this.onTitleTap,
    this.fromHentaiHub = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    final mode = ref.watch(uiSettingsProvider).cardStyle;
    final height = mode.getDimensions(context).height;

    if (mediaList.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: InkWell(
            onTap: onTitleTap,
            borderRadius: BorderRadius.circular(8),
            child: Row(
              children: [
                Expanded(child: Text(title, style: theme.textTheme.titleLarge)),
                if (onTitleTap != null) const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = MediaQuery.sizeOf(context).width >= 900;
            final cardWidth = mode.getDimensions(context).width;
            final visibleCount = ((constraints.maxWidth + 12) /
                    (cardWidth + 12))
                .floor()
                .clamp(1, mediaList.length);

            Widget buildCard(int index) {
              final media = mediaList[index];
              final tag = 'home-$title-${media.id}';
              return GestureDetector(
                onTap:
                    () => navigateToDetail(
                      context,
                      media,
                      tag,
                      fromHentaiHub: fromHentaiHub || media.isAdult,
                    ),
                child: AnimeCard(anime: media, tag: tag, mode: mode),
              );
            }

            return SizedBox(
              height: height,
              child:
                  isDesktop
                      ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (
                            var index = 0;
                            index < visibleCount;
                            index++
                          ) ...[
                            SizedBox(width: cardWidth, child: buildCard(index)),
                            if (index < visibleCount - 1)
                              const SizedBox(width: 12),
                          ],
                        ],
                      )
                      : ListView.builder(
                        addAutomaticKeepAlives: true,
                        addRepaintBoundaries: true,
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        itemCount: mediaList.length,
                        itemBuilder:
                            (context, index) => Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: buildCard(index),
                            ),
                      ),
            );
          },
        ),

        const SizedBox(height: 24),
      ],
    );
  }
}
