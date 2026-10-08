import 'dart:io';
import 'package:flutter/gestures.dart';
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
    if (path.startsWith('/details') || path.startsWith('/anime/')) return 'Anime Details';
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
    if (path.startsWith('/ai') || path.startsWith('/c/')) return Iconsax.magicpen;
    if (path.startsWith('/details') || path.startsWith('/anime/')) return Iconsax.video;
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
                  MacDesktopTopBar(
                    title: getTitleForRoute(currentRoute),
                    icon: getIconForRoute(currentRoute),
                  ),
                  Expanded(
                    child: child,
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
  double _accumulatedPanX = 0;
  DateTime? _lastGestureTime;

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
    if (route.startsWith('/settings/') &&
        route != '/settings/ui' &&
        route != '/settings') {
      context.go('/settings/ui');
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
      onPointerPanZoomUpdate: (event) {
        _accumulatedPanX += event.pan.dx;
      },
      onPointerPanZoomEnd: (event) {
        if (_accumulatedPanX > 45) {
          // Trackpad 2-finger swipe left-to-right -> BACK
          _handleBack(context);
        }
        _accumulatedPanX = 0;
      },
      onPointerSignal: (pointerSignal) {
        if (pointerSignal is PointerScrollEvent) {
          // Horizontal scroll gesture on trackpad
          if (pointerSignal.scrollDelta.dx < -110) {
            _handleBack(context);
          }
        }
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
        child: Focus(
          autofocus: true,
          child: widget.child,
        ),
      ),
    );
  }
}
