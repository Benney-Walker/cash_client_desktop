import 'package:cash_client_desktop/api/api_exception.dart';
import 'package:cash_client_desktop/auth/auth_session.dart';
import 'package:cash_client_desktop/staff/staff_api.dart';
import 'package:cash_client_desktop/staff/staff_models.dart';
import 'package:cash_client_desktop/staff/staff_page.dart';
import 'package:cash_client_desktop/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

const agentSession = AuthSession(
  staffId: 'STF0020',
  staffName: 'EFUA ASANTE',
  roles: ['AGENT'],
  accessToken: 'a',
  refreshToken: 'r',
);

void main() {
  late FakeStaffBackend backend;

  Future<void> pumpStaff(
    WidgetTester tester, {
    AuthSession session = adminSession,
    FakeStaffBackend? staffBackend,
  }) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    backend = staffBackend ?? FakeStaffBackend();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: StaffPage(
            session: session,
            api: backend.api,
            branchApi: backend.branchApi,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder key(String name) => find.byKey(Key(name));

  Future<void> select(WidgetTester tester, String staffId) async {
    await tester.tap(key('staff.item.$staffId'));
    await tester.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester tester, String name) async {
    await tester.ensureVisible(key(name));
    await tester.tap(key(name));
    await tester.pumpAndSettle();
  }

  group('list', () {
    testWidgets('shows everyone sorted by name, with their status',
        (tester) async {
      await pumpStaff(tester);

      final names = tester
          .widgetList<ListTile>(find.byType(ListTile))
          .map((t) => (t.title as Text).data)
          .toList();
      expect(names, [
        'Akosua Darko',
        'Efua Asante',
        'Kofi Mensah',
        'Kwame Owusu',
        'Yaw Boateng',
      ]);
      expect(find.text('5 staff'), findsOneWidget);
      expect(
        find.descendant(
          of: key('staff.item.STF0044'),
          matching: find.text('Locked'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: key('staff.item.STF0050'),
          matching: find.text('Inactive'),
        ),
        findsOneWidget,
      );
      expect(key('staff.nothingSelected'), findsOneWidget);
    });

    testWidgets('search matches names and staff IDs', (tester) async {
      await pumpStaff(tester);

      await tester.enterText(key('staff.search'), 'boat');
      await tester.pump();
      expect(key('staff.item.STF0031'), findsOneWidget);
      expect(find.text('1 staff member'), findsOneWidget);

      await tester.enterText(key('staff.search'), 'stf0050');
      await tester.pump();
      expect(key('staff.item.STF0050'), findsOneWidget);
      expect(key('staff.item.STF0031'), findsNothing);

      await tester.enterText(key('staff.search'), 'nobody');
      await tester.pump();
      expect(key('staff.empty'), findsOneWidget);
    });

    testWidgets('filters by role and status', (tester) async {
      await pumpStaff(tester);

      await tester.tap(key('staff.roleFilter'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Collector').last);
      await tester.pumpAndSettle();
      expect(find.text('2 staff'), findsOneWidget);

      await tester.tap(key('staff.statusFilter'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Locked').last);
      await tester.pumpAndSettle();
      expect(find.text('1 staff member'), findsOneWidget);
      expect(key('staff.item.STF0044'), findsOneWidget);
    });

    testWidgets('a failed list offers to try again', (tester) async {
      final failing = FakeStaffBackend()..listStatus = 500;
      await pumpStaff(tester, staffBackend: failing);

      expect(key('staff.listError'), findsOneWidget);
      failing.listStatus = 200;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('5 staff'), findsOneWidget);
    });
  });

  group('administrator actions', () {
    testWidgets('an agent shows Edit, Change roles and Deactivate',
        (tester) async {
      await pumpStaff(tester);
      await select(tester, 'STF0020');

      expect(key('staff.name'), findsOneWidget);
      expect(find.text('Efua Asante'), findsWidgets);
      expect(key('staff.edit'), findsOneWidget);
      expect(key('staff.roles'), findsOneWidget);
      expect(key('staff.deactivate'), findsOneWidget);
      expect(key('staff.unlock'), findsNothing);
      expect(key('staff.release'), findsNothing);
      expect(key('staff.reactivate'), findsNothing);
    });

    testWidgets("can't deactivate themselves", (tester) async {
      await pumpStaff(tester);
      await select(tester, 'STF0012');

      expect(key('staff.deactivate'), findsNothing);
      expect(key('staff.edit'), findsOneWidget);
    });

    testWidgets('unlock clears the lock', (tester) async {
      await pumpStaff(tester);
      await select(tester, 'STF0044');
      expect(key('staff.field.Locked'), findsOneWidget);

      await tapKey(tester, 'staff.unlock');

      expect(backend.actionPaths,
          ['POST /api/admin/v1/staff/STF0044/unlock']);
      expect(key('staff.done'), findsOneWidget);
      expect(key('staff.unlock'), findsNothing);
      expect(key('staff.field.Locked'), findsNothing);
      expect(
        find.descendant(
          of: key('staff.item.STF0044'),
          matching: find.text('Active'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('deactivate asks first, and Cancel sends nothing',
        (tester) async {
      await pumpStaff(tester);
      await select(tester, 'STF0020');

      await tapKey(tester, 'staff.deactivate');
      expect(key('staff.confirmDialog'), findsOneWidget);
      await tapKey(tester, 'staff.confirmCancel');
      expect(backend.actionPaths, isEmpty);

      await tapKey(tester, 'staff.deactivate');
      await tapKey(tester, 'staff.confirm');
      expect(backend.actionPaths, ['POST /api/staff/v1/deactivate/STF0020']);
      expect(key('staff.reactivate'), findsOneWidget);
      expect(key('staff.deactivate'), findsNothing);
    });

    testWidgets('reactivate needs no confirmation', (tester) async {
      await pumpStaff(tester);
      await select(tester, 'STF0050');

      await tapKey(tester, 'staff.reactivate');
      expect(backend.actionPaths, ['POST /api/staff/v1/reactivate/STF0050']);
      expect(key('staff.deactivate'), findsOneWidget);
    });

    testWidgets('edit fills the form in local phone format and saves',
        (tester) async {
      await pumpStaff(tester);
      await select(tester, 'STF0020');
      await tapKey(tester, 'staff.edit');

      final phone = tester.widget<TextField>(find.descendant(
        of: key('staff.phone'),
        matching: find.byType(TextField),
      ));
      expect(phone.controller!.text, '0241234567');

      await tester.enterText(key('staff.lastName'), 'Asante-Boakye');
      await tester.enterText(key('staff.phone'), '0551112222');
      await tapKey(tester, 'staff.save');

      expect(backend.actionPaths, ['PUT /api/staff/v1/update-staff/STF0020']);
      final sent = backend.requests.last.body;
      expect(sent, contains('"lastName":"Asante-Boakye"'));
      expect(sent, contains('"phoneNumber":"0551112222"'));
      expect(sent, contains('"dateOfBirth":"1990-05-04"'));
      expect(key('staff.editForm'), findsNothing);
      expect(find.text('Efua Asante-Boakye'), findsWidgets);
    });

    testWidgets('edit checks the fields before sending', (tester) async {
      await pumpStaff(tester);
      await select(tester, 'STF0020');
      await tapKey(tester, 'staff.edit');

      await tester.enterText(key('staff.phone'), '24123');
      await tester.enterText(key('staff.email'), 'nope');
      await tapKey(tester, 'staff.save');

      expect(find.text('Use 10 digits starting with 0'), findsOneWidget);
      expect(find.text('Enter a valid email address'), findsOneWidget);
      expect(backend.actionPaths, isEmpty);

      await tapKey(tester, 'staff.cancel');
      expect(key('staff.detailsCard'), findsOneWidget);
    });

    testWidgets('change roles follows the collector rule and saves',
        (tester) async {
      await pumpStaff(tester);
      await select(tester, 'STF0020');
      await tapKey(tester, 'staff.roles');

      await tapKey(tester, 'staffRoles.role.administrator');
      await tapKey(tester, 'staff.save');

      expect(backend.actionPaths, ['PUT /api/staff/v1/update-roles/STF0020']);
      expect(backend.requests.last.body,
          '{"roles":["ADMINISTRATOR","AGENT"]}');
      expect(find.text('Administrator and Agent'), findsWidgets);
    });

    testWidgets('no roles is refused before sending', (tester) async {
      await pumpStaff(tester);
      await select(tester, 'STF0020');
      await tapKey(tester, 'staff.roles');

      await tapKey(tester, 'staffRoles.role.agent');
      await tapKey(tester, 'staff.save');

      expect(find.text('Choose at least one role.'), findsOneWidget);
      expect(backend.actionPaths, isEmpty);
    });

    testWidgets("shows the backend's reason when an action is refused",
        (tester) async {
      final refusing = FakeStaffBackend()
        ..actionStatus = 409
        ..actionMessage = 'Branch Tarkwa Market already has an active agent';
      await pumpStaff(tester, staffBackend: refusing);
      await select(tester, 'STF0050');

      await tapKey(tester, 'staff.reactivate');

      expect(key('staff.error'), findsOneWidget);
      expect(find.text('Branch Tarkwa Market already has an active agent.'),
          findsOneWidget);
      expect(key('staff.reactivate'), findsOneWidget);
    });
  });

  group('release phone', () {
    testWidgets('asks first, then clears the registered phone',
        (tester) async {
      await pumpStaff(tester);
      await select(tester, 'STF0031');
      expect(key('staff.field.Registered phone'), findsOneWidget);
      expect(find.textContaining('Since 2026-11-02'), findsOneWidget);

      await tapKey(tester, 'staff.release');
      await tapKey(tester, 'staff.confirm');

      expect(backend.actionPaths, [
        'POST /api/staff/v1/collectors/STF0031/release-device',
        'GET /api/staff/v1/staff-details/STF0031',
      ]);
      expect(key('staff.done'), findsOneWidget);
      expect(key('staff.release'), findsNothing);
      expect(find.textContaining('None yet'), findsOneWidget);
    });

    testWidgets('still shows the release when the read-back fails',
        (tester) async {
      await pumpStaff(
        tester,
        staffBackend: FakeStaffBackend()..detailsWork = false,
      );
      await select(tester, 'STF0031');

      await tapKey(tester, 'staff.release');
      await tapKey(tester, 'staff.confirm');

      expect(key('staff.done'), findsOneWidget);
      expect(key('staff.error'), findsNothing);
      expect(find.textContaining('None yet'), findsOneWidget);
    });

    testWidgets("isn't offered for a collector with no registered phone",
        (tester) async {
      await pumpStaff(tester);
      await select(tester, 'STF0044');

      expect(key('staff.release'), findsNothing);
    });
  });

  group('agents', () {
    testWidgets('see no Add staff and only Release phone', (tester) async {
      await pumpStaff(tester, session: agentSession);
      expect(key('staff.add'), findsNothing);

      await select(tester, 'STF0031');
      expect(key('staff.release'), findsOneWidget);
      expect(key('staff.edit'), findsNothing);
      expect(key('staff.roles'), findsNothing);
      expect(key('staff.deactivate'), findsNothing);

      await select(tester, 'STF0044');
      expect(key('staff.unlock'), findsNothing);

      await select(tester, 'STF0050');
      expect(key('staff.reactivate'), findsNothing);
    });
  });

  group('models', () {
    test('local phone number turns +233 into 0', () {
      final member = StaffMember.fromJson(
        staffJson('STF1', 'Ama', 'Owusu'),
      )!;
      expect(member.localPhoneNumber, '0241234567');
      expect(member.rolesLabel, 'Agent');
      expect(member.isActive, isTrue);
    });

    test('a 403 with no message reads as administrators only', () {
      expect(
        staffActionErrorMessage(const ApiException(ApiFailure.forbidden)),
        'Only administrators can do this.',
      );
    });
  });
}
