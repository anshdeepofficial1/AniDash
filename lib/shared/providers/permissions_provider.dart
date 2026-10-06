import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:ani_dash/core/services/notification_service.dart';
import 'package:ani_dash/core/services/remote_push_service.dart';
import 'package:ani_dash/storage_provider.dart';

part 'permissions_provider.g.dart';

class PermissionState {
  final bool notification;
  final bool storage;
  final bool photos;
  final bool videos;

  const PermissionState({
    this.notification = false,
    this.storage = false,
    this.photos = false,
    this.videos = false,
  });

  PermissionState copyWith({
    bool? notification,
    bool? storage,
    bool? photos,
    bool? videos,
  }) {
    return PermissionState(
      notification: notification ?? this.notification,
      storage: storage ?? this.storage,
      photos: photos ?? this.photos,
      videos: videos ?? this.videos,
    );
  }
}

@Riverpod(keepAlive: true)
class Permissions extends _$Permissions {
  static const _storageConsentKey = 'storage_access_confirmed';
  int? _cachedSdkInt;

  @override
  PermissionState build() {
    _initSdkInt().then((_) => checkAll());
    return const PermissionState();
  }

  Future<void> checkAll() async {
    if (Platform.isIOS || Platform.isMacOS) {
      state = state.copyWith(
        notification: await Permission.notification.isGranted,
        storage: true,
        photos: true,
        videos: true,
      );
      return;
    }
    if (!Platform.isAndroid) {
      state = state.copyWith(
        notification: true,
        storage: true,
        photos: true,
        videos: true,
      );
      return;
    }
    await _initSdkInt();

    final consent =
        (await SharedPreferences.getInstance()).getBool(_storageConsentKey) ??
        false;
    final systemStorageGranted =
        _usesAppOwnedStorage || await _storagePermission().isGranted;
    final storageReady =
        consent && systemStorageGranted && await _hasWritableDownloadStorage();

    state = state.copyWith(
      notification: await Permission.notification.isGranted,
      storage: storageReady,
      photos: await _mediaPermission(Permission.photos).isGranted,
      videos: await _mediaPermission(Permission.videos).isGranted,
    );
  }

  Future<bool> requestNotificationPermission() async {
    if (Platform.isAndroid) {
      if (state.notification) return true;
      final granted = await _request(Permission.notification);
      if (granted) await RemotePushService.requestPermission();
      state = state.copyWith(notification: granted);
      return granted;
    }
    if (Platform.isMacOS || Platform.isIOS) {
      final granted = await NotificationService().requestSystemPermission();
      state = state.copyWith(notification: granted);
      return granted;
    }
    // Desktop (Windows/Linux)
    final newState = !state.notification;
    state = state.copyWith(notification: newState);
    return newState;
  }

  void setNotificationAccess(bool enabled) {
    state = state.copyWith(notification: enabled);
  }

  Future<bool> requestStoragePermission() async {
    if (Platform.isAndroid) {
      if (state.storage) return true;
      await _initSdkInt();
      if (_usesAppOwnedStorage) {
        if (!await _hasWritableDownloadStorage()) {
          state = state.copyWith(storage: false);
          return false;
        }
        await (await SharedPreferences.getInstance()).setBool(
          _storageConsentKey,
          true,
        );
        state = state.copyWith(storage: true);
        return true;
      }
      final granted = await _request(_storagePermission());
      final writable = granted && await _hasWritableDownloadStorage();
      if (writable) {
        await (await SharedPreferences.getInstance()).setBool(
          _storageConsentKey,
          true,
        );
      }
      state = state.copyWith(storage: writable);
      return writable;
    }

    // Desktop / macOS / iOS: Writable check
    final writable = await _hasWritableDownloadStorage();
    await (await SharedPreferences.getInstance()).setBool(
      _storageConsentKey,
      true,
    );
    state = state.copyWith(storage: writable);
    return writable;
  }

  Future<void> revokeStorageAccess() async {
    await (await SharedPreferences.getInstance()).setBool(
      _storageConsentKey,
      false,
    );
    state = state.copyWith(storage: false);
    if (Platform.isAndroid && !_usesAppOwnedStorage) {
      await openAppSettings();
    }
  }

  Future<bool> requestMediaPermissions() async {
    if (!Platform.isAndroid) return true;
    await _initSdkInt();

    if (_cachedSdkInt! < 33) {
      final granted = await _request(Permission.storage);
      state = state.copyWith(photos: granted, videos: granted);
      return granted;
    }

    final photosGranted = await _request(Permission.photos);
    final videosGranted = await _request(Permission.videos);

    state = state.copyWith(photos: photosGranted, videos: videosGranted);
    return photosGranted && videosGranted;
  }

  Permission _storagePermission() {
    return Permission.storage;
  }

  bool get _usesAppOwnedStorage => (_cachedSdkInt ?? 0) >= 29;

  Permission _mediaPermission(Permission modern) {
    return (_cachedSdkInt ?? 0) >= 33 ? modern : Permission.storage;
  }

  Future<void> _initSdkInt() async {
    if (_cachedSdkInt != null) return;
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      _cachedSdkInt = info.version.sdkInt;
    } catch (_) {
      _cachedSdkInt = 0;
    }
  }

  Future<bool> _hasWritableDownloadStorage() async {
    try {
      final directory = await StorageProvider.getDefaultDirectory();
      if (directory == null) return false;
      if (!await directory.exists()) await directory.create(recursive: true);
      final probe = File(
        '${directory.path}${Platform.pathSeparator}.anidash_write_test',
      );
      await probe.writeAsString('ok', flush: true);
      if (await probe.exists()) await probe.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _request(Permission permission) async {
    if (await permission.isGranted || !Platform.isAndroid) return true;
    final result = await permission.request();
    return result == PermissionStatus.granted ||
        result == PermissionStatus.limited;
  }
}
