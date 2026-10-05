import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:encrypt/encrypt.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:path/path.dart' as p;
import 'package:ani_dash/core/utils/app_logger.dart';
import 'package:ani_dash/features/downloads/model/download_item.dart';
import 'package:ani_dash/features/downloads/model/download_status.dart';
import 'package:ani_dash/features/downloads/view_model/downloads_notifier.dart';
import 'package:ani_dash/core/models/settings/download_settings_model.dart';
import 'package:ani_dash/shared/providers/permissions_provider.dart';
import 'package:ani_dash/shared/providers/settings/download_settings_notifier.dart';
import 'package:ani_dash/core/services/notification_service.dart';
import 'package:ani_dash/storage_provider.dart';

class DownloadService {
  final Ref ref;
  final DownloadsNotifier _notifier;
  int get _maxConcurrent => _settings.parallelDownloads.clamp(1, 10);

  final List<DownloadItem> _queue = [];
  final Map<String, Isolate> _isolates = {};
  final Map<String, SendPort> _ports = {};
  final Map<String, ReceivePort> _receivePorts = {};
  final Map<String, StreamSubscription<dynamic>> _receiveSubscriptions = {};
  final Map<String, DownloadItem> _waitingForWifi = {};
  final Map<String, DateTime> _lastProgressNotification = {};
  final Map<String, int> _lastNotifiedPercent = {};
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _networkRetryTimer;

