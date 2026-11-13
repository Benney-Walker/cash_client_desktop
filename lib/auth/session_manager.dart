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
  Future<String>? _refreshing;

  AuthSession? get session => _session;

  /// True when the backend refused the session, as opposed to the staff
  /// member signing out. The sign-in screen uses it to explain why they're
  /// there.
  bool get sessionEndedByServer => _endedByServer;

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
    if (session.role == null) throw const NotOfficeStaffException();
    _session = session;
    _endedByServer = false;
    notifyListeners();
  }

  /// The staff member chose to sign out.
  ///
  /// The backend has no logout endpoint, so this forgets the tokens; they
  /// stay valid on the server until they expire.
  void signOut() => _clear(endedByServer: false);

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
      final accessToken = await _api.refreshAccessToken(current.refreshToken);
      // Only keep it if nobody signed out (or in again) while the refresh
      // was in flight.
      if (identical(_session, current)) {
        _session = current.withAccessToken(accessToken);
      }
      return accessToken;
    } on ApiException catch (e) {
      if (e.failure == ApiFailure.unauthorized &&
          identical(_session, current)) {
        endSession();
      }
      rethrow;
    }
  }

  void _clear({required bool endedByServer}) {
    _session = null;
    _endedByServer = endedByServer;
    notifyListeners();
  }
}
