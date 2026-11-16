import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../api/api_exception.dart';
import 'auth_session.dart';

/// Calls the backend's public authentication endpoints. These take no
/// bearer token, so they use a plain client rather than
/// `AuthenticatedClient`.
class AuthApi {
  AuthApi({
    required String baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
  })  : _baseUrl = baseUrl.trim(),
        _client = client ?? http.Client();

  final String _baseUrl;
  final http.Client _client;
  final Duration timeout;

  /// `POST /api/auth/v1/staff-login` (the office endpoint; collectors have
  /// their own and get 403 here).
  ///
  /// Throws [ApiException]. Any staff member can sign in here; checking that
  /// they're an administrator or agent is the caller's job, because the
  /// backend accepts every role.
  Future<AuthSession> login({
    required String staffId,
    required String password,
  }) async {
    final response = await _post(
      '/api/auth/v1/staff-login',
      {'staffId': staffId, 'password': password},
    );
    final json = _jsonObject(response.body);
    final session =
        json == null ? null : AuthSession.fromLoginResponse(staffId, json);
    if (session == null) {
      throw const ApiException(ApiFailure.unexpectedResponse, statusCode: 200);
    }
    return session;
  }

  /// `POST /api/auth/v1/refresh-staff-token`.
  ///
  /// The backend rotates refresh tokens (owner decision 15 November 2026):
  /// it answers `{authToken, refreshToken}`, and the refresh token sent here
  /// stops working, so the caller must keep the new one. A retry within the
  /// backend's grace period (30 seconds by default) after a lost answer gets
  /// a fresh pair rather than ending the session.
  ///
  /// Older backends answered with the bare access token and kept the
  /// refresh token. That is still accepted, with [RefreshedTokens.refreshToken]
  /// null, so the app works against both until the change reaches `master`.
  ///
  /// The backend answers 401 ([ApiFailure.unauthorized]) when the refresh
  /// token has expired, was replaced or signed out, or the staff member is
  /// no longer active.
  Future<RefreshedTokens> refresh(String refreshToken) async {
    final response = await _post(
      '/api/auth/v1/refresh-staff-token',
      {'refreshToken': refreshToken},
    );
    final tokens = _tokenPair(response.body) ?? _bareTokenOnly(response.body);
    if (tokens == null) {
      throw const ApiException(ApiFailure.unexpectedResponse, statusCode: 200);
    }
    return tokens;
  }

  /// `POST /api/auth/v1/logout`: ends the session that [refreshToken]
  /// belongs to, on the backend. The backend always answers 204, whether or
  /// not it knew the token.
  ///
  /// Throws [ApiException] when the call itself fails; callers signing out
  /// ignore that, since the app forgets the tokens either way.
  Future<void> logout(String refreshToken) async {
    await _post(
      '/api/auth/v1/logout',
      {'refreshToken': refreshToken},
      okStatuses: const {200, 204},
      timeout: logoutTimeout,
    );
  }

  /// Signing out mustn't keep anyone waiting on a slow connection.
  static const logoutTimeout = Duration(seconds: 5);

  /// `{authToken, refreshToken}` in the body, or null if it isn't that.
  static RefreshedTokens? _tokenPair(String body) {
    final json = _jsonObject(body);
    if (json == null) return null;
    final access = json['authToken'];
    final refresh = json['refreshToken'];
    if (access is! String ||
        !_jwtShape.hasMatch(access) ||
        refresh is! String ||
        refresh.trim().isEmpty) {
      return null;
    }
    return RefreshedTokens(accessToken: access, refreshToken: refresh);
  }

  static RefreshedTokens? _bareTokenOnly(String body) {
    final access = _bareToken(body);
    return access == null ? null : RefreshedTokens(accessToken: access);
  }

  // The backend's tokens are signed JWTs: three base64url parts joined by
  // dots. Checking the shape catches a proxy error page or other stray body
  // before it's saved and sent as a bearer token.
  static final _jwtShape =
      RegExp(r'^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]*$');

  /// The token in a bare-token body (`abc.def.ghi` or `"abc.def.ghi"`), or
  /// null if the body isn't one.
  static String? _bareToken(String body) {
    var text = body.trim();
    if (text.startsWith('"')) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is! String) return null;
        text = decoded.trim();
      } on FormatException {
        return null;
      }
    }
    return _jwtShape.hasMatch(text) ? text : null;
  }

  static Map<String, dynamic>? _jsonObject(String body) {
    try {
      final json = jsonDecode(body);
      return json is Map<String, dynamic> ? json : null;
    } on FormatException {
      return null;
    }
  }

  /// Sends a JSON body and returns the response when its status is one of
  /// [okStatuses] (200 by default). Any other status becomes
  /// an [ApiException] built from the backend's standard error body.
  Future<http.Response> _post(
    String path,
    Map<String, Object?> body, {
    Set<int> okStatuses = const {200},
    Duration? timeout,
  }) async {
    final uri = _endpoint(path);
    final http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(timeout ?? this.timeout);
    } on TimeoutException {
      throw const ApiException(ApiFailure.network);
    } on http.ClientException {
      // Covers socket and DNS errors on every platform http supports.
      throw const ApiException(ApiFailure.network);
    }

    if (!okStatuses.contains(response.statusCode)) {
      throw ApiException.fromResponse(response.statusCode, response.body);
    }
    return response;
  }

  Uri _endpoint(String path) {
    if (_baseUrl.isEmpty) {
      throw const ApiException(ApiFailure.notConfigured);
    }
    final base = Uri.tryParse(_baseUrl);
    if (base == null || !base.hasScheme || base.host.isEmpty) {
      throw const ApiException(ApiFailure.notConfigured);
    }
    // Tolerate a base URL with or without a trailing slash, or with a path
    // prefix such as a reverse-proxy mount point.
    final prefix = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    return base.replace(path: '$prefix$path');
  }
}

/// What a refresh returns: a new access token and, from backends that
/// rotate refresh tokens, the refresh token to use next time.
class RefreshedTokens {
  const RefreshedTokens({required this.accessToken, this.refreshToken});

  final String accessToken;

  /// Null from older backends, which keep the same refresh token.
  final String? refreshToken;
}