  DownloadService(this.ref, this._notifier) {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      r,
    ) async {
      if (r.contains(ConnectivityResult.none) || _waitingForWifi.isEmpty) {
        return;
      }
      if (_settings.wifiOnly && !r.contains(ConnectivityResult.wifi)) return;
      final pending = _waitingForWifi.values.toList(growable: false);
      _waitingForWifi.clear();
      for (final item in pending) {
        unawaited(startDownload(item));
      }
    });
    ref.onDispose(dispose);
  }

  DownloadSettingsModel get _settings => ref.read(downloadSettingsProvider);

  void _scheduleNetworkRetry() {
    _networkRetryTimer ??= Timer(const Duration(seconds: 10), () async {
      _networkRetryTimer = null;
      if (_waitingForWifi.isEmpty) return;
      final connectivity = await Connectivity().checkConnectivity();
      if (_settings.wifiOnly &&
          !connectivity.contains(ConnectivityResult.wifi)) {
        _scheduleNetworkRetry();
        return;
      }
      if (connectivity.contains(ConnectivityResult.none)) {
        _scheduleNetworkRetry();
        return;
      }
      final pending = _waitingForWifi.values.toList(growable: false);
      _waitingForWifi.clear();
      for (final pendingItem in pending) {
        unawaited(startDownload(pendingItem));
      }
    });
  }

  Future<void> startDownload(DownloadItem item) async {
    List<ConnectivityResult>? connectivity;
    try {
      connectivity = await Connectivity().checkConnectivity();
    } catch (_) {}
    if (_settings.wifiOnly) {
      try {
        if (connectivity != null &&
            !connectivity.contains(ConnectivityResult.wifi)) {
          _waitingForWifi[item.id] = item;
          _notifier.updateDownloadState(
            item.copyWith(
              state: DownloadStatus.queued,
              error: 'Waiting for Wi-Fi (Wi-Fi only enabled)',
            ),
          );
          return;
        }
      } catch (_) {}
    }

    // A connectivity-check host can be blocked by DNS, privacy tools, or a
    // captive network even when the actual video CDN is reachable. Only hold
    // the task when Android reports no network; otherwise let the real request
    // run and use its retry policy as the source of truth.
    if (connectivity?.contains(ConnectivityResult.none) == true) {
      _waitingForWifi[item.id] = item;
      _notifier.updateDownloadState(
        item.copyWith(
          state: DownloadStatus.queued,
          error: 'Waiting for an active internet connection',
        ),
      );
      _scheduleNetworkRetry();
      return;
    }

    if (!await ref
        .read(permissionsProvider.notifier)
        .requestStoragePermission()) {
      return _fail(item, 'Storage permission denied');
    }

    String basePath;
    if (_settings.useCustomPath && _settings.customDownloadPath != null) {
      final customDir = Directory(_settings.customDownloadPath!);
      if (!customDir.existsSync()) {
        try {
          customDir.createSync(recursive: true);
        } catch (_) {}
      }
      final fallback = await StorageProvider.getDefaultDirectory();
      if (!customDir.existsSync() && fallback == null) {
        return _fail(item, 'No writable download directory is available');
      }
      basePath = customDir.existsSync() ? customDir.path : fallback!.path;
    } else {
      final directory = await StorageProvider.getDefaultDirectory();
      if (directory == null) {
        return _fail(item, 'No writable download directory is available');
      }
      basePath = directory.path;
    }

    final itemPath = item.filePath;
    String finalPath;
    if (p.isAbsolute(itemPath)) {
      finalPath = itemPath;
    } else {
      final cleanTitle =
          item.animeTitle.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
      String targetDir;
      if (_settings.folderStructure == 'Anime/Episode') {
        targetDir = p.join(
          basePath,
          cleanTitle,
          'Episode ${item.episodeNumber}',
        );
      } else if (_settings.folderStructure == 'Anime') {
        targetDir = p.join(basePath, cleanTitle);
      } else {
        targetDir = basePath;
      }
      try {
        Directory(targetDir).createSync(recursive: true);
      } catch (_) {}
      finalPath = p.join(targetDir, p.basename(itemPath));
    }

    final queuedItem = item.copyWith(
      state: DownloadStatus.queued,
      filePath: finalPath,
      clearError: true,
    );

    _notifier.updateDownloadState(queuedItem);
    if (!_queue.any((queued) => queued.id == queuedItem.id) &&
        !_isolates.containsKey(queuedItem.id)) {
      _queue.add(queuedItem);
    }
    _processQueue();
  }

  void pauseDownload(DownloadItem item) {
    _waitingForWifi.remove(item.id);
    if (_isolates.containsKey(item.id)) {
      _ports[item.id]?.send('cancel');
      _isolates[item.id]?.kill(priority: Isolate.immediate);
      _cleanup(item.id);
    } else {
      _queue.removeWhere((i) => i.id == item.id);
    }
    NotificationService().cancelNotification(item.id.hashCode);
    _notifier.updateDownloadState(item.copyWith(state: DownloadStatus.paused));
  }

  void resumeDownload(DownloadItem item) => startDownload(item);

  Future<void> deleteDownload(DownloadItem item) async {
    pauseDownload(item);
    try {
      final file = File(item.filePath);
      if (await file.exists()) await file.delete();

      if (await file.parent.exists() && file.parent.listSync().isEmpty) {
        await file.parent.delete();
      }
      _notifier.removeDownload(item);
    } catch (e) {
      AppLogger.e('Delete failed: $e');
    }
  }

  void _processQueue() {
    if (_isolates.length >= _maxConcurrent || _queue.isEmpty) return;
    _spawnIsolate(_queue.removeAt(0));
  }

  Future<void> _spawnIsolate(DownloadItem item) async {
    final receivePort = ReceivePort();
    _receivePorts[item.id] = receivePort;
    _notifier.updateDownloadState(
      item.copyWith(state: DownloadStatus.downloading, clearError: true),
    );

    try {
      final isolate = await Isolate.spawn(
        _downloadWorker,
        _TaskConfig(item, _settings, receivePort.sendPort),
      );

      _isolates[item.id] = isolate;
      _processQueue();

      _receiveSubscriptions[item.id] = receivePort.listen((msg) {
        if (msg is SendPort) {
          _ports[item.id] = msg;
        } else if (msg is DownloadItem) {
          _notifier.updateDownloadState(msg);
          final notifId = item.id.hashCode;
          if (msg.state == DownloadStatus.downloaded) {
            NotificationService().showDownloadCompletedNotification(
              id: notifId,
              animeTitle: msg.animeTitle,
              episodeNumber: msg.episodeNumber,
            );
            _cleanup(item.id);
          } else if (msg.state == DownloadStatus.downloading) {
            final now = DateTime.now();
            final percent = (msg.progressPercentage * 100).round();
            final lastAt = _lastProgressNotification[item.id];
            if (_lastNotifiedPercent[item.id] != percent &&
                (lastAt == null || now.difference(lastAt).inSeconds >= 1)) {
              _lastProgressNotification[item.id] = now;
              _lastNotifiedPercent[item.id] = percent;
              NotificationService().showDownloadProgressNotification(
                id: notifId,
                animeTitle: msg.animeTitle,
                episodeNumber: msg.episodeNumber,
                progress: msg.progressPercentage,
              );
            }
          }
        } else if (msg is String) {
          if (msg.startsWith('err:')) _fail(item, msg.substring(4));
          if (msg.startsWith('log:')) {
            AppLogger.d('[Isolate] ${msg.substring(4)}');
          }
        }
      });
    } catch (e) {
      _fail(item, 'Isolate Spawn Error: $e');
    }
  }

  void _cleanup(String id) {
    _isolates.remove(id);
    _ports.remove(id);
    _receiveSubscriptions.remove(id)?.cancel();
    _receivePorts.remove(id)?.close();
    _lastProgressNotification.remove(id);
    _lastNotifiedPercent.remove(id);
    _processQueue();
  }

  void dispose() {
    _networkRetryTimer?.cancel();
    _connectivitySubscription?.cancel();
    for (final isolate in _isolates.values) {
      isolate.kill(priority: Isolate.immediate);
    }
    for (final subscription in _receiveSubscriptions.values) {
      subscription.cancel();
    }
    for (final port in _receivePorts.values) {
      port.close();
    }
    _isolates.clear();
    _ports.clear();
    _receiveSubscriptions.clear();
    _receivePorts.clear();
  }

  void _fail(DownloadItem item, String reason) {
    AppLogger.e(reason);
    NotificationService().cancelNotification(item.id.hashCode);
    _notifier.updateDownloadState(
      item.copyWith(state: DownloadStatus.failed, error: reason),
    );
    _cleanup(item.id);
  }
}

