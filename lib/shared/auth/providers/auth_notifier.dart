import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:ani_dash/main.dart';
import 'package:ani_dash/shared/providers/anilist_service_provider.dart';
import 'package:ani_dash/core/services/anilist/auth_service.dart';
import 'package:ani_dash/core/services/myanimelist/auth_service.dart';
import 'package:ani_dash/core/services/auth_provider_enum.dart';
import 'package:commentum_client/commentum_client.dart';
import 'package:ani_dash/core/commentum/commentum_client.dart';
import 'package:ani_dash/core/models/auth/user.dart';
import 'package:ani_dash/core/services/remote_push_service.dart';
import 'package:ani_dash/core/utils/app_logger.dart';

part 'auth_notifier.g.dart';

@immutable
class AuthState {
  static const Object _unset = Object();
  final bool anilistLoading;
  final bool malLoading;
  final String? anilistAccessToken;
  final String? malAccessToken;
  final AuthUser? anilistUser;
  final AuthUser? malUser;
  final AuthPlatform activePlatform;

  const AuthState({
    this.anilistLoading = false,
    this.malLoading = false,
    this.anilistAccessToken,
    this.malAccessToken,
    this.anilistUser,
    this.malUser,
    this.activePlatform = AuthPlatform.anilist,
  });

  AuthState copyWith({
    bool? anilistLoading,
    bool? malLoading,
    Object? anilistAccessToken = _unset,
    Object? malAccessToken = _unset,
    Object? anilistUser = _unset,
    Object? malUser = _unset,
    AuthPlatform? activePlatform,
  }) {
    return AuthState(
      anilistLoading: anilistLoading ?? this.anilistLoading,
      malLoading: malLoading ?? this.malLoading,
      anilistAccessToken:
          identical(anilistAccessToken, _unset)
              ? this.anilistAccessToken
              : anilistAccessToken as String?,
      malAccessToken:
          identical(malAccessToken, _unset)
              ? this.malAccessToken
              : malAccessToken as String?,
      anilistUser:
          identical(anilistUser, _unset)
              ? this.anilistUser
              : anilistUser as AuthUser?,
      malUser: identical(malUser, _unset) ? this.malUser : malUser as AuthUser?,
      activePlatform: activePlatform ?? this.activePlatform,
    );
  }

  bool get isAniListAuthenticated => anilistAccessToken?.isNotEmpty == true;
  bool get isMalAuthenticated => malAccessToken?.isNotEmpty == true;

  bool isAuthenticatedFor(AuthPlatform platform) {
    return switch (platform) {
      AuthPlatform.anilist => isAniListAuthenticated,
      AuthPlatform.mal => isMalAuthenticated,
    };
  }

  AuthUser? userFor(AuthPlatform platform) {
    return switch (platform) {
      AuthPlatform.anilist => anilistUser,
      AuthPlatform.mal => malUser,
    };
  }

  bool isLoadingFor(AuthPlatform platform) {
    return switch (platform) {
      AuthPlatform.anilist => anilistLoading,
      AuthPlatform.mal => malLoading,
    };
  }
}

@Riverpod(keepAlive: true)
class Auth extends _$Auth {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  AniListAuthService get _anilistAuthService => AniListAuthService();
  MyAnimeListAuthService get _malAuthService => MyAnimeListAuthService();

  Future<bool>? _malRefreshFuture;

  @override
  AuthState build() {
    _init();
    return const AuthState();
  }

  Future<void> _init() async {
    await Future.wait([_loadAnilistToken(), _loadMalToken()]);
    await RemotePushService.identifyAniListUser(state.anilistUser?.id);
    await commentumClient.init();
    commentumClient.setActiveProvider(
      state.activePlatform == AuthPlatform.anilist
          ? CommentumProvider.anilist
          : CommentumProvider.myanimelist,
    );
  }

  AuthUser _buildAnilistUser(Map<String, dynamic> data) =>
      AuthUser.fromJson(data);

  AuthUser _buildMalUser(Map<String, dynamic> data) => AuthUser(
    id: data['id'].toString(),
    name: data['name'],
    avatarUrl: data['picture'],
  );

