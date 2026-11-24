import 'package:cash_client_desktop/members/member_api.dart';
import 'package:cash_client_desktop/members/member_models.dart';
import 'package:cash_client_desktop/members/members_page.dart';
import 'package:cash_client_desktop/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  late FakeMemberBackend backend;

  Future<(KycImage?, String?)?> pickPng() async =>
      KycImage.check('ghana-card.png', pngBytes);

  Future<void> pumpPage(WidgetTester tester, FakeMemberBackend members) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    backend = members;

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: MembersPage(
          api: members.api,
          branchApi: members.branchApi,
          pickImage: pickPng,
          acceptDrops: false,
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Finder key(String name) => find.byKey(Key(name));

  /// Types a search and waits out the pause before it's sent.
  Future<void> search(WidgetTester tester, String text) async {
    await tester.enterText(key('members.search'), text);
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
  }

  FakeMemberBackend withAma({Map<String, dynamic>? profile}) {
    return FakeMemberBackend()
      ..searchResults = [
        FakeMemberBackend.summaryJson('m-ama', 'Ama', status: 'PENDING'),
        FakeMemberBackend.summaryJson('m-kofi', 'Kofi'),
      ]
      ..profiles['m-ama'] =
          profile ?? FakeMemberBackend.profileJson(id: 'm-ama');
  }

  testWidgets('waits for two characters, then searches once typing pauses',
      (tester) async {
    await pumpPage(tester, withAma());

    await search(tester, 'A');
    expect(backend.searches, isEmpty);
    expect(key('members.searchHint'), findsOneWidget);

    await tester.enterText(key('members.search'), 'Am');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(key('members.search'), 'Ama');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();

    expect(backend.searches, [('Ama', 0)]);
    expect(find.text('2 members'), findsOneWidget);
    expect(key('members.result.m-ama'), findsOneWidget);
  });

  testWidgets('choosing a result shows the details and accounts',
      (tester) async {
    await pumpPage(tester, withAma());
    await search(tester, 'Ama');

    await tester.tap(key('members.result.m-ama'));
    await tester.pumpAndSettle();

    expect(key('memberDetails.name'), findsOneWidget);
    expect(find.text('Hse 3, Tarkwa'), findsOneWidget);
    expect(find.text('2026-11-16 by STF0012'), findsOneWidget);
    expect(find.text('2004567'), findsOneWidget);
    expect(find.text('ID not added'), findsWidgets);
    expect(key('memberDetails.upload'), findsOneWidget);
  });

  testWidgets('uploads an ID document from the details, then reloads',
      (tester) async {
    await pumpPage(tester, withAma());
    await search(tester, 'Ama');
    await tester.tap(key('members.result.m-ama'));
    await tester.pumpAndSettle();

    await tester.tap(key('memberDetails.upload'));
    await tester.pumpAndSettle();
    await tester.tap(key('memberDetails.documentType'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ghana Card').last);
    await tester.pumpAndSettle();
    await tester.enterText(key('memberDetails.idNumber'), 'GHA-123456789-0');
    await tester.ensureVisible(key('memberDetails.chooseImage'));
    await tester.tap(key('memberDetails.chooseImage'));
    await tester.pumpAndSettle();

    backend.profiles['m-ama'] = FakeMemberBackend.profileJson(
        id: 'm-ama', kycStatus: 'PENDING', canUpload: false);
    await tester.ensureVisible(key('memberDetails.sendUpload'));
    await tester.tap(key('memberDetails.sendUpload'));
    await tester.pumpAndSettle();

    final upload = backend.uploads.single;
    expect(upload.fields['memberId'], 'm-ama');
    expect(upload.fields['idNumber'], 'GHA-123456789-0');
    expect(key('memberDetails.uploaded'), findsOneWidget);
    expect(find.text('ID under review'), findsOneWidget);
    expect(key('memberDetails.upload'), findsNothing);
    expect(backend.detailCalls, 2);
  });

  testWidgets('a refused upload shows why and keeps the form',
      (tester) async {
    final members = withAma()
      ..uploadAnswers.add((
        409,
        errorBody(409, 'This ID number is already registered to another '
            'member'),
      ));
    await pumpPage(tester, members);
    await search(tester, 'Ama');
    await tester.tap(key('members.result.m-ama'));
    await tester.pumpAndSettle();
    await tester.tap(key('memberDetails.upload'));
    await tester.pumpAndSettle();
    await tester.tap(key('memberDetails.documentType'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ghana Card').last);
    await tester.pumpAndSettle();
    await tester.enterText(key('memberDetails.idNumber'), 'GHA-123456789-0');
    await tester.ensureVisible(key('memberDetails.chooseImage'));
    await tester.tap(key('memberDetails.chooseImage'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(key('memberDetails.sendUpload'));
    await tester.tap(key('memberDetails.sendUpload'));
    await tester.pumpAndSettle();

    expect(key('memberDetails.uploadError'), findsOneWidget);
    expect(key('memberDetails.uploadForm'), findsOneWidget);
  });

  testWidgets('a rejected ID shows the reason and who may re-upload',
      (tester) async {
    await pumpPage(
      tester,
      withAma(
        profile: FakeMemberBackend.profileJson(
            id: 'm-ama', kycStatus: 'REJECTED', canUpload: false),
      ),
    );
    await search(tester, 'Ama');
    await tester.tap(key('members.result.m-ama'));
    await tester.pumpAndSettle();

    expect(find.text('The picture is blurred'), findsOneWidget);
    expect(find.textContaining('Only the staff member who registered'),
        findsOneWidget);
    expect(key('memberDetails.upload'), findsNothing);
  });

  testWidgets("another branch's member shows the limited view",
      (tester) async {
    await pumpPage(
      tester,
      withAma(
          profile: FakeMemberBackend.profileJson(id: 'm-ama', limited: true)),
    );
    await search(tester, 'Ama');
    await tester.tap(key('members.result.m-ama'));
    await tester.pumpAndSettle();

    expect(key('memberDetails.limited'), findsOneWidget);
    expect(find.text('Hse 3, Tarkwa'), findsNothing);
    expect(key('memberDetails.kyc'), findsNothing);
    expect(find.text('2004567'), findsOneWidget);
  });

  testWidgets('without an ID status from the backend, no upload is offered',
      (tester) async {
    await pumpPage(
      tester,
      withAma(
          profile: FakeMemberBackend.profileJson(id: 'm-ama', withKyc: false)),
    );
    await search(tester, 'Ama');
    await tester.tap(key('members.result.m-ama'));
    await tester.pumpAndSettle();

    expect(find.textContaining("doesn't report this member's ID status"),
        findsOneWidget);
    expect(key('memberDetails.upload'), findsNothing);
  });

  testWidgets('says when the server has no search yet', (tester) async {
    await pumpPage(tester, FakeMemberBackend()..searchStatus = 404);

    await search(tester, 'Ama');

    expect(find.text("The server doesn't offer member search yet."),
        findsOneWidget);
  });

  testWidgets('no matches are said plainly', (tester) async {
    await pumpPage(tester, FakeMemberBackend());

    await search(tester, 'Zz');

    expect(key('members.noResults'), findsOneWidget);
  });

  testWidgets('more results load on request', (tester) async {
    final members = withAma()..searchTotal = MemberApi.pageSize + 1;
    await pumpPage(tester, members);
    await search(tester, 'Mensah');

    members.searchResults = [FakeMemberBackend.summaryJson('m-efua', 'Efua')];
    await tester.tap(key('members.more'));
    await tester.pumpAndSettle();

    expect(members.searches.last, ('Mensah', 1));
    expect(key('members.result.m-efua'), findsOneWidget);
    expect(key('members.more'), findsNothing);
  });

  testWidgets('a member that no longer exists is reported', (tester) async {
    final members = withAma()..profiles.clear();
    await pumpPage(tester, members);
    await search(tester, 'Ama');

    await tester.tap(key('members.result.m-ama'));
    await tester.pumpAndSettle();

    expect(find.text("This member couldn't be found."), findsOneWidget);
  });

  testWidgets('View member after registering opens their details',
      (tester) async {
    final members = FakeMemberBackend()
      ..profiles[FakeMemberBackend.newMemberId] =
          FakeMemberBackend.profileJson();
    await pumpPage(tester, members);
    await tester.tap(key('members.register'));
    await tester.pumpAndSettle();

    Future<void> next() async {
      await tester.ensureVisible(key('registerMember.next'));
      await tester.tap(key('registerMember.next'));
      await tester.pumpAndSettle();
    }

    await tester.enterText(key('registerMember.firstName'), 'Ama');
    await tester.enterText(key('registerMember.lastName'), 'Mensah');
    await tester.enterText(key('registerMember.dateOfBirth'), '1990-07-04');
    await next();
    await tester.enterText(key('registerMember.phone'), '0241234567');
    await tester.enterText(key('registerMember.occupation'), 'Trader');
    await tester.enterText(key('registerMember.address'), 'Hse 3, Tarkwa');
    await next();
    await tester.tap(key('registerMember.accountType.savings'));
    await tester.pumpAndSettle();
    await tester.tap(key('registerMember.branch'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tarkwa · Tarkwa Market').last);
    await tester.pumpAndSettle();
    await next();
    await tester.tap(key('registerMember.skipId'));
    await tester.pumpAndSettle();
    await next();

    await tester.tap(key('registerMember.view'));
    await tester.pumpAndSettle();

    expect(key('page.members'), findsOneWidget);
    expect(key('memberDetails.name'), findsOneWidget);
    expect(key('memberDetails.upload'), findsOneWidget);
  });

  test('search sends the trimmed query, page and size', () async {
    final members = FakeMemberBackend();

    await members.api.searchMembers('  0241 ', page: 2);

    expect(members.searches.single, ('0241', 2));
    expect(MemberApi.pageSize, 20);
  });
}
