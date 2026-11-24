import 'package:cash_client_desktop/members/member_details_pane.dart';
import 'package:cash_client_desktop/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  testWidgets('each account offers a statement with its number filled in',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final members = FakeMemberBackend()
      ..profiles['m-1'] = FakeMemberBackend.profileJson(id: 'm-1');
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: MemberDetailsPane(
          api: members.api,
          memberId: 'm-1',
          reportApi: FakeReportBackend().api,
          acceptDrops: false,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final button = find.byKey(const Key('memberDetails.statement.2004567'));
    expect(button, findsOneWidget);
    expect(find.byKey(const Key('memberDetails.statement.1001234')), findsOneWidget);

    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('statement.dialog')), findsOneWidget);
    final field = tester.widget<TextField>(find.byKey(const Key('statement.account')));
    expect(field.controller!.text, '2004567');
    expect(field.readOnly, isTrue);

    await tester.tap(find.byKey(const Key('statement.close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('statement.dialog')), findsNothing);
  });

  testWidgets('without the report API there is no statement button',
      (tester) async {
    final members = FakeMemberBackend()
      ..profiles['m-1'] = FakeMemberBackend.profileJson(id: 'm-1');
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: MemberDetailsPane(api: members.api, memberId: 'm-1', acceptDrops: false),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('memberDetails.statement.2004567')), findsNothing);
  });
}
