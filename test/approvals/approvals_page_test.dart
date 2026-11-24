import 'package:cash_client_desktop/approvals/approval_api.dart';
import 'package:cash_client_desktop/approvals/approvals_page.dart';
import 'package:cash_client_desktop/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  late FakeApprovalBackend backend;

  Future<void> pumpPage(
    WidgetTester tester, {
    bool admin = true,
    FakeApprovalBackend? approvals,
  }) async {
    tester.view.physicalSize = const Size(1400, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    backend = approvals ?? FakeApprovalBackend();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: ApprovalsPage(api: backend.api, isAdministrator: admin),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Finder key(String name) => find.byKey(Key(name));

  Future<void> tapKey(WidgetTester tester, String name) async {
    await tester.ensureVisible(key(name));
    await tester.tap(key(name));
    await tester.pumpAndSettle();
  }

  testWidgets('Agents see an explanation instead of the queues',
      (tester) async {
    await pumpPage(tester, admin: false);

    expect(key('approvals.agentsNote'), findsOneWidget);
    expect(key('approvals.tab.kyc'), findsNothing);
    expect(backend.requests, isEmpty);
  });

  group('ID documents', () {
    testWidgets('lists the documents needing review, oldest first',
        (tester) async {
      await pumpPage(tester);

      expect(find.text('ID documents (2)'), findsOneWidget);
      expect(find.text('Member updates (1)'), findsOneWidget);
      expect(key('kyc.item.m-1'), findsOneWidget);
      expect(key('kyc.item.m-2'), findsOneWidget);
      expect(key('kyc.item.m-3'), findsNothing);
      expect(find.text('2 items'), findsOneWidget);
      expect(key('kyc.nothingSelected'), findsOneWidget);
      expect(backend.requests.first.url.queryParameters['status'],
          'MANUAL_REVIEW');
    });

    testWidgets('opening one shows the picture once and the details',
        (tester) async {
      await pumpPage(tester);
      await tapKey(tester, 'kyc.item.m-1');

      expect(key('kyc.name'), findsOneWidget);
      expect(key('kycPicture.image'), findsOneWidget);
      expect(backend.pictureCalls, 1);
      expect(find.text('GHA-123456789-0'), findsOneWidget);
      expect(find.text('The name could not be read'), findsOneWidget);
      expect(key('kyc.field.Registered by'), findsOneWidget);
      expect(key('kycPicture.zoomIn'), findsOneWidget);
      expect(key('kycPicture.rotate'), findsOneWidget);

      await tapKey(tester, 'kycPicture.zoomIn');
      await tapKey(tester, 'kycPicture.rotate');
      await tapKey(tester, 'kycPicture.reset');
      // Zooming and rotating don't fetch the picture again.
      expect(backend.pictureCalls, 1);
    });

    testWidgets('approve removes it and opens the next one', (tester) async {
      await pumpPage(tester);
      await tapKey(tester, 'kyc.item.m-1');

      await tapKey(tester, 'kyc.approve');

      expect(backend.actionPaths, ['POST /api/admin/v1/manual-kyc-approval/m-1']);
      expect(key('kyc.item.m-1'), findsNothing);
      expect(key('kyc.done'), findsOneWidget);
      expect(find.textContaining("Ama Owusu's ID approved"), findsOneWidget);
      expect(find.text('ID documents (1)'), findsOneWidget);
      expect(find.text('Kojo Owusu'), findsWidgets);
      expect(key('kyc.pane'), findsOneWidget);
    });

    testWidgets('reject needs a reason, picked or typed', (tester) async {
      await pumpPage(tester);
      await tapKey(tester, 'kyc.item.m-1');

      await tapKey(tester, 'kyc.reject');
      expect(key('reject.dialog'), findsOneWidget);
      await tapKey(tester, 'reject.confirm');
      expect(find.text('Choose a reason or type one'), findsOneWidget);
      expect(backend.actionPaths, isEmpty);

      await tapKey(tester, 'reject.preset.0');
      final field = tester.widget<TextField>(key('reject.reason'));
      expect(field.controller!.text, 'The picture is blurry or hard to read.');
      await tester.enterText(
          key('reject.reason'), 'The picture is blurry. Retake it in daylight.');
      await tapKey(tester, 'reject.confirm');

      expect(backend.actionPaths,
          ['POST /api/admin/v1/manual-kyc-rejection/m-1']);
      expect(backend.lastBody('manual-kyc-rejection'), {
        'reason': 'The picture is blurry. Retake it in daylight.',
      });
      expect(find.textContaining("Ama Owusu's ID rejected"), findsOneWidget);
      expect(key('kyc.item.m-1'), findsNothing);
    });

    testWidgets('cancelling the reason sends nothing', (tester) async {
      await pumpPage(tester);
      await tapKey(tester, 'kyc.item.m-1');
      await tapKey(tester, 'kyc.reject');
      await tapKey(tester, 'reject.cancel');

      expect(backend.actionPaths, isEmpty);
      expect(key('kyc.item.m-1'), findsOneWidget);
    });

    testWidgets('verified documents show without Approve or Reject',
        (tester) async {
      await pumpPage(tester);

      await tester.tap(key('kyc.status'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Verified').last);
      await tester.pumpAndSettle();
      await tapKey(tester, 'kyc.item.m-3');

      expect(key('kyc.approve'), findsNothing);
      expect(key('kyc.reject'), findsNothing);
      // The tab still counts what's waiting.
      expect(find.text('ID documents (2)'), findsOneWidget);
    });

    testWidgets('a document someone else already reviewed is explained',
        (tester) async {
      final approvals = FakeApprovalBackend()
        ..actionStatus = 409
        ..actionMessage = "This member's KYC is VERIFIED and can't be reviewed";
      await pumpPage(tester, approvals: approvals);
      await tapKey(tester, 'kyc.item.m-1');
      await tapKey(tester, 'kyc.approve');

      expect(key('kyc.error'), findsOneWidget);
      expect(find.textContaining('already reviewed'), findsOneWidget);
      expect(key('kyc.item.m-1'), findsOneWidget);
    });

    testWidgets("a picture that won't load can be tried again",
        (tester) async {
      final approvals = FakeApprovalBackend()..pictureStatus = 500;
      await pumpPage(tester, approvals: approvals);
      await tapKey(tester, 'kyc.item.m-1');

      expect(key('kycPicture.error'), findsOneWidget);
      approvals.pictureStatus = 200;
      await tester.tap(find.descendant(
        of: key('kycPicture.error'),
        matching: find.text('Try again'),
      ));
      await tester.pumpAndSettle();
      expect(key('kycPicture.image'), findsOneWidget);
    });

    testWidgets('an empty queue says so', (tester) async {
      await pumpPage(tester, approvals: FakeApprovalBackend(kyc: []));

      expect(key('kyc.empty'), findsOneWidget);
      expect(find.text('ID documents'), findsOneWidget);
    });
  });

  group('Member updates', () {
    Future<void> openUpdates(WidgetTester tester) async {
      await tester.tap(key('approvals.tab.updates'));
      await tester.pumpAndSettle();
    }

    testWidgets('compares the new details with the current ones',
        (tester) async {
      await pumpPage(tester);
      await openUpdates(tester);
      await tapKey(tester, 'upd.item.req-1');

      expect(key('upd.compare'), findsOneWidget);
      expect(key('upd.new.Phone number'), findsOneWidget);
      expect(find.text('0559998887'), findsOneWidget);
      expect(find.text('No change'), findsNWidgets(2));
      expect(find.textContaining('STF0020'), findsWidgets);
    });

    testWidgets('approve saves it and empties the queue', (tester) async {
      await pumpPage(tester);
      await openUpdates(tester);
      await tapKey(tester, 'upd.item.req-1');
      await tapKey(tester, 'upd.approve');

      expect(backend.actionPaths,
          ['POST /api/admin/v1/member-update-requests/req-1/approve']);
      expect(find.textContaining('new details saved'), findsOneWidget);
      expect(key('upd.empty'), findsOneWidget);
      expect(find.text('Member updates'), findsOneWidget);
    });

    testWidgets('reject sends the reason', (tester) async {
      await pumpPage(tester);
      await openUpdates(tester);
      await tapKey(tester, 'upd.item.req-1');
      await tapKey(tester, 'upd.reject');
      await tapKey(tester, 'reject.preset.1');
      await tapKey(tester, 'reject.confirm');

      expect(backend.lastBody('/reject'), {
        'reason': "The new phone number couldn't be confirmed with the member.",
      });
      expect(key('upd.item.req-1'), findsNothing);
    });

    testWidgets('rejected requests show the reason and no actions',
        (tester) async {
      await pumpPage(tester);
      await openUpdates(tester);
      await tester.tap(key('upd.tab.rejected'));
      await tester.pumpAndSettle();
      await tapKey(tester, 'upd.item.req-2');

      expect(key('upd.field.reason'), findsOneWidget);
      expect(find.text('Wrong number'), findsOneWidget);
      expect(find.text('Member now'), findsOneWidget);
      expect(find.text('No change'), findsNothing);
      expect(key('upd.approve'), findsNothing);
    });

    testWidgets('switching tabs keeps each list', (tester) async {
      await pumpPage(tester);
      await tapKey(tester, 'kyc.item.m-2');
      await openUpdates(tester);
      await tester.tap(key('approvals.tab.kyc'));
      await tester.pumpAndSettle();

      expect(find.text('Kojo Owusu'), findsWidgets);
      expect(key('kyc.pane'), findsOneWidget);
    });
  });

  test('ID records read the backend shape', () {
    final record = KycRecord.fromJson(kycRecordJson('m-9', 'Abena'))!;
    expect(record.memberName, 'Abena Owusu');
    expect(record.status, KycReviewStatus.manualReview);
    expect(record.status.reviewable, isTrue);
    expect(record.documentType, KycDocumentType.ghanaCard);
    expect(record.submittedAt, DateTime(2026, 11, 22, 10, 15));
    expect(KycReviewStatus.verified.reviewable, isFalse);
  });
}
