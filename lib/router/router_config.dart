import 'dart:io';
import 'package:dartotsu_extension_bridge/Models/Source.dart';
import 'package:flutter/cupertino.dart';
import 'package:go_router/go_router.dart';
import 'package:ani_dash/features/extensions/view/extension_preference_screen.dart';
import 'package:ani_dash/main.dart';

// Core & Models
import 'package:ani_dash/core/models/anime/episode_model.dart';
import 'package:ani_dash/core/models/universal/universal_media.dart';

// Features
import 'package:ani_dash/features/watch/view/watch_screen.dart';
import 'package:ani_dash/features/browse/view/browse_screen.dart';
import 'package:ani_dash/features/browse/model/search_filter.dart';
import 'package:ani_dash/features/details/view/details_screen.dart';
import 'package:ani_dash/features/error/view/error_screen.dart';
import 'package:ani_dash/features/home/view/watch_history_screen.dart';
import 'package:ani_dash/features/news/view/news_screen.dart';
import 'package:ani_dash/features/notifications/view/notification_inbox_screen.dart';
import 'package:ani_dash/features/onboarding/view/onboarding_screen.dart';
import 'package:ani_dash/features/extensions/view/extensions_screen.dart';

// Settings Features
import 'package:ani_dash/features/settings/view/screens/about_screen.dart';
import 'package:ani_dash/features/settings/view/screens/account_settings_screen.dart';
import 'package:ani_dash/features/settings/view/screens/anime_sources_settings_screen.dart';
import 'package:ani_dash/features/settings/view/screens/download_settings_screen.dart';
import 'package:ani_dash/features/settings/view/screens/data_settings_screen.dart';
import 'package:ani_dash/features/settings/view/screens/home_settings_screen.dart';
import 'package:ani_dash/features/settings/view/screens/experimental_screen.dart';
import 'package:ani_dash/features/settings/view/screens/player_settings_screen.dart';
import 'package:ani_dash/features/settings/view/screens/advanced_player_settings_screen.dart';
import 'package:ani_dash/features/settings/view/screens/profile_settings_screen.dart';
import 'package:ani_dash/features/settings/view/screens/settings_screen.dart';
import 'package:ani_dash/features/settings/view/screens/subtitle_customization_screen.dart';
import 'package:ani_dash/features/settings/view/screens/theme_settings_screen.dart';
import 'package:ani_dash/features/settings/view/screens/ui_settings_screen.dart';
import 'package:ani_dash/features/settings/view/screens/tracking_settings_screen.dart';
import 'package:ani_dash/features/settings/view/screens/content_settings_screen.dart';
import 'package:ani_dash/features/debug/view/debug_screen.dart';
import 'package:ani_dash/features/settings/view/screens/permissions_settings_screen.dart';
import 'package:ani_dash/features/settings/view/screens/update_screen.dart';
import 'package:ani_dash/features/settings/view/screens/notification_settings_screen.dart';
import 'package:ani_dash/features/settings/view/screens/security_settings_screen.dart';
import 'package:ani_dash/features/settings/view/screens/admin_broadcast_screen.dart';
import 'package:ani_dash/router/router_wrapper.dart';
import 'package:ani_dash/features/ai/domain/ai_models.dart';
import 'package:ani_dash/features/ai/view/ai_chat_screen.dart';
import 'package:ani_dash/features/ai/view/ai_settings_screen.dart';
import 'package:ani_dash/router/desktop/desktop_adaptive_scaffold.dart';

class AnimatedGoRoute extends GoRoute {
  final bool wrapWithDesktopScaffold;