class _TaskConfig {
  final DownloadItem item;
  final DownloadSettingsModel settings;
  final SendPort port;
  _TaskConfig(this.item, this.settings, this.port);
}

Future<void> _downloadWorker(_TaskConfig task) async {
  final cmdPort = ReceivePort();
  task.port.send(cmdPort.sendPort);

  bool isCancelled = false;
  cmdPort.listen((msg) {
    if (msg == 'cancel') isCancelled = true;
  });

  final ioClient =
      HttpClient()
        ..maxConnectionsPerHost = 12
        ..connectionTimeout = const Duration(seconds: 15)
        ..idleTimeout = const Duration(seconds: 30);
  final client = IOClient(ioClient);
  final item = task.item;
  final isM3U8 = item.isM3U8;

  task.port.send('log: Processing as ${isM3U8 ? "M3U8" : "File"}');

  try {
    DownloadItem? result;
    Object? lastError;
    for (var attempt = 1; attempt <= 3 && !isCancelled; attempt++) {
      try {
        result =
            isM3U8
                ? await _processM3U8(task, client, () => isCancelled)
                : await _processFile(task, client, () => isCancelled);
        break;
      } catch (error) {
        lastError = error;
        task.port.send('log:Download attempt $attempt failed: $error');
        if (attempt < 3) await Future.delayed(Duration(seconds: attempt));
      }
    }
    if (result == null) throw lastError ?? Exception('Download failed');

    if (!isCancelled) {
      result = await _downloadSubtitleSidecars(result, client);
    }

    if (!isCancelled) task.port.send(result);
  } catch (e) {
    if (!isCancelled) task.port.send('err:$e');
  } finally {
    client.close();
    Isolate.exit();
  }
}

