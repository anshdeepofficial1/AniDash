import 'dart:convert';
import 'dart:io';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:ani_dash/core/network/http_client.dart';
import 'package:ani_dash/core/utils/app_logger.dart';

abstract class BaseOAuthService {
  bool get isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  String get redirectUri =>
      isDesktop
          ? 'http://localhost:43824/success?code=1337'
          : 'shonenx://callback';

  String get callbackUrlScheme =>
      isDesktop ? 'http://localhost:43824' : 'shonenx';

  /// Wraps [FlutterWebAuth2.authenticate] using common parameters and options.
  /// Returns the query parameters of the callback URL.
  Future<Map<String, String>?> performWebAuth(String url) async {
    try {
      AppLogger.i('Opening auth URL: $url');
      final result = await FlutterWebAuth2.authenticate(
        url: url,
        callbackUrlScheme: callbackUrlScheme,
        // AniList does not reliably render its authorization page in an
        // embedded Android WebView. Use a secure browser/custom tab on Android
        // and keep the existing embedded flow on Apple platforms.
        options: FlutterWebAuth2Options(
          useWebview: !isDesktop && !Platform.isAndroid,
        ),
      );
      AppLogger.i('Authentication callback received.');
      final callback = Uri.parse(result);
      final parameters = <String, String>{...callback.queryParameters};
      // OAuth implicit/public-client flows return tokens in the URL fragment.
      // FlutterWebAuth gives us the complete callback, so merge both forms.
      if (callback.fragment.isNotEmpty) {
        parameters.addAll(Uri.splitQueryString(callback.fragment));
      }
      return parameters;
    } catch (e, st) {
      AppLogger.e('Error during web authentication', e, st);
      return null;
    }
  }

  /// Sends a POST request to exchange a code or refresh a token.
  /// Handles the response checking and JSON decoding.
  Future<Map<String, dynamic>?> postTokenRequest(
    String url, {
    required Map<String, String> headers,
    required Object body,
  }) async {
    try {
      final response = await UniversalHttpClient.instance.post(
        Uri.parse(url),
        headers: headers,
        body: body,
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        AppLogger.w(
          'Token request failed: ${response.statusCode} - ${response.body}',
        );
        return null;
      }
    } catch (e, st) {
      AppLogger.e('Error performing token request', e, st);
      return null;
    }
  }
}
