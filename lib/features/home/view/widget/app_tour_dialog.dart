import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:ani_dash/main.dart';

class AppTourStep {
  final IconData icon;
  final String title;
  final String badge;
  final String description;
  final String tip;

  const AppTourStep({
    required this.icon,
    required this.title,
    required this.badge,
    required this.description,
    required this.tip,
  });
}

class AppTourDialog extends StatefulWidget {
  const AppTourDialog({super.key});

  static const String tourCompletedKey = 'has_completed_interactive_tour';

  static Future<void> showIfNeeded(BuildContext context) async {
    final hasCompleted = sharedPrefs.getBool(tourCompletedKey) ?? false;
    if (!hasCompleted && context.mounted) {
      await show(context);
    }
  }

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AppTourDialog(),
    );
  }

  @override
  State<AppTourDialog> createState() => _AppTourDialogState();
}

class _AppTourDialogState extends State<AppTourDialog> {
  final PageController _pageController = PageController();
  int _currentStep = 0;

  static const List<AppTourStep> _steps = [
    AppTourStep(
      icon: Iconsax.crown,
      badge: 'Welcome Guide',
      title: 'Welcome to AniDash!',
      description:
          'Your ultimate anime and manga streaming destination. Ultra-fast, clean, and completely customizable for anime fans.',
      tip: 'Everything you need to watch, read, and track in one place.',
    ),
    AppTourStep(
      icon: Iconsax.discover,
      badge: 'Home & Explore',
      title: 'Spotlight & Trending',
      description:
          'Discover featured spotlight anime, daily trending releases, seasonal shows, and top-rated classics right on your Home screen.',
      tip: 'Swipe across top spotlight banners for quick episode previews.',
    ),
    AppTourStep(
      icon: Iconsax.video_play,
      badge: 'Player Engine',
      title: 'Pro Video Playback',
      description:
          'Stream in crisp full HD with AniSkip auto intro/outro skipping, swipe gesture volume and brightness controls, and server selection.',
      tip: 'Tap the player gear icon to customize quality, speed, and audio.',
    ),
    AppTourStep(
      icon: Iconsax.subtitle,
      badge: 'Multi-Language',
      title: 'Subtitles & Audio in Your Language',
      description:
          'Enjoy full audio and subtitle support in Japanese, English, German, French, Hindi, and 14+ other languages. Auto-Enable Subtitles can be turned on or off anytime.',
      tip: 'Downloaded videos include full offline subtitle sidecars.',
    ),
    AppTourStep(
      icon: Iconsax.document_download,
      badge: 'Downloads & Sharing',
      title: 'Exact Quality Downloads',
      description:
          'Download episodes in exact chosen resolutions (360p to 1080p). Tap the Export / Share button on completed cards to open videos in VLC or send to external apps.',
      tip: 'Automatic cleanup keeps your storage free of temporary files.',
    ),
    AppTourStep(
      icon: Iconsax.magicpen,
      badge: 'AI Companion',
      title: 'Ask Nia AI Anytime',
      description:
          'Need what to watch next? Want to know which episode is filler or get watch orders for complex franchises? Tap Ask Nia anytime for instant answers.',
      tip: 'Find the Nia icon in the navigation bar to start chatting.',
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _completeTour() async {
    await sharedPrefs.setBool(AppTourDialog.tourCompletedKey, true);
    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  void _nextStep() {
    if (_currentStep < _steps.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    } else {
      _completeTour();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final totalSteps = _steps.length;
    final isLastStep = _currentStep == totalSteps - 1;

    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Container(
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 32,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Top progress indicator header
                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Step ${_currentStep + 1} of $totalSteps',
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Row(
                          children: List.generate(totalSteps, (index) {
                            final isCurrent = index == _currentStep;
                            final isPassed = index < _currentStep;
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              height: 6,
                              width: isCurrent ? 20 : 6,
                              decoration: BoxDecoration(
                                color: isCurrent
                                    ? colorScheme.primary
                                    : (isPassed
                                        ? colorScheme.primary.withValues(alpha: 0.5)
                                        : colorScheme.outlineVariant.withValues(alpha: 0.4)),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            );
                          }),
                        ),
                      ],
                    ),
                  ),

                  // Content PageView
                  Flexible(
                    child: SizedBox(
                      height: 320,
                      child: PageView.builder(
                        controller: _pageController,
                        physics: const BouncingScrollPhysics(),
                        itemCount: totalSteps,
                        onPageChanged: (index) => setState(() => _currentStep = index),
                        itemBuilder: (context, index) {
                          final step = _steps[index];
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Container(
                                  width: 64,
                                  height: 64,
                                  decoration: BoxDecoration(
                                    color: colorScheme.primary.withValues(alpha: 0.12),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: colorScheme.primary.withValues(alpha: 0.35),
                                      width: 2,
                                    ),
                                  ),
                                  child: Icon(
                                    step.icon,
                                    size: 32,
                                    color: colorScheme.primary,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: colorScheme.secondaryContainer.withValues(alpha: 0.7),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    step.badge.toUpperCase(),
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.1,
                                      color: colorScheme.onSecondaryContainer,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  step.title,
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  step.description,
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                    height: 1.35,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Iconsax.lamp_on,
                                        size: 16,
                                        color: colorScheme.primary,
                                      ),
                                      const SizedBox(width: 8),
                                      Flexible(
                                        child: Text(
                                          step.tip,
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: colorScheme.onSurface,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),

                  // Bottom Action Bar: Skip & Highlighted Next
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                    decoration: BoxDecoration(
                      color: colorScheme.surface,
                      border: Border(
                        top: BorderSide(
                          color: colorScheme.outlineVariant.withValues(alpha: 0.2),
                        ),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Skip Button (Subtle, non-distracting)
                        TextButton(
                          onPressed: _completeTour,
                          style: TextButton.styleFrom(
                            foregroundColor: colorScheme.onSurfaceVariant,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          ),
                          child: const Text(
                            'Skip Tour',
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
                        ),

                        // Next Button (Highlighted, prominent accent color)
                        FilledButton.icon(
                          onPressed: _nextStep,
                          style: FilledButton.styleFrom(
                            backgroundColor: colorScheme.primary,
                            foregroundColor: colorScheme.onPrimary,
                            elevation: 2,
                            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          iconAlignment: IconAlignment.end,
                          icon: Icon(
                            isLastStep ? Icons.check_circle_rounded : Icons.arrow_forward_rounded,
                            size: 18,
                          ),
                          label: Text(
                            isLastStep ? "Start Exploring" : 'Next',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