Future<DownloadItem> _downloadSubtitleSidecars(
  DownloadItem item,
  http.Client client,
) async {
  if (item.subtitles == null || item.subtitles!.isEmpty) return item;
  final localized = <dynamic>[];
  var index = 0;
  var failures = 0;
  for (final raw in item.subtitles!) {
    try {
      final map = Map<String, dynamic>.from(
        raw is String ? jsonDecode(raw) as Map : raw as Map,
      );
      final url = map['url']?.toString();
      if (url == null || url.isEmpty) continue;
      final bytes = await _fetch(url, item.headers, client);
      if (bytes == null) {
        localized.add(raw);
        failures++;
        continue;
      }
      final uri = Uri.tryParse(url);
      final remoteExt = uri == null ? '' : p.extension(uri.path).toLowerCase();
      final ext =
          const {'.vtt', '.srt', '.ass', '.ssa'}.contains(remoteExt)
              ? remoteExt
              : '.vtt';
      final lang = (map['lang']?.toString() ?? 'subtitle').replaceAll(
        RegExp(r'[^a-zA-Z0-9_-]'),
        '_',
      );
      final sidecar = File(
        '${p.withoutExtension(item.filePath)}.$lang.$index$ext',
      );
      await sidecar.writeAsBytes(bytes, flush: true);
      map['url'] = sidecar.uri.toString();
      localized.add(jsonEncode(map));
      index++;
    } catch (_) {
      localized.add(raw);
      failures++;
    }
  }
  return item.copyWith(
    subtitles: localized,
    error:
        failures == 0
            ? null
            : '$failures offline subtitle file(s) could not be downloaded',
  );
}

Future<DownloadItem> _processFile(
  _TaskConfig task,
  http.Client client,
  bool Function() isCancelled,
) async {
  final file = File(task.item.filePath);
  await file.parent.create(recursive: true);

  final existing = await file.exists() ? await file.length() : 0;
  final req = http.Request('GET', Uri.parse(task.item.downloadUrl));
  req.headers.addAll(task.item.headers.cast());
  if (existing > 0) req.headers['Range'] = 'bytes=$existing-';

  final res = await client.send(req);
  if (res.statusCode >= 400) throw Exception('HTTP ${res.statusCode}');

  int total = existing;
  if (res.statusCode == 200) {
    total = int.tryParse(res.headers['content-length'] ?? '0') ?? 0;
  } else if (res.statusCode == 206) {
    final range = res.headers['content-range']?.split('/').last;
    if (range != null && range != '*') total = int.parse(range);
  }

  final canResume = existing > 0 && res.statusCode == 206;
  final sink = file.openWrite(
    mode: canResume ? FileMode.append : FileMode.write,
  );
  int current = canResume ? existing : 0;
  DateTime lastLog = DateTime.now();

  final throttler = _Throttler(task.settings.speedLimitKBps);

  try {
    await for (final chunk in res.stream.timeout(const Duration(seconds: 30))) {
      if (isCancelled()) throw Exception("Cancelled");
      sink.add(chunk);
      current += chunk.length;
      await throttler.throttle(chunk.length);

      if (DateTime.now().difference(lastLog).inMilliseconds > 500) {
        task.port.send(
          task.item.copyWith(
            state: DownloadStatus.downloading,
            size: total,
            progress: current,
          ),
        );
        lastLog = DateTime.now();
      }
    }
  } finally {
    await sink.close();
  }

  return task.item.copyWith(
    state: DownloadStatus.downloaded,
    size: current,
    progress: current,
  );
}

