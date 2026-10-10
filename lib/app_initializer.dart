import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ani_dash/data/hive/models/anime_watch_progress_model.dart';

import 'package:ani_dash/core/utils/app_logger.dart';

import 'package:ani_dash/features/home/model/home_page.dart';
import 'package:ani_dash/features/downloads/model/download_item.dart';
import 'package:ani_dash/core/models/settings/experimental_model.dart';
import 'package:ani_dash/core/models/settings/player_model.dart';
import 'package:ani_dash/core/models/settings/subtitle_appearance_model.dart';
import 'package:ani_dash/core/models/settings/theme_model.dart';
import 'package:ani_dash/core/models/settings/download_settings_model.dart';
import 'package:ani_dash/core/models/settings/content_settings_model.dart';
import 'package:ani_dash/core/models/universal/universal_news.dart';
import 'package:ani_dash/core/services/notification_service.dart';
import 'package:ani_dash/core/services/remote_push_service.dart';
import 'package:ani_dash/core/models/settings/ui_model.dart';
import 'package:ani_dash/helpers/ui.dart';
import 'package:ani_dash/hive/hive_registrar.g.dart';

import 'package:window_manager/window_manager.dart';
import 'package:workmanager/workmanager.dart';

import 'package:ani_dash/background_handler.dart';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:ani_dash/core/services/update_scheduler.dart';
import 'package:ani_dash/core/models/settings/update_settings_model.dart';
import 'package:dartotsu_extension_bridge/dartotsu_extension_bridge.dart'
    hide isar;
import 'package:ani_dash/storage_provider.dart';
import 'package:ani_dash/core/repositories/watch_progress_repository.dart';
import 'main.dart';

