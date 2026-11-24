import 'package:cash_client_desktop/common/gradient_button.dart';
import 'package:cash_client_desktop/submissions/submissions_page.dart';
import 'package:cash_client_desktop/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  late FakeSubmissionBackend backend;

  Future<void> pumpPage(WidgetTester tester, {num expected = 2310}) async {
    tester.view.physicalSize = const Size(1280, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    backend = FakeSubmissionBackend()
      ..waiting.add(FakeSubmissionBackend.submissionJson('s1',
          expected: expected, failedCount: 1, failedAmount: 20))
      ..waiting.add(FakeSubmissionBackend.submissionJson('s2',
          collector: 'Esi Quaye', expected: 1145.5));
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: SubmissionsPage(api: backend.api)),
    ));
    await tester.pumpAndSettle();
  }

  Finder key(String name) => find.byKey(Key('sub.$name'));

  Future<void> open(WidgetTester tester, String id) async {
    await tester.tap(key('item.$id'));
    await tester.pumpAndSettle();
  }

  Future<void> count(WidgetTester tester, String denomination, int n) async {
    await tester.ensureVisible(key('count.$denomination'));
    await tester.enterText(key('count.$denomination'), '$n');
    await tester.pumpAndSettle();
  }

  bool approveEnabled(WidgetTester tester) =>
      tester.widget<GradientButton>(key('approve')).onPressed != null;

  testWidgets('lists waiting submissions with the expected cash',
      (tester) async {
    await pumpPage(tester);

    expect(key('nothingSelected'), findsOneWidget);
    expect(find.text('Yaw Owusu'), findsOneWidget);
    expect(find.text('2,310.00'), findsOneWidget);
    expect(find.text('1,145.50'), findsOneWidget);
  });

  testWidgets('a submission shows its totals, failed payments and payments',
      (tester) async {
    await pumpPage(tester);

    await open(tester, 's1');

    expect(key('summary'), findsOneWidget);
    expect(find.textContaining('not in the expected cash'), findsOneWidget);
    expect(find.text('Ama Mensah'), findsOneWidget);
    expect(find.textContaining('Failed: Account is INACTIVE'), findsOneWidget);
  });

  testWidgets('the count adds up; Approve waits until it reaches the '
      'expected cash, then turns green', (tester) async {
    await pumpPage(tester);
    await open(tester, 's1');

    expect(approveEnabled(tester), isFalse);

    await count(tester, 'cedis200', 5);
    await count(tester, 'cedis100', 8);
    expect(find.textContaining('GH₵ 1,800.00 · GH₵ 510.00 still to count'),
        findsOneWidget);
    expect(approveEnabled(tester), isFalse);

    await count(tester, 'cedis50', 6);
    await count(tester, 'cedis20', 10);
    await count(tester, 'cedis10', 1);
    expect(find.textContaining('matches the expected cash'), findsOneWidget);
    expect(approveEnabled(tester), isTrue);

    await tester.ensureVisible(key('approve'));
    await tester.tap(key('approve'));
    await tester.pumpAndSettle();

    expect(backend.approvals.single, ('s1', 2310.0));
    expect(key('countCard'), findsNothing);
    expect(find.text('Approved'), findsWidgets);
    // The list reloaded without it.
    expect(key('item.s1'), findsNothing);
  });

  testWidgets('a count above the expected cash approves as a surplus',
      (tester) async {
    await pumpPage(tester, expected: 100);
    await open(tester, 's1');

    await count(tester, 'cedis100', 1);
    await count(tester, 'pesewas50', 1);

    expect(find.textContaining('GH₵ 0.50 over, recorded as a surplus'),
        findsOneWidget);
    await tester.ensureVisible(key('approve'));
    await tester.tap(key('approve'));
    await tester.pumpAndSettle();

    expect(backend.approvals.single, ('s1', 100.5));
    expect(find.text('GH₵ 0.50'), findsOneWidget, reason: 'surplus recorded');
  });

  testWidgets('a refused approval shows the backend\'s reason',
      (tester) async {
    await pumpPage(tester, expected: 10);
    backend.approveAnswers.add((
      409,
      errorBody(409, 'This submission was already approved with GHS 12.00 '
          'counted'),
    ));
    await open(tester, 's1');
    await count(tester, 'cedis10', 1);

    await tester.ensureVisible(key('approve'));
    await tester.tap(key('approve'));
    await tester.pumpAndSettle();

    expect(find.textContaining('already approved with GHS 12.00'),
        findsOneWidget);
  });

  testWidgets('a lost answer can be approved again with the same count',
      (tester) async {
    await pumpPage(tester, expected: 10);
    backend.approveAnswers.add(null);
    await open(tester, 's1');
    await count(tester, 'cedis10', 1);

    await tester.ensureVisible(key('approve'));
    await tester.tap(key('approve'));
    await tester.pumpAndSettle();
    expect(find.textContaining("isn't clear whether this was approved"),
        findsOneWidget);

    await tester.tap(key('approve'));
    await tester.pumpAndSettle();

    expect(backend.approvals.map((a) => a.$2), [10.0, 10.0]);
    expect(key('countCard'), findsNothing);
  });

  testWidgets('the Approved tab lists approved days', (tester) async {
    await pumpPage(tester);
    backend.approved.add(FakeSubmissionBackend.submissionJson('s7',
        collector: 'Kojo Asare', status: 'APPROVED', counted: 900, overage: 0));

    await tester.tap(key('tab.approved'));
    await tester.pumpAndSettle();

    expect(backend.listCalls.last, ('APPROVED', 0));
    expect(find.text('Kojo Asare'), findsOneWidget);
    expect(find.text('Yaw Owusu'), findsNothing);
  });

  testWidgets('no waiting submissions is said plainly', (tester) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    backend = FakeSubmissionBackend();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: SubmissionsPage(api: backend.api)),
    ));
    await tester.pumpAndSettle();

    expect(find.text('No submissions are waiting.'), findsOneWidget);
  });
}
