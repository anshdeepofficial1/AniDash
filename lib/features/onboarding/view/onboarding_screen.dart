import 'dart:io';

import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:ani_dash/main.dart';
import 'package:iconsax/iconsax.dart';
import 'package:ani_dash/shared/providers/anime_source_provider.dart';
import 'package:ani_dash/shared/ui/cards/anime/anime_card_mode.dart';
import 'package:ani_dash/shared/ui/cards/spotlight/spotlight_card_mode.dart';
import 'package:ani_dash/shared/auth/widgets/auth_button.dart';
import 'package:ani_dash/features/settings/view/screens/anime_sources_settings_screen.dart';
import 'package:ani_dash/features/settings/view/screens/home_settings_screen.dart';
import 'package:ani_dash/features/settings/view/screens/ui_settings_screen.dart';
import 'package:ani_dash/features/settings/view/widgets/settings_item.dart';
import 'package:ani_dash/features/settings/view/widgets/settings_section.dart';
import 'package:ani_dash/shared/providers/permissions_provider.dart';
import 'package:ani_dash/shared/providers/settings/theme_notifier.dart';
import 'package:ani_dash/shared/providers/settings/ui_notifier.dart';
import 'package:ani_dash/shared/providers/update_provider.dart';
import 'package:ani_dash/features/ai/view/widgets/assistant_avatar.dart';
import 'package:ani_dash/features/ai/view/widgets/anidash_ai_emblem.dart';
import 'package:window_manager/window_manager.dart';
import 'package:ani_dash/router/desktop/windows_caption_buttons.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingBenefit extends StatelessWidget {
  const _OnboardingBenefit({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  final int _totalPages = Platform.isAndroid ? 11 : 10;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextPage() {
    // Immediately persist that onboarding has started/progressed
    sharedPrefs.setBool('is_onboarded', true);
    if (_currentPage < _totalPages - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOutCubicEmphasized,
      );
    } else {
      _completeOnboarding();
    }
  }

  void _previousPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOutCubicEmphasized,
      );
    }
  }

  Future<void> _skipOnboarding() async {
    await sharedPrefs.setBool('is_onboarded', true);
    final diskPrefs = await SharedPreferences.getInstance();
    await diskPrefs.setBool('is_onboarded', true);
    if (mounted) context.go('/');
  }

  Future<void> _completeOnboarding() async {
    await sharedPrefs.setBool('is_onboarded', true);
    final diskPrefs = await SharedPreferences.getInstance();
    await diskPrefs.setBool('is_onboarded', true);
    if (mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDesktop = !Platform.isAndroid && !Platform.isIOS;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_currentPage > 0) {
            _previousPage();
          }
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: colorScheme.surface,
          body: SafeArea(
            child: Column(
              children: [
                if (isDesktop)
                  Container(
                    height: 38,
                    color: colorScheme.surface,
                    child: Row(
                      children: [
                        const SizedBox(width: 16),
                        Icon(
                          Icons.dashboard_rounded,
                          size: 16,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'AniDash Setup',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: theme.brightness == Brightness.dark
                                ? Colors.white70
                                : Colors.black87,
                          ),
                        ),
                        const Expanded(
                          child: DragToMoveArea(
                            child: SizedBox(height: double.infinity),
                          ),
                        ),
                        const WindowsCaptionButtons(height: 38),
                      ],
                    ),
                  ),
                Padding(
                  padding: EdgeInsets.fromLTRB(24, isDesktop ? 8 : 16, 24, 0),
                  child: Row(
                children: List.generate(_totalPages, (index) {
                  final isActive = index <= _currentPage;
                  return Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeOutExpo,
                      height: 4,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color:
                            isActive
                                ? colorScheme.primary
                                : colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                }),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (index) => setState(() => _currentPage = index),
                children: [
                  _buildIntroStep(context),
                  _buildAuthStep(context),
                  _buildThemeStep(context, ref),
                  _buildSourceStep(context, ref),
                  _buildCardModeStep(context, ref),
                  _buildSpotlightModeStep(context, ref),
                  _buildHomeLayoutStep(context, ref),
                  _buildAiTeamStep(context),
                  if (Platform.isAndroid) _buildPermissionsStep(context, ref),
                  _buildUpdatesStep(context, ref),
                  _buildSupportDeveloperStep(context),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (_currentPage > 0)
                    TextButton.icon(
                      onPressed: _previousPage,
                      icon: const Icon(Iconsax.arrow_left_2),
                      label: const Text('Back'),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 16,
                        ),
                      ),
                    )
                  else
                    TextButton(
                      onPressed: _skipOnboarding,
                      child: const Text('Skip to Home'),
                    ),
                  Row(
                    children: [
                      if (_currentPage > 0 && _currentPage < _totalPages - 1) ...[
                        TextButton(
                          onPressed: _skipOnboarding,
                          child: const Text('Skip to Home'),
                        ),
                        const SizedBox(width: 8),
                      ],
                      FilledButton.icon(
                        onPressed: _nextPage,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 16,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        label: Text(
                          _currentPage == _totalPages - 1 ? 'Get Started' : 'Next',
                        ),
                        icon: Icon(
                          _currentPage == _totalPages - 1
                              ? Iconsax.tick_circle
                              : Iconsax.arrow_right_3,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
    ),
    );
  }

  Widget _buildHeader(BuildContext context, String title, String subtitle) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w800,
              height: 1.1,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            subtitle,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAiTeamStep(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const team = [
      ('coordinator', 'Mira', 'Plans and coordinates'),
      ('anime_text', 'Nia', 'Anime and watch-order expert'),
      ('vision', 'Aira', 'Understands screenshots'),
      ('action', 'Kiro', 'Handles approved actions'),
    ];
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(
            context,
            'Meet your\nAI team',
            'Four specialists work together so you can ask naturally from anywhere in AniDash.',
          ),
          Center(
            child: Container(
              width: 112,
              height: 112,
              margin: const EdgeInsets.only(bottom: 22),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.primaryContainer.withValues(alpha: .34),
                border: Border.all(
                  color: scheme.primary.withValues(alpha: .22),
                ),
                boxShadow: [
                  BoxShadow(
                    color: scheme.primary.withValues(alpha: .18),
                    blurRadius: 28,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Center(child: AniDashAiEmblem(size: 72)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: team.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisExtent: 132,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemBuilder: (context, index) {
                final member = team[index];
                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: .45),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AssistantAvatar(assistantId: member.$1, size: 48),
                      const Spacer(),
                      Text(
                        member.$2,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        member.$3,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(32, 18, 32, 8),
            child: Text(
              'Ask from Home, Search, anime details, Episodes or Downloads. The right specialist joins automatically.',
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthStep(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(
            context,
            'Connect your\naccount',
            'Optional, but useful when you want your progress everywhere.',
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: AccountAuthenticationSection(),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Card(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Why connect?',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const _OnboardingBenefit(
                      icon: Icons.sync_rounded,
                      text: 'Sync progress with AniList or MyAnimeList',
                    ),
                    const _OnboardingBenefit(
                      icon: Icons.devices_rounded,
                      text: 'Keep your library across devices',
                    ),
                    const _OnboardingBenefit(
                      icon: Icons.cloud_off_rounded,
                      text: 'Skip now and use AniDash completely locally',
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildIntroStep(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 112,
            height: 112,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(32),
            ),
            padding: const EdgeInsets.all(16),
            clipBehavior: Clip.antiAlias,
            child: Image.asset(
              'assets/icons/anidash_logo.png',
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(height: 34),
          Text(
            'Welcome to AniDash',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 16),
          Text(
            'Discover anime, choose your preferred language and provider, download episodes, and continue exactly where you stopped.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeStep(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeSettingsProvider);
    final themeNotifier = ref.read(themeSettingsProvider.notifier);
    final colorScheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(
            context,
            'Customize\nAppearance',
            'Make AniDash truly yours.',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                SettingsSection(
                  title: 'Theme',
                  titleColor: colorScheme.primary,
                  children: [
                    SegmentedToggleSettingsItem<dynamic>(
                      accent: colorScheme.primary,
                      iconColor: colorScheme.primary,
                      title: 'Mode',
                      description: 'Select base theme',
                      selectedValue:
                          theme.themeMode == 'light'
                              ? 1
                              : theme.themeMode == 'dark'
                              ? 2
                              : 0,
                      onValueChanged: (index) {
                        final mode =
                            index == 0
                                ? 'system'
                                : index == 1
                                ? 'light'
                                : 'dark';
                        themeNotifier.updateSettings(
                          (p) => p.copyWith(themeMode: mode),
                        );
                      },
                      children: const {
                        0: Icon(Iconsax.monitor),
                        1: Icon(Iconsax.sun_1),
                        2: Icon(Iconsax.moon),
                      },
                      labels: const {0: 'System', 1: 'Light', 2: 'Dark'},
                      icon: const Icon(Iconsax.color_swatch),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SettingsSection(
                  title: 'Palette',
                  titleColor: colorScheme.primary,
                  children: [
                    if (theme.themeMode == 'dark' ||
                        (theme.themeMode == 'system' &&
                            Theme.of(context).brightness == Brightness.dark))
                      ToggleableSettingsItem(
                        icon: Icon(
                          Iconsax.colorfilter,
                          color: colorScheme.primary,
                        ),
                        accent: colorScheme.primary,
                        title: 'True Black',
                        description: 'OLED optimization',
                        value: theme.amoled,
                        onChanged:
                            (v) => themeNotifier.updateSettings(
                              (p) => p.copyWith(amoled: v),
                            ),
                      ),
                    NormalSettingsItem(
                      icon: Icon(
                        Iconsax.colors_square,
                        color: colorScheme.primary,
                      ),
                      accent: colorScheme.primary,
                      title: 'Color Scheme',
                      description: _formatSchemeName(theme.flexScheme ?? ''),
                      onTap:
                          () => _showColorSchemeSheet(
                            context,
                            ref,
                            themeNotifier,
                          ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceStep(BuildContext context, WidgetRef ref) {
    final selectedAnimeSource = ref.watch(selectedAnimeProvider);
    const preferredOrder = ['justanime', 'hianime', 'anikoto'];
    final registry = ref.read(animeSourceRegistryProvider);
    final animeSources = preferredOrder.where(registry.has).toList();
    final providerStatus = ref.watch(providerStatusProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(
          context,
          'Select\nSource',
          'Choose your content provider.',
        ),
        Expanded(
          child: providerStatus.when(
            data:
                (statusData) => ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                      child: Text(
                        'CANONICAL SOURCES',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                    for (final provider in animeSources) ...[
                      Builder(
                        builder: (context) {
                          // A registered built-in source is ready for selection.
                          // Startup website probes are not a reliable playback
                          // health signal and previously marked every source
                          // offline while the device network was warming up.
                          const status = 'online';
                          final isSelected =
                              selectedAnimeSource?.providerName ==
                              provider.toLowerCase();
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: SelectableSettingsItem(
                              icon: Icon(_getStatusIcon(status)),
                              iconColor: _getStatusColor(status),
                              accent: _getStatusColor(status),
                              title:
                                  provider == 'justanime'
                                      ? 'JUSTANIME  •  RECOMMENDED'
                                      : provider.toUpperCase(),
                              description:
                                  provider == 'justanime'
                                      ? '${status.toUpperCase()} • Preselected'
                                      : status.toUpperCase(),
                              isInSelectionMode: true,
                              isSelected: isSelected,
                              onTap: () {
                                ref
                                    .read(selectedProviderKeyProvider.notifier)
                                    .select(provider);
                              },
                            ),
                          );
                        },
                      ),
                    ],
                  ],
                ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, s) => Center(child: Text('Error: $e')),
          ),
        ),
      ],
    );
  }

  Widget _buildCardModeStep(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(context, 'Card\nStyle', 'Choose the look of anime cards.'),
        Expanded(
          child: StyleSelector(
            isSpotlight: false,
            initialStyle: ref.read(
              uiSettingsProvider.select((s) => s.cardStyle.name),
            ),
            onChanged: (val) {
              ref
                  .read(uiSettingsProvider.notifier)
                  .updateSettings(
                    (s) =>
                        s.copyWith(cardStyle: AnimeCardMode.values.byName(val)),
                  );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSpotlightModeStep(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(
          context,
          'Spotlight\nStyle',
          'Choose the featured banner style.',
        ),
        Expanded(
          child: StyleSelector(
            isSpotlight: true,
            initialStyle: ref.read(
              uiSettingsProvider.select((s) => s.spotlightCardStyle.name),
            ),
            onChanged: (val) {
              ref
                  .read(uiSettingsProvider.notifier)
                  .updateSettings(
                    (s) => s.copyWith(
                      spotlightCardStyle: SpotlightCardMode.values.byName(val),
                    ),
                  );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHomeLayoutStep(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(
          context,
          'Home\nLayout',
          'Use AniDash with your own preferred home layout.',
        ),
        Expanded(child: HomeSettingsScreen(noAppBar: true)),
      ],
    );
  }

  Widget _buildUpdatesStep(BuildContext context, WidgetRef ref) {
    final isAuto = ref.watch(automaticUpdatesProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(
          context,
          'Final\nTouches',
          'Keep AniDash fresh and up to date.',
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ToggleableSettingsItem(
            icon: Icon(Iconsax.refresh, color: colorScheme.primary),
            accent: colorScheme.primary,
            title: 'Automatic Updates',
            description: 'Check for new features on startup',
            value: isAuto,
            onChanged:
                (val) => ref.read(automaticUpdatesProvider.notifier).toggle(),
          ),
        ),
      ],
    );
  }

  Widget _buildSupportDeveloperStep(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    const upiId = 'anshdeep200618-3@oksbi';

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(
            context,
            'Support\nAniDash ☕✨',
            '100% free, open source, and ad-free.',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'AniDash is built and maintained by a passionate solo developer. If you love the experience and want to support active development and server costs, every contribution helps keep the app fast and ad-free! ❤️🚀',
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.8),
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 20),

                // Buy Me A Coffee Button
                Material(
                  color: const Color(0xFFFFDD00).withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () async {
                      final uri = Uri.parse('https://buymeacoffee.com/anshdeepofficial');
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Row(
                        children: [
                          const Icon(Iconsax.coffee, color: Color(0xFFFFDD00), size: 24),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Buy Me a Coffee',
                                  style: textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  'buymeacoffee.com/anshdeepofficial',
                                  style: textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.open_in_new_rounded, size: 20, color: colorScheme.onSurfaceVariant),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // GitHub Sponsors Button
                Material(
                  color: const Color(0xFFEA4AAA).withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () async {
                      final uri = Uri.parse('https://github.com/sponsors/anshdeepofficial1');
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Row(
                        children: [
                          const Icon(Iconsax.heart, color: Color(0xFFEA4AAA), size: 24),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'GitHub Sponsor',
                                  style: textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  'github.com/sponsors/anshdeepofficial1',
                                  style: textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.open_in_new_rounded, size: 20, color: colorScheme.onSurfaceVariant),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Direct UPI Payment Button
                Material(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () async {
                      final upiUri = Uri.parse(
                        'upi://pay?pa=$upiId&pn=Anshdeep%20Singh&cu=INR&tn=AniDash%20Support',
                      );
                      bool launched = false;
                      try {
                        launched = await launchUrl(
                          upiUri,
                          mode: LaunchMode.externalApplication,
                        );
                      } catch (_) {}
                      if (!launched && context.mounted) {
                        await Clipboard.setData(const ClipboardData(text: upiId));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'UPI ID ($upiId) copied to clipboard! Open your UPI app to sponsor.',
                            ),
                          ),
                        );
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Row(
                        children: [
                          Icon(Iconsax.card, color: colorScheme.primary, size: 24),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Sponsor via UPI (GPay, PhonePe, Paytm)',
                                  style: textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  upiId,
                                  style: textTheme.bodySmall?.copyWith(
                                    color: colorScheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.touch_app_rounded, size: 20, color: colorScheme.primary),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionsStep(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final permissionsState = ref.watch(permissionsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(
          context,
          'Grant\nPermissions',
          'Allow access to storage to download anime.',
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ToggleableSettingsItem(
            icon: Icon(Iconsax.folder_open, color: colorScheme.primary),
            accent: colorScheme.primary,
            title: 'Storage Access',
            description:
                'Allow access to storage to download anime and support extensions.',
            value: permissionsState.storage,
            onChanged: (val) async {
              if (val == false) {
                await ref
                    .read(permissionsProvider.notifier)
                    .revokeStorageAccess();
                return;
              }
              final approved = await showDialog<bool>(
                context: context,
                builder:
                    (dialogContext) => AlertDialog(
                      title: const Text('Allow storage access?'),
                      content: const Text(
                        'AniDash will use its private app storage for downloads and extension data. Other apps cannot access these files.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext, false),
                          child: const Text('Not now'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(dialogContext, true),
                          child: const Text('Allow'),
                        ),
                      ],
                    ),
              );
              if (approved != true) return;
              await ref
                  .read(permissionsProvider.notifier)
                  .requestStoragePermission();
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ToggleableSettingsItem(
            icon: Icon(Iconsax.notification, color: colorScheme.primary),
            accent: colorScheme.primary,
            title: 'Notification Access',
            description:
                'Allow access to notifications to get notified about new anime news.',
            value: permissionsState.notification,
            onChanged: (val) async {
              if (val == false) return;
              await ref
                  .read(permissionsProvider.notifier)
                  .requestNotificationPermission();
            },
          ),
        ),
      ],
    );
  }

  void _showColorSchemeSheet(
    BuildContext context,
    WidgetRef ref,
    ThemeSettingsNotifier themeNotifier,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        final theme = ref.watch(themeSettingsProvider);
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 16),
                    width: 32,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: FlexScheme.values.length,
                      itemBuilder: (context, index) {
                        final scheme = FlexScheme.values[index];
                        final isSelected = theme.flexScheme == scheme.name;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            onTap:
                                () => themeNotifier.updateSettings(
                                  (p) => p.copyWith(flexScheme: scheme.name),
                                ),
                            leading: _buildMinimalPreview(scheme),
                            title: Text(_formatSchemeName(scheme.name)),
                            trailing:
                                isSelected
                                    ? Icon(
                                      Iconsax.tick_circle,
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                    )
                                    : null,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            tileColor:
                                isSelected
                                    ? Theme.of(
                                      context,
                                    ).colorScheme.secondaryContainer
                                    : null,
                          ),
                        );
                      },
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      border: Border(
                        top: BorderSide(
                          color: Theme.of(
                            context,
                          ).colorScheme.outlineVariant.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                    ),
                    child: SafeArea(
                      top: false,
                      child: SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton.icon(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.check_rounded),
                          label: const Text(
                            'Done',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMinimalPreview(FlexScheme scheme) {
    final colors = FlexThemeData.light(scheme: scheme).colorScheme;
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Row(
          children: [
            Expanded(flex: 2, child: Container(color: colors.primary)),
            Expanded(
              child: Column(
                children: [
                  Expanded(child: Container(color: colors.secondary)),
                  Expanded(child: Container(color: colors.tertiary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatSchemeName(String name) => name
      .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}')
      .split(' ')
      .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : w)
      .join(' ');

  Color _getStatusColor(String? status) =>
      status?.toLowerCase() == 'online'
          ? Colors.green
          : status?.toLowerCase() == 'offline'
          ? Colors.red
          : Colors.orange;

  IconData _getStatusIcon(String? status) =>
      status?.toLowerCase() == 'online'
          ? Iconsax.health
          : status?.toLowerCase() == 'offline'
          ? Iconsax.danger
          : Iconsax.warning_2;
}
