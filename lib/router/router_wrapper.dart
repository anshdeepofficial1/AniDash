import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:ani_dash/features/browse/view/browse_screen.dart';
import 'package:ani_dash/features/downloads/view/downloads_screen.dart';
import 'package:ani_dash/features/home/view/home_screen.dart' as h_screen;
import 'package:ani_dash/features/loading/view_model/initialization_notifier.dart';
import 'package:ani_dash/features/watchlist/view/watchlist_screen.dart';
import 'package:ani_dash/features/manga/view/manga_screen.dart';
import 'package:ani_dash/core/services/offline_sync_queue_service.dart';
import 'package:ani_dash/core/services/notification_service.dart';
import 'package:ani_dash/core/services/remote_push_service.dart';
import 'package:ani_dash/core/services/update_scheduler.dart';
import 'package:ani_dash/core/services/update_service.dart';
import 'package:ani_dash/core/utils/updater.dart';
import 'package:ani_dash/core/utils/app_logger.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:ani_dash/shared/providers/settings/ui_notifier.dart';
import 'package:ani_dash/shared/providers/settings/update_settings_notifier.dart';
import 'package:ani_dash/shared/providers/permissions_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ani_dash/router/desktop/mac_desktop_sidebar.dart';
import 'package:ani_dash/router/desktop/mac_desktop_top_bar.dart';

class NavItem {
  final int branchIndex;
  final String path;
  final IconData icon;
  final Widget screen;
  final String label;

  const NavItem({
    required this.branchIndex,
    required this.path,
    required this.icon,
    required this.screen,
    required this.label,
  });
}

final List<NavItem> navItems = [
  const NavItem(
    branchIndex: 0,
    path: '/',
    icon: Iconsax.home,
    screen: h_screen.HomeScreen(),
    label: 'Home',
  ),
  const NavItem(
    branchIndex: 1,
    path: '/browse',
    icon: Iconsax.search_normal_1,
    screen: BrowseScreen(),
    label: 'Browse',
  ),
  const NavItem(
    branchIndex: 2,
    path: '/manga',
    icon: Iconsax.book,
    screen: MangaScreen(),
    label: 'Manga',
  ),
  const NavItem(
    branchIndex: 3,
    path: '/downloads',
    icon: Iconsax.receive_square,
    screen: DownloadsScreen(),
    label: 'Downloads',
  ),
  const NavItem(
    branchIndex: 4,
    path: '/watchlist',
    icon: Iconsax.bookmark,
    screen: WatchlistScreen(),
    label: 'Watchlist',
  ),
];

class AppRouterScreen extends ConsumerStatefulWidget {
  final StatefulNavigationShell navigationShell;
  final List<Widget> children;

  const AppRouterScreen({
    super.key,
    required this.navigationShell,
    required this.children,
  });

  @override
  ConsumerState<AppRouterScreen> createState() => _AppRouterScreenState();
}

