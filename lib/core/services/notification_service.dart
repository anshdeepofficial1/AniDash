import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:ani_dash/core/utils/app_logger.dart';
import 'package:ani_dash/core/services/notification_inbox_service.dart';

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) async {
  final prefs = await SharedPreferences.getInstance();
  final version = response.payload?.replaceFirst('update:', '').trim() ?? '';
  if (response.actionId == 'update_remind_1h') {
    await prefs.setInt(
      'remind_update_after',
      DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch,
    );
    if (version.isNotEmpty) {
      await prefs.setString('remind_update_version', version);
    }
  } else if (response.actionId == 'update_skip_day') {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    await prefs.setInt('remind_update_after', tomorrow.millisecondsSinceEpoch);
    if (version.isNotEmpty) {
      await prefs.setString('remind_update_version', version);
    }
  }
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();

  factory NotificationService() => _instance;

  NotificationService._internal();

  static const notificationCheckTask = 'anidash_notification_check';
  static const notificationBootstrapTask =
      'anidash_notification_check_bootstrap';
  static const notificationWorkerTag = 'anidash_notifications';

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  final StreamController<String> playbackActionController =
      StreamController<String>.broadcast();
  Stream<String> get onPlaybackAction => playbackActionController.stream;

  final StreamController<String> updateTapController =
      StreamController<String>.broadcast();
  Stream<String> get onUpdateTapped => updateTapController.stream;

  final StreamController<String> notificationRouteController =
      StreamController<String>.broadcast();
  Stream<String> get onNotificationRoute => notificationRouteController.stream;

  void openRoute(String route) {
    if (route.trim().isNotEmpty) notificationRouteController.add(route.trim());
  }

  Future<bool> requestSystemPermission() async {
    if (Platform.isAndroid) {
      final android =
          flutterLocalNotificationsPlugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >();
      return await android?.requestNotificationsPermission() ?? true;
    }
    if (Platform.isIOS || Platform.isMacOS) {
      final darwin =
          flutterLocalNotificationsPlugin
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >();
      return await darwin?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }
    return true;
  }

  Future<void> registerPeriodicNotificationWorker({
    bool forceReplace = true,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await Workmanager().registerPeriodicTask(
        notificationCheckTask,
        notificationCheckTask,
        frequency: const Duration(minutes: 15),
        flexInterval: const Duration(minutes: 5),
        tag: notificationWorkerTag,
        existingWorkPolicy:
            forceReplace ? ExistingWorkPolicy.replace : ExistingWorkPolicy.keep,
        constraints: Constraints(networkType: NetworkType.connected),
        backoffPolicy: BackoffPolicy.exponential,
        backoffPolicyDelay: const Duration(seconds: 30),
      );

      final prefs = await SharedPreferences.getInstance();
      final lastBootstrap =
          prefs.getInt('notification_worker_bootstrap_at') ?? 0;
      final bootstrapDue =
          forceReplace ||
          DateTime.now().millisecondsSinceEpoch - lastBootstrap >=
              const Duration(hours: 12).inMilliseconds;
      // A one-off verification is useful after explicit settings changes, but
      // must not fire every app launch and replay missed notifications.
      if (bootstrapDue) {
        await Workmanager().registerOneOffTask(
          notificationBootstrapTask,
          notificationBootstrapTask,
          tag: notificationWorkerTag,
          existingWorkPolicy: ExistingWorkPolicy.replace,
          initialDelay: const Duration(seconds: 10),
          constraints: Constraints(networkType: NetworkType.connected),
          backoffPolicy: BackoffPolicy.exponential,
          backoffPolicyDelay: const Duration(seconds: 30),
        );
        await prefs.setInt(
          'notification_worker_bootstrap_at',
          DateTime.now().millisecondsSinceEpoch,
        );
      }
      await prefs.setInt(
        'notification_worker_registered_at',
        DateTime.now().millisecondsSinceEpoch,
      );
      AppLogger.i(
        '[NotificationWorker] Registered periodic + bootstrap workers '
        '(frequency: 15m, policy: ${forceReplace ? "replace" : "keep"})',
      );
    } catch (e) {
      AppLogger.w('Could not register periodic notification worker: $e');
    }
  }

  static const String _iconName = 'ic_notification';
  static const Color _brandColor = Color(0xFF4CAF50);

  static bool _timeZoneInitialized = false;

  static void _setupTimeZone() {
    if (_timeZoneInitialized) return;
    try {
      tz.initializeTimeZones();
      final timeZoneName = DateTime.now().timeZoneName;
      if (tz.timeZoneDatabase.locations.containsKey(timeZoneName)) {
        tz.setLocalLocation(tz.getLocation(timeZoneName));
        _timeZoneInitialized = true;
        return;
      }
      final offset = DateTime.now().timeZoneOffset;
      for (final loc in tz.timeZoneDatabase.locations.values) {
        if (loc.currentTimeZone.offset == offset.inMilliseconds) {
          tz.setLocalLocation(loc);
          _timeZoneInitialized = true;
          return;
        }
      }
      tz.setLocalLocation(tz.getLocation('UTC'));
      _timeZoneInitialized = true;
    } catch (e) {
      AppLogger.w('Timezone initialization error: $e');
    }
  }

  Future<bool> _isCategoryEnabled(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final raw = prefs.getString('notification_settings_data');
      if (raw == null || raw.isEmpty) return true;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      return data[key] as bool? ?? true;
    } catch (_) {
      // A malformed persisted preference must never re-enable a category the
      // user may have explicitly disabled.
      return false;
    }
  }

  Future<bool> _prefersEnglishDub() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final raw = prefs.getString('player_settings_data');
      if (raw == null || raw.isEmpty) return true;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final language = data['preferredAudioLanguage'] as String?;
      return language == 'dub' ||
          (language == null && (data['preferDub'] as bool? ?? false));
    } catch (_) {
      return true;
    }
  }

  Future<void> reconcileScheduledReleaseAlerts() async {
    final allowSub =
        await _isCategoryEnabled('enableSubReleases') &&
        !await _prefersEnglishDub();
    if (allowSub) return;
    try {
      final pending =
          await flutterLocalNotificationsPlugin.pendingNotificationRequests();
      for (final request in pending) {
        if (request.payload?.startsWith('details:') == true) {
          await flutterLocalNotificationsPlugin.cancel(request.id);
        }
      }
    } catch (e) {
      AppLogger.w('Could not reconcile scheduled release alerts: $e');
    }
  }

  Future<void> initialize({bool isBackground = false}) async {
    _setupTimeZone();
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings(_iconName);

    const DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        );

    const LinuxInitializationSettings initializationSettingsLinux =
        LinuxInitializationSettings(defaultActionName: 'Open notification');

    const WindowsInitializationSettings initializationSettingsWindows =
        WindowsInitializationSettings(
          appName: 'AniDash',
          appUserModelId: 'RoshanKumar.AniDash.App.v2',
          guid: '0516d984-72bf-47d4-bfbc-b2b8fd563479',
        );

    const InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsDarwin,
          macOS: initializationSettingsDarwin,
          linux: initializationSettingsLinux,
          windows: initializationSettingsWindows,
        );

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) async {
        final prefs = await SharedPreferences.getInstance();
        final version =
            response.payload?.replaceFirst('update:', '').trim() ?? '';
        if (response.actionId == 'update_remind_1h') {
          await prefs.setInt(
            'remind_update_after',
            DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch,
          );
          if (version.isNotEmpty) {
            await prefs.setString('remind_update_version', version);
          }
        } else if (response.actionId == 'update_skip_day') {
          final now = DateTime.now();
          final tomorrow = DateTime(now.year, now.month, now.day + 1);
          await prefs.setInt(
            'remind_update_after',
            tomorrow.millisecondsSinceEpoch,
          );
          if (version.isNotEmpty) {
            await prefs.setString('remind_update_version', version);
          }
        } else if (response.actionId == 'update_now' ||
            (response.payload?.startsWith('update:') == true &&
                response.actionId == null)) {
          _instance.updateTapController.add(version);
        } else if (response.actionId != null) {
          _instance.playbackActionController.add(response.actionId!);
        } else if (response.payload != null && response.payload!.isNotEmpty) {
          final payload = response.payload!;
          if (payload.startsWith('details:') ||
              payload.startsWith('/details/')) {
            final mediaId =
                payload
                    .replaceFirst('details:', '')
                    .replaceFirst('/details/', '')
                    .trim();
            final targetRoute =
                mediaId.contains('?')
                    ? (mediaId.startsWith('/') ? mediaId : '/details/$mediaId')
                    : '/details/$mediaId?tab=episodes';
            unawaited(
              NotificationInboxService().markReadByRouteOrMedia(
                targetRoute,
                mediaId,
              ),
            );
            _instance.notificationRouteController.add(targetRoute);
          } else if (payload.startsWith('route:')) {
            final route = payload.replaceFirst('route:', '').trim();
            unawaited(
              NotificationInboxService().markReadByRouteOrMedia(route, null),
            );
            _instance.notificationRouteController.add(route);
          } else if (payload == '/downloads' ||
              payload == '/news' ||
              payload == '/watchlist') {
            unawaited(
              NotificationInboxService().markReadByRouteOrMedia(payload, null),
            );
            _instance.notificationRouteController.add(payload);
          }
        }
        AppLogger.infoPair('Notification tapped', response.payload);
      },
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    await _createNotificationChannels();
    if (!isBackground) {
      final androidPlugin =
          flutterLocalNotificationsPlugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >();
      await androidPlugin?.requestExactAlarmsPermission();
    }
    await reconcileScheduledReleaseAlerts();
  }

  Future<void> ensureSoundChannelsCreated([String? ignoredSoundId]) async {
    final androidImplementation =
        flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();

    const newsChannel = AndroidNotificationChannel(
      'AniDash_news',
      'AniDash News',
      description: 'Notifications for latest anime news',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );

    const episodeChannel = AndroidNotificationChannel(
      'AniDash_episodes',
      'Episode Releases',
      description: 'Notifications when new Sub or Dub episodes are released',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );

    const updateChannel = AndroidNotificationChannel(
      'AniDash_updates',
      'App Updates',
      description: 'Notifications when a new AniDash version is available',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );

    const reminderChannel = AndroidNotificationChannel(
      'AniDash_reminders',
      'Continue Watching Reminders',
      description: 'Reminders to continue watching your paused anime',
      importance: Importance.defaultImportance,
      playSound: true,
      enableVibration: true,
    );

    await androidImplementation?.createNotificationChannel(newsChannel);
    await androidImplementation?.createNotificationChannel(episodeChannel);
    await androidImplementation?.createNotificationChannel(updateChannel);
    await androidImplementation?.createNotificationChannel(reminderChannel);
  }

  Future<void> _createNotificationChannels() async {
    final androidImplementation =
        flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();

    // Delete deprecated v1 channels to migrate to custom sound channels
    try {
      await androidImplementation?.deleteNotificationChannel(
        'AniDash_news_channel',
      );
      await androidImplementation?.deleteNotificationChannel(
        'AniDash_episodes_channel',
      );
      await androidImplementation?.deleteNotificationChannel(
        'AniDash_updates_channel',
      );
      await androidImplementation?.deleteNotificationChannel(
        'AniDash_news_channel_v2',
      );
      await androidImplementation?.deleteNotificationChannel(
        'AniDash_episodes_channel_v2',
      );
      await androidImplementation?.deleteNotificationChannel(
        'AniDash_updates_channel_v2',
      );
    } catch (_) {}

    const AndroidNotificationChannel downloadChannel =
        AndroidNotificationChannel(
          'AniDash_downloads_channel',
          'Downloads',
          description: 'Download progress and completed status',
          importance: Importance.low,
          playSound: false,
          enableVibration: false,
          showBadge: false,
        );

    const AndroidNotificationChannel playbackChannel =
        AndroidNotificationChannel(
          'AniDash_playback_channel',
          'Media Playback',
          description:
              'Controls for active media playback and lock screen controls',
          importance: Importance.low,
          playSound: false,
          enableVibration: false,
          showBadge: false,
        );

    await androidImplementation?.createNotificationChannel(downloadChannel);
    await androidImplementation?.createNotificationChannel(playbackChannel);

    await ensureSoundChannelsCreated();
  }

  AndroidNotificationDetails _buildAndroidDetails({
    required String channelBaseId,
    required String channelName,
    required String channelDescription,
    Importance importance = Importance.max,
    Priority priority = Priority.max,
    bool playSound = true,
    bool enableVibration = true,
    List<AndroidNotificationAction>? actions,
    StyleInformation? styleInformation,
    Color? color,
  }) {
    return AndroidNotificationDetails(
      channelBaseId,
      channelName,
      channelDescription: channelDescription,
      importance: importance,
      priority: priority,
      playSound: playSound,
      enableVibration: enableVibration,
      icon: _iconName,
      color: color ?? _brandColor,
      actions: actions,
      styleInformation: styleInformation,
      visibility: NotificationVisibility.public,
      channelShowBadge: true,
      showWhen: true,
    );
  }

  Future<void> _safeShow(
    int id,
    String title,
    String body,
    NotificationDetails details, {
    String? payload,
    String? channelBaseId,
    String? channelName,
    String? channelDescription,
    StyleInformation? styleInformation,
  }) async {
    try {
      await flutterLocalNotificationsPlugin.show(
        id,
        title,
        body,
        details,
        payload: payload,
      );
    } catch (e, st) {
      AppLogger.w('Failed to show system notification (trying fallback): $e');
      if (Platform.isAndroid && channelBaseId != null) {
        try {
          final fallbackDetails = NotificationDetails(
            android: AndroidNotificationDetails(
              channelBaseId,
              channelName ?? 'AniDash Notifications',
              channelDescription: channelDescription ?? 'AniDash Alerts',
              importance: Importance.max,
              priority: Priority.max,
              playSound: true,
              enableVibration: true,
              icon: _iconName,
              color: _brandColor,
              styleInformation:
                  styleInformation ??
                  BigTextStyleInformation(body, contentTitle: title),
              visibility: NotificationVisibility.public,
            ),
          );
          await flutterLocalNotificationsPlugin.show(
            id,
            title,
            body,
            fallbackDetails,
            payload: payload,
          );
          AppLogger.success('Fallback system notification posted successfully');
        } catch (e2) {
          AppLogger.e('Fallback system notification also failed: $e2', e2, st);
        }
      }
    }
  }

  Future<void> showTestNotification({String? title, String? body}) async {
    await ensureSoundChannelsCreated();

    final details = NotificationDetails(
      android: _buildAndroidDetails(
        channelBaseId: 'AniDash_updates',
        channelName: 'App Updates',
        channelDescription:
            'Notifications when a new AniDash version is available',
        styleInformation: BigTextStyleInformation(
          body ?? 'Notifications are enabled and using your system sound.',
          contentTitle: title ?? 'AniDash Notification Test',
        ),
      ),
    );

    await flutterLocalNotificationsPlugin.show(
      8888,
      title ?? 'AniDash Notification Test',
      body ?? 'Notifications are enabled and using your system sound.',
      details,
    );
  }

  Future<void> showNewsNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!await _isCategoryEnabled('enableNews')) return;
    const notifId = 1000;
    await NotificationInboxService().add(
      title: title,
      body: body,
      route: payload,
      dedupeKey: 'news:${payload ?? title}',
      notificationType: 'news',
      systemNotificationId: notifId,
    );
    await ensureSoundChannelsCreated();

    final styleInfo = BigTextStyleInformation(body, contentTitle: title);

    final platformChannelSpecifics = NotificationDetails(
      android: _buildAndroidDetails(
        channelBaseId: 'AniDash_news',
        channelName: 'AniDash News',
        channelDescription: 'Notifications for latest anime news',
        styleInformation: styleInfo,
      ),
    );

    await _safeShow(
      notifId,
      title,
      body,
      platformChannelSpecifics,
      payload: payload,
      channelBaseId: 'AniDash_news',
      channelName: 'AniDash News',
      channelDescription: 'Notifications for latest anime news',
      styleInformation: styleInfo,
    );
  }

  Future<void> showDownloadProgressNotification({
    required int id,
    required String animeTitle,
    required int episodeNumber,
    required double progress,
  }) async {
    if (!await _isCategoryEnabled('enableDownloads')) return;
    final percent = (progress * 100).clamp(0, 100).toInt();
    final AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
          'AniDash_downloads_channel',
          'Downloads',
          channelDescription: 'Download progress and completed status',
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          onlyAlertOnce: true,
          showProgress: true,
          maxProgress: 100,
          progress: percent,
          icon: _iconName,
          color: _brandColor,
        );

    final NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
    );

    await flutterLocalNotificationsPlugin.show(
      id,
      'Downloading EP $episodeNumber - $animeTitle',
      '$percent% completed',
      platformChannelSpecifics,
    );
  }

  Future<void> showDownloadCompletedNotification({
    required int id,
    required String animeTitle,
    required int episodeNumber,
  }) async {
    if (!await _isCategoryEnabled('enableDownloads')) return;
    await NotificationInboxService().add(
      title: 'Download Complete',
      body: '$animeTitle - Episode $episodeNumber is ready offline',
      route: '/downloads',
      dedupeKey: 'download:$animeTitle:$episodeNumber',
      systemNotificationId: id,
    );
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
          'AniDash_downloads_channel',
          'Downloads',
          channelDescription: 'Download progress and completed status',
          importance: Importance.high,
          priority: Priority.high,
          ongoing: false,
          icon: _iconName,
          color: _brandColor,
        );

    final NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
    );

    await flutterLocalNotificationsPlugin.show(
      id,
      'Download Complete',
      '$animeTitle - Episode $episodeNumber is ready to watch offline',
      platformChannelSpecifics,
    );
  }

  Future<void> showEpisodeReleaseNotification({
    required String animeTitle,
    required int episodeNumber,
    bool isDub = false,
    String? mediaId,
    String? customTitle,
    String? customBody,
    String? audioType,
    String? dedupeKey,
  }) async {
    final isDubRelease =
        isDub ||
        audioType == 'english_dub' ||
        (audioType?.contains('dub') ?? false);
    if (isDubRelease != await _prefersEnglishDub()) return;
    if (!await _isCategoryEnabled(
      isDubRelease ? 'enableDubReleases' : 'enableSubReleases',
    )) {
      return;
    }
    final title =
        customTitle ?? (isDubRelease ? 'New Dub Episode' : 'New SUB Episode');
    final body =
        customBody ?? '$animeTitle Episode $episodeNumber is now available.';
    final effectiveDedupeKey =
        dedupeKey ??
        'release:${mediaId ?? animeTitle}:$episodeNumber:${audioType ?? (isDub ? "dub" : "sub")}';
    final notifId =
        (mediaId ?? animeTitle).hashCode ^
        episodeNumber ^
        (audioType ?? '').hashCode;

    await NotificationInboxService().add(
      title: title,
      body: body,
      route: mediaId != null ? '/details/$mediaId?tab=episodes' : null,
      dedupeKey: effectiveDedupeKey,
      notificationType: audioType ?? (isDub ? 'dub' : 'sub'),
      mediaId: mediaId,
      episodeNumber: episodeNumber,
      language: isDubRelease ? 'en' : 'ja',
      systemNotificationId: notifId,
    );
    await ensureSoundChannelsCreated();

    final styleInfo = BigTextStyleInformation(
      body,
      contentTitle: title,
      summaryText: isDubRelease ? 'English Dub' : 'Japanese Sub',
    );

    final platformChannelSpecifics = NotificationDetails(
      android: _buildAndroidDetails(
        channelBaseId: 'AniDash_episodes',
        channelName: 'Episode Releases',
        channelDescription:
            'Notifications when new Sub or Dub episodes are released',
        importance: Importance.max,
        priority: Priority.max,
        styleInformation: styleInfo,
      ),
    );

    await _safeShow(
      notifId,
      title,
      body,
      platformChannelSpecifics,
      payload: mediaId != null ? 'details:$mediaId?tab=episodes' : null,
      channelBaseId: 'AniDash_episodes',
      channelName: 'Episode Releases',
      channelDescription:
          'Notifications when new Sub or Dub episodes are released',
      styleInformation: styleInfo,
    );
  }

  /// Schedules exact Android alarms for upcoming episodes (24h, 2h, 1h, and exact release).
  /// These alarms are registered directly with Android AlarmManager, so they wake up the device
  /// and trigger notifications even if AniDash is closed or terminated.
  Future<void> scheduleUpcomingEpisodeAlerts({
    required int mediaId,
    required String animeTitle,
    required int episodeNumber,
    required int airingAtEpoch,
  }) async {
    if (!Platform.isAndroid) return;
    if (!await _isCategoryEnabled('enableSubReleases')) return;
    if (await _prefersEnglishDub()) return;
    _setupTimeZone();
    await ensureSoundChannelsCreated();

    final nowEpoch = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final timeUntilAiring = airingAtEpoch - nowEpoch;
    if (timeUntilAiring <= 0) return;

    final pref = await SharedPreferences.getInstance();

    final details = NotificationDetails(
      android: _buildAndroidDetails(
        channelBaseId: 'AniDash_episodes',
        channelName: 'Episode Releases',
        channelDescription:
            'Notifications when new Sub or Dub episodes are released',
        importance: Importance.max,
        priority: Priority.max,
      ),
    );

    // 1. 24-hour countdown alert (airingAt - 86400)
    final alert24hEpoch = airingAtEpoch - 86400;
    if (alert24hEpoch > nowEpoch &&
        !(pref.getBool('notif_24h_${mediaId}_$episodeNumber') ?? false)) {
      final scheduled24h = tz.TZDateTime.fromMillisecondsSinceEpoch(
        tz.local,
        alert24hEpoch * 1000,
      );
      final id24h = ((mediaId.hashCode ^ episodeNumber) * 31 + 24) & 0x7FFFFFFF;
      await _safeZonedSchedule(
        id: id24h,
        title: 'Upcoming: $animeTitle • Ep $episodeNumber',
        body: 'Episode $episodeNumber releases tomorrow (in 24 hours)!',
        scheduledDate: scheduled24h,
        notificationDetails: details,
        payload: 'details:$mediaId?tab=episodes',
      );
    }

    // 2. 2-hour countdown alert (airingAt - 7200)
    final alert2hEpoch = airingAtEpoch - 7200;
    if (alert2hEpoch > nowEpoch &&
        !(pref.getBool('notif_2h_${mediaId}_$episodeNumber') ?? false)) {
      final scheduled2h = tz.TZDateTime.fromMillisecondsSinceEpoch(
        tz.local,
        alert2hEpoch * 1000,
      );
      final id2h = ((mediaId.hashCode ^ episodeNumber) * 31 + 2) & 0x7FFFFFFF;
      await _safeZonedSchedule(
        id: id2h,
        title: 'Upcoming: $animeTitle • Ep $episodeNumber',
        body: 'Episode $episodeNumber releases in 2 hours!',
        scheduledDate: scheduled2h,
        notificationDetails: details,
        payload: 'details:$mediaId?tab=episodes',
      );
    }

    // 3. 1-hour countdown alert (airingAt - 3600)
    final alert1hEpoch = airingAtEpoch - 3600;
    if (alert1hEpoch > nowEpoch &&
        !(pref.getBool('notif_1h_${mediaId}_$episodeNumber') ?? false)) {
      final scheduled1h = tz.TZDateTime.fromMillisecondsSinceEpoch(
        tz.local,
        alert1hEpoch * 1000,
      );
      final id1h = ((mediaId.hashCode ^ episodeNumber) * 31 + 1) & 0x7FFFFFFF;
      await _safeZonedSchedule(
        id: id1h,
        title: 'Upcoming: $animeTitle • Ep $episodeNumber',
        body: 'Episode $episodeNumber releases in 1 hour!',
        scheduledDate: scheduled1h,
        notificationDetails: details,
        payload: 'details:$mediaId?tab=episodes',
      );
    }

    // 4. Exact release alert (airingAt)
    if (airingAtEpoch > nowEpoch &&
        !(pref.getBool('sub_release_${mediaId}_$episodeNumber') ?? false)) {
      final scheduledRelease = tz.TZDateTime.fromMillisecondsSinceEpoch(
        tz.local,
        airingAtEpoch * 1000,
      );
      final idRelease =
          ((mediaId.hashCode ^ episodeNumber) * 31 + 0) & 0x7FFFFFFF;
      await _safeZonedSchedule(
        id: idRelease,
        title: '$animeTitle • Ep $episodeNumber Released',
        body:
            'Episode $episodeNumber is now officially available to watch on AniDash.',
        scheduledDate: scheduledRelease,
        notificationDetails: details,
        payload: 'details:$mediaId?tab=episodes',
      );
    }
  }

  Future<void> _safeZonedSchedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime scheduledDate,
    required NotificationDetails notificationDetails,
    String? payload,
  }) async {
    try {
      await flutterLocalNotificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        scheduledDate,
        notificationDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: payload,
      );
      AppLogger.i(
        '[NotificationService] Exact alarm scheduled: $title at ${scheduledDate.toIso8601String()}',
      );
    } catch (_) {
      try {
        await flutterLocalNotificationsPlugin.zonedSchedule(
          id,
          title,
          body,
          scheduledDate,
          notificationDetails,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: payload,
        );
        AppLogger.i(
          '[NotificationService] Inexact alarm scheduled (fallback): $title at ${scheduledDate.toIso8601String()}',
        );
      } catch (e2) {
        AppLogger.w('Failed to schedule alarm: $e2');
      }
    }
  }

  Future<void> showContinueWatchingNotification({
    required String animeTitle,
    required int episodeNumber,
    String? mediaId,
    String? customBody,
  }) async {
    if (!await _isCategoryEnabled('enableContinueWatching')) return;
    final title = 'Continue Watching $animeTitle';
    final body =
        customBody ??
        'You stopped at Episode $episodeNumber. Continue where you left off.';
    final effectiveDedupeKey =
        'continue:${mediaId ?? animeTitle}:$episodeNumber';
    final notifId = (mediaId ?? animeTitle).hashCode;

    await NotificationInboxService().add(
      title: title,
      body: body,
      route: mediaId != null ? '/details/$mediaId?tab=episodes' : '/watchlist',
      dedupeKey: effectiveDedupeKey,
      notificationType: 'continue_watching',
      mediaId: mediaId,
      episodeNumber: episodeNumber,
      systemNotificationId: notifId,
    );
    await ensureSoundChannelsCreated();

    final styleInfo = BigTextStyleInformation(body, contentTitle: title);

    final platformChannelSpecifics = NotificationDetails(
      android: _buildAndroidDetails(
        channelBaseId: 'AniDash_reminders',
        channelName: 'Continue Watching Reminders',
        channelDescription: 'Reminders to continue watching your paused anime',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        styleInformation: styleInfo,
      ),
    );

    await _safeShow(
      notifId,
      title,
      body,
      platformChannelSpecifics,
      payload: mediaId != null ? 'details:$mediaId?tab=episodes' : '/watchlist',
      channelBaseId: 'AniDash_reminders',
      channelName: 'Continue Watching Reminders',
      channelDescription: 'Reminders to continue watching your paused anime',
      styleInformation: styleInfo,
    );
  }

  Future<void> cancelNotification(int id) async {
    try {
      await flutterLocalNotificationsPlugin.cancel(id);
    } catch (_) {}
  }

  Future<void> cancelAllNotifications() async {
    try {
      await flutterLocalNotificationsPlugin.cancelAll();
    } catch (_) {}
  }

  Future<void> showUpdateAvailableNotification(String version) async {
    const notifId = 1901;
    await NotificationInboxService().add(
      title: 'AniDash v$version is available',
      body: 'A new stable version is ready to install.',
      route: '/settings/update',
      dedupeKey: 'update:$version',
      systemNotificationId: notifId,
    );
    await ensureSoundChannelsCreated();

    const styleInfo = BigTextStyleInformation(
      'A new version has been released on GitHub. Tap to update or snooze.',
      contentTitle: 'AniDash Update Available',
      summaryText: 'New version available',
    );

    final details = NotificationDetails(
      android: _buildAndroidDetails(
        channelBaseId: 'AniDash_updates',
        channelName: 'App Updates',
        channelDescription:
            'Notifications when a new AniDash version is available',
        styleInformation: styleInfo,
        actions: const <AndroidNotificationAction>[
          AndroidNotificationAction(
            'update_now',
            'Update Now',
            cancelNotification: true,
            showsUserInterface: true,
          ),
          AndroidNotificationAction(
            'update_remind_1h',
            'Remind in 1h',
            cancelNotification: true,
            showsUserInterface: false,
          ),
          AndroidNotificationAction(
            'update_skip_day',
            'Skip for today',
            cancelNotification: true,
            showsUserInterface: false,
          ),
        ],
      ),
    );
    await _safeShow(
      notifId,
      'AniDash v$version is available',
      'A new version has been released on GitHub. Tap to update or snooze.',
      details,
      payload: 'update:$version',
      channelBaseId: 'AniDash_updates',
      channelName: 'App Updates',
      channelDescription:
          'Notifications when a new AniDash version is available',
      styleInformation: styleInfo,
    );
  }

  Future<void> showPlaybackNotification({
    required String animeTitle,
    required String episodeTitle,
    required int episodeNumber,
    required bool isPlaying,
    String? posterUrl,
  }) async {
    final AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
          'AniDash_playback_channel',
          'Media Playback',
          channelDescription:
              'Controls for active media playback and lock screen controls',
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          autoCancel: false,
          onlyAlertOnce: true,
          showWhen: false,
          color: const Color(0xFFE91E63),
          icon: _iconName,
          styleInformation: const MediaStyleInformation(
            htmlFormatContent: false,
            htmlFormatTitle: false,
          ),
          actions: <AndroidNotificationAction>[
            const AndroidNotificationAction(
              'prev',
              'Previous',
              cancelNotification: false,
              showsUserInterface: false,
            ),
            AndroidNotificationAction(
              'play_pause',
              isPlaying ? 'Pause' : 'Play',
              cancelNotification: false,
              showsUserInterface: false,
            ),
            const AndroidNotificationAction(
              'next',
              'Next',
              cancelNotification: false,
              showsUserInterface: false,
            ),
          ],
        );

    final NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
    );

    await flutterLocalNotificationsPlugin.show(
      9999,
      '$animeTitle - EP $episodeNumber',
      episodeTitle,
      platformChannelSpecifics,
    );
  }

  Future<void> hidePlaybackNotification() async {
    await flutterLocalNotificationsPlugin.cancel(9999);
  }

  Future<void> showIssueAlert({
    required int issueNumber,
    required String title,
    required String author,
  }) async {
    const androidPlatformChannelSpecifics = AndroidNotificationDetails(
      'anidash_issues_channel',
      'Issue & Feedback Alerts',
      channelDescription: 'Notifications for new GitHub issues and user reports',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    const platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: DarwinNotificationDetails(),
    );

    await flutterLocalNotificationsPlugin.show(
      88000 + (issueNumber % 1000),
      'New Issue #$issueNumber by $author',
      title,
      platformChannelSpecifics,
      payload: 'issue:$issueNumber',
    );
  }
}
