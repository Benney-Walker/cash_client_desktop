import 'package:cash_client_desktop/api/api_exception.dart';
import 'package:cash_client_desktop/auth/auth_session.dart';
import 'package:cash_client_desktop/auth/session_manager.dart';
import 'package:cash_client_desktop/auth/sign_in.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  group('signIn', () {
    test('an administrator is signed in', () async {
      final sessions = SessionManager(api: fakeAuthApi(200, loginBody()));

      await sessions.signIn(staffId: 'STF001', password: 'x');

      expect(sessions.session?.staffId, 'STF001');
      expect(sessions.session?.role, StaffRole.administrator);
      expect(sessions.sessionEndedByServer, isFalse);
    });

    test('an agent is signed in as an agent', () async {
      final sessions = SessionManager(
        api: fakeAuthApi(200, loginBody(roles: ['AGENT'])),
      );

      await sessions.signIn(staffId: 'STF002', password: 'x');

      expect(sessions.session?.role, StaffRole.agent);
    });

    test('someone with both roles is treated as an administrator', () async {
      final sessions = SessionManager(
        api: fakeAuthApi(200, loginBody(roles: ['AGENT', 'ADMINISTRATOR'])),
      );

      await sessions.signIn(staffId: 'STF003', password: 'x');

      expect(sessions.session?.role, StaffRole.administrator);
    });

    test('a collector who also has an office role is allowed', () async {
      final sessions = SessionManager(
        api: fakeAuthApi(200, loginBody(roles: ['COLLECTOR', 'AGENT'])),
      );

      await sessions.signIn(staffId: 'STF004', password: 'x');

      expect(sessions.session?.role, StaffRole.agent);
    });

    test('a collector is refused and no session is kept', () async {
      final sessions = SessionManager(
        api: fakeAuthApi(200, loginBody(roles: ['COLLECTOR'])),
      );
      var notified = 0;
      sessions.addListener(() => notified++);

      await expectLater(
        sessions.signIn(staffId: 'STF005', password: 'x'),
        throwsA(isA<NotOfficeStaffException>()),
      );
      expect(sessions.session, isNull);
      expect(notified, 0);
    });

    test('a failed login passes the API error on', () async {
      final sessions = SessionManager(
        api: fakeAuthApi(401, errorBody(401, 'Invalid ID or password')),
      );

      await expectLater(
        sessions.signIn(staffId: 'STF001', password: 'wrong'),
        throwsA(isA<ApiException>()
            .having((e) => e.failure, 'failure', ApiFailure.unauthorized)),
      );
      expect(sessions.session, isNull);
    });
  });

  group('signOut and endSession', () {
    late SessionManager sessions;

    setUp(() async {
      sessions = SessionManager(api: fakeAuthApi(200, loginBody()));
      await sessions.signIn(staffId: 'STF001', password: 'x');
    });

    test('signing out forgets the session', () {
      sessions.signOut();

      expect(sessions.session, isNull);
      expect(sessions.sessionEndedByServer, isFalse);
    });

    test('the backend ending it is remembered for the sign-in screen', () {
      sessions.endSession();

      expect(sessions.session, isNull);
      expect(sessions.sessionEndedByServer, isTrue);
    });

    test('signing in again clears the ended flag', () async {
      sessions.endSession();

      await sessions.signIn(staffId: 'STF001', password: 'x');

      expect(sessions.sessionEndedByServer, isFalse);
    });
  });

  group('refreshAccessToken', () {
    late FakeRefreshApi backend;
    late SessionManager sessions;

    Future<void> start((int, String) refresh, {Duration? delay}) async {
      backend = FakeRefreshApi(refresh, delay: delay ?? Duration.zero);
      sessions = SessionManager(api: backend.api);
      await sessions.signIn(staffId: 'STF001', password: 'x');
    }

    test('keeps the new access token and the same refresh token', () async {
      await start(FakeRefreshApi.issues('new.access.token'));

      final token = await sessions.refreshAccessToken();

      expect(token, 'new.access.token');
      expect(sessions.session?.accessToken, 'new.access.token');
      expect(sessions.session?.refreshToken, 'refresh-token');
    });

    test('accepts the token as a JSON string too', () async {
      await start((200, '"new.access.token"'));

      expect(await sessions.refreshAccessToken(), 'new.access.token');
    });

    test('overlapping callers share one refresh call', () async {
      await start(
        FakeRefreshApi.issues('new.access.token'),
        delay: const Duration(milliseconds: 20),
      );

      final results = await Future.wait([
        sessions.refreshAccessToken(),
        sessions.refreshAccessToken(),
        sessions.refreshAccessToken(),
      ]);

      expect(results, everyElement('new.access.token'));
      expect(backend.calls, 1);
    });

    test('a refused refresh ends the session', () async {
      await start(FakeRefreshApi.refuses());

      await expectLater(
        sessions.refreshAccessToken(),
        throwsA(isA<ApiException>()
            .having((e) => e.failure, 'failure', ApiFailure.unauthorized)),
      );
      expect(sessions.session, isNull);
      expect(sessions.sessionEndedByServer, isTrue);
    });

    test('no connection keeps the session', () async {
      await start(FakeRefreshApi.issues('new.access.token'));
      backend.offline = true;

      await expectLater(
        sessions.refreshAccessToken(),
        throwsA(isA<ApiException>()
            .having((e) => e.failure, 'failure', ApiFailure.network)),
      );
      expect(sessions.session, isNotNull);
    });

    test('a sign-out during the refresh is not undone', () async {
      await start(
        FakeRefreshApi.issues('new.access.token'),
        delay: const Duration(milliseconds: 20),
      );

      final refreshing = sessions.refreshAccessToken();
      sessions.signOut();
      await refreshing;

      expect(sessions.session, isNull);
    });
  });

  group('signInErrorMessage', () {
    test('explains who the app is for', () {
      expect(
        signInErrorMessage(const NotOfficeStaffException()),
        contains('administrators and agents'),
      );
    });

    test('maps each API failure to a message', () {
      for (final failure in ApiFailure.values) {
        expect(signInErrorMessage(ApiException(failure)), isNotEmpty);
      }
      expect(
        signInErrorMessage(const ApiException(ApiFailure.unauthorized)),
        'Wrong staff ID or password.',
      );
    });
  });
}
