import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:ani_dash/main.dart';
import 'package:ani_dash/router/desktop/mac_desktop_sidebar.dart';
import 'package:ani_dash/router/desktop/mac_desktop_top_bar.dart';
import 'package:ani_dash/router/router_wrapper.dart';

class DesktopSidebarCollapsedNotifier extends Notifier<bool> {
  @override
  bool build() {
    return sharedPrefs.getBool('desktop_sidebar_collapsed') ?? false;
  }

  void toggle() {
    state = !state;
    sharedPrefs.setBool('desktop_sidebar_collapsed', state);
  }

  void setCollapsed(bool value) {
    state = value;
    sharedPrefs.setBool('desktop_sidebar_collapsed', value);
  }
}

final desktopSidebarCollapsedProvider =
    NotifierProvider<DesktopSidebarCollapsedNotifier, bool>(
      DesktopSidebarCollapsedNotifier.new,
    );

class DesktopAdaptiveScaffold extends ConsumerWidget {
  final Widget child;

  const DesktopAdaptiveScaffold({super.key, required this.child});

  static String getTitleForRoute(String path) {
    if (path == '/') return 'Home';
    if (path.startsWith('/browse')) return 'Browse';
    if (path.startsWith('/manga')) return 'Manga';
    if (path.startsWith('/downloads')) return 'Downloads';
    if (path.startsWith('/watchlist')) return 'Your Library';
    if (path.startsWith('/watch-history')) return 'Watch History';
    if (path.startsWith('/notifications')) return 'Notifications';
    if (path.startsWith('/news')) return 'Anime News';
    if (path.startsWith('/extensions')) return 'Extensions';
    if (path.startsWith('/ai') || path.startsWith('/c/')) return 'AniCore AI';
    if (path.startsWith('/details') || path.startsWith('/anime/')) {
      return 'Anime Details';
    }
    if (path == '/settings') return 'Settings';
    if (path == '/settings/ui') return 'Appearance & UI';
    if (path == '/settings/theme') return 'Theme & Colors';
    if (path == '/settings/player') return 'Player Settings';
    if (path == '/settings/player/advanced') return 'Advanced Player';
    if (path == '/settings/player/subtitles') return 'Subtitles';
    if (path == '/settings/anime-sources') return 'Anime Sources';
    if (path == '/settings/downloads') return 'Downloads';
    if (path == '/settings/account') return 'Account & Sync';
    if (path == '/settings/tracking') return 'Tracking';
    if (path == '/settings/security') return 'Security & PIN';
    if (path == '/settings/home-layout') return 'Home Layout';
    if (path == '/settings/content') return 'Content & Filter';
    if (path == '/settings/data') return 'Data & Backup';
    if (path == '/settings/notifications') return 'Notifications';
    if (path == '/settings/update') return 'Check for Updates';
    if (path == '/settings/about') return 'About AniDash';
    if (path == '/settings/debug') return 'Debug Console';
    if (path.startsWith('/settings')) return 'Settings';
    return 'AniDash';
  }

