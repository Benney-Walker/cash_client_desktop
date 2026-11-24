import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/api_exception.dart';
import 'auth_api.dart';
import 'auth_session.dart';
import 'sign_in.dart';

/// Owns the signed-in session: signing in and out, refreshing the access
/// token, and ending the session when the backend refuses it.
///
/// The session lives in memory only (owner decision 13 November 2026): it's
/// gone when the app closes, and staff sign in again next time. That suits
/// shared office computers and means no tokens are ever stored on disk.
///
/// Widgets listen to it to switch between the sign-in screen and the app.
class SessionManager extends ChangeNotifier {
  SessionManager({required AuthApi api}) : _api = api;

  final AuthApi _api;

  AuthSession? _session;
  bool _endedByServer = false;
  String? _signOutNotice;
  Future<String>? _refreshing;
  int _signInCount = 0;

  AuthSession? get session => _session;

  /// Goes up with every successful sign-in, unlocks included, but not with
  /// token refreshes, so listeners can tell a new sign-in from a refresh.
  int get signInCount => _signInCount;

  /// Shown on the sign-in screen when an administrator changed the staff
  /// member's roles during their session (owner decision 24 November 2026:
  /// sign them out).
  static const rolesChangedNotice = 'Your roles were changed by an '
      'administrator. Sign in again to continue.';

  /// True when the backend refused the session, as opposed to the staff
  /// member signing out. The sign-in screen uses it to explain why they're
  /// there.
  bool get sessionEndedByServer => _endedByServer;

  /// What the sign-in screen should explain, if anything: the reason given
  /// to [signOut], or that the backend ended the session.
  String? get signInNotice =>
      _signOutNotice ?? (_endedByServer ? sessionEndedNotice : null);

  /// Signs an administrator or agent in.
  ///
  /// Throws [NotOfficeStaffException] for anyone else, without keeping their
  /// tokens, and [ApiException] when the login call fails. The backend still
  /// enforces permissions on every endpoint; this check only keeps people
  /// out of an app that isn't built for them.
  Future<void> signIn({
    required String staffId,
    required String password,
  }) async {
    final session = await _api.login(staffId: staffId, password: password);
    if (session.role == null) {
      // Their tokens are never used, so end that session on the backend too.
      _logOutQuietly(session);
      throw const NotOfficeStaffException();
    }
    final previous = _session;
    if (previous != null &&
        previous.staffId == session.staffId &&
        !setEquals(previous.roles.toSet(), session.roles.toSet())) {
      // Unlocking found different roles: sign out rather than carry on
      // with a session that started under the old ones.
      _logOutQuietly(session);
      _logOutQuietly(previous);
      _clear(endedByServer: false, notice: rolesChangedNotice);
      return;
    }
    _session = session;
    _signInCount++;
    _endedByServer = false;
    _signOutNotice = null;
    notifyListeners();
    // Unlocking signs in again, which starts a new backend session. End the
    // old one only now that the new one exists: the backend's logout also
    // refuses access tokens issued before it, and a token refused that way
    // is recovered with one refresh, whereas a failed unlock that had
    // already ended the old session would sign the staff member out.
    if (previous != null) _logOutQuietly(previous);
  }

  /// The staff member chose to sign out.
  ///
  /// The app forgets the tokens at once and asks the backend to end the
  /// session (`POST /api/auth/v1/logout`) in the background. If that call
  /// fails, for example offline, the tokens are still gone from the app and
  /// the backend's session simply runs until it expires.
  /// [notice] is shown on the sign-in screen, for example why the app
  /// signed them out.
  void signOut({String? notice}) {
    final session = _session;
    _clear(endedByServer: false, notice: notice);
    if (session != null) _logOutQuietly(session);
  }

  /// The backend refused the session: the refresh token expired, or the
  /// staff member was deactivated.
  void endSession() => _clear(endedByServer: true);

  /// Gets a new access token.
  ///
  /// Concurrent callers share one refresh call: when several requests hit a
  /// 401 together, the backend is asked once.
  ///
  /// Throws [ApiException]. A 401 from the refresh endpoint ends the session
  /// before it's rethrown. Other failures, such as no connection, leave the
  /// session alone so nobody is signed out just for being offline.
  Future<String> refreshAccessToken() {
    return _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  }

  Future<String> _refresh() async {
    final current = _session;
    if (current == null) throw const ApiException(ApiFailure.unauthorized);
    try {
      final tokens = await _api.refresh(current.refreshToken);
      // Only keep them if nobody signed out (or in again) while the refresh
      // was in flight. The backend has already retired the refresh token
      // just sent, so the new one must replace it (rotation).
      if (identical(_session, current)) {
        _session = current.withTokens(
          accessToken: tokens.accessToken,
          refreshToken: tokens.refreshToken,
        );
      } else if (tokens.refreshToken != null) {
        // Signed out meanwhile: end the session this refresh continued.
        _logOutWithToken(tokens.refreshToken!);
      }
      return tokens.accessToken;
    } on ApiException catch (e) {
      if (e.failure == ApiFailure.unauthorized &&
          identical(_session, current)) {
        endSession();
      }
      rethrow;
    }
  }

  void _logOutQuietly(AuthSession session) =>
      _logOutWithToken(session.refreshToken);

  void _logOutWithToken(String refreshToken) {
    unawaited(
      _api.logout(refreshToken).then<void>((_) {}, onError: (Object _) {}),
    );
  }

  void _clear({required bool endedByServer, String? notice}) {
    _session = null;
    _endedByServer = endedByServer;
    _signOutNotice = notice;
    notifyListeners();
  }
}
