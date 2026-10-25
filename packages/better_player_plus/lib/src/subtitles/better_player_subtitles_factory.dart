import 'dart:convert';
import 'dart:io';
import 'package:better_player_plus/better_player_plus.dart';
import 'package:better_player_plus/src/core/better_player_utils.dart';

class BetterPlayerSubtitlesFactory {
  const BetterPlayerSubtitlesFactory._();

  static Future<List<BetterPlayerSubtitle>> parseSubtitles(BetterPlayerSubtitlesSource source) async {
    switch (source.type) {
      case BetterPlayerSubtitlesSourceType.file:
        return _parseSubtitlesFromFile(source);
      case BetterPlayerSubtitlesSourceType.network:
        return _parseSubtitlesFromNetwork(source);
      case BetterPlayerSubtitlesSourceType.memory:
        return _parseSubtitlesFromMemory(source);
      default:
        return [];
    }
  }

  static Future<List<BetterPlayerSubtitle>> _parseSubtitlesFromFile(BetterPlayerSubtitlesSource source) async {
    try {
      final List<BetterPlayerSubtitle> subtitles = [];
      for (final String? url in source.urls!) {
        if (url == null || url.isEmpty) continue;
        final cleanPath = url.startsWith('file://')
            ? (Uri.tryParse(url)?.toFilePath() ?? url.replaceFirst('file://', ''))
            : url;
        final file = File(cleanPath);
        if (file.existsSync()) {
          final String fileContent = await file.readAsString();
          final subtitlesCache = _parseString(fileContent);
          subtitles.addAll(subtitlesCache);
        } else {
          BetterPlayerUtils.log("$cleanPath doesn't exist!");
        }
      }
      return subtitles;
    } on Exception catch (exception) {
      BetterPlayerUtils.log('Failed to read subtitles from file: $exception');
    }
    return [];
  }

  static Future<List<BetterPlayerSubtitle>> _parseSubtitlesFromNetwork(BetterPlayerSubtitlesSource source) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 15);
      final List<BetterPlayerSubtitle> subtitles = [];
      for (final String? url in source.urls!) {
        if (url == null || url.isEmpty) continue;
        final request = await client.getUrl(Uri.parse(url));
        source.headers?.forEach((key, value) {
          request.headers.set(key, value);
        });
        final response = await request.close();
        if (response.statusCode != 200) {
          BetterPlayerUtils.log('Failed to fetch subtitles: HTTP ${response.statusCode}');
          continue;
        }
        final data = await response.transform(const Utf8Decoder(allowMalformed: true)).join();
        final cacheList = _parseString(data);
        subtitles.addAll(cacheList);
      }
      client.close();

      BetterPlayerUtils.log('Parsed total subtitles: ${subtitles.length}');
      return subtitles;
    } catch (exception) {
      BetterPlayerUtils.log('Failed to read subtitles from network: $exception');
    }
    return [];
  }

  static List<BetterPlayerSubtitle> _parseSubtitlesFromMemory(BetterPlayerSubtitlesSource source) {
    try {
      return _parseString(source.content!);
    } catch (exception) {
      BetterPlayerUtils.log('Failed to read subtitles from memory: $exception');
    }
    return [];
  }

  static List<BetterPlayerSubtitle> _parseString(String value) {
    final normalized = value.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
    if (normalized.isEmpty) {
      return [];
    }

    final List<BetterPlayerSubtitle> subtitlesObj = [];

    // Check if this is an Advanced SubStation Alpha (.ass / .ssa) file
    final lower = normalized.toLowerCase();
    if (lower.contains('[events]') || lower.contains('dialogue:')) {
      final lines = normalized.split('\n');
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.toLowerCase().startsWith('dialogue:')) {
          final subtitle = BetterPlayerSubtitle.fromAss(trimmed);
          if (subtitle.start != null &&
              subtitle.end != null &&
              subtitle.texts != null &&
              subtitle.texts!.isNotEmpty) {
            subtitlesObj.add(subtitle);
          }
        }
      }
      if (subtitlesObj.isNotEmpty) {
        return subtitlesObj;
      }
    }

    final List<String> components = normalized.split(RegExp(r'\n\s*\n'));

    // Skip parsing files with no cues
    if (components.isEmpty) {
      return [];
    }

    final bool isWebVTT = normalized.startsWith('WEBVTT') || normalized.contains('-->');
    for (final component in components) {
      final trimmed = component.trim();
      if (trimmed.isEmpty || trimmed == 'WEBVTT' || trimmed.startsWith('WEBVTT\n') || trimmed.startsWith('NOTE')) {
        continue;
      }
      final subtitle = BetterPlayerSubtitle(trimmed, isWebVTT);
      if (subtitle.start != null && subtitle.end != null && subtitle.texts != null && subtitle.texts!.isNotEmpty) {
        subtitlesObj.add(subtitle);
      }
    }

    return subtitlesObj;
  }
}