class _AppRouterScreenState extends ConsumerState<AppRouterScreen>
    with WidgetsBindingObserver {
  late final PageController _pageController;
  bool _updateCheckInProgress = false;
  bool _updateSheetVisible = false;
  DateTime? _lastForegroundUpdateCheck;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _foregroundUpdateTimer;
  StreamSubscription<String>? _updateTapSubscription;
  StreamSubscription<String>? _notificationRouteSubscription;
  ProviderSubscription? _updateSettingsSub;
  bool _deferredUpdateCheck = false;
  bool _wasWatchingVideo = false;
  GoRouter? _goRouter;

  bool get _isWatchingVideo {
    if (!mounted) return false;
    final router = _goRouter ?? GoRouter.of(context);
    return router.routerDelegate.currentConfiguration.uri.path.startsWith(
      '/watch/',
    );
  }

  void _handleRouteChange() {
    if (!mounted) return;
    final isWatching = _isWatchingVideo;
    final justLeftPlayer = _wasWatchingVideo && !isWatching;
    _wasWatchingVideo = isWatching;
    if (justLeftPlayer && _deferredUpdateCheck) {
      _deferredUpdateCheck = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _checkForScheduledUpdate(isAppOpen: true, force: true);
        }
      });
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // This shell stays mounted while changing tabs, unlike HomeScreen. Keep a
    // single truthful app-visibility flag for background notification tasks.
    SharedPreferences.getInstance().then(
      (prefs) => prefs.setBool('is_app_open', true),
    );
    Future.microtask(
      () => ref.read(initializationProvider.notifier).initialize(),
    );
    _pageController = PageController(
      initialPage: widget.navigationShell.currentIndex,
    );
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      results,
    ) {
      if (results.any((r) => r != ConnectivityResult.none)) {
        OfflineSyncQueueService.flushQueue(ref);
        RemotePushService.refreshActivity();
      }
    });
    _updateTapSubscription = NotificationService().onUpdateTapped.listen((
      version,
    ) {
      if (mounted) {
        _checkForScheduledUpdate(isAppOpen: true, force: true);
      }
    });
    _notificationRouteSubscription = NotificationService().onNotificationRoute
        .listen((route) {
          if (mounted) {
            context.push(route);
          }
        });
    _updateSettingsSub = ref.listenManual(updateSettingsProvider, (prev, next) {
      _startPeriodicForegroundUpdateCheck();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _wasWatchingVideo = _isWatchingVideo;
      _goRouter = GoRouter.of(context);
      _goRouter!.routerDelegate.addListener(_handleRouteChange);
      _openDownloadsOffline();
      try {
        await ref.read(permissionsProvider.notifier).checkAll();
      } catch (_) {}
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) _checkForScheduledUpdate(isAppOpen: true);
      });
      _startPeriodicForegroundUpdateCheck();
      OfflineSyncQueueService.flushQueue(ref);
      RemotePushService.refreshActivity();
    });
  }

  @override
  void dispose() {
    _goRouter?.routerDelegate.removeListener(_handleRouteChange);
    SharedPreferences.getInstance().then(
      (prefs) => prefs.setBool('is_app_open', false),
    );
    _foregroundUpdateTimer?.cancel();
    _updateSettingsSub?.close();
    _updateTapSubscription?.cancel();
    _notificationRouteSubscription?.cancel();
    _connectivitySubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    SharedPreferences.getInstance().then(
      (prefs) =>
          prefs.setBool('is_app_open', state == AppLifecycleState.resumed),
    );
    if (state == AppLifecycleState.resumed) {
      ref.read(permissionsProvider.notifier).checkAll();
      _checkForScheduledUpdate(isAppOpen: true);
      _startPeriodicForegroundUpdateCheck();
      OfflineSyncQueueService.flushQueue(ref);
    } else if (state == AppLifecycleState.paused) {
      _foregroundUpdateTimer?.cancel();
    }
  }

  void _startPeriodicForegroundUpdateCheck() {
    _foregroundUpdateTimer?.cancel();
    final settings = ref.read(updateSettingsProvider);
    if (!settings.autoCheckEnabled) return;
    final minutes = settings.checkIntervalMinutes.clamp(1, 60);
    _foregroundUpdateTimer = Timer.periodic(Duration(minutes: minutes), (_) {
      _checkForScheduledUpdate(isAppOpen: true);
    });
  }

  Future<void> _checkForScheduledUpdate({
    bool isAppOpen = false,
    bool force = false,
  }) async {
    if (_updateCheckInProgress || !mounted) return;
    if (_isWatchingVideo) {
      _deferredUpdateCheck = true;
      return;
    }
    final settings = ref.read(updateSettingsProvider);
    if (!settings.autoCheckEnabled && !force) return;

    // Strict window check: if not in 24-hour mode, only check within user's custom window
    if (!force && !UpdateScheduler.isInsideWindow(settings)) {
      return;
    }

    final now = DateTime.now();
    if (!force &&
        !isAppOpen &&
        _lastForegroundUpdateCheck != null &&
        now.difference(_lastForegroundUpdateCheck!).inMinutes < 1) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();

    _updateCheckInProgress = true;
    _lastForegroundUpdateCheck = now;
    try {
      final updateInfo = await UpdateService().checkForUpdate();
      if (updateInfo != null && mounted) {
        // Never interrupt playback with an update prompt. Preserve the check
        // and present it immediately after the user leaves the player.
        if (_isWatchingVideo) {
          _deferredUpdateCheck = true;
          return;
        }
        final latest = updateInfo.version.replaceFirst('v', '').trim();

        // Check if user snoozed ("Remind in 1 hour" or "Skip for today")
        final remindAfter = prefs.getInt('remind_update_after') ?? 0;
        final remindVersion = prefs.getString('remind_update_version');
        final isSnoozed =
            !force &&
            remindVersion == latest &&
            now.millisecondsSinceEpoch < remindAfter;

        if (isSnoozed) {
          return;
        }

        // A foreground timer, app-resume callback and the background worker can
        // all discover the same release. Present it at most once per 24 hours unless explicit reminder is due.
        final lastPresentedVersion = prefs.getString('last_presented_update');
        final lastPresentedAt = prefs.getInt('last_presented_update_time') ?? 0;
        final isExplicitReminderDue =
            remindVersion == latest &&
            remindAfter > 0 &&
            now.millisecondsSinceEpoch >= remindAfter;
        final wasRecentlyPresented =
            !isExplicitReminderDue &&
            lastPresentedVersion == latest &&
            now.millisecondsSinceEpoch - lastPresentedAt <
                const Duration(hours: 24).inMilliseconds;
        if (!force && (wasRecentlyPresented || _updateSheetVisible)) return;

        if (remindAfter != 0 && now.millisecondsSinceEpoch >= remindAfter) {
          await prefs.remove('remind_update_after');
          await prefs.remove('remind_update_version');
        }

        // Post to the notification bar with the action buttons in safe try-catch
        try {
          await NotificationService().showUpdateAvailableNotification(latest);
        } catch (notifErr) {
          AppLogger.w(
            'Notification post encountered non-fatal error: $notifErr',
          );
        }

        // Also trigger the in-app update dialog so the user sees it immediately on screen
        final packageInfo = await PackageInfo.fromPlatform();
        if (!mounted) return;
        _updateSheetVisible = true;
        await prefs.setString('last_presented_update', latest);
        await prefs.setInt(
          'last_presented_update_time',
          now.millisecondsSinceEpoch,
        );
        if (!mounted) return;
        try {
          await showUpdateBottomSheet(
            context,
            updateInfo.version,
            packageInfo.version,
            UpdateType.stable,
            releaseNotes: updateInfo.releaseNotes,
            apkDownloadUrl: updateInfo.downloadUrl,
            apkSha256: updateInfo.sha256,
          );
        } finally {
          _updateSheetVisible = false;
        }
      }
    } catch (e) {
      AppLogger.w('Update check encountered error: $e');
    } finally {
      _updateCheckInProgress = false;
    }
  }

  List<NavItem> _getVisibleNavItems(dynamic uiSettings) {
    return navItems.where((item) {
      switch (item.branchIndex) {
        case 0:
          return true; // Home is always enabled
        case 1:
          return uiSettings.showBrowseNav as bool;
        case 2:
          return uiSettings.showMangaNav as bool;
        case 3:
          return uiSettings.showDownloadsNav as bool;
        case 4:
          return uiSettings.showWatchlistNav as bool;
        default:
          return true;
      }
    }).toList();
  }

  int _pageIndexForBranch(int branchIndex, List<NavItem> visibleItems) {
    final idx = visibleItems.indexWhere((it) => it.branchIndex == branchIndex);
    return idx != -1 ? idx : 0;
  }

  void _onNavTap(int branchIndex, List<NavItem> visibleItems) {
    final targetPage = _pageIndexForBranch(branchIndex, visibleItems);
    if (_pageController.hasClients) {
      _pageController.jumpToPage(targetPage);
    }
    widget.navigationShell.goBranch(branchIndex);
  }

  Future<void> _openDownloadsOffline() async {
    final connections = await Connectivity().checkConnectivity();
    if (!mounted || widget.navigationShell.currentIndex != 0) return;
    if (connections.every(
      (connection) => connection == ConnectivityResult.none,
    )) {
      final uiSettings = ref.read(uiSettingsProvider);
      if (!uiSettings.showDownloadsNav) return;
      final visibleItems = _getVisibleNavItems(uiSettings);
      final targetPage = _pageIndexForBranch(3, visibleItems);
      widget.navigationShell.goBranch(3);
      if (_pageController.hasClients) {
        _pageController.jumpToPage(targetPage);
      }
    }
  }

  @override
  void didUpdateWidget(covariant AppRouterScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final uiSettings = ref.read(uiSettingsProvider);
    final visibleItems = _getVisibleNavItems(uiSettings);
    final targetPage = _pageIndexForBranch(
      widget.navigationShell.currentIndex,
      visibleItems,
    );
    if (_pageController.hasClients &&
        _pageController.page?.round() != targetPage) {
      _pageController.jumpToPage(targetPage);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(updateSettingsProvider, (previous, next) {
      if (previous?.checkIntervalMinutes != next.checkIntervalMinutes ||
          previous?.autoCheckEnabled != next.autoCheckEnabled ||
          previous?.fullDay != next.fullDay ||
          previous?.startHour != next.startHour ||
          previous?.endHour != next.endHour) {
        _startPeriodicForegroundUpdateCheck();
      }
    });

    final isWide = MediaQuery.sizeOf(context).width > 800;
    final uiSettings = ref.watch(uiSettingsProvider);
    final visibleNavItems = _getVisibleNavItems(uiSettings);

    // If active branch was disabled by user in settings, safely redirect to Home (branch 0)
    final isCurrentVisible = visibleNavItems.any(
      (item) => item.branchIndex == widget.navigationShell.currentIndex,
    );
    if (!isCurrentVisible && widget.navigationShell.currentIndex != 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.navigationShell.goBranch(0);
          if (_pageController.hasClients) {
            _pageController.jumpToPage(0);
          }
        }
      });
    }

    final currentTargetPage = _pageIndexForBranch(
      widget.navigationShell.currentIndex,
      visibleNavItems,
    );
    if (_pageController.hasClients &&
        _pageController.page?.round() != currentTargetPage) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            _pageController.hasClients &&
            _pageController.page?.round() != currentTargetPage) {
          _pageController.jumpToPage(currentTargetPage);
        }
      });
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (widget.navigationShell.currentIndex != 0) {
          widget.navigationShell.goBranch(0);
          if (_pageController.hasClients) {
            _pageController.jumpToPage(0);
          }
        } else {
          showExitConfirmationDialog(context, isSystemExit: true);
        }
      },
      child: Scaffold(
        extendBody: true,
        extendBodyBehindAppBar: true,
        body: Stack(
          fit: StackFit.expand,
          children: [
            PageView(
              controller: _pageController,
              onPageChanged: (pageIndex) {
                if (pageIndex >= 0 && pageIndex < visibleNavItems.length) {
                  final targetBranch = visibleNavItems[pageIndex].branchIndex;
                  if (targetBranch != widget.navigationShell.currentIndex) {
                    widget.navigationShell.goBranch(targetBranch);
                  }
                }
              },
              physics: const BouncingScrollPhysics(),
              children:
                  visibleNavItems.map((item) {
                    final child = widget.children[item.branchIndex];
                    return Padding(
                      padding: EdgeInsets.fromLTRB(
                        isWide ? 90 : 0,
                        isWide ? 15 : 0,
                        0,
                        isWide ? 15 : 0,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(15),
                        child: _KeepAliveWrapper(child: child),
                      ),
                    );
                  }).toList(),
            ),
            Positioned(
              left: isWide ? 10 : 0,
              right: isWide ? null : 0,
              top: isWide ? 10 : null,
              bottom: 10,
              child: SafeArea(
                child:
                    isWide
                        ? _SideNav(
                          shell: widget.navigationShell,
                          items: visibleNavItems,
                          onTabSelected:
                              (branch) => _onNavTap(branch, visibleNavItems),
                        )
                        : _BottomNav(
                          shell: widget.navigationShell,
                          items: visibleNavItems,
                          onTabSelected:
                              (branch) => _onNavTap(branch, visibleNavItems),
                        ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SideNav extends StatelessWidget {
  final StatefulNavigationShell shell;
  final List<NavItem> items;
  final void Function(int branchIndex)? onTabSelected;

  const _SideNav({
    required this.shell,
    required this.items,
    this.onTabSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      width: 75,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(35),
        border: Border.all(color: colorScheme.primary),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: List.generate(items.length, (index) {
          final item = items[index];
          final isSelected = shell.currentIndex == item.branchIndex;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.all(5),
              child: InkWell(
                onTap: () {
                  if (onTabSelected != null) {
                    onTabSelected!(item.branchIndex);
                  } else {
                    shell.goBranch(item.branchIndex);
                  }
                },
                borderRadius: BorderRadius.circular(30),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(30),
                    color:
                        isSelected
                            ? colorScheme.primary.withValues(alpha: 0.2)
                            : null,
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    item.icon,
                    color:
                        isSelected
                            ? colorScheme.primary
                            : colorScheme.onSurface,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  final StatefulNavigationShell shell;
  final List<NavItem> items;
  final void Function(int branchIndex)? onTabSelected;

  const _BottomNav({
    required this.shell,
    required this.items,
    this.onTabSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final width = MediaQuery.sizeOf(context).width;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: width * 0.08),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(100),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: colorScheme.surface.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(100),
              border: Border.all(
                color: colorScheme.primary.withValues(alpha: 0.8),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(items.length, (index) {
                final item = items[index];
                final isSelected = shell.currentIndex == item.branchIndex;
                return Expanded(
                  child: InkWell(
                    onTap: () {
                      if (onTabSelected != null) {
                        onTabSelected!(item.branchIndex);
                      } else {
                        shell.goBranch(item.branchIndex);
                      }
                    },
                    borderRadius: BorderRadius.circular(100),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color:
                            isSelected
                                ? colorScheme.primary.withValues(alpha: 0.2)
                                : null,
                        borderRadius: BorderRadius.circular(100),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        item.icon,
                        color:
                            isSelected
                                ? colorScheme.primary
                                : colorScheme.onSurface,
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

void showExitConfirmationDialog(
  BuildContext context, {
  bool isSystemExit = false,
}) {
  showDialog(
    context: context,
    builder:
        (context) => AlertDialog(
          title: const Text('Confirm Exit'),
          content: const Text('Are you sure you want to exit the app?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                if (isSystemExit) {
                  SystemNavigator.pop();
                } else {
                  context.pop();
                }
              },
              child: const Text('Exit'),
            ),
          ],
        ),
  );
}

class _KeepAliveWrapper extends StatefulWidget {
  final Widget child;

  const _KeepAliveWrapper({required this.child});

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
