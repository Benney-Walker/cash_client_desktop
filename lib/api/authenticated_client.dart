import 'package:http/http.dart' as http;

import '../auth/session_manager.dart';
import 'api_exception.dart';

/// An HTTP client for the backend's protected endpoints.
///
/// It adds the staff member's access token to every request. When the backend
/// answers 401 (the access token expired), it refreshes the token once and
/// replays the request, so callers never deal with token expiry.
///
/// When the refresh itself is refused, the session is over: the
/// [SessionManager] ends it, the app returns to the login screen, and this
/// client throws [ApiException] with [ApiFailure.unauthorized].
///
/// A 403 is passed straight through: it means the role isn't allowed, and a
/// new token wouldn't change that. It also calls [onForbidden], so the app
/// can check whether the staff member's roles changed (Phase 6).
///
/// Besides the usual [http.ClientException], [send] can throw
/// [ApiException]: `unauthorized` when there's no session or it was just
/// ended, and `network` when the refresh couldn't reach the server.
class AuthenticatedClient extends http.BaseClient {
  AuthenticatedClient(this._inner, this._sessions);

  final http.Client _inner;
  final SessionManager _sessions;

  /// Called after any 403. Set once the profile controller exists.
  void Function()? onForbidden;

  http.StreamedResponse _seen(http.StreamedResponse response) {
    if (response.statusCode == 403) onForbidden?.call();
    return response;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final session = _sessions.session;
    if (session == null) throw const ApiException(ApiFailure.unauthorized);

    // A streamed or multipart body can only be sent once, so those requests
    // can't be replayed. They still trigger a refresh on 401, so the next
    // call works.
    if (request is! http.Request) {
      request.headers['Authorization'] = 'Bearer ${session.accessToken}';
      final response = await _inner.send(request);
      if (response.statusCode == 401) await _tokenAfter401(session.accessToken);
      return _seen(response);
    }

    final response = await _inner.send(_copy(request, session.accessToken));
    if (response.statusCode != 401) return _seen(response);

    // Free the connection; the first answer is about to be replaced.
    await response.stream.drain<void>();
    final token = await _tokenAfter401(session.accessToken);
    final retry = await _inner.send(_copy(request, token));
    if (retry.statusCode == 401) {
      // A token the backend just issued was refused, so this session can't
      // be used any more (for example, the staff member was deactivated).
      _sessions.endSession();
    }
    return _seen(retry);
  }

  /// The token to retry with after [rejectedToken] got a 401.
  Future<String> _tokenAfter401(String rejectedToken) async {
    // Another request may already have refreshed while this one was in
    // flight; if so, use its token instead of refreshing again.
    final current = _sessions.session;
    if (current != null && current.accessToken != rejectedToken) {
      return current.accessToken;
    }
    return _sessions.refreshAccessToken();
  }

  static http.Request _copy(http.Request original, String accessToken) {
    final copy = http.Request(original.method, original.url)
      ..followRedirects = original.followRedirects
      ..maxRedirects = original.maxRedirects
      ..persistentConnection = original.persistentConnection
      ..headers.addAll(original.headers)
      ..headers['Authorization'] = 'Bearer $accessToken';
    copy.bodyBytes = original.bodyBytes;
    return copy;
  }

  @override
  void close() => _inner.close();
}
