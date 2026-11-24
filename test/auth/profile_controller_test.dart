import 'package:cash_client_desktop/api/api_exception.dart';
import 'package:cash_client_desktop/auth/profile_controller.dart';
import 'package:cash_client_desktop/auth/session_manager.dart';
import 'package:cash_client_desktop/auth/staff_profile.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

Future<void> settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

StaffProfile profileWith(Set<String> roles, {String branch = 'Tarkwa'}) =>
    StaffProfile(
      staffId: 'STF001',
      roles: roles,
      fullName: 'Kofi Mensah',
      branchId: 'b-tarkwa',
      branchName: branch,
    );

void main() {
  late FakeRefreshApi auth;
  late SessionManager sessions;
  late int fetches;
  late Object Function() answer;
  late ProfileController profile;

  setUp(() {
    auth = FakeRefreshApi(FakeRefreshApi.rotates('access-2', 'refresh-2'));
    sessions = SessionManager(api: auth.api);
    fetches = 0;
    answer = () => profileWith({'ADMINISTRATOR'});
    profile = ProfileController(
      sessions: sessions,
      fetch: () async {
        fetches++;
        final value = answer();
        if (value is StaffProfile) return value;
        throw value;
      },
    );
  });

  tearDown(() => profile.dispose());

  test('reads the profile once a staff member signs in', () async {
    expect(profile.profile, isNull);
    expect(fetches, 0);

    await sessions.signIn(staffId: 'STF001', password: 'x');
    await settle();

    expect(fetches, 1);
    expect(profile.branchName, 'Tarkwa');
  });

  test("a token refresh doesn't read it again; a new sign-in does",
      () async {
    await sessions.signIn(staffId: 'STF001', password: 'x');
    await settle();

    await sessions.refreshAccessToken();
    await settle();
    expect(fetches, 1);

    answer = () => profileWith({'ADMINISTRATOR'}, branch: 'Bogoso');
    await sessions.signIn(staffId: 'STF001', password: 'x');
    await settle();
    expect(fetches, 2);
    expect(profile.branchName, 'Bogoso');
  });

  test('signing out forgets it', () async {
    await sessions.signIn(staffId: 'STF001', password: 'x');
    await settle();

    sessions.signOut();
    await settle();

    expect(profile.profile, isNull);
  });

  test('a profile that fails to load leaves the branch out', () async {
    answer = () => const ApiException(ApiFailure.network);
    await sessions.signIn(staffId: 'STF001', password: 'x');
    await settle();

    expect(profile.profile, isNull);
    expect(sessions.session, isNotNull);
  });

  test('roles that differ from the sign-in sign the staff member out',
      () async {
    answer = () => profileWith({'AGENT'});
    await sessions.signIn(staffId: 'STF001', password: 'x');
    await settle();

    expect(sessions.session, isNull);
    expect(sessions.signInNotice, SessionManager.rolesChangedNotice);
  });

  test("a profile refused with 403 (no longer office staff) signs out",
      () async {
    answer = () => const ApiException(ApiFailure.forbidden);
    await sessions.signIn(staffId: 'STF001', password: 'x');
    await settle();

    expect(sessions.session, isNull);
    expect(sessions.signInNotice, SessionManager.rolesChangedNotice);
  });

  group('checkRoles after a 403', () {
    test('keeps the session when the roles are the same', () async {
      await sessions.signIn(staffId: 'STF001', password: 'x');
      await settle();

      await profile.checkRoles();

      expect(fetches, 2);
      expect(sessions.session, isNotNull);
    });

    test('signs out when an administrator changed the roles', () async {
      await sessions.signIn(staffId: 'STF001', password: 'x');
      await settle();

      answer = () => profileWith({'AGENT'});
      await profile.checkRoles();

      expect(sessions.session, isNull);
      expect(sessions.signInNotice, SessionManager.rolesChangedNotice);
    });

    test('overlapping 403s check once', () async {
      await sessions.signIn(staffId: 'STF001', password: 'x');
      await settle();

      await Future.wait([profile.checkRoles(), profile.checkRoles()]);

      expect(fetches, 2);
    });

    test('does nothing when signed out', () async {
      await profile.checkRoles();
      expect(fetches, 0);
    });
  });

  test('profile JSON reads the branch and roles', () {
    final p = StaffProfile.fromJson({
      'staffId': 'STF0020',
      'firstName': 'Efua',
      'middleName': null,
      'lastName': 'Asante',
      'branchId': 'b-1',
      'branchName': 'Tarkwa Market',
      'roles': ['AGENT'],
      'status': 'ACTIVE',
    })!;
    expect(p.fullName, 'Efua Asante');
    expect(p.roles, {'AGENT'});
    expect(p.branchName, 'Tarkwa Market');
    expect(StaffProfile.fromJson({'staffId': 'X'}), isNull);
  });
}