  Future<void> updateAnilistProfile({required String about}) async {
    try {
      await ref.read(anilistServiceProvider).updateUser(about: about);

      if (state.anilistUser != null) {
        final token = state.anilistAccessToken;
        if (token != null) {
          final userData = await ref
              .read(anilistServiceProvider)
              .getUserProfile(token);
          state = state.copyWith(anilistUser: _buildAnilistUser(userData));
        }
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _loadAnilistToken() async {
    final token = await _secureStorage.read(key: 'anilist-token');
    if (token?.isNotEmpty != true) return;

    // Immediately restore cached profile offline
    final cachedUserJson = sharedPrefs.getString('anilist-user-cache');
    if (cachedUserJson != null && cachedUserJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(cachedUserJson) as Map<String, dynamic>;
        state = state.copyWith(
          anilistAccessToken: token,
          anilistUser: _buildAnilistUser(decoded),
        );
      } catch (_) {}
    } else {
      state = state.copyWith(anilistAccessToken: token);
    }

    state = state.copyWith(anilistLoading: true);
    try {
      final userData = await ref
          .read(anilistServiceProvider)
          .getUserProfile(token!);
      await sharedPrefs.setString('anilist-user-cache', jsonEncode(userData));
      state = state.copyWith(
        anilistAccessToken: token,
        anilistUser: _buildAnilistUser(userData),
      );
    } catch (e) {
      final errStr = e.toString().toLowerCase();
      // Only delete credentials if explicitly 401 Unauthorized / Invalid Token
      if (errStr.contains('401') ||
          errStr.contains('unauthorized') ||
          errStr.contains('invalid token')) {
        await _secureStorage.delete(key: 'anilist-token');
        await sharedPrefs.remove('anilist-user-cache');
        state = state.copyWith(anilistAccessToken: null, anilistUser: null);
      }
    } finally {
      state = state.copyWith(anilistLoading: false);
    }
  }

  Future<void> _loginWithAnilist() async {
    state = state.copyWith(
      anilistLoading: true,
      activePlatform: AuthPlatform.anilist,
    );
    try {
      final code = await _anilistAuthService.authenticate();
      if (code == null) {
        AppLogger.w('[AniList] Authentication aborted or returned no code.');
        return;
      }

      final tokenData = await _anilistAuthService.getAccessToken(code);
      if (tokenData == null) {
        AppLogger.e('[AniList] Failed to obtain access token from AniList.');
        return;
      }

      final token = tokenData['access_token'] as String?;
      if (token == null || token.isEmpty) {
        AppLogger.e('[AniList] Access token was empty in token response.');
        return;
      }

      await _secureStorage.write(key: 'anilist-token', value: token);
      final userData = await ref
          .read(anilistServiceProvider)
          .getUserProfile(token);
      if (userData.isEmpty) {
        AppLogger.e('[AniList] User profile query returned empty.');
        return;
      }
      await sharedPrefs.setString('anilist-user-cache', jsonEncode(userData));

      // Login to Commentum
      try {
        await commentumClient.login(CommentumProvider.anilist, token);
      } catch (e) {
        debugPrint('Failed to login to Commentum with AniList: $e');
      }

      state = state.copyWith(
        anilistAccessToken: token,
        anilistUser: _buildAnilistUser(userData),
        activePlatform: AuthPlatform.anilist,
      );
      await RemotePushService.identifyAniListUser(state.anilistUser?.id);
      AppLogger.success('[AniList] Successfully connected to AniList account.');
    } catch (e, st) {
      AppLogger.e('[AniList] Unexpected error during login flow', e, st);
    } finally {
      state = state.copyWith(anilistLoading: false);
    }
  }

  Future<void> _loadMalToken() async {
    final token = await _secureStorage.read(key: 'mal-token');
    if (token?.isNotEmpty != true) return;

    state = state.copyWith(malLoading: true);
    try {
      final profile = await _malAuthService.getUserProfile(token!);
      if (profile != null) {
        state = state.copyWith(
          malAccessToken: token,
          malUser: _buildMalUser(profile),
        );
      } else {
        // Token might be expired, attempt refresh
        final refreshed = await refreshMalToken();
        if (refreshed && state.malAccessToken != null) {
          final retryProfile = await _malAuthService.getUserProfile(
            state.malAccessToken!,
          );
          if (retryProfile != null) {
            state = state.copyWith(malUser: _buildMalUser(retryProfile));
          } else {
            await logout(AuthPlatform.mal);
          }
        } else {
          await logout(AuthPlatform.mal);
        }
      }
    } catch (_) {
      await logout(AuthPlatform.mal);
    } finally {
      state = state.copyWith(malLoading: false);
    }
  }

  Future<void> _loginWithMal() async {
    state = state.copyWith(malLoading: true, activePlatform: AuthPlatform.mal);
    try {
      final code = await _malAuthService.authenticate();
      if (code == null) return;

      final tokenData = await _malAuthService.getAccessToken(code);
      if (tokenData == null) return;

      final accesToken = tokenData['access_token'];

      await _secureStorage.write(key: 'mal-token', value: accesToken);
      await _secureStorage.write(
        key: 'mal-refresh-token',
        value: tokenData['refresh_token'],
      );

      final profile = await _malAuthService.getUserProfile(accesToken);
      if (profile != null) {
        // Login to Commentum
        try {
          await commentumClient.login(
            CommentumProvider.myanimelist,
            accesToken,
          );
        } catch (e) {
          debugPrint('Failed to login to Commentum with MAL: $e');
        }

        state = state.copyWith(
          malAccessToken: accesToken,
          malUser: _buildMalUser(profile),
          activePlatform: AuthPlatform.mal,
        );
      }
    } finally {
      state = state.copyWith(malLoading: false);
    }
  }

  Future<void> reLoginCommentum(AuthPlatform platform) async {
    if (platform == AuthPlatform.anilist) {
      commentumClient.login(
        CommentumProvider.anilist,
        state.anilistAccessToken!,
      );
    } else if (platform == AuthPlatform.mal) {
      commentumClient.login(
        CommentumProvider.myanimelist,
        state.malAccessToken!,
      );
    }
  }

  Future<void> login(AuthPlatform platform) async {
    return switch (platform) {
      AuthPlatform.anilist => _loginWithAnilist(),
      AuthPlatform.mal => _loginWithMal(),
    };
  }

  Future<void> logout(AuthPlatform platform) async {
    switch (platform) {
      case AuthPlatform.anilist:
        await _secureStorage.delete(key: 'anilist-token');
        await sharedPrefs.remove('anilist-user-cache');
        await commentumClient.logout(CommentumProvider.anilist);
        state = state.copyWith(anilistAccessToken: null, anilistUser: null);
        await RemotePushService.identifyAniListUser(null);
        break;
      case AuthPlatform.mal:
        await _secureStorage.delete(key: 'mal-token');
        await _secureStorage.delete(key: 'mal-refresh-token');
        await commentumClient.logout(CommentumProvider.myanimelist);
        state = state.copyWith(malAccessToken: null, malUser: null);
        break;
    }

    if (state.activePlatform == platform) {
      // Logic for handling null platform if needed
    }
  }

  Future<bool> refreshMalToken() async {
    if (_malRefreshFuture != null) {
      return _malRefreshFuture!;
    }

    _malRefreshFuture = _performMalTokenRefresh();
    try {
      final result = await _malRefreshFuture!;
      return result;
    } finally {
      _malRefreshFuture = null;
    }
  }

  Future<bool> _performMalTokenRefresh() async {
    try {
      final refreshToken = await _secureStorage.read(key: 'mal-refresh-token');
      if (refreshToken == null) {
        await logout(AuthPlatform.mal);
        return false;
      }

      final tokenData = await _malAuthService.refreshToken(refreshToken);
      if (tokenData != null) {
        state = state.copyWith(malAccessToken: tokenData['access_token']);
        await _secureStorage.write(
          key: 'mal-token',
          value: tokenData['access_token'],
        );
        await _secureStorage.write(
          key: 'mal-refresh-token',
          value: tokenData['refresh_token'],
        );
        return true;
      } else {
        await logout(AuthPlatform.mal);
        return false;
      }
    } catch (e) {
      await logout(AuthPlatform.mal);
      return false;
    }
  }

  void changePlatform(AuthPlatform platform) {
    state = state.copyWith(activePlatform: platform);
    commentumClient.setActiveProvider(
      platform == AuthPlatform.anilist
          ? CommentumProvider.anilist
          : CommentumProvider.myanimelist,
    );
  }
}
