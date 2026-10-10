import 'package:ani_dash/core/services/anilist/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AniList authorization URL', () {
    test('mobile uses the implicit flow without overriding redirect URI', () {
      final uri = AniListAuthService().buildAuthorizationUri(desktop: false);

      expect(uri.scheme, 'https');
      expect(uri.host, 'anilist.co');
      expect(uri.queryParameters['client_id'], isNotEmpty);
      expect(uri.queryParameters['response_type'], 'token');
      expect(uri.queryParameters, isNot(contains('redirect_uri')));
    });

    test('desktop keeps the authorization-code redirect URI', () {
      final uri = AniListAuthService().buildAuthorizationUri(
        desktop: true,
        state: 'expected-state',
      );

      expect(uri.queryParameters['response_type'], 'code');
      expect(
        uri.queryParameters['redirect_uri'],
        'http://localhost:43824/success?code=1337',
      );
      expect(uri.queryParameters['state'], 'expected-state');
    });
  });
}
