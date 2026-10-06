import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:ani_dash/main.dart';

class SecurityState {
  final bool appLockEnabled;
  final String? appLockPinHash;
  final bool appLockBiometrics;
  final String appLockType;
  final int appLockDelaySeconds;
  final bool hentaiLockEnabled;
  final String? hentaiLockPinHash;
  final bool hentaiLockBiometrics;
  final bool recentAppsPrivacy;
  final bool screenshotPrivacy;
  final bool isAppUnlocked;
  final bool isHentaiUnlocked;

  const SecurityState({
    this.appLockEnabled = false,
    this.appLockPinHash,
    this.appLockBiometrics = true,
    this.appLockType = 'pin4',
    this.appLockDelaySeconds = 0,
    this.hentaiLockEnabled = false,
    this.hentaiLockPinHash,
    this.hentaiLockBiometrics = true,
    this.recentAppsPrivacy = true,
    this.screenshotPrivacy = false,
    this.isAppUnlocked = false,
    this.isHentaiUnlocked = false,
  });

  SecurityState copyWith({
    bool? appLockEnabled,
    String? appLockPinHash,
    bool? appLockBiometrics,
    String? appLockType,
    int? appLockDelaySeconds,
    bool? hentaiLockEnabled,
    String? hentaiLockPinHash,
    bool? hentaiLockBiometrics,
    bool? recentAppsPrivacy,
    bool? screenshotPrivacy,
    bool? isAppUnlocked,
    bool? isHentaiUnlocked,
  }) {
    return SecurityState(
      appLockEnabled: appLockEnabled ?? this.appLockEnabled,
      appLockPinHash: appLockPinHash ?? this.appLockPinHash,
      appLockBiometrics: appLockBiometrics ?? this.appLockBiometrics,
      appLockType: appLockType ?? this.appLockType,
      appLockDelaySeconds: appLockDelaySeconds ?? this.appLockDelaySeconds,
      hentaiLockEnabled: hentaiLockEnabled ?? this.hentaiLockEnabled,
      hentaiLockPinHash: hentaiLockPinHash ?? this.hentaiLockPinHash,
      hentaiLockBiometrics: hentaiLockBiometrics ?? this.hentaiLockBiometrics,
      recentAppsPrivacy: recentAppsPrivacy ?? this.recentAppsPrivacy,
      screenshotPrivacy: screenshotPrivacy ?? this.screenshotPrivacy,
      isAppUnlocked: isAppUnlocked ?? this.isAppUnlocked,
      isHentaiUnlocked: isHentaiUnlocked ?? this.isHentaiUnlocked,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'appLockEnabled': appLockEnabled,
      'appLockBiometrics': appLockBiometrics,
      'appLockType': appLockType,
      'appLockDelaySeconds': appLockDelaySeconds,
      'hentaiLockEnabled': hentaiLockEnabled,
      'hentaiLockBiometrics': hentaiLockBiometrics,
      'recentAppsPrivacy': recentAppsPrivacy,
      'screenshotPrivacy': screenshotPrivacy,
    };
  }

  factory SecurityState.fromMap(Map<String, dynamic> map) {
    final appLock = map['appLockEnabled'] == true;
    final hentaiLock = map['hentaiLockEnabled'] == true;
    return SecurityState(
      appLockEnabled: appLock,
      appLockPinHash: map['appLockPinHash'],
      appLockBiometrics: map['appLockBiometrics'] ?? true,
      appLockType: map['appLockType'] ?? 'pin4',
      appLockDelaySeconds: map['appLockDelaySeconds'] ?? 0,
      hentaiLockEnabled: hentaiLock,
      hentaiLockPinHash: map['hentaiLockPinHash'],
      hentaiLockBiometrics: map['hentaiLockBiometrics'] ?? true,
      recentAppsPrivacy: map['recentAppsPrivacy'] ?? true,
      screenshotPrivacy: map['screenshotPrivacy'] ?? false,
      isAppUnlocked: !appLock,
      isHentaiUnlocked: !hentaiLock,
    );
  }

  String toJson() => json.encode(toMap());
  factory SecurityState.fromJson(String source) =>
      SecurityState.fromMap(json.decode(source));
}

final securityProvider = NotifierProvider<SecurityNotifier, SecurityState>(
  SecurityNotifier.new,
);

class SecurityNotifier extends Notifier<SecurityState> {
  static const _prefsKey = 'ani_security_settings';
  static const _channel = MethodChannel('shonenx/security');
  static const _appCredentialKey = 'ani_app_lock_credential';
  static const _adultCredentialKey = 'ani_adult_lock_credential';
  static const _iterations = 30000;
  static const _storage = FlutterSecureStorage();
  int _appFailures = 0;
  int _adultFailures = 0;
  DateTime? _appLockedUntil;
  DateTime? _adultLockedUntil;

  @override
  SecurityState build() {
    final raw = sharedPrefs.getString(_prefsKey);
    final initial =
        raw != null ? SecurityState.fromJson(raw) : const SecurityState();
    _applySecureFlag(initial.screenshotPrivacy);
    Future.microtask(_loadSecureCredentials);
    return initial;
  }

  String hashPin(String pin) {
    final random = Random.secure();
    final salt = List<int>.generate(16, (_) => random.nextInt(256));
    return _deriveCredential(pin, salt);
  }

