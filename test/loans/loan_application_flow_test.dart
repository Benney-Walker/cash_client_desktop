import 'package:cash_client_desktop/loans/loan_application_flow.dart';
import 'package:cash_client_desktop/members/member_profile.dart';
import 'package:cash_client_desktop/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  late FakeLoanBackend loans;
  late FakeMemberBackend members;
  late int closed;

  Future<void> pumpFlow(
    WidgetTester tester, {
    PickedMember? member,
    FakeLoanBackend? loanBackend,
  }) async {
    tester.view.physicalSize = const Size(1280, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    loans = loanBackend ?? FakeLoanBackend();
    members = FakeMemberBackend()
      ..searchResults = [
        FakeMemberBackend.summaryJson('m-1', 'Ama'),
        FakeMemberBackend.summaryJson('m-3', 'Yaw', status: 'PENDING'),
        FakeMemberBackend.summaryJson('m-9', 'Kofi'),
      ];
    closed = 0;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: LoanApplicationFlow(
          api: loans.api,
          memberApi: members.api,
          member: member,
          onClose: () => closed++,
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Finder key(String name) => find.byKey(Key('applyLoan.$name'));

  Future<void> tapKey(WidgetTester tester, String name) async {
    await tester.ensureVisible(key(name));
    await tester.tap(key(name));
    await tester.pumpAndSettle();
  }

  Future<void> search(WidgetTester tester, String field, String text) async {
    await tester.enterText(key('$field.field'), text);
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
  }

  Future<void> chooseAma(WidgetTester tester) async {
    await search(tester, 'memberSearch', 'Mensah');
    await tapKey(tester, 'memberSearch.result.m-1');
  }

  Future<void> fillProduct(WidgetTester tester, {String amount = '2000', String term = '6'}) async {
    await tester.tap(key('productChoice'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salary advance').last);
    await tester.pumpAndSettle();
    await tester.enterText(key('amount'), amount);
    await tester.enterText(key('term'), term);
    await tester.pump();
  }

  testWidgets('needs a member, and an active one', (tester) async {
    await pumpFlow(tester);

    await tapKey(tester, 'next');
    expect(find.text('Choose the member the loan is for'), findsOneWidget);

    await search(tester, 'memberSearch', 'Mensah');
    await tapKey(tester, 'memberSearch.result.m-3');
    await tapKey(tester, 'next');
    expect(find.textContaining('Only active members'), findsOneWidget);

    await tapKey(tester, 'changeMember');
    await chooseAma(tester);
    await tapKey(tester, 'next');
    expect(key('product'), findsOneWidget);
  });

  testWidgets('shows only active products and works out the cost',
      (tester) async {
    await pumpFlow(tester);
    await chooseAma(tester);
    await tapKey(tester, 'next');

    await tester.tap(key('productChoice'));
    await tester.pumpAndSettle();
    expect(find.text('Emergency loan'), findsNothing); // switched off
    await tester.tap(find.text('Salary advance').last);
    await tester.pumpAndSettle();

    await tester.enterText(key('amount'), '2000');
    await tester.enterText(key('term'), '6');
    await tester.pump();

    expect(find.text('GH₵ 2,240.00'), findsOneWidget);
    expect(find.text('GH₵ 373.33 × 5, then GH₵ 373.35'), findsOneWidget);
    expect(find.text('GH₵ 1,960.00'), findsOneWidget);
  });

  testWidgets("checks the amount and term against the product", (tester) async {
    await pumpFlow(tester);
    await chooseAma(tester);
    await tapKey(tester, 'next');
    await fillProduct(tester, amount: '9000', term: '24');

    await tapKey(tester, 'next');
    expect(find.text('Between GH₵ 500.00 and GH₵ 5,000.00'), findsOneWidget);
    expect(find.text('1 to 12 months'), findsOneWidget);
    expect(key('guarantors'), findsNothing);
  });

  testWidgets('guarantors: the right number, active, not the borrower',
      (tester) async {
    await pumpFlow(tester);
    await chooseAma(tester);
    await tapKey(tester, 'next');
    await fillProduct(tester);
    await tapKey(tester, 'next');

    await tapKey(tester, 'next');
    expect(find.text('Salary advance needs 1 guarantor'), findsOneWidget);

    await search(tester, 'guarantorSearch', 'Mensah');
    await tapKey(tester, 'guarantorSearch.result.m-1');
    expect(find.text("A member can't guarantee their own loan"), findsOneWidget);

    await search(tester, 'guarantorSearch', 'Mensah');
    await tapKey(tester, 'guarantorSearch.result.m-3');
    expect(find.textContaining('is not an active member'), findsOneWidget);

    await search(tester, 'guarantorSearch', 'Mensah');
    await tapKey(tester, 'guarantorSearch.result.m-9');
    expect(key('guarantor.m-9'), findsOneWidget);
    expect(key('guarantorSearch.field'), findsNothing);

    await tester.enterText(key('purpose'), 'School fees');
    await tapKey(tester, 'next');
    expect(key('review'), findsOneWidget);
  });

  testWidgets('sends the application and says so', (tester) async {
    await pumpFlow(tester);
    await chooseAma(tester);
    await tapKey(tester, 'next');
    await fillProduct(tester);
    await tapKey(tester, 'next');
    await search(tester, 'guarantorSearch', 'Mensah');
    await tapKey(tester, 'guarantorSearch.result.m-9');
    await tester.enterText(key('purpose'), 'School fees');
    await tapKey(tester, 'next');

    await tapKey(tester, 'next');

    expect(loans.lastBody('/applications'), {
      'memberId': 'm-1',
      'productId': 1,
      'amount': 2000.0,
      'termMonths': 6,
      'guarantorMemberIds': ['m-9'],
      'purpose': 'School fees',
    });
    expect(key('sent'), findsOneWidget);
    await tapKey(tester, 'done');
    expect(closed, 1);
  });

  testWidgets('a lost answer then "already waiting" is explained',
      (tester) async {
    final backend = FakeLoanBackend()..dropApply = true;
    await pumpFlow(tester, loanBackend: backend);
    await chooseAma(tester);
    await tapKey(tester, 'next');
    await fillProduct(tester);
    await tapKey(tester, 'next');
    await search(tester, 'guarantorSearch', 'Mensah');
    await tapKey(tester, 'guarantorSearch.result.m-9');
    await tapKey(tester, 'next');

    await tapKey(tester, 'next');
    expect(find.textContaining("isn't clear whether"), findsOneWidget);

    backend
      ..actionStatus = 409
      ..actionMessage = 'This member already has a loan application waiting for review';
    await tapKey(tester, 'next');
    expect(find.textContaining('was probably sent then'), findsOneWidget);
  });

  testWidgets('started from a member, the member is filled in',
      (tester) async {
    await pumpFlow(
      tester,
      member: const PickedMember(
        id: 'm-1',
        name: 'Ama Mensah',
        status: MembershipStatus.active,
      ),
    );

    expect(key('chosenMember'), findsOneWidget);
    await tapKey(tester, 'next');
    expect(key('product'), findsOneWidget);

    // Nothing entered yet: leaving needs no confirmation.
    await tapKey(tester, 'back');
    await tapKey(tester, 'back');
    expect(closed, 1);
  });
}