  static IconData getIconForRoute(String path) {
    if (path == '/') return Iconsax.home;
    if (path.startsWith('/browse')) return Iconsax.search_normal_1;
    if (path.startsWith('/manga')) return Iconsax.book;
    if (path.startsWith('/downloads')) return Iconsax.receive_square;
    if (path.startsWith('/watchlist')) return Iconsax.bookmark;
    if (path.startsWith('/watch-history')) return Iconsax.clock;
    if (path.startsWith('/notifications')) return Iconsax.notification;
    if (path.startsWith('/news')) return Iconsax.document_text;
    if (path.startsWith('/extensions')) return Iconsax.box;
    if (path.startsWith('/ai') || path.startsWith('/c/')) {
      return Iconsax.magicpen;
    }
    if (path.startsWith('/details') || path.startsWith('/anime/')) {
      return Iconsax.video;
    }
    if (path == '/settings/ui') return Iconsax.element_3;
    if (path == '/settings/theme') return Iconsax.colorfilter;
    if (path == '/settings/player') return Iconsax.video_play;
    if (path == '/settings/player/advanced') return Iconsax.video_square;
    if (path == '/settings/player/subtitles') return Iconsax.subtitle;
    if (path == '/settings/anime-sources') return Iconsax.global;
    if (path == '/settings/downloads') return Iconsax.document_download;
    if (path == '/settings/account') return Iconsax.user;
    if (path == '/settings/tracking') return Iconsax.chart_2;
    if (path == '/settings/security') return Iconsax.security_safe;
    if (path == '/settings/home-layout') return Iconsax.grid_edit;
    if (path == '/settings/content') return Iconsax.shield_tick;
    if (path == '/settings/data') return Iconsax.folder_favorite;
    if (path == '/settings/notifications') return Iconsax.notification;
    if (path == '/settings/update') return Iconsax.refresh_2;
    if (path == '/settings/about') return Iconsax.info_circle;
    if (path.startsWith('/settings')) return Iconsax.setting_2;
    return Iconsax.play;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (Platform.isAndroid || Platform.isIOS) {
      return child;
    }

    final isCollapsed = ref.watch(desktopSidebarCollapsedProvider);
    final currentRoute = GoRouterState.of(context).matchedLocation;
    final childOwnsTopBar = currentRoute.startsWith('/settings');

    return DesktopGestureAndShortcutsWrapper(
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: Row(
          children: [
            MacDesktopSidebar(
              shell: null,
              items: navItems,
              isCollapsed: isCollapsed,
              onToggleCollapse: () {
                ref.read(desktopSidebarCollapsedProvider.notifier).toggle();
              },
              onTabSelected: (branchIndex) {
                final item = navItems[branchIndex];
                context.go(item.path);
              },
            ),
            Expanded(
              child: Column(
                children: [
                  if (!childOwnsTopBar)
                    MacDesktopTopBar(
                      title: getTitleForRoute(currentRoute),
                      icon: getIconForRoute(currentRoute),
                    ),
                  Expanded(
                    child: KeyedSubtree(
                      key: ValueKey('view_$currentRoute'),
                      child: child,
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

class DesktopGestureAndShortcutsWrapper extends StatefulWidget {
  final Widget child;

  const DesktopGestureAndShortcutsWrapper({super.key, required this.child});

  @override
  State<DesktopGestureAndShortcutsWrapper> createState() =>
      _DesktopGestureAndShortcutsWrapperState();
}

class _DesktopGestureAndShortcutsWrapperState
    extends State<DesktopGestureAndShortcutsWrapper> {
  DateTime? _lastGestureTime;
  double _accumulatedPanX = 0;
  bool _isVerticalScroll = false;

  void _handleBack(BuildContext context) {
    final now = DateTime.now();
    if (_lastGestureTime != null &&
        now.difference(_lastGestureTime!).inMilliseconds < 350) {
      return;
    }
    _lastGestureTime = now;

    // 1. If an editable text field has focus, unfocus it first
    final primaryFocus = FocusManager.instance.primaryFocus;
    if (primaryFocus != null &&
        primaryFocus.hasFocus &&
        primaryFocus.context?.widget is EditableText) {
      primaryFocus.unfocus();
      return;
    }

    // 2. Standard navigator pop (dialogs, bottom sheets, pushed subpages)
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }

    // 3. Smart step-back logic
    final route = GoRouterState.of(context).matchedLocation;
    if (route.startsWith('/settings/player/') && route != '/settings/player') {
      context.go('/settings/player');
    } else if (route.startsWith('/settings/account/') &&
        route != '/settings/account') {
      context.go('/settings/account');
    } else if (route.startsWith('/settings/extensions/') &&
        route != '/settings/extensions') {
      context.go('/settings/extensions');
    } else if (route != '/') {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktopPlatform =
        Platform.isWindows || Platform.isMacOS || Platform.isLinux;
    if (!isDesktopPlatform) return widget.child;

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerPanZoomStart: (_) {
        _accumulatedPanX = 0;
        _isVerticalScroll = false;
      },
      onPointerPanZoomUpdate: (event) {
        // If there's any vertical motion, this is content scrolling, NOT a back swipe
        if (event.pan.dy.abs() > 8) {
          _isVerticalScroll = true;
        }
        if (!_isVerticalScroll && event.pan.dx.abs() > 3 * event.pan.dy.abs()) {
          _accumulatedPanX += event.pan.dx;
        }
      },
      onPointerPanZoomEnd: (_) {
        // Only trigger back if strictly horizontal and deliberate swipe
        if (!_isVerticalScroll && _accumulatedPanX > 150) {
          _handleBack(context);
        }
        _accumulatedPanX = 0;
        _isVerticalScroll = false;
      },
      onPointerDown: (event) {
        // Mouse Back button is 8 (kBackMouseButton)
        if ((event.buttons & 8) != 0) {
          _handleBack(context);
        }
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape):
              () => _handleBack(context),
          const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true):
              () => _handleBack(context),
          const SingleActivator(LogicalKeyboardKey.bracketLeft, meta: true):
              () => _handleBack(context),
          const SingleActivator(LogicalKeyboardKey.browserBack):
              () => _handleBack(context),
        },
        child: Focus(autofocus: true, child: widget.child),
      ),
    );
  }
}
