import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Device-local relay for HLS playlists and media chunks.
///
/// Some providers allow Dart HTTP downloads with their Referer/Cookie headers
/// but reject libmpv's independent HLS segment requests. This forwards every
/// playlist, segment, subtitle and AES-key request through Dart's HTTP stack.
/// Nothing is uploaded to a third-party proxy: the server binds to 127.0.0.1.
class HlsPlaybackRelay {
  HlsPlaybackRelay._(this._headers);

  final Map<String, String> _headers;
  final _targets = <String, Uri>{};
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 20)
    ..idleTimeout = const Duration(seconds: 30)
    ..autoUncompress = false;
  HttpServer? _server;
  StreamSubscription<HttpRequest>? _subscription;
  int _nextId = 0;

  String get localUrl => 'http://127.0.0.1:${_server!.port}${_initialPath!}';
  String? _initialPath;

  static Future<HlsPlaybackRelay> start(
    String streamUrl,
    Map<String, String> headers,
  ) async {
    final uri = Uri.tryParse(streamUrl);
    if (uri == null || !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw ArgumentError.value(streamUrl, 'streamUrl', 'Expected HTTP(S)');
    }
    final relay = HlsPlaybackRelay._(Map.of(headers));
    try {
      relay._server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      relay._initialPath = relay._addTarget(uri);
      relay._subscription = relay._server!.listen(relay._serve);
      return relay;
    } catch (_) {
      await relay.close();
      rethrow;
    }
  }

  String _addTarget(Uri uri) {
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw FormatException('Unexpected URI scheme: ${uri.scheme}');
    }
    final file = uri.pathSegments.isEmpty ? 'playlist.m3u8'
        : uri.pathSegments.last.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final path = '/media/${_nextId++}/${file.isEmpty ? 'stream' : file}';
    _targets[path] = uri;
    return path;
  }

  String _relayReference(String reference, Uri base) {
    final resolved = base.resolve(reference.trim());
    if (resolved.scheme != 'http' && resolved.scheme != 'https') {
      return reference;
    }
    return _addTarget(resolved);
  }

  String _rewritePlaylist(String playlist, Uri base) {
    final attributes = RegExp(r'URI="([^"]+)"');
    return playlist.split(RegExp(r'\r?\n')).map((line) {
      if (line.startsWith('#')) {
        return line.replaceAllMapped(attributes, (m) =>
          'URI="${_relayReference(m.group(1)!, base)}"');
      }
      final reference = line.trim();
      if (reference.isEmpty) return line;
      return _relayReference(reference, base);
    }).join('\n');
  }

  Future<void> _serve(HttpRequest incoming) async {
    final output = incoming.response;
    try {
      if (incoming.method != 'GET' && incoming.method != 'HEAD') {
        output.statusCode = HttpStatus.methodNotAllowed;
        return;
      }
      final uri = _targets[incoming.uri.path];
      if (uri == null) {
        output.statusCode = HttpStatus.notFound;
        return;
      }

      final request = await _client.openUrl(incoming.method, uri)
          .timeout(const Duration(seconds: 25));
      request.followRedirects = true;
      request.maxRedirects = 5;
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      for (final header in _headers.entries) {
        final key = header.key.toLowerCase();
        if (key == 'host' || key == 'content-length' ||
            key == 'accept-encoding' || key == 'connection') continue;
        request.headers.set(header.key, header.value);
      }
      for (final key in [HttpHeaders.rangeHeader, HttpHeaders.ifRangeHeader]) {
        final value = incoming.headers.value(key);
        if (value != null) request.headers.set(key, value);
      }
      final upstream = await request.close().timeout(
        const Duration(seconds: 30),
      );
      output.statusCode = upstream.statusCode;
      final mime = upstream.headers.contentType?.mimeType.toLowerCase() ?? '';
      final isPlaylist = uri.path.toLowerCase().endsWith('.m3u8') ||
          uri.path.toLowerCase().endsWith('.m3u') ||
          mime.contains('mpegurl');
      if (incoming.method == 'HEAD') {
        final length = upstream.contentLength;
        if (length >= 0) output.contentLength = length;
        if (mime.isNotEmpty) output.headers.set(HttpHeaders.contentTypeHeader, mime);
        return;
      }
      if (isPlaylist && upstream.statusCode == HttpStatus.ok) {
        final text = await utf8.decoder.bind(upstream).join();
        // Redirects can change the base URL of relative segment references.
        final base = upstream.redirects.isEmpty
            ? uri : upstream.redirects.last.location;
        output.headers.set(
          HttpHeaders.contentTypeHeader, 'application/vnd.apple.mpegurl',
        );
        output.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
        output.write(_rewritePlaylist(text, base));
      } else {
        for (final name in [
          HttpHeaders.contentTypeHeader,
          HttpHeaders.contentRangeHeader,
          HttpHeaders.acceptRangesHeader,
        ]) {
          final value = upstream.headers.value(name);
          if (value != null) output.headers.set(name, value);
        }
        if (upstream.contentLength >= 0) {
          output.contentLength = upstream.contentLength;
        }
        await output.addStream(upstream);
      }
    } catch (e) {
      if (!output.headersSent) {
        output.statusCode = HttpStatus.badGateway;
        output.write('Media relay unavailable');
      }
    } finally {
      try { await output.close(); } catch (_) {}
    }
  }

  Future<void> close() async {
    await _subscription?.cancel();
    await _server?.close(force: true);
    _client.close(force: true);
  }
}
