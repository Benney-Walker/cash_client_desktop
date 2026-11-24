import 'dart:typed_data';

import 'package:cash_client_desktop/reports/report_api.dart';
import 'package:cash_client_desktop/reports/reports_page.dart';
import 'package:cash_client_desktop/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  late FakeReportBackend backend;
  late List<String> saved;
  late List<String> printed;
  late bool cancelSave;
  final now = DateTime(2026, 11, 24, 18);

  Future<void> pumpPage(
    WidgetTester tester, {
    bool admin = true,
    FakeReportBackend? reports,
    String? scopeBranch,
  }) async {
    tester.view.physicalSize = const Size(1500, 1300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    backend = reports ?? FakeReportBackend();
    saved = [];
    printed = [];
    cancelSave = false;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: ReportsPage(
          api: backend.api,
          branchApi: backend.branchApi,
          isAdministrator: admin,
          scopeBranch: scopeBranch,
          now: () => now,
          savePdf: (Uint8List bytes, String name) async {
            if (cancelSave) return false;
            expect(bytes.first, 0x25); // "%"
            saved.add(name);
            return true;
          },
          printPdf: (Uint8List bytes, String name) async => printed.add(name),
        ),
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

  Future<void> openTab(WidgetTester tester, String tab) async {
    await tester.tap(key('reports.tab.$tab'));
    await tester.pumpAndSettle();
  }

  testWidgets('Administrators get six tabs, Agents four with their branch',
      (tester) async {
    await pumpPage(tester);
    expect(key('reports.tab.audit'), findsOneWidget);
    expect(key('reports.tab.trialBalance'), findsOneWidget);

    await pumpPage(tester, admin: false, scopeBranch: 'Tarkwa');
    expect(key('reports.tab.audit'), findsNothing);
    expect(key('reports.tab.trialBalance'), findsNothing);
    expect(find.text('Tarkwa branch only'), findsOneWidget);
    expect(key('txReport.branch'), findsNothing);
    expect(backend.callsTo(ReportApi.auditLogPath), 0);
  });

  group('Transactions', () {
    testWidgets('opens on this month with totals and days', (tester) async {
      await pumpPage(tester);

      final q = backend.lastQuery(ReportApi.transactionsPath);
      expect(q, {'from': '2026-11-01', 'to': '2026-11-24'});
      expect(find.text('From 2026-11-01'), findsWidgets);
      expect(find.descendant(of: key('txReport.figure.Amount'), matching: find.text('GH₵ 1,800.00')),
          findsOneWidget);
      expect(key('txReport.totals.table'), findsOneWidget);
      expect(key('txReport.rows.table'), findsOneWidget);
      expect(find.text('Deposits'), findsNWidgets(2));
    });

    testWidgets('a branch narrows the report and names the PDF', (tester) async {
      await pumpPage(tester);

      await tester.tap(key('txReport.branch'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tarkwa').last);
      await tester.pumpAndSettle();
      expect(backend.lastQuery(ReportApi.transactionsPath)['branchId'], 'b-tarkwa');

      await tapKey(tester, 'txReport.savePdf');
      expect(saved, ['transactions-2026-11-01-2026-11-24-tarkwa.pdf']);
      expect(backend.lastQuery('/transactions/pdf'),
          {'from': '2026-11-01', 'to': '2026-11-24', 'branchId': 'b-tarkwa'});
      expect(find.text('PDF saved.'), findsOneWidget);
    });

    testWidgets('print sends the PDF to the print dialog', (tester) async {
      await pumpPage(tester);
      await tapKey(tester, 'txReport.printPdf');

      expect(printed, ['transactions-2026-11-01-2026-11-24']);
    });

    testWidgets('a cancelled save says nothing', (tester) async {
      await pumpPage(tester);
      cancelSave = true;
      await tapKey(tester, 'txReport.savePdf');

      expect(saved, isEmpty);
      expect(key('txReport.pdfMessage'), findsNothing);
    });

    testWidgets('a failed report can be tried again', (tester) async {
      final failing = FakeReportBackend()..failing.add(ReportApi.transactionsPath);
      await pumpPage(tester, reports: failing);

      expect(key('txReport.error'), findsOneWidget);
      failing.failing.clear();
      await tester.tap(find.descendant(of: key('txReport.error'), matching: find.text('Try again')));
      await tester.pumpAndSettle();
      expect(key('txReport.rows.table'), findsOneWidget);
    });
  });

  testWidgets('Collector collections shows days and handovers', (tester) async {
    await pumpPage(tester);
    await openTab(tester, 'collections');

    expect(key('colReport.days.table'), findsOneWidget);
    expect(key('colReport.handovers.table'), findsOneWidget);
    expect(find.text('Approved by STF0020'), findsOneWidget);
    expect(find.descendant(of: key('colReport.figure.Surplus'), matching: find.text('GH₵ 5.00')),
        findsOneWidget);
  });

  testWidgets('Loan portfolio has no dates and a PDF for today', (tester) async {
    await pumpPage(tester);
    await openTab(tester, 'portfolio');

    expect(key('loanReport.from'), findsNothing);
    expect(key('loanReport.loans.table'), findsOneWidget);
    await tapKey(tester, 'loanReport.savePdf');
    expect(saved, ['loan-portfolio-2026-11-24.pdf']);
  });

  group('Statement', () {
    testWidgets('needs an account number, then saves the PDF', (tester) async {
      await pumpPage(tester);
      await openTab(tester, 'statement');

      expect(tester.widget<OutlinedButton>(key('statement.savePdf')).onPressed, isNull);
      await tester.enterText(key('statement.account'), '2004567891');
      await tester.pump();
      await tapKey(tester, 'statement.savePdf');

      expect(saved, ['statement-2004567891-2026-11-01-2026-11-24.pdf']);
      final r = backend.requests.last;
      expect(r.url.path, '${ReportApi.statementPath}/2004567891');
      expect(r.url.queryParameters, {'from': '2026-11-01', 'to': '2026-11-24'});
    });

    testWidgets("another branch's member is explained", (tester) async {
      final refusing = FakeReportBackend()
        ..failing.add(ReportApi.statementPath)
        ..failStatus = 403
        ..failMessage = 'Agents can only make statements for their own branch';
      await pumpPage(tester, admin: false, reports: refusing);
      await openTab(tester, 'statement');
      await tester.enterText(key('statement.account'), '2004567891');
      await tester.pump();
      await tapKey(tester, 'statement.printPdf');

      expect(find.text('Agents can only make statements for their own branch.'), findsOneWidget);
      expect(printed, isEmpty);
    });
  });

  group('Audit log', () {
    testWidgets('lists the last 7 days with plain names', (tester) async {
      await pumpPage(tester);
      await openTab(tester, 'audit');

      final q = backend.lastQuery(ReportApi.auditLogPath);
      expect(q['from'], '2026-11-18T00:00:00Z');
      expect(q['to'], '2026-11-25T00:00:00Z');
      expect(find.text('3 entries'), findsOneWidget);
      expect(find.text('Loan approved and paid out'), findsOneWidget);
      expect(find.text('Sign-in failed'), findsOneWidget);
      expect(find.textContaining('By the system'), findsOneWidget);
      expect(find.text('By STF0012 · Loan application app-1'), findsOneWidget);
      expect(find.text('GHS 2000.00 paid in'), findsOneWidget);
    });

    testWidgets('filters go to the backend', (tester) async {
      await pumpPage(tester);
      await openTab(tester, 'audit');

      await tester.tap(key('audit.action'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign-in failed').last);
      await tester.pumpAndSettle();
      await tester.enterText(key('audit.actor'), 'STF0020');
      await tapKey(tester, 'audit.apply');

      final q = backend.lastQuery(ReportApi.auditLogPath);
      expect(q['action'], 'LOGIN_FAILED');
      expect(q['actorStaffId'], 'STF0020');
      expect(q['size'], '50');
    });

    testWidgets('more entries load on request', (tester) async {
      final many = FakeReportBackend()..auditTotal = 60;
      await pumpPage(tester, reports: many);
      await openTab(tester, 'audit');

      await tapKey(tester, 'audit.more');
      expect(backend.lastQuery(ReportApi.auditLogPath)['page'], '1');
    });
  });

  group('Trial balance', () {
    testWidgets('shows the accounts and that it balances', (tester) async {
      await pumpPage(tester);
      await openTab(tester, 'trialBalance');

      expect(key('trialBalance.balanced'), findsOneWidget);
      expect(find.text('Cash on hand'), findsOneWidget);
      expect(find.text('6,200.00'), findsNWidgets(2));
    });

    testWidgets('says so loudly when it does not', (tester) async {
      await pumpPage(tester, reports: FakeReportBackend()..balanced = false);
      await openTab(tester, 'trialBalance');

      expect(key('trialBalance.unbalanced'), findsOneWidget);
    });
  });

  test('audit filters become instants, the last day included', () {
    final q = AuditFilter(
      from: DateTime(2026, 11, 1),
      to: DateTime(2026, 11, 30),
      actorStaffId: '',
      action: 'LOAN_APPROVED',
    ).toQuery();
    expect(q, {
      'from': '2026-11-01T00:00:00Z',
      'to': '2026-12-01T00:00:00Z',
      'action': 'LOAN_APPROVED',
    });
  });
}