  AnimatedGoRoute({
    required super.path,
    required Widget Function(BuildContext, GoRouterState) contentBuilder,
    super.routes = const <RouteBase>[],
    super.redirect,
    this.wrapWithDesktopScaffold = false,
  }) : super(
         pageBuilder: (context, state) {
           final child = wrapWithDesktopScaffold
               ? DesktopAdaptiveScaffold(
                   key: ValueKey(state.uri.toString()),
                   child: contentBuilder(context, state),
                 )
               : contentBuilder(context, state);

           final isDesktop =
               Platform.isWindows || Platform.isMacOS || Platform.isLinux;
           if (isDesktop || wrapWithDesktopScaffold) {
             return NoTransitionPage(
               key: ValueKey('desktop_page_${state.matchedLocation}'),
               child: child,
             );
           }

           return CustomTransitionPage(
             key: state.pageKey,
             child: child,
             transitionsBuilder: (
               context,
               animation,
               secondaryAnimation,
               child,
             ) {
               return SlideTransition(
                 position: animation.drive(
                   Tween<Offset>(
                     begin: const Offset(0, 1),
                     end: Offset.zero,
                   ).chain(CurveTween(curve: Curves.easeOutCubic)),
                 ),
                 child: child,
               );
             },
           );
         },
       );
}

class DesktopAdaptiveRoute extends AnimatedGoRoute {
  DesktopAdaptiveRoute({
    required super.path,
    required super.contentBuilder,
    super.routes = const <RouteBase>[],
    super.redirect,
  }) : super(wrapWithDesktopScaffold: true);
}

bool _isUserOnboarded() {
  if (sharedPrefs.getBool('is_onboarded') == true) return true;

  // Detect existing installations, updates, or prior sessions:
  final hasTokens = sharedPrefs.containsKey('anilist-token') ||
      sharedPrefs.containsKey('mal-token') ||
      sharedPrefs.containsKey('anilist-user-cache') ||
      sharedPrefs.containsKey('mal-user-cache');
  final hasConfigured = sharedPrefs.containsKey('selected_provider') ||
      sharedPrefs.containsKey('app_version') ||
      sharedPrefs.containsKey('last_presented_update') ||
      sharedPrefs.containsKey('notification_inbox_v1');

  if (hasTokens || hasConfigured) {
    // Mark onboarded permanently so existing users and updates land straight on home
    sharedPrefs.setBool('is_onboarded', true);
    return true;
  }

  return false;
}

final rootNavigatorKey = GlobalKey<NavigatorState>();

