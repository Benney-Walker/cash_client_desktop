import 'package:cash_client_desktop/dashboard/dashboard_api.dart';
import 'package:cash_client_desktop/dashboard/dashboard_page.dart';
import 'package:cash_client_desktop/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  late FakeDashboardBackend backend;
  late List<DashboardTarget> opened;

  // A Wednesday morning.
  final now = DateTime(2026, 11, 25, 9, 30);

  Future<void> pumpDashboard(
    WidgetTester tester, {
    bool admin = true,
    String? scopeBranch,
    FakeDashboardBackend? dashboard,
  }) async {
    tester.view.physicalSize = const Size(1280, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    backend = dashboard ?? FakeDashboardBackend();
    opened = [];
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: DashboardPage(
          api: backend.api,
          branchApi: backend.branchApi,
          staffName: 'KOFI MENSAH',
          isAdministrator: admin,
          scopeBranch: scopeBranch,
          onOpen: opened.add,
          now: () => now,
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Finder key(String name) => find.byKey(Key('dashboard.$name'));

  String textOf(WidgetTester tester, String name) =>
      tester.widget<Text>(key(name)).data!;

  group('Administrators', () {
    testWidgets("headline shows today's deposits, withdrawals and waiting",
        (tester) async {
      await pumpDashboard(tester);

      expect(find.text('Good morning, Kofi'), findsOneWidget);
      expect(textOf(tester, 'scope'), 'Today · All branches');
      expect(textOf(tester, 'money'),
          'GH₵ 1,500.00 deposited · GH₵ 300.00 withdrawn today');
      // 3 collector days + 2 ID documents + 1 update + 1 loan application.
      expect(textOf(tester, 'waiting'), '7 things waiting for you');

      final q = backend.lastQuery(DashboardApi.transactionsReportPath);
      expect(q['from'], '2026-11-25');
      expect(q['to'], '2026-11-25');
      expect(q.containsKey('branchId'), isFalse);
    });

    testWidgets('shows every waiting card with its count', (tester) async {
      await pumpDashboard(tester);

      for (final (target, count) in [
        ('submissions', '3'),
        ('idDocuments', '2'),
        ('memberUpdates', '1'),
        ('loanApplications', '1'),
        ('pendingMembers', '4'),
      ]) {
        expect(textOf(tester, 'count.$target'), count, reason: target);
      }
      expect(
        backend.lastQuery(DashboardApi.kycReviewsPath)['status'],
        'MANUAL_REVIEW',
      );
      expect(backend.lastQuery(DashboardApi.submissionsPath)['size'], '1');
    });

    testWidgets('cards open their page', (tester) async {
      await pumpDashboard(tester);

      await tester.tap(key('card.memberUpdates'));
      await tester.tap(key('card.submissions'));

      expect(opened, [DashboardTarget.memberUpdates, DashboardTarget.submissions]);
    });

    testWidgets('the sections show totals by type and the loans',
        (tester) async {
      await pumpDashboard(tester);

      expect(key('type.DEPOSIT'), findsOneWidget);
      expect(find.text('4 transactions'), findsOneWidget);
      expect(find.text('Withdrawals'), findsOneWidget);
      expect(find.text('GH₵ 4.00'), findsOneWidget); // fees
      expect(key('collected'), findsOneWidget);
      expect(find.text('GH₵ 860.00'), findsNWidgets(2));
      expect(find.text('Active loans'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('GH₵ 8,000.00'), findsOneWidget);
      expect(find.text('GH₵ 450.00'), findsOneWidget);
    });

    testWidgets('switching to this week asks from Monday', (tester) async {
      await pumpDashboard(tester);

      await tester.tap(key('period.week'));
      await tester.pumpAndSettle();

      final q = backend.lastQuery(DashboardApi.transactionsReportPath);
      expect(q['from'], '2026-11-23');
      expect(q['to'], '2026-11-25');
      expect(textOf(tester, 'scope'), 'This week · All branches');
      expect(textOf(tester, 'money'), endsWith('withdrawn this week'));
      expect(find.text('This week by type'), findsOneWidget);
      // Waiting counts don't depend on the period.
      expect(backend.callsTo(DashboardApi.submissionsPath), 1);
    });

    testWidgets('choosing a branch narrows money, loans and pending members',
        (tester) async {
      await pumpDashboard(tester);

      await tester.tap(key('branch'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tarkwa').last);
      await tester.pumpAndSettle();

      for (final path in [
        DashboardApi.transactionsReportPath,
        DashboardApi.collectionsReportPath,
        DashboardApi.loanPortfolioPath,
        DashboardApi.membersPath,
      ]) {
        expect(backend.lastQuery(path)['branchId'], 'b-tarkwa', reason: path);
      }
      expect(textOf(tester, 'scope'), 'Today · Tarkwa');
      expect(key('branchNote'), findsOneWidget);
    });

    testWidgets('a failed report leaves the rest showing', (tester) async {
      final failing = FakeDashboardBackend()
        ..failing.add(DashboardApi.transactionsReportPath)
        ..failing.add(DashboardApi.kycReviewsPath);
      await pumpDashboard(tester, dashboard: failing);

      expect(textOf(tester, 'money'), "Today's totals couldn't be loaded");
      expect(key('countError.idDocuments'), findsOneWidget);
      expect(textOf(tester, 'count.submissions'), '3');
      expect(find.text('Active loans'), findsOneWidget);
      // One count missing: no waiting total rather than a wrong one.
      expect(textOf(tester, 'waiting').trim(), isEmpty);

      failing.failing.clear();
      await tester.tap(key('refresh'));
      await tester.pumpAndSettle();
      expect(textOf(tester, 'money'), startsWith('GH₵ 1,500.00 deposited'));
      expect(textOf(tester, 'waiting'), '7 things waiting for you');
    });

    testWidgets('a quiet day says so', (tester) async {
      final quiet = FakeDashboardBackend()..totals = [];
      quiet.counts.updateAll((_, __) => 0);
      await pumpDashboard(tester, dashboard: quiet);

      expect(key('noTransactions'), findsOneWidget);
      expect(textOf(tester, 'money'),
          'GH₵ 0.00 deposited · GH₵ 0.00 withdrawn today');
      expect(textOf(tester, 'waiting'), 'Nothing waiting for you');
    });
  });

  group('Agents', () {
    testWidgets('see their branch and only branch cards', (tester) async {
      await pumpDashboard(tester, admin: false, scopeBranch: 'Tarkwa');

      expect(find.text('Tarkwa branch only'), findsOneWidget);
      expect(textOf(tester, 'scope'), 'Today · Tarkwa branch');
      expect(key('card.submissions'), findsOneWidget);
      expect(key('card.pendingMembers'), findsOneWidget);
      expect(key('card.idDocuments'), findsNothing);
      expect(key('card.memberUpdates'), findsNothing);
      expect(key('card.loanApplications'), findsNothing);
      expect(key('branch'), findsNothing);
      expect(textOf(tester, 'waiting'), '3 things waiting for you');
      // Nothing Administrator-only is asked for.
      expect(backend.callsTo(DashboardApi.kycReviewsPath), 0);
      expect(backend.callsTo(DashboardApi.memberUpdatesPath), 0);
      expect(backend.callsTo(DashboardApi.loanApplicationsPath), 0);
    });
  });

  group('models', () {
    test('periods count from today, the Monday, or the first', () {
      final wed = DateTime(2026, 11, 25, 17);
      expect(DashboardPeriod.today.range(wed),
          (DateTime(2026, 11, 25), DateTime(2026, 11, 25)));
      expect(DashboardPeriod.week.range(wed),
          (DateTime(2026, 11, 23), DateTime(2026, 11, 25)));
      expect(DashboardPeriod.month.range(wed),
          (DateTime(2026, 11, 1), DateTime(2026, 11, 25)));
      final monday = DateTime(2026, 11, 23, 8);
      expect(DashboardPeriod.week.range(monday).$1, DateTime(2026, 11, 23));
    });

    test('transaction totals read the report and sort by amount', () {
      final summary = TransactionSummary.fromJson({
        'totals': [
          {'type': 'WITHDRAWAL', 'count': 1, 'amount': 50, 'fees': 2},
          {'type': 'DEPOSIT', 'count': 3, 'amount': '900.50', 'fees': 0},
        ],
        'count': 4,
        'amount': 950.5,
        'fees': 2,
      })!;
      expect(summary.byType.first.label, 'Deposits');
      expect(summary.deposits.pesewas, 90050);
      expect(summary.withdrawals.pesewas, 5000);
      expect(transactionTypeLabel('LOAN_DISBURSEMENT'), 'Loans paid out');
      expect(transactionTypeLabel('SOMETHING_NEW'), 'SOMETHING_NEW');
    });
  });
}
