import 'package:cash_client_desktop/api/api_exception.dart';
import 'package:cash_client_desktop/auth/auth_session.dart';
import 'package:cash_client_desktop/auth/session_manager.dart';
import 'package:cash_client_desktop/auth/sign_in.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

/// Lets the background logout call finish.
Future<void> settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

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

    test('keeps both new tokens and uses the new refresh token next time',
        () async {
      await start(FakeRefreshApi.rotates('new.access.token', 'refresh-2'));

      expect(await sessions.refreshAccessToken(), 'new.access.token');
      expect(sessions.session?.refreshToken, 'refresh-2');

      backend.refresh = FakeRefreshApi.rotates('third.access.token', 'refresh-3');
      await sessions.refreshAccessToken();

      expect(backend.refreshedWith, ['refresh-token', 'refresh-2']);
      expect(sessions.session?.refreshToken, 'refresh-3');
    });

    test('an older backend keeps the same refresh token', () async {
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

    test('a sign-out during a rotating refresh ends the new session too',
        () async {
      await start(
        FakeRefreshApi.rotates('new.access.token', 'refresh-2'),
        delay: const Duration(milliseconds: 20),
      );

      final refreshing = sessions.refreshAccessToken();
      sessions.signOut();
      await refreshing;
      await settle();

      expect(sessions.session, isNull);
      expect(backend.loggedOut, containsAll(['refresh-token', 'refresh-2']));
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

  group('backend logout', () {
    test('signing out ends the session on the backend', () async {
      final backend = FakeRefreshApi(FakeRefreshApi.refuses());
      final sessions = SessionManager(api: backend.api);
      await sessions.signIn(staffId: 'STF001', password: 'x');

      sessions.signOut();
      await settle();

      expect(sessions.session, isNull);
      expect(backend.loggedOut, ['refresh-token']);
    });

    test('signing in again (unlock) ends the previous session afterwards',
        () async {
      final backend = FakeRefreshApi(FakeRefreshApi.refuses());
      final sessions = SessionManager(api: backend.api);
      await sessions.signIn(staffId: 'STF001', password: 'x');

      await sessions.signIn(staffId: 'STF001', password: 'x');
      await settle();

      expect(sessions.session?.refreshToken, 'refresh-token-2');
      expect(backend.loggedOut, ['refresh-token']);
    });

    test("a refused collector's tokens are ended on the backend", () async {
      final backend = FakeRefreshApi(
        FakeRefreshApi.refuses(),
        loginRoles: const ['COLLECTOR'],
      );
      final sessions = SessionManager(api: backend.api);

      await expectLater(
        sessions.signIn(staffId: 'COL001', password: 'x'),
        throwsA(isA<NotOfficeStaffException>()),
      );
      await settle();

      expect(backend.loggedOut, ['refresh-token']);
    });

    test('the backend ending the session sends no logout', () async {
      final backend = FakeRefreshApi(FakeRefreshApi.refuses());
      final sessions = SessionManager(api: backend.api);
      await sessions.signIn(staffId: 'STF001', password: 'x');

      sessions.endSession();
      await settle();

      expect(backend.loggedOut, isEmpty);
    });

    test('a failed logout still signs out', () async {
      final sessions = SessionManager(api: fakeAuthApi(200, loginBody()));
      await sessions.signIn(staffId: 'STF001', password: 'x');

      // fakeAuthApi answers the logout with the login body and 200; any
      // answer, or none, leaves the staff member signed out.
      sessions.signOut();
      await settle();

      expect(sessions.session, isNull);
    });
  });

  group('signInNotice', () {
    test('a reason given at sign-out is shown, and cleared by signing in',
        () async {
      final sessions = SessionManager(api: fakeAuthApi(200, loginBody()));
      await sessions.signIn(staffId: 'STF001', password: 'x');

      sessions.signOut(notice: 'This account is locked.');
      expect(sessions.signInNotice, 'This account is locked.');

      await sessions.signIn(staffId: 'STF001', password: 'x');
      expect(sessions.signInNotice, isNull);
    });

    test('a plain sign-out has no notice; a server-ended session has one',
        () async {
      final sessions = SessionManager(api: fakeAuthApi(200, loginBody()));
      await sessions.signIn(staffId: 'STF001', password: 'x');

      sessions.signOut();
      expect(sessions.signInNotice, isNull);

      await sessions.signIn(staffId: 'STF001', password: 'x');
      sessions.endSession();
      expect(sessions.signInNotice, sessionEndedNotice);
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
        startsWith('Wrong staff ID or password.'),
      );
      // The office login endpoint answers 403 for collectors.
      expect(
        signInErrorMessage(const ApiException(ApiFailure.forbidden,
            message: 'Collectors sign in through the collector app')),
        contains('administrators and agents'),
      );
    });

    test('a locked account gets the backend\'s own words, not the '
        'collectors message', () {
      const locked = ApiException(
        ApiFailure.forbidden,
        message: 'This account is locked after 5 wrong passwords. Ask an '
            'administrator to unlock it',
        statusCode: 403,
      );

      expect(isAccountLocked(locked), isTrue);
      expect(
        signInErrorMessage(locked),
        'This account is locked after 5 wrong passwords. Ask an '
        'administrator to unlock it.',
      );
      expect(
        isAccountLocked(const ApiException(ApiFailure.forbidden,
            message: 'Collectors sign in through the collector app')),
        isFalse,
      );
      expect(isAccountLocked(const ApiException(ApiFailure.unauthorized)),
          isFalse);
    });
  });

  group('unlocking with changed roles', () {
    test('signs out with an explanation and ends both sessions', () async {
      final auth = FakeRefreshApi(FakeRefreshApi.refuses());
      final sessions = SessionManager(api: auth.api);
      await sessions.signIn(staffId: 'STF001', password: 'x');
      final first = sessions.signInCount;

      auth.loginRoles = ['AGENT'];
      await sessions.signIn(staffId: 'STF001', password: 'x');
      await settle();

      expect(sessions.session, isNull);
      expect(sessions.signInNotice, SessionManager.rolesChangedNotice);
      expect(sessions.signInCount, first);
      expect(auth.loggedOut, containsAll(['refresh-token', 'refresh-token-2']));
    });

    test('the same roles carry on and count a new sign-in', () async {
      final auth = FakeRefreshApi(FakeRefreshApi.refuses());
      final sessions = SessionManager(api: auth.api);
      await sessions.signIn(staffId: 'STF001', password: 'x');
      await sessions.signIn(staffId: 'STF001', password: 'x');

      expect(sessions.session, isNotNull);
      expect(sessions.signInCount, 2);
    });
  });
}
