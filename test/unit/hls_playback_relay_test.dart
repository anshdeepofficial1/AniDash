import 'dart:convert';
import 'dart:io';

import 'package:ani_dash/core/network/hls_playback_relay.dart';
import 'package:flutter_test/flutter_test.dart';

Future<String> readText(HttpClient client, Uri url) async {
  final response = await (await client.getUrl(url)).close();
  expect(response.statusCode, HttpStatus.ok);
  return utf8.decoder.bind(response).join();
}

void main() {
  test(
    'relay rewrites HLS playlists and carries authenticated headers',
    () async {
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final seenReferers = <String?>[];
      final serverSubscription = upstream.listen((request) async {
        seenReferers.add(request.headers.value(HttpHeaders.refererHeader));
        if (request.uri.path == '/master.m3u8') {
          request.response.headers.contentType = ContentType.parse(
            'application/vnd.apple.mpegurl',
          );
          request.response.write(
            '#EXTM3U\n'
            '#EXT-X-MEDIA:TYPE=SUBTITLES,URI="subs.vtt"\n'
            '#EXT-X-KEY:METHOD=AES-128,URI="key.bin"\n'
            '#EXTINF:5,\nchunk.ts\n#EXT-X-ENDLIST\n',
          );
        } else if (request.uri.path == '/chunk.ts') {
          final range = request.headers.value(HttpHeaders.rangeHeader);
          request.response.statusCode =
              range != null ? HttpStatus.partialContent : HttpStatus.ok;
          request.response.headers.contentType = ContentType('video', 'mp2t');
          request.response.add([1, 2, 3, 4]);
        } else if (request.uri.path == '/key.bin') {
          request.response.add(List<int>.filled(16, 7));
        } else if (request.uri.path == '/subs.vtt') {
          request.response.write('WEBVTT\n');
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });
      final client = HttpClient();
      final relay = await HlsPlaybackRelay.start(
        'http://127.0.0.1:${upstream.port}/master.m3u8',
        {'Referer': 'https://anime.example/', 'User-Agent': 'AniDashTest'},
      );
      try {
        final body = await readText(client, Uri.parse(relay.localUrl));
        expect(body, startsWith('#EXTM3U'));
        expect(body, contains('/media/'));
        expect(body, isNot(contains('URI="key.bin"')));
        expect(body, isNot(contains('URI="subs.vtt"')));

        final segmentPath = body
            .split('\n')
            .firstWhere((line) => line.contains('chunk.ts'));
        final segmentRequest = await client.getUrl(
          Uri.parse(relay.localUrl).resolve(segmentPath),
        );
        segmentRequest.headers.set(HttpHeaders.rangeHeader, 'bytes=0-3');
        final segment = await segmentRequest.close();
        expect(segment.statusCode, HttpStatus.partialContent);
        expect(await segment.fold<List<int>>(<int>[], (a, b) => a..addAll(b)), [
          1,
          2,
          3,
          4,
        ]);
        expect(seenReferers, everyElement('https://anime.example/'));
      } finally {
        client.close(force: true);
        await relay.close();
        await serverSubscription.cancel();
        await upstream.close(force: true);
      }
    },
  );

  test('handles redirects and extensionless HLS quality playlists', () async {
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = upstream.listen((request) async {
      final path = request.uri.path;
      if (path == '/redirect.m3u8') {
        request.response.statusCode = HttpStatus.found;
        request.response.headers.set(HttpHeaders.locationHeader,
            '/cdn/master.m3u8');
      } else if (path == '/cdn/master.m3u8') {
        request.response.headers.contentType =
            ContentType.parse('application/vnd.apple.mpegurl');
        request.response.write(
            '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=500000\n'
            'levels/720?auth=test\n');
      } else if (path == '/cdn/levels/720') {
        request.response.headers.contentType = ContentType.text;
        request.response.write('#EXTM3U\n#EXTINF:6,\nchunk.ts\n');
      } else if (path == '/cdn/levels/chunk.ts') {
        request.response.add([10, 20, 30]);
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
    final client = HttpClient();
    final relay = await HlsPlaybackRelay.start(
      'http://127.0.0.1:${upstream.port}/redirect.m3u8',
      {'Referer': 'https://anime.example/'},
    );
    try {
      final master = await readText(client, Uri.parse(relay.localUrl));
      final variant = master.split('\n').firstWhere(
          (line) => line.contains('720') && !line.startsWith('#'));
      final nested = await readText(
          client, Uri.parse(relay.localUrl).resolve(variant));
      expect(nested, contains('#EXTINF:6,'));
      final segmentPath =
          nested.split('\n').firstWhere((line) => line.contains('chunk.ts'));
      final response = await (await client.getUrl(
          Uri.parse(relay.localUrl).resolve(segmentPath))).close();
      expect(response.statusCode, HttpStatus.ok);
      expect(await response.fold<List<int>>(<int>[],
          (bytes, chunk) => bytes..addAll(chunk)), [10, 20, 30]);
    } finally {
      client.close(force: true);
      await relay.close();
      await subscription.cancel();
      await upstream.close(force: true);
    }
  });
}