  String _deriveCredential(String pin, List<int> salt) {
    final mac = Hmac(sha256, utf8.encode(pin));
    var block = mac.convert(<int>[...salt, 0, 0, 0, 1]).bytes;
    final derived = List<int>.from(block);
    for (var i = 1; i < _iterations; i++) {
      block = mac.convert(block).bytes;
      for (var j = 0; j < derived.length; j++) {
        derived[j] ^= block[j];
      }
    }
    return 'pbkdf2-sha256\$$_iterations\$${base64UrlEncode(salt)}\$${base64UrlEncode(derived)}';
  }

  bool _verifyCredential(String pin, String stored) {
    if (!stored.startsWith('pbkdf2-sha256\$')) {
      return sha256.convert(utf8.encode(pin)).toString() == stored;
    }
    final parts = stored.split('\$');
    if (parts.length != 4) return false;
    final salt = base64Url.decode(parts[2]);
    final candidate = _deriveCredential(pin, salt);
    if (candidate.length != stored.length) return false;
    var difference = 0;
    for (var i = 0; i < candidate.length; i++) {
      difference |= candidate.codeUnitAt(i) ^ stored.codeUnitAt(i);
    }
    return difference == 0;
  }

  Future<void> _loadSecureCredentials() async {
    final app = await _storage.read(key: _appCredentialKey);
    final adult = await _storage.read(key: _adultCredentialKey);
    if (app != null || adult != null) {
      state = state.copyWith(
        appLockPinHash: app ?? state.appLockPinHash,
        hentaiLockPinHash: adult ?? state.hentaiLockPinHash,
      );
    }
    // Migrate legacy credentials out of ordinary preferences.
    if (app == null && state.appLockPinHash != null) {
      await _storage.write(key: _appCredentialKey, value: state.appLockPinHash);
    }
    if (adult == null && state.hentaiLockPinHash != null) {
      await _storage.write(
        key: _adultCredentialKey,
        value: state.hentaiLockPinHash,
      );
    }
    _save();
  }

  bool verifyAppPin(String pin) {
    if (_appLockedUntil?.isAfter(DateTime.now()) == true) return false;
    if (state.appLockPinHash == null) return !state.appLockEnabled;
    final match = _verifyCredential(pin, state.appLockPinHash!);
    if (match) {
      _appFailures = 0;
      state = state.copyWith(isAppUnlocked: true);
    } else if (++_appFailures >= 5) {
      _appFailures = 0;
      _appLockedUntil = DateTime.now().add(const Duration(seconds: 30));
    }
    return match;
  }

  bool verifyHentaiPin(String pin) {
    if (_adultLockedUntil?.isAfter(DateTime.now()) == true) return false;
    if (state.hentaiLockPinHash == null) return !state.hentaiLockEnabled;
    final match = _verifyCredential(pin, state.hentaiLockPinHash!);
    if (match) {
      _adultFailures = 0;
      state = state.copyWith(isHentaiUnlocked: true);
    } else if (++_adultFailures >= 5) {
      _adultFailures = 0;
      _adultLockedUntil = DateTime.now().add(const Duration(seconds: 30));
    }
    return match;
  }

  void unlockApp() {
    state = state.copyWith(isAppUnlocked: true);
  }

  void lockApp() {
    if (state.appLockEnabled) {
      state = state.copyWith(isAppUnlocked: false);
    }
  }

  void unlockHentai() {
    state = state.copyWith(isHentaiUnlocked: true);
  }

  void lockHentai() {
    if (state.hentaiLockEnabled) {
      state = state.copyWith(isHentaiUnlocked: false);
    }
  }

  void setAppLock(bool enabled, [String? pin]) {
    final pinHash = pin != null ? hashPin(pin) : state.appLockPinHash;
    if (pinHash != null) {
      _storage.write(key: _appCredentialKey, value: pinHash);
    }
    state = state.copyWith(
      appLockEnabled: enabled,
      appLockPinHash: pinHash,
      isAppUnlocked: !enabled,
    );
    _save();
  }

  void setHentaiLock(bool enabled, [String? pin]) {
    final pinHash = pin != null ? hashPin(pin) : state.hentaiLockPinHash;
    if (pinHash != null) {
      _storage.write(key: _adultCredentialKey, value: pinHash);
    }
    state = state.copyWith(
      hentaiLockEnabled: enabled,
      hentaiLockPinHash: pinHash,
      isHentaiUnlocked: !enabled,
    );
    _save();
  }

  void toggleAppLockBiometrics(bool val) {
    state = state.copyWith(appLockBiometrics: val);
    _save();
  }

  void setAppLockType(String type, String credential) {
    final credentialHash = hashPin(credential);
    _storage.write(key: _appCredentialKey, value: credentialHash);
    state = state.copyWith(
      appLockType: type,
      appLockPinHash: credentialHash,
      isAppUnlocked: true,
    );
    _save();
  }

  void setPreferredAppLockType(String type) {
    state = state.copyWith(appLockType: type);
    _save();
  }

  void setAppLockDelay(int seconds) {
    state = state.copyWith(appLockDelaySeconds: seconds);
    _save();
  }

  void toggleHentaiLockBiometrics(bool val) {
    state = state.copyWith(hentaiLockBiometrics: val);
    _save();
  }

  void toggleRecentAppsPrivacy(bool val) {
    state = state.copyWith(recentAppsPrivacy: val);
    _save();
  }

  void toggleScreenshotPrivacy(bool val) {
    state = state.copyWith(screenshotPrivacy: val);
    _applySecureFlag(val);
    _save();
  }

  void _applySecureFlag(bool enable) {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      _channel.invokeMethod('setSecureFlag', {'enable': enable}).catchError((_) {});
    } catch (_) {}
  }

  void _save() {
    sharedPrefs.setString(_prefsKey, state.toJson());
  }
}
