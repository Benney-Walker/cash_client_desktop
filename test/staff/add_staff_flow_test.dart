import 'package:cash_client_desktop/auth/auth_session.dart';
import 'package:cash_client_desktop/staff/staff_page.dart';
import 'package:cash_client_desktop/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  late FakeStaffBackend backend;

  Future<void> pumpStaff(
    WidgetTester tester, {
    AuthSession session = adminSession,
    FakeStaffBackend? staffBackend,
  }) async {
    tester.view.physicalSize = const Size(1280, 1000);
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
  }

  Finder key(String name) => find.byKey(Key('addStaff.$name'));

  Future<void> next(WidgetTester tester) async {
    await tester.tap(key('next'));
    await tester.pumpAndSettle();
  }

  Future<void> openAddStaff(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('staff.add')));
    await tester.pumpAndSettle();
  }

  Future<void> fillPersonal(WidgetTester tester) async {
    await tester.enterText(key('firstName'), 'Ama');
    await tester.enterText(key('lastName'), 'Owusu');
    await tester.enterText(key('dateOfBirth'), '1994-03-21');
  }

  Future<void> fillContact(WidgetTester tester) async {
    await tester.enterText(key('phone'), '0241234567');
    await tester.enterText(key('email'), 'ama@example.com');
    await tester.enterText(key('address'), 'Hse 12, Tarkwa');
  }

  Future<void> chooseAgentAtTarkwa(WidgetTester tester) async {
    await tester.tap(key('role.agent'));
    await tester.pump();
    await tester.tap(key('branch'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tarkwa · Tarkwa Market').last);
    await tester.pumpAndSettle();
  }

  Future<void> goToReview(WidgetTester tester) async {
    await openAddStaff(tester);
    await fillPersonal(tester);
    await next(tester);
    await fillContact(tester);
    await next(tester);
    await chooseAgentAtTarkwa(tester);
    await next(tester);
  }

  group('Staff page', () {
    testWidgets('administrators see Add staff above the list',
        (tester) async {
      await pumpStaff(tester);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('staff.add')), findsOneWidget);
      expect(find.byKey(const Key('staff.search')), findsOneWidget);
    });

    testWidgets('agents see the list without Add staff', (tester) async {
      await pumpStaff(
        tester,
        session: const AuthSession(
          staffId: 'STF0020',
          staffName: 'EFUA ASANTE',
          roles: ['AGENT'],
          accessToken: 'a',
          refreshToken: 'r',
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byKey(const Key('staff.add')), findsNothing);
      expect(find.byKey(const Key('staff.search')), findsOneWidget);
    });
  });

  group('steps', () {
    testWidgets('opens on step 1 of 4', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpStaff(tester);
      await openAddStaff(tester);

      expect(key('personal'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Step 1 of 4')), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('step 1 asks for names and a valid date of birth',
        (tester) async {
      await pumpStaff(tester);
      await openAddStaff(tester);

      await next(tester);
      expect(find.text('Enter the first name'), findsOneWidget);
      expect(find.text('Enter the last name'), findsOneWidget);
      expect(find.text('Enter the date of birth'), findsOneWidget);

      await tester.enterText(key('dateOfBirth'), '2026-02-30');
      await next(tester);
      expect(find.text('Use the format yyyy-mm-dd'), findsOneWidget);

      await tester.enterText(key('dateOfBirth'), '2999-01-01');
      await next(tester);
      expect(find.textContaining("can't be in the future"), findsOneWidget);
      expect(key('personal'), findsOneWidget);
    });

    testWidgets('step 2 checks the phone number and email', (tester) async {
      await pumpStaff(tester);
      await openAddStaff(tester);
      await fillPersonal(tester);
      await next(tester);

      await tester.enterText(key('phone'), '241234567');
      await tester.enterText(key('email'), 'not-an-email');
      await next(tester);

      expect(find.text('Use 10 digits starting with 0'), findsOneWidget);
      expect(find.text('Enter a valid email address'), findsOneWidget);
      expect(find.text('Enter the residential address'), findsOneWidget);
      expect(key('contact'), findsOneWidget);
    });

    testWidgets('step 3 needs a role and a branch', (tester) async {
      await pumpStaff(tester);
      await openAddStaff(tester);
      await fillPersonal(tester);
      await next(tester);
      await fillContact(tester);
      await next(tester);

      await next(tester);

      expect(find.text('Choose at least one role'), findsOneWidget);
      expect(find.text('Choose a branch'), findsOneWidget);
      expect(key('rules'), findsOneWidget);
    });

    testWidgets('choosing Collector clears the other roles', (tester) async {
      await pumpStaff(tester);
      await openAddStaff(tester);
      await fillPersonal(tester);
      await next(tester);
      await fillContact(tester);
      await next(tester);

      await tester.tap(key('role.administrator'));
      await tester.tap(key('role.agent'));
      await tester.pump();
      expect(find.byIcon(Icons.check_box), findsNWidgets(2));

      await tester.tap(key('role.collector'));
      await tester.pump();
      expect(find.byIcon(Icons.check_box), findsOneWidget);
    });

    testWidgets('without the branch list, step 3 says so and blocks Next',
        (tester) async {
      await pumpStaff(
        tester,
        staffBackend: FakeStaffBackend(branchesStatus: 404),
      );
      await openAddStaff(tester);
      await fillPersonal(tester);
      await next(tester);
      await fillContact(tester);
      await next(tester);
      await tester.tap(key('role.agent'));
      await tester.pump();

      expect(find.textContaining("doesn't offer the branch list yet"),
          findsOneWidget);
      await next(tester);
      expect(key('roleAndBranch'), findsOneWidget);

      backend.branchesStatus = 200;
      await tester.tap(key('retryBranches'));
      await tester.pumpAndSettle();
      expect(key('branch'), findsOneWidget);
    });

    testWidgets('Back keeps what was entered', (tester) async {
      await pumpStaff(tester);
      await openAddStaff(tester);
      await fillPersonal(tester);
      await next(tester);

      await tester.tap(key('back'));
      await tester.pumpAndSettle();

      expect(find.text('Ama'), findsOneWidget);
      expect(find.text('1994-03-21'), findsOneWidget);
    });
  });

  group('review and submit', () {
    testWidgets('review shows everything and explains the password',
        (tester) async {
      await pumpStaff(tester);
      await goToReview(tester);

      expect(key('review'), findsOneWidget);
      expect(find.text('Ama Owusu'), findsOneWidget);
      expect(find.text('1994-03-21'), findsOneWidget);
      expect(find.text('0241234567'), findsOneWidget);
      expect(find.text('Agent'), findsOneWidget);
      expect(find.text('Tarkwa'), findsOneWidget);
      expect(find.textContaining('texts the staff ID to 0241234567'),
          findsOneWidget);
      expect(find.text('Add staff'), findsWidgets);
    });

    testWidgets('Edit goes back to that step', (tester) async {
      await pumpStaff(tester);
      await goToReview(tester);

      await tester.tap(find.byKey(const Key('addStaff.edit.Contact')));
      await tester.pumpAndSettle();

      expect(key('contact'), findsOneWidget);
      expect(find.text('0241234567'), findsOneWidget);
    });

    testWidgets('adding sends the details and shows the SMS message',
        (tester) async {
      await pumpStaff(tester);
      await goToReview(tester);

      await tester.tap(key('next'));
      await tester.pumpAndSettle();

      expect(backend.lastAdd['firstName'], 'Ama');
      expect(backend.lastAdd['dateOfBirth'], '1994-03-21');
      expect(backend.lastAdd['roles'], ['AGENT']);
      expect(backend.lastAdd['branchId'], 'b-tarkwa');
      expect(backend.lastAdd.containsKey('password'), isFalse);
      expect(key('added'), findsOneWidget);
      expect(find.textContaining('sent by SMS to 0241234567'), findsOneWidget);
    });

    testWidgets('a duplicate phone number offers to fix Contact',
        (tester) async {
      await pumpStaff(
        tester,
        staffBackend: FakeStaffBackend(
          addStatus: 409,
          addBody: errorBody(409, 'Phone number already exist'),
        ),
      );
      await goToReview(tester);

      await tester.tap(key('next'));
      await tester.pumpAndSettle();

      expect(key('error'), findsOneWidget);
      expect(find.textContaining('already uses this phone number'),
          findsOneWidget);

      await tester.tap(key('fixStep'));
      await tester.pumpAndSettle();
      expect(key('contact'), findsOneWidget);
    });

    testWidgets('a second active agent is explained', (tester) async {
      await pumpStaff(
        tester,
        staffBackend: FakeStaffBackend(
          addStatus: 409,
          addBody: errorBody(409, 'Branch Tarkwa already has an active agent'),
        ),
      );
      await goToReview(tester);

      await tester.tap(key('next'));
      await tester.pumpAndSettle();

      expect(find.textContaining('only one active agent'), findsOneWidget);
    });

    testWidgets('Add another starts again from step 1', (tester) async {
      await pumpStaff(tester);
      await goToReview(tester);
      await tester.tap(key('next'));
      await tester.pumpAndSettle();

      await tester.tap(key('addAnother'));
      await tester.pumpAndSettle();

      expect(key('personal'), findsOneWidget);
      expect(find.text('Ama'), findsNothing);
    });

    testWidgets('Back to staff returns to the Staff page', (tester) async {
      await pumpStaff(tester);
      await goToReview(tester);
      await tester.tap(key('next'));
      await tester.pumpAndSettle();

      await tester.tap(key('done'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('staff.add')), findsOneWidget);
    });
  });

  group('leaving', () {
    testWidgets('cancelling an empty form leaves straight away',
        (tester) async {
      await pumpStaff(tester);
      await openAddStaff(tester);

      await tester.tap(key('back'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('staff.add')), findsOneWidget);
    });

    testWidgets('cancelling with details entered asks first', (tester) async {
      await pumpStaff(tester);
      await openAddStaff(tester);
      await tester.enterText(key('firstName'), 'Ama');

      await tester.tap(key('back'));
      await tester.pumpAndSettle();
      expect(find.text('Discard this new staff member?'), findsOneWidget);

      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(key('personal'), findsOneWidget);

      await tester.tap(key('breadcrumb'));
      await tester.pumpAndSettle();
      await tester.tap(key('discard'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('staff.add')), findsOneWidget);
    });
  });
}
