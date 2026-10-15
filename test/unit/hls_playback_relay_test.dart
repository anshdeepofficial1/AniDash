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
  test('relay rewrites HLS playlists and carries authenticated headers', () async {
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final seenReferers = <String?>[];
    final serverSubscription = upstream.listen((request) async {
      seenReferers.add(request.headers.value(HttpHeaders.refererHeader));
      if (request.uri.path == '/master.m3u8') {
        request.response.headers.contentType =
            ContentType.parse('application/vnd.apple.mpegurl');
        request.response.write('#EXTM3U\n'
            '#EXT-X-MEDIA:TYPE=SUBTITLES,URI="subs.vtt"\n'
            '#EXT-X-KEY:METHOD=AES-128,URI="key.bin"\n'
            '#EXTINF:5,\nchunk.ts\n#EXT-X-ENDLIST\n');
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

      final segmentPath = body.split('\n')
          .firstWhere((line) => line.contains('chunk.ts'));
      final segmentRequest = await client.getUrl(
          Uri.parse(relay.localUrl).resolve(segmentPath));
      segmentRequest.headers.set(HttpHeaders.rangeHeader, 'bytes=0-3');
      final segment = await segmentRequest.close();
      expect(segment.statusCode, HttpStatus.partialContent);
      expect(await segment.fold<List<int>>(<int>[], (a, b) => a..addAll(b)),
          [1, 2, 3, 4]);
      expect(seenReferers, everyElement('https://anime.example/'));
    } finally {
      client.close(force: true);
      await relay.close();
      await serverSubscription.cancel();
      await upstream.close(force: true);
    }
  });
}
