import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Deep Link Resolution Tests', () {
    String? resolveDeepLink(Uri uri) {
      final path = uri.path;
      final host = uri.host.toLowerCase();

      // 1. Anime details deep links
      if (path.startsWith('/anime/') || (uri.scheme == 'anidash' && host == 'anime')) {
        final segments = path.split('/').where((s) => s.isNotEmpty).toList();
        final id = (host == 'anime')
            ? (segments.isNotEmpty ? segments.first : null)
            : (segments.length >= 2 ? segments[1] : null);
        if (id != null && id.isNotEmpty) {
          return '/details/$id';
        }
      }

      // 2. Episode deep links -> open anime details
      if (path.startsWith('/episode/') || (uri.scheme == 'anidash' && host == 'episode')) {
        final segments = path.split('/').where((s) => s.isNotEmpty).toList();
        final id = (host == 'episode')
            ? (segments.isNotEmpty ? segments.first : null)
            : (segments.length >= 2 ? segments[1] : null);
        if (id != null && id.isNotEmpty) {
          return '/details/$id';
        }
      }

      // 3. Shared chat deep links
      if (path.startsWith('/c/') || (uri.scheme == 'anidash' && host == 'c')) {
        final segments = path.split('/').where((s) => s.isNotEmpty).toList();
        final id = (host == 'c')
            ? (segments.isNotEmpty ? segments.first : null)
            : (segments.length >= 2 ? segments[1] : null);
        if (id != null && id.isNotEmpty) {
          return '/c/$id';
        }
      }

      return null;
    }

    test('resolves https anime link', () {
      final uri = Uri.parse('https://anidashweb.vercel.app/anime/21');
      expect(resolveDeepLink(uri), '/details/21');
    });

    test('resolves https anime link with trailing slash', () {
      final uri = Uri.parse('https://anidashweb.vercel.app/anime/154587/');
      expect(resolveDeepLink(uri), '/details/154587');
    });

    test('resolves anidash://anime/123 scheme', () {
      final uri = Uri.parse('anidash://anime/21');
      expect(resolveDeepLink(uri), '/details/21');
    });

    test('resolves anidash:///anime/123 scheme', () {
      final uri = Uri.parse('anidash:///anime/21');
      expect(resolveDeepLink(uri), '/details/21');
    });

    test('resolves https episode link', () {
      final uri = Uri.parse('https://anidashweb.vercel.app/episode/21/5');
      expect(resolveDeepLink(uri), '/details/21');
    });

    test('resolves anidash://episode/21/5 scheme', () {
      final uri = Uri.parse('anidash://episode/21/5');
      expect(resolveDeepLink(uri), '/details/21');
    });

    test('resolves chat link', () {
      final uri = Uri.parse('https://anidashweb.vercel.app/c/abc123xyz');
      expect(resolveDeepLink(uri), '/c/abc123xyz');
    });
  });
}
