import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ani_dash/core/models/settings/notification_settings_model.dart';
import 'package:ani_dash/core/services/notification_service.dart';
import 'package:ani_dash/core/services/notification_inbox_service.dart';
import 'package:ani_dash/main.dart';

final notificationSettingsProvider =
    NotifierProvider<NotificationSettingsNotifier, NotificationSettingsModel>(
      NotificationSettingsNotifier.new,
    );

class NotificationSettingsNotifier extends Notifier<NotificationSettingsModel> {
  static const _prefsKey = 'notification_settings_data';

  @override
  NotificationSettingsModel build() {
    final jsonString = sharedPrefs.getString(_prefsKey);
    if (jsonString != null) {
      try {
        final map = jsonDecode(jsonString) as Map<String, dynamic>;
        final settings = NotificationSettingsModel.fromJson(map);
        if (!settings.enableNews) {
          Future.microtask(NotificationInboxService().removeNews);
        }
        return settings;
      } catch (_) {}
    }
    return const NotificationSettingsModel();
  }

  Future<void> updateSettings(
    NotificationSettingsModel Function(NotificationSettingsModel) updater,
  ) async {
    final previous = state;
    state = updater(state);
    await sharedPrefs.setString(_prefsKey, jsonEncode(state.toJson()));
    final enabledSomething =
        (!previous.enableNews && state.enableNews) ||
        (!previous.enableDubReleases && state.enableDubReleases) ||
        (!previous.enableSubReleases && state.enableSubReleases) ||
        (!previous.enableContinueWatching && state.enableContinueWatching) ||
        (!previous.enableDownloads && state.enableDownloads);
    if (enabledSomething) {
      await NotificationService().requestSystemPermission();
    }
    if (previous.enableNews && !state.enableNews) {
      await NotificationInboxService().removeNews();
    }
    await NotificationService().reconcileScheduledReleaseAlerts();
    await NotificationService().registerPeriodicNotificationWorker();
  }
}