final routerConfig = GoRouter(
  navigatorKey: rootNavigatorKey,
  errorBuilder: (context, state) => ErrorScreen(error: state.error),
  initialLocation: '/',
  redirect: (context, state) {
    final isOnboarded = _isUserOnboarded();
    final isGoingToOnboarding = state.matchedLocation == '/onboarding';
    if (!isOnboarded && !isGoingToOnboarding) return '/onboarding';
    if (isOnboarded && isGoingToOnboarding) return '/';

    // On desktop, landing on exact '/settings' route opens Appearance & UI
    if (state.uri.path == '/settings' &&
        (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      return '/settings/ui';
    }

    // Handle incoming deep links (e.g. anidash://anime/123 or https://anilist.co/anime/123/...)
    final path = state.uri.path;
    if (path.startsWith('/anime/')) {
      final segments = path.split('/').where((s) => s.isNotEmpty).toList();
      if (segments.length >= 2) {
        final id = segments[1];
        return '/details/$id';
      }
    }
    return null;
  },
  routes: [
    StatefulShellRoute(
      navigatorContainerBuilder: (context, navigationShell, children) {
        return AppRouterScreen(
          navigationShell: navigationShell,
          children: children,
        );
      },
      builder: (context, state, navigationShell) {
        return navigationShell;
      },
      branches:
          navItems.map((item) {
            return StatefulShellBranch(
              routes: [
                AnimatedGoRoute(
                  path: item.path,
                  contentBuilder:
                      (context, state) =>
                          item.path == '/browse'
                              ? BrowseScreen(
                                key: ValueKey(state.uri.toString()),
                                keyword: state.uri.queryParameters['keyword'],
                                initialFilter: state.extra as SearchFilter?,
                              )
                              : item.screen,
                ),
              ],
            );
          }).toList(),
    ),
    DesktopAdaptiveRoute(
      path: '/extensions',
      contentBuilder: (_, _) => const ExtensionScreen(),
    ),
    DesktopAdaptiveRoute(
      path: '/news',
      contentBuilder: (_, _) => const NewsScreen(),
    ),
    DesktopAdaptiveRoute(
      path: '/notifications',
      contentBuilder: (_, _) => const NotificationInboxScreen(),
    ),
    DesktopAdaptiveRoute(
      path: '/ai',
      contentBuilder:
          (_, state) => AiChatScreen(
            contextData:
                state.extra is AiContext
                    ? state.extra as AiContext
                    : const AiContext(),
          ),
    ),
    DesktopAdaptiveRoute(
      path: '/c/:id',
      contentBuilder:
          (_, state) => AiChatScreen(sharedChatId: state.pathParameters['id']),
    ),
    AnimatedGoRoute(
      path: '/onboarding',
      contentBuilder: (_, _) => const OnboardingScreen(),
    ),
    DesktopAdaptiveRoute(
      path: '/details',
      contentBuilder:
          (context, state) => AnimeDetailsScreen(
            anime: state.extra as UniversalMedia,
            tag: state.uri.queryParameters['tag'] ?? '',
            forceFetch: state.uri.queryParameters['forceFetch'] == 'true',
          ),
    ),
    DesktopAdaptiveRoute(
      path: '/details/:id',
      contentBuilder: (context, state) {
        final anime =
            state.extra is UniversalMedia
                ? state.extra as UniversalMedia
                : UniversalMedia(
                  id: state.pathParameters['id']!,
                  title: const UniversalTitle(
                    english: 'Anime',
                    romaji: 'Anime',
                  ),
                  coverImage: const UniversalCoverImage(),
                );
        final tabParam = state.uri.queryParameters['tab'];
        final initialTabIndex =
            tabParam == 'episodes' ? 1 : (int.tryParse(tabParam ?? '') ?? 0);
        return AnimeDetailsScreen(
          anime: anime,
          tag: state.uri.queryParameters['tag'] ?? '',
          forceFetch: true,
          initialTabIndex: initialTabIndex,
        );
      },
    ),
    DesktopAdaptiveRoute(
      path: '/anime/:id',
      contentBuilder: (context, state) {
        final anime =
            state.extra is UniversalMedia
                ? state.extra as UniversalMedia
                : UniversalMedia(
                  id: state.pathParameters['id']!,
                  title: const UniversalTitle(
                    english: 'Anime',
                    romaji: 'Anime',
                  ),
                  coverImage: const UniversalCoverImage(),
                );
        final tabParam = state.uri.queryParameters['tab'];
        final initialTabIndex =
            tabParam == 'episodes' ? 1 : (int.tryParse(tabParam ?? '') ?? 0);
        return AnimeDetailsScreen(
          anime: anime,
          tag: state.uri.queryParameters['tag'] ?? '',
          forceFetch: true,
          initialTabIndex: initialTabIndex,
        );
      },
    ),
    AnimatedGoRoute(
      path: '/episode/:id/:episode',
      contentBuilder:
          (context, state) => WatchScreen(
            mediaId: state.pathParameters['id']!,
            animeId: state.pathParameters['id']!,
            animeName: state.uri.queryParameters['title'] ?? 'Anime',
            animeCover: state.uri.queryParameters['cover'] ?? '',
            episode: int.tryParse(state.pathParameters['episode'] ?? '1') ?? 1,
            forceRefetch: true,
            episodes: const <EpisodeDataModel>[],
          ),
    ),
    AnimatedGoRoute(
      path: '/watch/:id',
      contentBuilder:
          (context, state) => WatchScreen(
            mediaId: state.pathParameters['id']!,
            animeId: state.uri.queryParameters['animeId'],
            animeName: state.uri.queryParameters['animeName']!,
            animeFormat: state.uri.queryParameters['animeFormat'],
            animeCover: state.uri.queryParameters['animeCover']!,
            episode:
                int.tryParse(state.uri.queryParameters['episode'] ?? '1') ?? 1,
            malId: int.tryParse(state.uri.queryParameters['malId'] ?? ''),
            startAtPosition: int.tryParse(
              state.uri.queryParameters['startAtPosition'] ?? '',
            ),
            forceRefetch: state.uri.queryParameters['forceRefetch'] == 'true',
            episodes:
                (state.extra is List<EpisodeDataModel>)
                    ? state.extra as List<EpisodeDataModel>
                    : ((state.extra is List)
                        ? (state.extra as List)
                            .whereType<EpisodeDataModel>()
                            .toList()
                        : const <EpisodeDataModel>[]),
          ),
    ),
    DesktopAdaptiveRoute(
      path: '/watch-history',
      contentBuilder: (_, _) => const WatchHistoryScreen(),
    ),
    DesktopAdaptiveRoute(
      path: '/settings',
      contentBuilder: (_, _) => const SettingsScreen(),
      routes: [
        DesktopAdaptiveRoute(
          path: 'debug',
          contentBuilder: (_, _) => const DebugScreen(),
        ),
        DesktopAdaptiveRoute(
          path: 'account',
          contentBuilder: (_, _) => const AccountSettingsScreen(),
          routes: [
            DesktopAdaptiveRoute(
              path: 'profile',
              contentBuilder: (_, _) => const ProfileSettingsScreen(),
            ),
          ],
        ),
        DesktopAdaptiveRoute(
          path: 'anime-sources',
          contentBuilder: (_, _) => const AnimeSourcesSettingsScreen(),
        ),
        DesktopAdaptiveRoute(
          path: 'downloads',
          contentBuilder: (_, _) => const DownloadSettingsScreen(),
        ),
        DesktopAdaptiveRoute(
          path: 'data',
          contentBuilder: (_, _) => const DataSettingsScreen(),
        ),
        DesktopAdaptiveRoute(
          path: 'home-layout',
          contentBuilder: (_, _) => const HomeSettingsScreen(),
        ),
        DesktopAdaptiveRoute(
          path: 'theme',
          contentBuilder: (_, _) => const ThemeSettingsScreen(),
        ),
        DesktopAdaptiveRoute(
          path: 'ui',
          contentBuilder: (_, _) => const UiSettingsScreen(),
        ),
        DesktopAdaptiveRoute(
          path: 'content',
          contentBuilder: (_, _) => const ContentSettingsScreen(),
        ),
        DesktopAdaptiveRoute(
          path: 'about',
          contentBuilder: (_, _) => const AboutScreen(),
        ),
        DesktopAdaptiveRoute(
          path: 'update',
          contentBuilder: (_, _) => const UpdateScreen(),
        ),
        DesktopAdaptiveRoute(
          path: 'notifications',
          contentBuilder: (_, _) => const NotificationSettingsScreen(),
        ),
        DesktopAdaptiveRoute(
          path: 'watch-history',
          contentBuilder: (_, _) => const WatchHistoryScreen(),
        ),
        DesktopAdaptiveRoute(
          path: 'tracking',
          contentBuilder: (_, _) => const TrackingSettingsScreen(),
        ),
        DesktopAdaptiveRoute(
          path: 'player',
          contentBuilder: (_, _) => const PlayerSettingsScreen(),
          routes: [
            DesktopAdaptiveRoute(
              path: 'subtitles',
              contentBuilder: (_, _) => const SubtitleCustomizationScreen(),
            ),
            DesktopAdaptiveRoute(
              path: 'advanced',
              contentBuilder: (_, _) => const AdvancedPlayerSettingsScreen(),
            ),
          ],
        ),
        DesktopAdaptiveRoute(
          path: 'extensions',
          contentBuilder: (_, _) => const ExtensionScreen(),
          routes: [
            DesktopAdaptiveRoute(
              path: 'extension-preference',
              contentBuilder:
                  (_, state) =>
                      ExtensionPreferenceScreen(source: state.extra as Source),
            ),
          ],
        ),
        DesktopAdaptiveRoute(
          path: 'experimental',
          contentBuilder: (_, _) => ExperimentalScreen(),
        ),
        DesktopAdaptiveRoute(
          path: 'permissions',
          contentBuilder: (_, _) => const PermissionsSettingsScreen(),
        ),
        DesktopAdaptiveRoute(
          path: 'security',
          contentBuilder: (_, _) => const SecuritySettingsScreen(),
        ),
        DesktopAdaptiveRoute(
          path: 'admin-broadcast',
          contentBuilder: (_, _) => const AdminBroadcastScreen(),
        ),
        DesktopAdaptiveRoute(
          path: 'ai',
          contentBuilder: (_, _) => const AiSettingsScreen(),
        ),
      ],
    ),
  ],
);