class AppInitializer {
  static Future<void> initialize() async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      AppLogger.w("⚠️ Running in test mode, exiting main.");
      return;
    }

    AppLogger.section('App Initialization');

    await AppLogger.init();

    await _initializeBackgroundService();

    WidgetsFlutterBinding.ensureInitialized();
    AppLogger.success('Flutter bindings initialized');

    // Tune Flutter image cache to conserve RAM under heavy system usage
    PaintingBinding.instance.imageCache.maximumSizeBytes =
        64 * 1024 * 1024; // 64 MB
    PaintingBinding.instance.imageCache.maximumSize = 300;

    await _initializeHive();
    await _initializeSharedPrefs();
    await _initializeIsar();
    await _initializeWindowManager();
    await _initializeMediaKit();
    try {
      await RemotePushService.initialize();
      await NotificationService().initialize();
      // Keep the existing periodic worker: replacing it on every launch and
      // immediately checking again causes delayed alerts to burst together.
      await NotificationService().registerPeriodicNotificationWorker(
        forceReplace: false,
      );
      AppLogger.success('Notification service initialized');
    } catch (e, st) {
      AppLogger.fail('Notification service initialization failed');
      AppLogger.e('Notification Service Error', e, st);
    }
    try {
      final jsonString = sharedPrefs.getString('update_settings_data');
      final settings =
          jsonString != null
              ? UpdateSettingsModel.fromJson(jsonString)
              : const UpdateSettingsModel(fullDay: true);
      await UpdateScheduler.apply(settings);
      AppLogger.success('Update scheduler registered at startup');
    } catch (e) {
      AppLogger.w('Update scheduler startup registration failed: $e');
    }
    AppLogger.section('Initialization Complete');
  }

  static Future<void> _initializeSharedPrefs() async {
    AppLogger.section('Shared Preferences');
    try {
      sharedPrefs = await SharedPreferencesWithCache.create(
        cacheOptions: const SharedPreferencesWithCacheOptions(),
      );
      try {
        final info = await PackageInfo.fromPlatform();
        final fullVersion =
            info.buildNumber.isNotEmpty
                ? '${info.version}+${info.buildNumber}'
                : info.version;
        final diskPrefs = await SharedPreferences.getInstance();
        await diskPrefs.setString('app_version', fullVersion);
        if (diskPrefs.getBool('is_onboarded') == true) {
          await sharedPrefs.setBool('is_onboarded', true);
        } else if (sharedPrefs.getBool('is_onboarded') == true) {
          await diskPrefs.setBool('is_onboarded', true);
        }
      } catch (_) {}
      AppLogger.success('Shared Preferences initialized');
    } catch (e, st) {
      AppLogger.fail('Shared Preferences initialization failed');
      AppLogger.e('Shared Preferences Error', e, st);
    }
  }

  static Future<void> _initializeBackgroundService() async {
    if (!(Platform.isAndroid || Platform.isIOS)) return;
    AppLogger.section('Background services');
    try {
      Workmanager().initialize(callbackDispatcher);
      AppLogger.success('Background services initialized');
    } catch (e, st) {
      AppLogger.fail('Background services initialization failed');
      AppLogger.e('Workmanager Error', e, st);
    }
  }

  static Future<void> _initializeMediaKit() async {
    AppLogger.section('MediaKit');

    try {
      MediaKit.ensureInitialized();
      AppLogger.success('MediaKit initialized');
    } catch (e, st) {
      AppLogger.fail('MediaKit initialization failed');
      AppLogger.e('MediaKit Initialization Error', e, st);
    }
  }

  static Future<void> _initializeHive() async {
    AppLogger.section('Hive Database');

    try {
      final appSupportDir = await getApplicationSupportDirectory();
      final customPath = p.join(appSupportDir.path, 'AniDash', 'appdata');

      AppLogger.infoPair('Hive Path', customPath);

      Hive
        ..init(customPath)
        ..registerAdapters();

      AppLogger.success('Hive initialized');

      AppLogger.section('Hive Boxes');

      final boxesToOpen = <String, Future<void> Function()>{
        'theme_settings': () => Hive.openBox<ThemeModel>('theme_settings'),
        'themedata': () => Hive.openBox('themedata'),
        'subtitle_appearance':
            () => Hive.openBox<SubtitleAppearanceModel>('subtitle_appearance'),
        'home_page': () => Hive.openBox<HomePageModel>('home_page'),
        'ui_settings': () => Hive.openBox<UiSettings>('ui_settings'),
        'selected_provider': () => Hive.openBox<String>('selected_provider'),
        'player_settings': () => Hive.openBox<PlayerModel>('player_settings'),
        'anime_watch_progress':
            () => Hive.openBox<AnimeWatchProgressEntry>('anime_watch_progress'),
        'experimental_features':
            () => Hive.openBox<ExperimentalFeaturesModel>(
              'experimental_features',
            ),
        'downloads': () => Hive.openBox<DownloadItem>('downloads'),
        'settings': () => Hive.openBox('settings'),
        'onboard': () => Hive.openBox('onboard'),
        'download_settings':
            () => Hive.openBox<DownloadSettingsModel>('download_settings'),
        'content_settings':
            () => Hive.openBox<ContentSettingsModel>('content_settings'),
        'news_cache': () => Hive.openBox<UniversalNews>('news_cache'),
        'news_read_status': () => Hive.openBox<String>('news_read_status'),
        'home_layout': () => Hive.openBox('home_layout'),
        'http_cache_v1': () => Hive.openBox('http_cache_v1'),
      };

      for (final entry in boxesToOpen.entries) {
        try {
          AppLogger.i('Opening box: ${entry.key}');
          await entry.value();
        } catch (e) {
          AppLogger.fail('Failed to open box [${entry.key}]: $e');
          AppLogger.fail(
            'Preserving Hive box [${entry.key}] after open failure; no data was deleted.',
          );
        }
      }

      AppLogger.success('Hive boxes opened');
    } catch (e, st) {
      AppLogger.fail('Hive initialization failed');
      AppLogger.e('Hive Initialization Error', e, st);
    }
  }

  static Future<void> _initializeWindowManager() async {
    AppLogger.section('Window / System UI');

    if (!kIsWeb && !Platform.isAndroid && !Platform.isIOS) {
      AppLogger.infoPair('Platform', Platform.operatingSystem);

      try {
        await windowManager.ensureInitialized();

        await windowManager.waitUntilReadyToShow(
          const WindowOptions(
            size: Size(1280, 800),
            minimumSize: Size(960, 600),
            center: true,
            backgroundColor: Colors.transparent,
            skipTaskbar: false,
            title: 'AniDash',
            titleBarStyle: TitleBarStyle.hidden,
          ),
          () async {
            await windowManager.show();
            await windowManager.focus();
            if (!Platform.isLinux) {
              await windowManager.setHasShadow(true);
            }
          },
        );
        await windowManager.show();
        await windowManager.focus();

        AppLogger.success('Window manager initialized');
      } catch (e, st) {
        AppLogger.fail('Window manager initialization failed');
        AppLogger.e('Window Manager Error', e, st);
      }
    } else {
      try {
        await UIHelper.exitImmersiveMode();
        await UIHelper.forcePortrait();
        SystemChrome.setSystemUIOverlayStyle(
          const SystemUiOverlayStyle(statusBarColor: Colors.transparent),
        );
        AppLogger.success('Mobile system UI configured');
      } catch (e, st) {
        AppLogger.fail('Mobile system UI configuration failed');
        AppLogger.e('Mobile System UI Error', e, st);
      }
    }
  }

  static Future<void> _initializeIsar() async {
    AppLogger.section('Isar Database');
    try {
      isar = await StorageProvider.initDB(null, inspector: kDebugMode);
      AppLogger.success('Isar database initialized');
      try {
        await WatchProgressRepository().migrateFromHive();
      } catch (e, st) {
        AppLogger.e('Error migrating watch progress from Hive', e, st);
      }
      try {
        final bridge = DartotsuExtensionBridge();
        await bridge.init(isar, 'AniDash');
        AppLogger.success('Extension bridge initialized with Isar');
      } catch (e, st) {
        AppLogger.e('Error initializing extension bridge', e, st);
      }
    } catch (e, st) {
      AppLogger.fail('Isar database initialization failed: $e');
      AppLogger.e('Isar Error', e, st);
    }
  }
}
