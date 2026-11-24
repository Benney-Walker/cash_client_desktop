import 'package:cash_client_desktop/loans/loans_page.dart';
import 'package:cash_client_desktop/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  late FakeLoanBackend backend;
  late FakeMemberBackend members;

  Future<void> pumpPage(
    WidgetTester tester, {
    bool admin = true,
    FakeLoanBackend? loans,
    String? scopeBranch,
  }) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    backend = loans ?? FakeLoanBackend();
    members = FakeMemberBackend()
      ..profiles['m-1'] = FakeMemberBackend.profileJson(id: 'm-1');
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: LoansPage(
          api: backend.api,
          memberApi: members.api,
          isAdministrator: admin,
          scopeBranch: scopeBranch,
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
    await tester.tap(key('loans.tab.$tab'));
    await tester.pumpAndSettle();
  }

  group('Applications', () {
    testWidgets('lists waiting applications with what each costs',
        (tester) async {
      await pumpPage(tester);

      expect(find.text('Applications (1)'), findsOneWidget);
      expect(key('loanApp.item.app-1'), findsOneWidget);
      await tapKey(tester, 'loanApp.item.app-1');

      expect(find.text('Kofi Mensah'), findsOneWidget); // guarantor, from the full read
      expect(tester.widget<Text>(find.descendant(
        of: key('loanApp.quote.toRepay'),
        matching: find.text('GH₵ 2,240.00'),
      )).data, 'GH₵ 2,240.00');
      expect(find.descendant(
        of: key('loanApp.quote.paidIn'),
        matching: find.text('GH₵ 1,960.00'),
      ), findsOneWidget);
    });

    testWidgets('approving confirms the payout, and can approve less',
        (tester) async {
      await pumpPage(tester);
      await tapKey(tester, 'loanApp.item.app-1');

      await tapKey(tester, 'loanApp.approve');
      expect(key('approveLoan.dialog'), findsOneWidget);
      expect(find.text('Approve and pay in GH₵ 1,960.00'), findsOneWidget);
      expect(find.textContaining('Savings 2004567'), findsOneWidget);

      await tester.enterText(key('approveLoan.amount'), '3000');
      await tester.pump();
      await tapKey(tester, 'approveLoan.confirm');
      expect(find.textContaining("Can't be more than"), findsOneWidget);
      expect(backend.posts, isEmpty);

      await tester.enterText(key('approveLoan.amount'), '1500');
      await tester.pump();
      expect(find.text('Approve and pay in GH₵ 1,470.00'), findsOneWidget);
      await tapKey(tester, 'approveLoan.confirm');

      expect(backend.posts,
          ['POST /api/admin/v1/loan-applications/app-1/approve']);
      expect(backend.lastBody('/approve'), {'approvedAmount': 1500.0});
      expect(find.textContaining('GH₵ 1,500.00 approved'), findsOneWidget);
      expect(key('loanApp.item.app-1'), findsNothing);
    });

    testWidgets('approving the full amount sends no body', (tester) async {
      await pumpPage(tester);
      await tapKey(tester, 'loanApp.item.app-1');
      await tapKey(tester, 'loanApp.approve');
      await tapKey(tester, 'approveLoan.confirm');

      expect(backend.lastBody('/approve'), isNull);
    });

    testWidgets('cancelling the confirmation sends nothing', (tester) async {
      await pumpPage(tester);
      await tapKey(tester, 'loanApp.item.app-1');
      await tapKey(tester, 'loanApp.approve');
      await tapKey(tester, 'approveLoan.cancel');

      expect(backend.posts, isEmpty);
    });

    testWidgets('reject sends a reason', (tester) async {
      await pumpPage(tester);
      await tapKey(tester, 'loanApp.item.app-1');
      await tapKey(tester, 'loanApp.reject');
      await tapKey(tester, 'reject.preset.0');
      await tapKey(tester, 'reject.confirm');

      expect(backend.lastBody('/reject'),
          {'reason': "The member can't afford the repayments."});
      expect(key('loanApp.item.app-1'), findsNothing);
    });

    testWidgets("the backend's reason is shown when approving fails",
        (tester) async {
      final refusing = FakeLoanBackend()
        ..actionStatus = 409
        ..actionMessage = 'This member already has a loan being repaid';
      await pumpPage(tester, loans: refusing);
      await tapKey(tester, 'loanApp.item.app-1');
      await tapKey(tester, 'loanApp.approve');
      await tapKey(tester, 'approveLoan.confirm');

      expect(find.text('This member already has a loan being repaid.'),
          findsOneWidget);
      expect(key('loanApp.item.app-1'), findsOneWidget);
    });

    testWidgets('rejected applications show the reason', (tester) async {
      await pumpPage(tester);
      await tester.tap(key('loanApp.tab.rejected'));
      await tester.pumpAndSettle();
      await tapKey(tester, 'loanApp.item.app-2');

      expect(key('loanApp.reason'), findsOneWidget);
      expect(key('loanApp.approve'), findsNothing);
    });

    testWidgets('Agents see applications without Approve or Reject',
        (tester) async {
      await pumpPage(tester, admin: false);
      await tapKey(tester, 'loanApp.item.app-1');

      expect(key('loanApp.approve'), findsNothing);
      expect(key('loanApp.reject'), findsNothing);
      expect(key('loanApp.agentNote'), findsOneWidget);
    });
  });

  group('Active loans', () {
    testWidgets('lists the portfolio and opens a loan with installments',
        (tester) async {
      await pumpPage(tester);
      await openTab(tester, 'active');

      expect(key('activeLoans.item.loan-1'), findsOneWidget);
      expect(key('activeLoans.item.loan-2'), findsOneWidget);
      await tester.tap(key('activeLoans.overdueOnly'));
      await tester.pumpAndSettle();
      expect(key('activeLoans.item.loan-1'), findsNothing);
      expect(key('activeLoans.item.loan-2'), findsOneWidget);
      await tester.tap(key('activeLoans.overdueOnly'));
      await tester.pumpAndSettle();

      await tapKey(tester, 'activeLoans.item.loan-1');
      expect(key('loan.installment.1'), findsOneWidget);
      expect(key('loan.installment.2'), findsOneWidget);
      expect(find.text('GH₵ 1,866.65'), findsWidgets);
      expect(find.textContaining('GH₵ 373.33 on 2026-12-24'), findsOneWidget);
    });

    testWidgets("Agents see the branch chip only on Active loans",
        (tester) async {
      await pumpPage(tester, admin: false, scopeBranch: 'Tarkwa');
      expect(find.text('Tarkwa branch only'), findsNothing);

      await openTab(tester, 'active');
      expect(find.text('Tarkwa branch only'), findsOneWidget);
    });
  });

  group('Products', () {
    testWidgets('shows a product and lets Administrators edit it',
        (tester) async {
      await pumpPage(tester);
      await openTab(tester, 'products');

      await tapKey(tester, 'products.item.1');
      expect(find.text('24% a year (flat)'), findsOneWidget);
      expect(find.text('1 needed'), findsOneWidget);
      expect(key('products.item.2'), findsOneWidget); // switched off, still listed

      await tapKey(tester, 'products.edit');
      await tester.enterText(key('productForm.rate'), '26.5');
      await tapKey(tester, 'productForm.save');

      expect(backend.posts, ['PUT /api/admin/v1/loan-products/1']);
      expect(backend.lastBody('/loan-products/1')!['interestRatePercent'], 26.5);
      expect(key('products.done'), findsOneWidget);
      expect(find.text('26.5% a year (flat)'), findsOneWidget);
    });

    testWidgets('a new product is checked before it is sent', (tester) async {
      await pumpPage(tester);
      await openTab(tester, 'products');
      await tapKey(tester, 'products.add');

      await tester.enterText(key('productForm.name'), 'Market women');
      await tester.enterText(key('productForm.rate'), '20');
      await tester.enterText(key('productForm.term'), '400');
      await tester.enterText(key('productForm.min'), '1000');
      await tester.enterText(key('productForm.max'), '500');
      await tapKey(tester, 'productForm.save');

      expect(find.text('Months: 1 to 360'), findsOneWidget);
      expect(find.text("Can't be less than the smallest loan"), findsOneWidget);
      expect(backend.posts, isEmpty);

      await tester.enterText(key('productForm.term'), '6');
      await tester.enterText(key('productForm.max'), '3000');
      await tapKey(tester, 'productForm.save');

      expect(backend.posts, ['POST /api/admin/v1/loan-products']);
      expect(backend.lastBody('/loan-products')!['name'], 'Market women');
      expect(find.text('Market women added.'), findsOneWidget);
    });

    testWidgets('Agents see products read only', (tester) async {
      await pumpPage(tester, admin: false);
      await openTab(tester, 'products');
      await tapKey(tester, 'products.item.1');

      expect(key('products.add'), findsNothing);
      expect(key('products.edit'), findsNothing);
    });
  });
}
