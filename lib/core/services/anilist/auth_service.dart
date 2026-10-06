import 'dart:convert';
import 'package:ani_dash/core/services/oauth/base_oauth_service.dart';
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
    return queryParams?[isDesktop ? 'code' : 'access_token'];
  }

  Future<Map<String, dynamic>?> getAccessToken(String tokenOrCode) async {
    if (!isDesktop || tokenOrCode.length > 50) {
      return {'access_token': tokenOrCode, 'token_type': 'Bearer'};
    }

    return await postTokenRequest(
      _tokenUrl,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        'grant_type': 'authorization_code',
        'client_id': _clientId,
        'client_secret': _clientSecret,
        'redirect_uri': redirectUri,
        'code': tokenOrCode,
      }),
    );
  }
}
