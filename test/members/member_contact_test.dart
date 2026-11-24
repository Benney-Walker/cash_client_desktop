import 'dart:convert';

import 'package:cash_client_desktop/members/member_api.dart';
import 'package:cash_client_desktop/members/member_details_pane.dart';
import 'package:cash_client_desktop/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  late FakeMemberBackend members;
  late FakeApprovalBackend approvals;

  Future<void> pumpPane(
    WidgetTester tester, {
    required bool admin,
    FakeMemberBackend? memberBackend,
    FakeApprovalBackend? approvalBackend,
    bool limited = false,
  }) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    members = memberBackend ?? FakeMemberBackend();
    members.profiles['m-1'] ??=
        FakeMemberBackend.profileJson(id: 'm-1', limited: limited);
    approvals = approvalBackend ?? FakeApprovalBackend(updates: []);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: MemberDetailsPane(
          api: members.api,
          memberId: 'm-1',
          approvalApi: approvals.api,
          isAdministrator: admin,
          acceptDrops: false,
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Finder key(String name) => find.byKey(Key('memberDetails.$name'));

  Future<void> tapKey(WidgetTester tester, String name) async {
    await tester.ensureVisible(key(name));
    await tester.tap(key(name));
    await tester.pumpAndSettle();
  }

  String fieldText(WidgetTester tester, String name) => tester
      .widget<TextField>(
          find.descendant(of: key(name), matching: find.byType(TextField)))
      .controller!
      .text;

  group('Administrators', () {
    testWidgets('edit contact details directly and see them saved',
        (tester) async {
      await pumpPane(tester, admin: true);
      expect(key('requestChange'), findsNothing);

      await tapKey(tester, 'editContact');
      expect(fieldText(tester, 'phone'), '0241234567');
      expect(fieldText(tester, 'address'), 'Hse 3, Tarkwa');
      expect(fieldText(tester, 'occupation'), 'Trader');

      await tester.enterText(key('phone'), '0559998887');
      await tester.enterText(key('occupation'), 'Teacher');
      await tapKey(tester, 'saveContact');

      expect(members.contactCalls.single.$1, 'PUT');
      expect(members.contactCalls.single.$2, {
        'phoneNumber': '0559998887',
        'residentialAddress': 'Hse 3, Tarkwa',
        'occupation': 'Teacher',
      });
      expect(key('contactForm'), findsNothing);
      expect(key('contactDone'), findsOneWidget);
      expect(find.text('0559998887'), findsOneWidget);
      expect(find.text('Teacher'), findsOneWidget);
    });

    testWidgets('checks the fields before sending', (tester) async {
      await pumpPane(tester, admin: true);
      await tapKey(tester, 'editContact');

      await tester.enterText(key('phone'), '24123');
      await tester.enterText(key('address'), ' ');
      await tapKey(tester, 'saveContact');

      expect(find.text('Use 10 digits starting with 0'), findsOneWidget);
      expect(find.text('Enter the residential address'), findsOneWidget);
      expect(members.contactCalls, isEmpty);

      await tapKey(tester, 'cancelContact');
      expect(key('contactForm'), findsNothing);
      expect(key('editContact'), findsOneWidget);
    });

    testWidgets('a phone number another member has is explained',
        (tester) async {
      final backend = FakeMemberBackend()
        ..contactAnswers.add(
            (409, errorBody(409, 'A member with this phone number already exists.')));
      await pumpPane(tester, admin: true, memberBackend: backend);
      await tapKey(tester, 'editContact');
      await tester.enterText(key('phone'), '0559998887');
      await tapKey(tester, 'saveContact');

      expect(key('contactError'), findsOneWidget);
      expect(find.text('Another member already uses this phone number.'),
          findsOneWidget);
      expect(key('contactForm'), findsOneWidget);
    });

    testWidgets('see when a change is waiting in Approvals', (tester) async {
      await pumpPane(
        tester,
        admin: true,
        approvalBackend: FakeApprovalBackend(
          updates: [updateRequestJson(memberId: 'm-1')],
        ),
      );

      expect(key('pendingForAdmin'), findsOneWidget);
      expect(find.textContaining('STF0020 asked to change'), findsOneWidget);
      // Administrators can still edit directly.
      expect(key('editContact'), findsOneWidget);
    });
  });

  group('Agents', () {
    testWidgets('send a change for approval and see it waiting',
        (tester) async {
      await pumpPane(tester, admin: false);
      expect(key('editContact'), findsNothing);
      expect(key('request'), findsNothing);

      await tapKey(tester, 'requestChange');
      await tester.enterText(key('phone'), '0559998887');
      await tapKey(tester, 'saveContact');

      expect(members.contactCalls.single.$1, 'POST');
      expect(members.contactCalls.single.$2['phoneNumber'], '0559998887');
      expect(key('contactDone'), findsOneWidget);
      expect(key('request'), findsOneWidget);
      expect(find.text('Change waiting for approval'), findsOneWidget);
      expect(find.text('0559998887'), findsOneWidget);
      // One waiting change per member: no second request.
      expect(key('requestChange'), findsNothing);
      // The member's own details don't change until it's approved.
      expect(find.text('0241234567'), findsOneWidget);
    });

    testWidgets('see their last request rejected, with the reason',
        (tester) async {
      final backend = FakeMemberBackend()
        ..myRequests = [
          updateRequestJson(
            memberId: 'other',
            requestId: 'req-x',
          ),
          updateRequestJson(
            memberId: 'm-1',
            status: 'REJECTED',
            reviewedBy: 'STF0012',
            rejectionReason: 'Wrong number',
          ),
        ];
      await pumpPane(tester, admin: false, memberBackend: backend);

      expect(key('request'), findsOneWidget);
      expect(find.text('Your change was rejected'), findsOneWidget);
      expect(find.text('Wrong number'), findsOneWidget);
      expect(key('requestChange'), findsOneWidget);
    });

    testWidgets("someone else's waiting change is explained", (tester) async {
      final backend = FakeMemberBackend()
        ..contactAnswers.add((
          409,
          errorBody(409, 'This member already has a change waiting for approval'),
        ));
      await pumpPane(tester, admin: false, memberBackend: backend);
      await tapKey(tester, 'requestChange');
      await tester.enterText(key('phone'), '0559998887');
      await tapKey(tester, 'saveContact');

      expect(find.textContaining('already has a change waiting'),
          findsOneWidget);
    });

    testWidgets('a lost answer says to refresh before trying again',
        (tester) async {
      final backend = FakeMemberBackend()..dropNextContact();
      await pumpPane(tester, admin: false, memberBackend: backend);
      await tapKey(tester, 'requestChange');
      await tester.enterText(key('phone'), '0559998887');
      await tapKey(tester, 'saveContact');

      expect(find.textContaining("isn't clear whether the change"),
          findsOneWidget);
    });

    testWidgets("isn't offered for another branch's member", (tester) async {
      await pumpPane(tester, admin: false, limited: true);

      expect(key('requestChange'), findsNothing);
    });

    testWidgets('a failed request lookup leaves the card out',
        (tester) async {
      final backend = FakeMemberBackend()..myRequestsStatus = 500;
      await pumpPane(tester, admin: false, memberBackend: backend);

      expect(key('request'), findsNothing);
      expect(key('requestChange'), findsOneWidget);
    });
  });

  test('a request lists only the fields that change', () {
    final record = MemberUpdateRequestRecord.fromJson(
      jsonDecode(jsonEncode(updateRequestJson())),
    )!;
    expect(record.changes, [('Phone number', '0241234567', '0559998887')]);
    expect(record.status, MemberUpdateStatus.pending);
    expect(record.requestedAt, DateTime(2026, 11, 24, 9, 30));
  });
}
