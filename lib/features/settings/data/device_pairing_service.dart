import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';

import 'package:ani_dash/core/constants/anidash_go.dart';
import 'package:ani_dash/main.dart';
import 'package:ani_dash/shared/auth/providers/auth_notifier.dart';

enum DevicePairingStatus {
  success,
  invalidCode,
  expiredCode,
  noAccount,
  websiteNotReady,
  networkError,
  serverError,
}

class DevicePairingResult {
  const DevicePairingResult(this.status, this.message);

  final DevicePairingStatus status;
  final String message;

  bool get isSuccess => status == DevicePairingStatus.success;
}

class PendingPairingDevice {
  const PendingPairingDevice({
    required this.code,
    required this.name,
    required this.browser,
    required this.operatingSystem,
    this.location,
    this.expiresAt,
  });

  final String code;
  final String name;
  final String browser;
  final String operatingSystem;
  final String? location;
  final DateTime? expiresAt;
}

class DevicePairingInspection {
  const DevicePairingInspection({this.device, required this.result});

  final PendingPairingDevice? device;
  final DevicePairingResult result;

  bool get isSuccess => device != null && result.isSuccess;
}

class PairedDeviceRecord {
  const PairedDeviceRecord({
    required this.id,
    required this.name,
    required this.browser,
    required this.operatingSystem,
    required this.scannedAt,
    required this.connectedAt,
    required this.lastConfirmedAt,
    this.location,
    this.sessionExpiresAt,
    this.current = false,
    this.isRemote = false,
  });

  final String id;
  final String name;
  final String browser;
  final String operatingSystem;
  final String? location;
  final DateTime scannedAt;
  final DateTime connectedAt;
  final DateTime lastConfirmedAt;
  final DateTime? sessionExpiresAt;
  final bool current;
  final bool isRemote;

  DateTime get expectedSessionExpiry =>
      sessionExpiresAt ?? connectedAt.add(const Duration(days: 30));

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'browser': browser,
    'operatingSystem': operatingSystem,
    'location': location,
    'scannedAt': scannedAt.toUtc().toIso8601String(),
    'connectedAt': connectedAt.toUtc().toIso8601String(),
    'lastConfirmedAt': lastConfirmedAt.toUtc().toIso8601String(),
    'sessionExpiresAt': sessionExpiresAt?.toUtc().toIso8601String(),
    'current': current,
    'isRemote': isRemote,
  };

  factory PairedDeviceRecord.fromJson(Map<String, dynamic> json) {
    final connectedAt = DateTime.parse(json['connectedAt'] as String).toLocal();
    return PairedDeviceRecord(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Unknown device',
      browser: json['browser'] as String? ?? 'Web browser',
      operatingSystem: json['operatingSystem'] as String? ?? 'Unknown system',
      location: json['location'] as String?,
      scannedAt:
          DateTime.tryParse(json['scannedAt'] as String? ?? '')?.toLocal() ??
          connectedAt,
      connectedAt: connectedAt,
      lastConfirmedAt:
          DateTime.tryParse(
            json['lastConfirmedAt'] as String? ?? '',
          )?.toLocal() ??
          connectedAt,
      sessionExpiresAt:
          DateTime.tryParse(
            json['sessionExpiresAt'] as String? ?? '',
          )?.toLocal(),
      current: json['current'] == true,
      isRemote: json['isRemote'] == true,
    );
  }

  factory PairedDeviceRecord.fromServer(Map<String, dynamic> json) {
    final pairedAt =
        DateTime.tryParse(json['pairedAt']?.toString() ?? '')?.toLocal() ??
        DateTime.now();
    return PairedDeviceRecord(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Unknown browser',
      browser: json['browser']?.toString() ?? 'Web browser',
      operatingSystem: json['os']?.toString() ?? 'Unknown system',
      location: json['location']?.toString(),
      scannedAt: pairedAt,
      connectedAt: pairedAt,
      lastConfirmedAt:
          DateTime.tryParse(
            json['lastActiveAt']?.toString() ?? '',
          )?.toLocal() ??
          pairedAt,
      sessionExpiresAt:
          DateTime.tryParse(
            json['sessionExpiresAt']?.toString() ?? '',
          )?.toLocal(),
      current: json['current'] == true,
      isRemote: true,
    );
  }
}

class DevicePairingService {
  DevicePairingService({
    http.Client? client,
    FlutterSecureStorage? secureStorage,
  }) : _client = client ?? http.Client(),
       _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final http.Client _client;
  final FlutterSecureStorage _secureStorage;

