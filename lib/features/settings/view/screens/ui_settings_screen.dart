import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:go_router/go_router.dart';
import 'package:ani_dash/shared/ui/cards/anime/anime_card.dart';
import 'package:ani_dash/shared/ui/cards/anime/anime_card_mode.dart';
import 'package:ani_dash/shared/ui/cards/spotlight/anime_spotlight_card.dart';
import 'package:ani_dash/shared/ui/cards/spotlight/spotlight_card_mode.dart';
import 'package:ani_dash/shared/providers/settings/ui_notifier.dart';
import 'package:ani_dash/features/settings/view/widgets/settings_item.dart';
import 'package:ani_dash/features/settings/view/widgets/settings_section.dart';
import 'package:ani_dash/core/models/universal/universal_media.dart';

class UiSettingsScreen extends ConsumerWidget {
  const UiSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final uiSettings = ref.watch(uiSettingsProvider);
    final isDesktop =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton.filledTonal(
          onPressed: () => context.pop(),
          icon: const Icon(Iconsax.arrow_left_2),
        ),
        title: const Text('UI Settings'),
        forceMaterialTransparency: true,
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              isDesktop ? 20 : 10,
              isDesktop ? 16 : 10,
              isDesktop ? 20 : 10,
              48,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SettingsSection(
                  title: 'Content Display',
                  titleColor: colorScheme.primary,
                  children: [
                    NormalSettingsItem(
                      icon: Icon(Iconsax.card, color: colorScheme.primary),
                      accent: colorScheme.primary,
                      title: 'Card Style',
                      description: 'Customize standard anime card appearance',
                      onTap: () => _showStyleSelector(context, ref, false),
                    ),
                    NormalSettingsItem(
                      icon: Icon(Iconsax.star_1, color: colorScheme.primary),
                      accent: colorScheme.primary,
                      title: 'Spotlight Card Style',
                      description: 'Customize spotlight/banner appearance',
                      onTap: () => _showStyleSelector(context, ref, true),
                    ),
                    DropdownSettingsItem(
                      icon: Icon(Iconsax.task, color: colorScheme.primary),
                      accent: colorScheme.primary,
                      title: 'Episode View Mode',
                      description: 'Choose how episodes are displayed',
                      value: uiSettings.episodeViewMode,
                      items: const [
                        DropdownMenuItem(value: 'list', child: Text('List')),
                        DropdownMenuItem(
                          value: 'compact',
                          child: Text('Compact'),
                        ),
                        DropdownMenuItem(value: 'grid', child: Text('Grid')),
                        DropdownMenuItem(value: 'block', child: Text('Block')),
                        DropdownMenuItem(
                          value: 'banner',
                          child: Text('Banner'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          ref
                              .read(uiSettingsProvider.notifier)
                              .updateSettings(
                                (s) => s.copyWith(episodeViewMode: value),
                              );
                        }
                      },
                    ),
                  ],
                ),
                SettingsSection(
                  title: 'Navigation Bar',
                  titleColor: colorScheme.primary,
                  children: [
                    ToggleableSettingsItem(
                      icon: Icon(Iconsax.home, color: colorScheme.primary),
                      accent: colorScheme.primary,
                      title: 'Home',
                      description: 'Primary landing screen (Always enabled)',
                      value: true,
                      onChanged: (val) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Home tab cannot be disabled'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                    ToggleableSettingsItem(
                      icon: Icon(
                        Iconsax.search_normal_1,
                        color: colorScheme.primary,
                      ),
                      accent: colorScheme.primary,
                      title: 'Browse',
                      description:
                          'Discover trending, popular and seasonal anime',
                      value: uiSettings.showBrowseNav,
                      onChanged: (value) {
                        ref
                            .read(uiSettingsProvider.notifier)
                            .updateSettings(
                              (s) => s.copyWith(showBrowseNav: value),
                            );
                      },
                    ),
                    ToggleableSettingsItem(
                      icon: Icon(Iconsax.book, color: colorScheme.primary),
                      accent: colorScheme.primary,
                      title: 'Manga',
                      description: 'Read manga chapters and titles',
                      value: uiSettings.showMangaNav,
                      onChanged: (value) {
                        ref
                            .read(uiSettingsProvider.notifier)
                            .updateSettings(
                              (s) => s.copyWith(showMangaNav: value),
                            );
                      },
                    ),
                    ToggleableSettingsItem(
                      icon: Icon(
                        Iconsax.receive_square,
                        color: colorScheme.primary,
                      ),
                      accent: colorScheme.primary,
                      title: 'Downloads',
                      description: 'Offline episodes and manager',
                      value: uiSettings.showDownloadsNav,
                      onChanged: (value) {
                        ref
                            .read(uiSettingsProvider.notifier)
                            .updateSettings(
                              (s) => s.copyWith(showDownloadsNav: value),
                            );
                      },
                    ),
                    ToggleableSettingsItem(
                      icon: Icon(Iconsax.bookmark, color: colorScheme.primary),
                      accent: colorScheme.primary,
                      title: 'Watchlist',
                      description: 'Personal anime library and tracker',
                      value: uiSettings.showWatchlistNav,
                      onChanged: (value) {
                        ref
                            .read(uiSettingsProvider.notifier)
                            .updateSettings(
                              (s) => s.copyWith(showWatchlistNav: value),
                            );
                      },
                    ),
                  ],
                ),
                SettingsSection(
                  title: "Responsive",
                  children: [
                    SliderSettingsItem(
                      icon: Icon(Iconsax.task, color: colorScheme.primary),
                      accent: colorScheme.primary,
                      title: 'Scale',
                      description: "${uiSettings.scale.toStringAsFixed(1)}x",
                      value: uiSettings.scale,
                      min: 0.5,
                      max: 1.5,
                      divisions: 10,
                      onChanged: (value) {
                        ref
                            .read(uiSettingsProvider.notifier)
                            .updateSettings((s) => s.copyWith(scale: value));
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showStyleSelector(
    BuildContext context,
    WidgetRef ref,
    bool isSpotlight,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (context) => StyleSelector(
            isSpotlight: isSpotlight,
            initialStyle: ref.read(
              uiSettingsProvider.select(
                (s) =>
                    isSpotlight ? s.spotlightCardStyle.name : s.cardStyle.name,
              ),
            ),
            onChanged: (newStyle) {
              ref
                  .read(uiSettingsProvider.notifier)
                  .updateSettings(
                    (s) =>
                        isSpotlight
                            ? s.copyWith(
                              spotlightCardStyle: SpotlightCardMode.values
                                  .byName(newStyle),
                            )
                            : s.copyWith(
                              cardStyle: AnimeCardMode.values.byName(newStyle),
                            ),
                  );
            },
          ),
    );
  }
}

class StyleSelector extends StatefulWidget {
  final bool isSpotlight;
  final String initialStyle;
  final ValueChanged<String> onChanged;

  const StyleSelector({
    super.key,
    required this.isSpotlight,
    required this.initialStyle,
    required this.onChanged,
  });

  @override
  State<StyleSelector> createState() => StyleSelectorState();
}

class StyleSelectorState extends State<StyleSelector> {
  late PageController _pageController;
  late int _currentIndex;
  late final List<String> _modes;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _modes =
        widget.isSpotlight
            ? SpotlightCardMode.values.map((e) => e.name).toList()
            : AnimeCardMode.values.map((e) => e.name).toList();

    _currentIndex = _modes.indexOf(widget.initialStyle);
    if (_currentIndex == -1) _currentIndex = 0;

    _pageController = PageController(
      initialPage: _currentIndex,
      viewportFraction: 0.75,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _navigate(int delta) {
    final newIndex = _currentIndex + delta;
    if (newIndex >= 0 && newIndex < _modes.length) {
      _pageController.animateToPage(
        newIndex,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final size = MediaQuery.sizeOf(context);
    final isWideScreen = size.width > 600;

    final double sheetHeight = widget.isSpotlight ? 500 : 600;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            _navigate(-1);
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            _navigate(1);
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Container(
        height: sheetHeight,
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          children: [
            Center(
              child: Container(
                width: 48,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              widget.isSpotlight ? 'Spotlight Style' : 'Card Style',
              style: theme.textTheme.titleMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 4),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(
                _modes[_currentIndex],
                key: ValueKey(_currentIndex),
                style: theme.textTheme.headlineLarge?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const Spacer(),
            SizedBox(
              height: widget.isSpotlight ? 260 : 340,
              child: Row(
                children: [
                  if (isWideScreen)
                    IconButton(
                      onPressed: () => _navigate(-1),
                      icon: const Icon(Iconsax.arrow_left_2),
                      color:
                          _currentIndex > 0
                              ? colorScheme.primary
                              : colorScheme.surfaceContainerHighest,
                    ),
                  Expanded(
                    child: PageView.builder(
                      controller: _pageController,
                      itemCount: _modes.length,
                      onPageChanged: (index) {
                        setState(() => _currentIndex = index);
                        widget.onChanged(_modes[index]);
                      },
                      itemBuilder: (context, index) {
                        return AnimatedBuilder(
                          animation: _pageController,
                          builder: (context, child) {
                            double value = 1.0;
                            if (_pageController.position.haveDimensions) {
                              value = _pageController.page! - index;
                              value = (1 - (value.abs() * 0.3)).clamp(0.0, 1.0);
                            } else {
                              value = index == _currentIndex ? 1.0 : 0.7;
                            }
                            return Center(
                              child: Transform.scale(
                                scale: Curves.easeOut.transform(value),
                                child: Opacity(
                                  opacity: value < 0.8 ? 0.4 : 1.0,
                                  child: child,
                                ),
                              ),
                            );
                          },
                          child: _buildPreviewCard(index),
                        );
                      },
                    ),
                  ),
                  if (isWideScreen)
                    IconButton(
                      onPressed: () => _navigate(1),
                      icon: const Icon(Iconsax.arrow_right_3),
                      color:
                          _currentIndex < _modes.length - 1
                              ? colorScheme.primary
                              : colorScheme.surfaceContainerHighest,
                    ),
                ],
              ),
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_modes.length, (index) {
                final isSelected = _currentIndex == index;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  height: 8,
                  width: isSelected ? 24 : 8,
                  decoration: BoxDecoration(
                    color:
                        isSelected
                            ? colorScheme.primary
                            : colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewCard(int index) {
    final styleName = _modes[index];
    final anime = UniversalMedia(
      id: '1',
      coverImage: UniversalCoverImage(
        large:
            'https://s4.anilist.co/file/anilistcdn/media/anime/cover/large/bx21-YCDoj1EkAxFn.jpg',
        medium:
            'https://s4.anilist.co/file/anilistcdn/media/anime/cover/large/bx21-YCDoj1EkAxFn.jpg',
      ),
      title: UniversalTitle(
        english: "One Piece",
        romaji: "One Piece",
        native: "One Piece",
      ),
      format: 'TV',
      averageScore: 88,
      status: 'Ongoing',
      genres: ['Adventure', 'Action'],
      episodes: 1000,
      season: 'Fall',
    );

    return IgnorePointer(
      child:
          widget.isSpotlight
              ? AnimeSpotlightCard(
                anime: anime,
                heroTag: 'prev_$styleName',
                mode: SpotlightCardMode.values.firstWhere(
                  (e) => e.name == styleName,
                ),
              )
              : AnimeCard(
                anime: anime,
                tag: 'prev_$styleName',
                mode: AnimeCardMode.values.firstWhere(
                  (e) => e.name == styleName,
                ),
              ),
    );
  }
}