Future<DownloadItem> _processM3U8(
  _TaskConfig task,
  http.Client client,
  bool Function() isCancelled,
) async {
  final tempDir = Directory(
    '${p.dirname(task.item.filePath)}/.temp_${task.item.id.hashCode}',
  );
  await tempDir.create(recursive: true);

  final segments = await _parsePlaylist(
    task.item.downloadUrl,
    task.item.headers,
    client,
    task.port,
  );
  if (segments.isEmpty) throw Exception("Empty playlist");

  var currentItem = task.item.copyWith(
    state: DownloadStatus.downloading,
    totalSegments: segments.length,
    progress: 0,
  );
  task.port.send(currentItem);

  // HLS segments are small. Keep enough requests in flight to saturate fast
  // Wi-Fi while capping concurrency to avoid provider throttling.
  // Six concurrent segments saturate typical mobile/Wi-Fi links without
  // provoking CDN throttling or starving the active video player.
  const workerCount = 8;
  int completed = 0;
  int downloadedBytesTotal = 0;
  int? estimatedTotalBytes;
  DateTime lastLog = DateTime.now();

  for (var s in segments) {
    final f = File(p.join(tempDir.path, '${s.index}.ts'));
    if (f.existsSync()) {
      completed++;
      downloadedBytesTotal += f.lengthSync();
    }
  }

  final throttler = _Throttler(task.settings.speedLimitKBps);

  var nextSegment = 0;
  Future<void> worker() async {
    while (!isCancelled()) {
      final index = nextSegment++;
      if (index >= segments.length) return;
      final seg = segments[index];
      final file = File(p.join(tempDir.path, '${seg.index}.ts'));
      if (await file.exists()) continue;

      final bytes = await _fetch(seg.url, task.item.headers, client);
      if (bytes == null) continue;
      final data =
          seg.key != null
              ? _decrypt(bytes, seg.key!, seg.iv, seg.index)
              : bytes;
      await file.writeAsBytes(data);
      completed++;
      downloadedBytesTotal += data.length;
      await throttler.throttle(data.length);

      if (DateTime.now().difference(lastLog).inMilliseconds > 300) {
        // Do not invent a total before there is a useful sample. Once enough
        // segments are present, expose a clearly approximate total; completion
        // replaces it with the exact merged-file size.
        final sampleThreshold = (segments.length * 0.1).ceil().clamp(5, 12);
        if (completed >= sampleThreshold) {
          estimatedTotalBytes =
              (downloadedBytesTotal / completed * segments.length).round();
          currentItem = currentItem.copyWith(size: estimatedTotalBytes);
        }
        task.port.send(
          currentItem.copyWith(
            progress: completed,
            downloadedBytes: downloadedBytesTotal,
          ),
        );
        lastLog = DateTime.now();
      }
    }
  }

  await Future.wait(List.generate(workerCount, (_) => worker()));

  if (isCancelled()) throw Exception("Cancelled");

  // Never mark a partial HLS file as completed. Retry any failed segments
  // with exponential backoff to handle temporary network disconnections/travel drops.
  for (int attempt = 0; attempt < 3; attempt++) {
    final missingSegments = <_Segment>[];
    for (final segment in segments) {
      if (!await File(p.join(tempDir.path, '${segment.index}.ts')).exists()) {
        missingSegments.add(segment);
      }
    }
    if (missingSegments.isEmpty) break;
    if (isCancelled()) throw Exception("Cancelled");

    if (attempt > 0) {
      task.port.send(
        'log:Retrying ${missingSegments.length} missing segments (attempt $attempt)...',
      );
      await Future.delayed(Duration(seconds: 1 << attempt));
    }

    for (final segment in missingSegments) {
      if (isCancelled()) throw Exception("Cancelled");
      final file = File(p.join(tempDir.path, '${segment.index}.ts'));
      if (await file.exists()) continue;
      final bytes = await _fetch(segment.url, task.item.headers, client);
      if (bytes != null) {
        final data =
            segment.key != null
                ? _decrypt(bytes, segment.key!, segment.iv, segment.index)
                : bytes;
        await file.writeAsBytes(data, flush: true);
        completed++;
        downloadedBytesTotal += data.length;
      }
    }
  }

  final missing = <int>[];
  for (final segment in segments) {
    if (!await File(p.join(tempDir.path, '${segment.index}.ts')).exists()) {
      missing.add(segment.index);
    }
  }
  if (missing.isNotEmpty) {
    throw Exception(
      'Download incomplete: ${missing.length} of ${segments.length} segments failed after retries',
    );
  }

  final output = File(task.item.filePath);
  final sink = output.openWrite();
  int totalSize = 0;

  for (var s in segments) {
    final f = File(p.join(tempDir.path, '${s.index}.ts'));
    if (await f.exists()) {
      totalSize += await f.length();
      await sink.addStream(f.openRead());
    }
  }
  await sink.close();
  await tempDir.delete(recursive: true);

  return currentItem.copyWith(
    state: DownloadStatus.downloaded,
    size: totalSize,
    downloadedBytes: totalSize,
    progress: segments.length,
    durationSeconds: segments.fold<int>(
      0,
      (total, segment) => total + segment.duration.ceil(),
    ),
  );
}

