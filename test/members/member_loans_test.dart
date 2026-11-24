import 'package:cash_client_desktop/loans/loan_application_flow.dart';
import 'package:cash_client_desktop/members/member_details_pane.dart';
import 'package:cash_client_desktop/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  late List<PickedMember> applied;

  Future<void> pumpPane(
    WidgetTester tester, {
    required String memberId,
    String status = 'ACTIVE',
    FakeLoanBackend? loans,
  }) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final members = FakeMemberBackend()
      ..profiles[memberId] = (FakeMemberBackend.profileJson(id: memberId)
        ..['membershipStatus'] = status);
    applied = [];
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: MemberDetailsPane(
          api: members.api,
          memberId: memberId,
          loanApi: (loans ?? FakeLoanBackend()).api,
          onApplyForLoan: applied.add,
          acceptDrops: false,
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Finder key(String name) => find.byKey(Key('memberDetails.$name'));

  testWidgets("shows the member's loans and a waiting application",
      (tester) async {
    await pumpPane(tester, memberId: 'm-1');

    expect(key('loans'), findsOneWidget);
    expect(key('loanWaiting'), findsOneWidget);
    expect(key('loan.loan-1'), findsOneWidget);
    expect(find.text('GH₵ 1,866.65 still owed'), findsOneWidget);
    // An application is already waiting: no second one from here.
    expect(key('applyForLoan'), findsNothing);
  });

  testWidgets('a loan opens with its installments', (tester) async {
    await pumpPane(tester, memberId: 'm-1');

    await tester.ensureVisible(key('loan.loan-1'));
    await tester.tap(key('loan.loan-1'));
    await tester.pumpAndSettle();

    expect(key('loanDialog'), findsOneWidget);
    expect(find.byKey(const Key('loan.installment.2')), findsOneWidget);
    await tester.tap(key('closeLoan'));
    await tester.pumpAndSettle();
    expect(key('loanDialog'), findsNothing);
  });

  testWidgets('an active member with no loan can apply', (tester) async {
    await pumpPane(tester, memberId: 'm-7');

    expect(key('noLoans'), findsOneWidget);
    await tester.ensureVisible(key('applyForLoan'));
    await tester.tap(key('applyForLoan'));
    await tester.pump();

    expect(applied.single.id, 'm-7');
    expect(applied.single.active, isTrue);
  });

  testWidgets('a pending member is told why they cannot apply',
      (tester) async {
    await pumpPane(tester, memberId: 'm-7', status: 'PENDING');

    expect(key('cannotApply'), findsOneWidget);
    expect(find.textContaining('Only active members'), findsOneWidget);
    expect(key('applyForLoan'), findsNothing);
  });

  testWidgets('one loan at a time', (tester) async {
    final loans = FakeLoanBackend()..applications.clear();
    await pumpPane(tester, memberId: 'm-1', loans: loans);

    expect(find.textContaining('One loan at a time'), findsOneWidget);
    expect(key('applyForLoan'), findsNothing);
  });
}
