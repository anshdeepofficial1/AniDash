import 'package:ani_dash/core/network/http_client.dart';
import 'package:ani_dash/core/utils/app_logger.dart';

Future<List<Map<String, dynamic>>> extractQualities(
  String url,
  Map<String, String>? headers,
  bool isM3U8,
) async {
  if (!isM3U8) {
    return [
      {'quality': 'Default', 'url': url},
    ];
  }

  final effectiveHeaders = <String, String>{
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
    ...?headers,
  };

  if (!effectiveHeaders.containsKey('Referer')) {
    try {
      final uri = Uri.parse(url);
      if (uri.scheme.startsWith('http')) {
        effectiveHeaders['Referer'] = '${uri.scheme}://${uri.host}/';
      }
    } catch (_) {}
  }

  try {
    final response = await UniversalHttpClient.instance
        .get(
          Uri.parse(url),
          headers: effectiveHeaders,
          cacheConfig: CacheConfig.none,
        )
        .timeout(const Duration(seconds: 12));

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return _parseM3U8(response.body, url);
    }
  } catch (e) {
    AppLogger.w('Error parsing M3U8: $e');
  }

  return [
    {'quality': 'Default', 'url': url},
  ];
}

List<Map<String, dynamic>> _parseM3U8(String body, String masterUrl) {
  if (!body.contains('#EXTM3U')) {
    return [
      {'quality': 'Default', 'url': masterUrl}
    ];
  }

  final cleanBody = body.replaceAll('\r', '');
  final lines = cleanBody.split('\n');
  final extractedQualities = <Map<String, dynamic>>[];

  for (int i = 0; i < lines.length; i++) {
    final line = lines[i];
    
    if (line.startsWith('#EXT-X-STREAM-INF')) {
      final resolutionMatch = RegExp(r'RESOLUTION=\d+x(\d+)', caseSensitive: false).firstMatch(line);
      final nameMatch = RegExp(r'NAME="?([^",\r\n]+)"?', caseSensitive: false).firstMatch(line);
      final bandwidthMatch = RegExp(r'BANDWIDTH=(\d+)', caseSensitive: false).firstMatch(line);
      
      String quality = 'Unknown';

      final bw = bandwidthMatch != null ? int.tryParse(bandwidthMatch.group(1)!) : null;
      if (resolutionMatch != null) {
        quality = '${resolutionMatch.group(1)}p';
      } else if (nameMatch != null) {
        quality = nameMatch.group(1)!;
      } else if (bw != null) {
        if (bw >= 4000000) {
          quality = '1080p';
        } else if (bw >= 2000000) {
          quality = '720p';
        } else if (bw >= 1000000) {
          quality = '480p';
        } else {
          quality = '360p';
        }
      }

      for (int j = i + 1; j < lines.length; j++) {
        final candidate = lines[j].trim();
        if (candidate.isEmpty) continue;
        if (candidate.startsWith('#')) {
          if (candidate.startsWith('#EXT-X-STREAM-INF')) break;
          continue;
        }
        final fullUrl = Uri.parse(masterUrl).resolve(candidate).toString();
        extractedQualities.add({
          'quality': quality,
          'url': fullUrl,
          if (bw != null) 'bandwidth': bw,
        });
        break;
      }
    }
  }

  if (extractedQualities.isEmpty) {
    return [{'quality': 'Default', 'url': masterUrl}];
  }

  extractedQualities.sort((a, b) {
    final aVal = int.tryParse(a['quality'].replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    final bVal = int.tryParse(b['quality'].replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    return bVal.compareTo(aVal);
  });

  return [
    {'quality': 'Auto', 'url': masterUrl},
    ...extractedQualities,
  ];
}
