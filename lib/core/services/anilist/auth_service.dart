import 'package:ani_dash/core/services/oauth/base_oauth_service.dart';
import 'package:ani_dash/core/utils/app_logger.dart';
import 'package:ani_dash/core/utils/env_loader.dart';

class AniListAuthService extends BaseOAuthService {
  String get _clientId =>
      isDesktop
          ? ANILIST_CLIENT_ID.split('|')[1]
          : ANILIST_CLIENT_ID.split('|')[0];

  String get _clientSecret =>
      isDesktop
          ? ANILIST_CLIENT_SECRET.split('|')[1]
          : ANILIST_CLIENT_SECRET.split('|')[0];

  static const String _authUrl = 'https://anilist.co/api/v2/oauth/authorize';
  static const String _tokenUrl = 'https://anilist.co/api/v2/oauth/token';

  Uri buildAuthorizationUri({bool? desktop}) {
    final useDesktopFlow = desktop ?? isDesktop;
    final clientId =
        useDesktopFlow
            ? ANILIST_CLIENT_ID.split('|')[1]
            : ANILIST_CLIENT_ID.split('|')[0];
    final parameters = <String, String>{
      'client_id': clientId,
      'response_type': useDesktopFlow ? 'code' : 'token',
    };

    if (useDesktopFlow) {
      parameters['redirect_uri'] = redirectUri;
    }

    return Uri.parse(_authUrl).replace(queryParameters: parameters);
  }

  Future<String?> authenticate() async {
    final loginUrl = buildAuthorizationUri().toString();

    final queryParams = await performWebAuth(loginUrl);
    if (queryParams == null) return null;
    if (queryParams.containsKey('access_token') &&
        queryParams['access_token']!.isNotEmpty) {
      return queryParams['access_token'];
    }
    return queryParams['code'];
  }

  Future<Map<String, dynamic>?> getAccessToken(String tokenOrCode) async {
    // On mobile, authenticate() returns access_token directly from implicit flow fragment.
    if (!isDesktop) {
      return {'access_token': tokenOrCode, 'token_type': 'Bearer'};
    }

    AppLogger.i('Exchanging code for AniList access token...');
    final body = <String, String>{
      'grant_type': 'authorization_code',
      'client_id': _clientId,
      'client_secret': _clientSecret,
      'redirect_uri': redirectUri,
      'code': tokenOrCode,
    };

    final result = await postTokenRequest(
      _tokenUrl,
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Accept': 'application/json',
      },
      body: body,
    );

    if (result != null && result.containsKey('access_token')) {
      AppLogger.i('Successfully received AniList access token.');
    } else {
      AppLogger.w('Failed to receive AniList access token: $result');
    }
    return result;
  }
}