Future<List<_Segment>> _parsePlaylist(
  String url,
  Map headers,
  http.Client client,
  SendPort port,
) async {
  final bytes = await _fetch(url, headers, client);
  if (bytes == null) throw Exception("Failed to load m3u8");

  final lines = LineSplitter.split(utf8.decode(bytes)).toList();
  final baseUri = Uri.parse(url);
  final segments = <_Segment>[];

  if (lines.any((l) => l.contains('#EXT-X-STREAM-INF'))) {
    String? bestVariant;
    var bestBandwidth = -1;
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].startsWith('#EXT-X-STREAM-INF') && i + 1 < lines.length) {
        final next = lines[i + 1].trim();
        if (next.isNotEmpty && !next.startsWith('#')) {
          final bandwidth =
              int.tryParse(
                RegExp(r'BANDWIDTH=(\d+)').firstMatch(lines[i])?.group(1) ?? '',
              ) ??
              0;
          if (bandwidth > bestBandwidth) {
            bestBandwidth = bandwidth;
            bestVariant = next;
          }
        }
      }
    }
    if (bestVariant != null) {
      return _parsePlaylist(
        baseUri.resolve(bestVariant).toString(),
        headers,
        client,
        port,
      );
    }
  }

  Uint8List? key, iv;
  var pendingDuration = 0.0;
  for (final line in lines) {
    final trim = line.trim();
    if (trim.isEmpty) continue;

    if (trim.startsWith('#EXTINF:')) {
      pendingDuration =
          double.tryParse(trim.substring(8).split(',').first) ?? 0.0;
    } else if (trim.startsWith('#EXT-X-KEY')) {
      final keyUri = RegExp(r'URI="([^"]+)"').firstMatch(trim)?.group(1);
      final ivHex = RegExp(r'IV=0x([0-9A-Fa-f]+)').firstMatch(trim)?.group(1);

      if (keyUri != null) {
        key = await _fetch(baseUri.resolve(keyUri).toString(), headers, client);
      }
      if (ivHex != null) iv = _hexToBytes(ivHex);
    } else if (!trim.startsWith('#')) {
      segments.add(
        _Segment(
          baseUri.resolve(trim).toString(),
          key,
          iv,
          segments.length,
          pendingDuration,
        ),
      );
      pendingDuration = 0;
    }
  }

  port.send('log:Parsed ${segments.length} segments');
  return segments;
}

Future<Uint8List?> _fetch(String url, Map headers, http.Client client) async {
  for (int i = 0; i < 5; i++) {
    try {
      final res = await client
          .get(Uri.parse(url), headers: headers.cast())
          .timeout(const Duration(seconds: 25));
      if (res.statusCode == 200 || res.statusCode == 206) {
        return res.bodyBytes;
      }
    } catch (_) {}
    if (i < 4) {
      await Future.delayed(Duration(milliseconds: 250 * (i + 1)));
    }
  }
  return null;
}

Uint8List _decrypt(Uint8List bytes, Uint8List key, Uint8List? iv, int seq) {
  final effectiveIV = iv ?? _seqToIV(seq);
  final encrypter = Encrypter(AES(Key(key), mode: AESMode.cbc));
  return Uint8List.fromList(
    encrypter.decryptBytes(Encrypted(bytes), iv: IV(effectiveIV)),
  );
}

Uint8List _seqToIV(int seq) {
  final iv = Uint8List(16);
  for (int i = 15; i >= 0; i--) {
    iv[i] = (seq >> (8 * (15 - i))) & 0xFF;
  }
  return iv;
}

Uint8List _hexToBytes(String hex) {
  hex = hex.replaceAll('0x', '');
  if (hex.length % 2 != 0) hex = '0$hex';
  return Uint8List.fromList(
    List.generate(
      hex.length ~/ 2,
      (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16),
    ),
  );
}

class _Segment {
  final String url;
  final Uint8List? key;
  final Uint8List? iv;
  final int index;
  final double duration;
  _Segment(this.url, this.key, this.iv, this.index, this.duration);
}

class _Throttler {
  final int limitKBps;
  int _bytesTransferred = 0;
  final DateTime _startTime = DateTime.now();

  _Throttler(this.limitKBps);

  Future<void> throttle(int newBytes) async {
    if (limitKBps <= 0) return;

    _bytesTransferred += newBytes;
    final elapsedMs = DateTime.now().difference(_startTime).inMilliseconds;
    if (elapsedMs == 0) return;

    final expectedMs = (_bytesTransferred / (limitKBps * 1024)) * 1000;

    if (expectedMs > elapsedMs) {
      final waitMs = (expectedMs - elapsedMs).toInt();
      if (waitMs > 10) {
        await Future.delayed(Duration(milliseconds: waitMs));
      }
    }
  }
}