  static final RegExp _codePattern = RegExp(r'^[A-Za-z0-9_-]{6,128}$');
  static const _deviceHistoryKey = 'anidash_go_paired_devices_v1';
  static const _managementTokenKey = 'anidash_go_device_management_token_v1';
  static const _managementExpiryKey = 'anidash_go_device_management_expiry_v1';

  static String? parsePairingCode(String input) {
    final value = input.trim();
    if (_codePattern.hasMatch(value)) return value;

    final uri = Uri.tryParse(value);
    if (uri == null) return null;

    final isOfficialWebLink =
        uri.scheme == 'https' &&
        uri.host.toLowerCase() == 'anidashgo.vercel.app' &&
        (uri.path == '/connect' || uri.path == '/pair');
    final isAppLink =
        uri.scheme.toLowerCase() == 'anidash' &&
        (uri.host.toLowerCase() == 'pair' || uri.path == '/pair');
    if (!isOfficialWebLink && !isAppLink) return null;

    final code = uri.queryParameters['code']?.trim();
    return code != null && _codePattern.hasMatch(code) ? code : null;
  }

  Future<DevicePairingInspection> inspect(String input) async {
    final code = parsePairingCode(input);
    if (code == null) {
      return const DevicePairingInspection(
        result: DevicePairingResult(
          DevicePairingStatus.invalidCode,
          'That QR code or pairing code is not valid for AniDash Go.',
        ),
      );
    }

    try {
      final endpoint = Uri.parse(
        AniDashGo.pairingSessionUrl,
      ).replace(queryParameters: {'code': code});
      final response = await _client
          .get(endpoint, headers: const {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 404 || response.statusCode == 405) {
        return const DevicePairingInspection(
          result: DevicePairingResult(
            DevicePairingStatus.websiteNotReady,
            'Device pairing is ready in the app, but it is not enabled on the AniDash Go website yet.',
          ),
        );
      }
      if (response.statusCode == 400 || response.statusCode == 410) {
        return const DevicePairingInspection(
          result: DevicePairingResult(
            DevicePairingStatus.expiredCode,
            'This pairing code is invalid, expired, or has already been used.',
          ),
        );
      }
      if (response.statusCode != 200) {
        return const DevicePairingInspection(
          result: DevicePairingResult(
            DevicePairingStatus.serverError,
            'AniDash Go could not verify this device. Please try again.',
          ),
        );
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final session =
          (json['session'] as Map?)?.cast<String, dynamic>() ?? json;
      final device =
          (session['device'] as Map?)?.cast<String, dynamic>() ?? session;
      String safeText(dynamic value, String fallback) {
        final text = value?.toString().trim() ?? '';
        if (text.isEmpty) return fallback;
        return text.length > 80 ? text.substring(0, 80) : text;
      }

      final expiresAt = DateTime.tryParse(
        session['expiresAt']?.toString() ?? '',
      );
      return DevicePairingInspection(
        device: PendingPairingDevice(
          code: code,
          name: safeText(device['name'], 'Unknown device'),
          browser: safeText(device['browser'], 'Web browser'),
          operatingSystem: safeText(
            device['os'] ?? device['operatingSystem'],
            'Unknown system',
          ),
          location:
              safeText(device['location'], '').isEmpty
                  ? null
                  : safeText(device['location'], ''),
          expiresAt: expiresAt,
        ),
        result: const DevicePairingResult(
          DevicePairingStatus.success,
          'Device verified.',
        ),
      );
    } on TimeoutException {
      return const DevicePairingInspection(
        result: DevicePairingResult(
          DevicePairingStatus.networkError,
          'The pairing request timed out. Check your connection and try again.',
        ),
      );
    } catch (_) {
      return const DevicePairingInspection(
        result: DevicePairingResult(
          DevicePairingStatus.networkError,
          'AniDash Go could not be reached. Check your connection and try again.',
        ),
      );
    }
  }

  Future<DevicePairingResult> approve({
    required String input,
    required AuthState auth,
  }) async {
    final code = parsePairingCode(input);
    if (code == null) {
      return const DevicePairingResult(
        DevicePairingStatus.invalidCode,
        'That QR code or pairing code is not valid for AniDash Go.',
      );
    }
    if (!auth.isAniListAuthenticated && !auth.isMalAuthenticated) {
      return const DevicePairingResult(
        DevicePairingStatus.noAccount,
        'Connect AniList or MyAnimeList in AniDash before pairing a device.',
      );
    }

    final accounts = await _accountsFor(auth);
    final package = await PackageInfo.fromPlatform();
    final clientMetadata = await _clientMetadata(package);
    final sourceKind =
        sharedPrefs.getString('selected_playback_source_kind') ?? 'native';
    final nativeSource = sharedPrefs.getString('selected_provider');
    final extensionSource = sharedPrefs.getString('active_anime_source_id');
    final effectiveSource =
        sourceKind == 'extension' ? extensionSource : nativeSource;
    final isHindiSource =
        effectiveSource?.toLowerCase().contains('hindi') == true;
    Map<String, dynamic> preferenceSubset(String key, List<String> allowed) {
      final raw = sharedPrefs.getString(key);
      if (raw == null || raw.isEmpty) return const {};
      try {
        final decoded = (jsonDecode(raw) as Map).cast<String, dynamic>();
        return {
          for (final name in allowed)
            if (decoded[name] != null) name: decoded[name],
        };
      } catch (_) {
        return const {};
      }
    }

    final body = jsonEncode({
      'code': code,
      'accounts': accounts,
      'sync': {
        'schemaVersion': 1,
        'preferences': {
          'playbackSourceKind': sourceKind,
          'nativeSource': nativeSource,
          'hindiSource': isHindiSource ? effectiveSource : null,
          'hindiSourceEnabled': isHindiSource,
          'player': preferenceSubset('player_settings_data', [
            'preferredAudioLanguage',
            'defaultQuality',
            'autoEnableSubtitles',
          ]),
        },
        'capabilities': [
          'tracker_lists',
          'watch_progress',
          'source_preference',
          'audio_language',
          'hindi_source_state',
        ],
      },
      'client': clientMetadata,
    });

    try {
      final response = await _client
          .post(
            Uri.parse(AniDashGo.pairingApprovalUrl),
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200 || response.statusCode == 201) {
        await _captureManagementCredential(response.body);
        return const DevicePairingResult(
          DevicePairingStatus.success,
          'AniDash Go is connected. Return to the browser to continue.',
        );
      }
      if (response.statusCode == 404 || response.statusCode == 405) {
        return const DevicePairingResult(
          DevicePairingStatus.websiteNotReady,
          'Device pairing is ready in the app, but it is not enabled on the AniDash Go website yet.',
        );
      }
      if (response.statusCode == 400 || response.statusCode == 409) {
        return const DevicePairingResult(
          DevicePairingStatus.expiredCode,
          'This pairing code is invalid, expired, or has already been used.',
        );
      }
      return const DevicePairingResult(
        DevicePairingStatus.serverError,
        'AniDash Go could not approve this device. Please try again.',
      );
    } on TimeoutException {
      return const DevicePairingResult(
        DevicePairingStatus.networkError,
        'The pairing request timed out. Check your connection and try again.',
      );
    } catch (_) {
      return const DevicePairingResult(
        DevicePairingStatus.networkError,
        'AniDash Go could not be reached. Check your connection and try again.',
      );
    }
  }

  Future<Map<String, dynamic>> _accountsFor(AuthState auth) async {
    final accounts = <String, dynamic>{};
    if (auth.isAniListAuthenticated) {
      accounts['anilist'] = {
        'accessToken': auth.anilistAccessToken,
        'userId': auth.anilistUser?.id,
        'username': auth.anilistUser?.name,
      };
    }
    if (auth.isMalAuthenticated) {
      accounts['myanimelist'] = {
        'accessToken': auth.malAccessToken,
        'refreshToken': await _secureStorage.read(key: 'mal-refresh-token'),
        'userId': auth.malUser?.id,
        'username': auth.malUser?.name,
      };
    }

    return accounts;
  }

  Future<Map<String, dynamic>> _clientMetadata(PackageInfo package) async {
    final metadata = <String, dynamic>{
      'platform': defaultTargetPlatform.name,
      'appVersion': package.version,
      'buildNumber': package.buildNumber,
    };
    try {
      final android = await DeviceInfoPlugin().androidInfo;
      metadata.addAll({
        'manufacturer': android.manufacturer,
        'model': android.model,
        'androidVersion': android.version.release,
        'sdkInt': android.version.sdkInt,
      });
    } catch (_) {
      // Package/version metadata is still enough on unsupported test platforms.
    }
    return metadata;
  }

  Future<void> _captureManagementCredential(String responseBody) async {
    try {
      final decoded = jsonDecode(responseBody) as Map<String, dynamic>;
      final credential =
          (decoded['deviceManagement'] as Map?)?.cast<String, dynamic>();
      final token = credential?['token']?.toString();
      final expiresAt = credential?['expiresAt']?.toString();
      if (token == null || !RegExp(r'^[0-9a-f]{64}$').hasMatch(token)) return;
      await _secureStorage.write(key: _managementTokenKey, value: token);
      if (expiresAt != null) {
        await _secureStorage.write(key: _managementExpiryKey, value: expiresAt);
      }
    } catch (_) {
      // A successful pairing remains valid even if an older backend omitted it.
    }
  }

  Future<String?> _managementToken(AuthState auth) async {
    var token = await _secureStorage.read(key: _managementTokenKey);
    final expiry = DateTime.tryParse(
      await _secureStorage.read(key: _managementExpiryKey) ?? '',
    );
    if (token != null &&
        RegExp(r'^[0-9a-f]{64}$').hasMatch(token) &&
        (expiry == null || expiry.isAfter(DateTime.now()))) {
      return token;
    }
    await _clearManagementCredential();
    if (!auth.isAniListAuthenticated && !auth.isMalAuthenticated) return null;
    try {
      final package = await PackageInfo.fromPlatform();
      final response = await _client
          .post(
            Uri.parse(AniDashGo.deviceManagementUrl),
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'accounts': await _accountsFor(auth),
              'client': await _clientMetadata(package),
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) return null;
      await _captureManagementCredential(response.body);
      token = await _secureStorage.read(key: _managementTokenKey);
      return token != null && RegExp(r'^[0-9a-f]{64}$').hasMatch(token)
          ? token
          : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _clearManagementCredential() async {
    await _secureStorage.delete(key: _managementTokenKey);
    await _secureStorage.delete(key: _managementExpiryKey);
  }

  Future<List<PairedDeviceRecord>> fetchPairedDevices(AuthState auth) async {
    final token = await _managementToken(auth);
    if (token == null) return loadPairedDevices();
    try {
      final response = await _client
          .get(
            Uri.parse(AniDashGo.pairedDevicesUrl),
            headers: {
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 401) {
        await _clearManagementCredential();
        return loadPairedDevices();
      }
      if (response.statusCode != 200) return loadPairedDevices();
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final devices =
          (decoded['devices'] as List? ?? const [])
              .whereType<Map>()
              .map(
                (item) =>
                    PairedDeviceRecord.fromServer(item.cast<String, dynamic>()),
              )
              .where((device) => device.id.isNotEmpty)
              .toList();
      devices.sort((a, b) => b.lastConfirmedAt.compareTo(a.lastConfirmedAt));
      return devices;
    } catch (_) {
      return loadPairedDevices();
    }
  }

  Future<bool> revokePairedDevice(
    PairedDeviceRecord device,
    AuthState auth,
  ) async {
    if (!device.isRemote) {
      await forgetPairedDevice(device.id);
      return true;
    }
    final token = await _managementToken(auth);
    if (token == null) return false;
    try {
      final response = await _client
          .delete(
            Uri.parse('${AniDashGo.pairedDevicesUrl}/${device.id}'),
            headers: {
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 15));
      return response.statusCode == 200 || response.statusCode == 404;
    } catch (_) {
      return false;
    }
  }

  Future<void> deny(String input) async {
    final code = parsePairingCode(input);
    if (code == null) return;
    try {
      await _client
          .post(
            Uri.parse(AniDashGo.pairingApprovalUrl),
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({'code': code, 'approved': false}),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // Denial is best-effort. The server also expires every code in 5 minutes.
    }
  }

  List<PairedDeviceRecord> loadPairedDevices() {
    final raw = sharedPrefs.getString(_deviceHistoryKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      final records =
          decoded
              .whereType<Map>()
              .map(
                (item) =>
                    PairedDeviceRecord.fromJson(item.cast<String, dynamic>()),
              )
              .toList()
            ..sort((a, b) => b.connectedAt.compareTo(a.connectedAt));
      return records;
    } catch (_) {
      return const [];
    }
  }

  Future<void> rememberPairedDevice({
    required PendingPairingDevice device,
    required DateTime scannedAt,
  }) async {
    final now = DateTime.now();
    final records = loadPairedDevices();
    final duplicateIndex = records.indexWhere(
      (item) =>
          item.name == device.name &&
          item.browser == device.browser &&
          item.operatingSystem == device.operatingSystem,
    );
    final record = PairedDeviceRecord(
      id: '${now.microsecondsSinceEpoch}',
      name: device.name,
      browser: device.browser,
      operatingSystem: device.operatingSystem,
      location: device.location,
      scannedAt: scannedAt,
      connectedAt: now,
      lastConfirmedAt: now,
    );
    if (duplicateIndex >= 0) records.removeAt(duplicateIndex);
    records.insert(0, record);
    await sharedPrefs.setString(
      _deviceHistoryKey,
      jsonEncode(records.take(20).map((item) => item.toJson()).toList()),
    );
  }

  Future<void> forgetPairedDevice(String id) async {
    final records = loadPairedDevices().where((item) => item.id != id).toList();
    await sharedPrefs.setString(
      _deviceHistoryKey,
      jsonEncode(records.map((item) => item.toJson()).toList()),
    );
  }
}
