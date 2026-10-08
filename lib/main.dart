import 'dart:ui';
import 'package:awesome_snackbar_content/awesome_snackbar_content.dart';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:isar_community/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ani_dash/app_initializer.dart';
import 'package:ani_dash/core/utils/app_logger.dart';
import 'package:ani_dash/shared/providers/settings/theme_notifier.dart';
import 'package:ani_dash/shared/providers/settings/ui_notifier.dart';
import 'package:ani_dash/router/router_config.dart';
import 'package:ani_dash/shared/ui/security_gate.dart';

late Isar isar;
late SharedPreferencesWithCache sharedPrefs;
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    AppLogger.e('FlutterError: ${details.exceptionAsString()}', details.exception, details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    AppLogger.e('Uncaught Platform Error: $error', error, stack);
    return true;
  };

  try {
    AppLogger.i('Starting app initialization');
    await AppInitializer.initialize();
  } catch (e, st) {
    AppLogger.e('Error initializing app: $e', e, st);
    runApp(
      MaterialApp(
        home: Scaffold(body: Center(child: Text('Initialization failed: $e'))),
      ),
    );
    return;
  }

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemStatusBarContrastEnforced: false,
    ),
  );

  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeSettingsProvider);
    final scale = ref.watch(uiSettingsProvider.select((s) => s.scale));
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        final ColorScheme? lightScheme =
            (theme.useDynamicColors && lightDynamic != null)
                ? lightDynamic
                : null;
        final ColorScheme? darkScheme =
            (theme.useDynamicColors && darkDynamic != null)
                ? darkDynamic
                : null;

        final customLightScheme =
            theme.flexScheme == FlexScheme.custom.name
                ? ColorScheme.fromSeed(
                  seedColor: Color(theme.customPrimaryColor),
                  brightness: Brightness.light,
                ).copyWith(
                  primary: Color(theme.customPrimaryColor),
                  secondary: Color(theme.customSecondaryColor),
                  tertiary: Color(theme.customTertiaryColor),
                  surface: Color(theme.customSurfaceColor),
                )
                : null;
        final customDarkScheme =
            theme.flexScheme == FlexScheme.custom.name
                ? ColorScheme.fromSeed(
                  seedColor: Color(theme.customPrimaryColor),
                  brightness: Brightness.dark,
                ).copyWith(
                  primary: Color(theme.customPrimaryColor),
                  secondary: Color(theme.customSecondaryColor),
                  tertiary: Color(theme.customTertiaryColor),
                  surface: Color(theme.customSurfaceColor),
                )
                : null;

        final lightTheme = FlexThemeData.light(
          colorScheme: lightScheme ?? customLightScheme,
          swapColors: theme.swapColors,
          blendLevel: theme.blendLevel,
          scheme:
              lightScheme != null || customLightScheme != null
                  ? null
                  : theme.flexSchemeEnum,
          useMaterial3: theme.useMaterial3,
          textTheme: GoogleFonts.montserratTextTheme(),
        );

        final darkTheme = FlexThemeData.dark(
          colorScheme: darkScheme ?? customDarkScheme,
          swapColors: theme.swapColors,
          blendLevel: theme.amoled ? 0 : theme.blendLevel,
          scheme:
              darkScheme != null || customDarkScheme != null
                  ? null
                  : theme.flexSchemeEnum,
          darkIsTrueBlack: theme.amoled,
          useMaterial3: theme.useMaterial3,
          textTheme: GoogleFonts.montserratTextTheme(),
        ).copyWith(
          scaffoldBackgroundColor: theme.amoled ? Colors.black : null,
          canvasColor: theme.amoled ? Colors.black : null,
        );

        final themeMode =
            theme.themeMode == 'light'
                ? ThemeMode.light
                : theme.themeMode == 'dark'
                ? ThemeMode.dark
                : ThemeMode.system;

        return MaterialApp.router(
          debugShowCheckedModeBanner: false,
          scaffoldMessengerKey: scaffoldMessengerKey,
          routerConfig: routerConfig,
          supportedLocales: const [Locale('en')],
          builder: (context, child) {
            final mediaQuery = MediaQuery.of(context);
            final scaledSize = mediaQuery.size / scale;
            return GlobalDesktopNavigationScope(
              child: MediaQuery(
                data: mediaQuery.copyWith(
                  textScaler: TextScaler.linear(scale),
                  size: scaledSize,
                ),
                child: Semantics(
                  container: true,
                  label: 'AniDash application',
                  child: SecurityGate(child: child!),
                ),
              ),
            );
          },
          theme: lightTheme,
          darkTheme: darkTheme,
          themeMode: themeMode,
        );
      },
    );
  }
}

void showAppSnackBar(String title, String message, {ContentType? type}) {
  type ??= ContentType.success;
  final messenger = scaffoldMessengerKey.currentState;
  if (messenger != null) {
    messenger
      ..removeCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.fixed,
          elevation: 0,
          backgroundColor: Colors.transparent,
          content: AwesomeSnackbarContent(
            title: title,
            message: message,
            contentType: type,
          ),
        ),
      );
  }
}

class GlobalDesktopNavigationScope extends StatefulWidget {
  final Widget child;

  const GlobalDesktopNavigationScope({super.key, required this.child});

  @override
  State<GlobalDesktopNavigationScope> createState() =>
      _GlobalDesktopNavigationScopeState();
}

class _GlobalDesktopNavigationScopeState
    extends State<GlobalDesktopNavigationScope> {
  void _triggerStepBack() {
    final nav = rootNavigatorKey.currentState;
    if (nav != null && nav.canPop()) {
      nav.pop();
      return;
    }
    final ctx = rootNavigatorKey.currentContext;
    if (ctx != null) {
      try {
        final currentLoc = GoRouterState.of(ctx).matchedLocation;
        if (currentLoc != '/') {
          ctx.go('/');
        }
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _triggerStepBack,
        const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true):
            _triggerStepBack,
        const SingleActivator(LogicalKeyboardKey.bracketLeft, meta: true):
            _triggerStepBack,
      },
      child: Listener(
        onPointerDown: (event) {
          // Mouse side back button (kBackMouseButton is 8)
          if (event.buttons & kBackMouseButton != 0) {
            _triggerStepBack();
          }
        },
        child: widget.child,
      ),
    );
  }
}

