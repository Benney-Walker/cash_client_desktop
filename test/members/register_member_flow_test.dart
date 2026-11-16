import 'package:cash_client_desktop/members/kyc_image_picker.dart';
import 'package:cash_client_desktop/members/member_models.dart';
import 'package:cash_client_desktop/members/members_page.dart';
import 'package:cash_client_desktop/members/register_member_flow.dart';
import 'package:cash_client_desktop/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  late FakeMemberBackend backend;
  late int closed;

  Future<(KycImage?, String?)?> pickPng() async =>
      KycImage.check('ghana-card.png', pngBytes);

  Future<void> pumpFlow(
    WidgetTester tester, {
    FakeMemberBackend? memberBackend,
    PickKycImage? pickImage,
  }) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    backend = memberBackend ?? FakeMemberBackend();
    closed = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: RegisterMemberFlow(
            api: backend.api,
            branchApi: backend.branchApi,
            onClose: () => closed++,
            pickImage: pickImage ?? pickPng,
            acceptDrops: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder key(String name) => find.byKey(Key('registerMember.$name'));

  Future<void> tapKey(WidgetTester tester, String name) async {
    await tester.ensureVisible(key(name));
    await tester.tap(key(name));
    await tester.pumpAndSettle();
  }

  Future<void> next(WidgetTester tester) => tapKey(tester, 'next');

  Future<void> fillPersonal(WidgetTester tester) async {
    await tester.enterText(key('firstName'), 'Ama');
    await tester.enterText(key('lastName'), 'Mensah');
    await tester.enterText(key('dateOfBirth'), '1990-07-04');
  }

  Future<void> fillContact(WidgetTester tester) async {
    await tester.enterText(key('phone'), '0241234567');
    await tester.enterText(key('occupation'), 'Trader');
    await tester.enterText(key('address'), 'Hse 3, Tarkwa');
  }

  Future<void> fillAccount(WidgetTester tester) async {
    await tapKey(tester, 'accountType.savings');
    await tapKey(tester, 'branch');
    await tester.tap(find.text('Tarkwa · Tarkwa Market').last);
    await tester.pumpAndSettle();
  }

  Future<void> fillId(WidgetTester tester) async {
    await tapKey(tester, 'documentType');
    await tester.tap(find.text('Ghana Card').last);
    await tester.pumpAndSettle();
    await tester.enterText(key('idNumber'), 'gha-123456789-0');
    await tapKey(tester, 'chooseImage');
  }

  /// Fills the first three steps and lands on the ID step.
  Future<void> toIdStep(WidgetTester tester) async {
    await fillPersonal(tester);
    await next(tester);
    await fillContact(tester);
    await next(tester);
    await fillAccount(tester);
    await next(tester);
  }

  Future<void> toReviewWithId(WidgetTester tester) async {
    await toIdStep(tester);
    await fillId(tester);
    await next(tester);
  }

  testWidgets('the Members page opens Register member', (tester) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final members = FakeMemberBackend();

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
    expect(find.byKey(const Key('members.nothingSelected')), findsOneWidget);

    await tester.tap(find.byKey(const Key('members.register')));
    await tester.pumpAndSettle();

    expect(key('personal'), findsOneWidget);

    // Nothing entered, so Cancel goes straight back.
    await tester.tap(key('back'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('page.members')), findsOneWidget);
  });

  testWidgets('each step checks its fields before moving on', (tester) async {
    await pumpFlow(tester);

    await next(tester);
    expect(find.text('Enter the first name'), findsOneWidget);
    expect(find.text('Enter the date of birth'), findsOneWidget);

    await fillPersonal(tester);
    await next(tester);
    await tester.enterText(key('phone'), '24123456');
    await next(tester);
    expect(find.text('Use 10 digits starting with 0'), findsOneWidget);
    expect(find.text('Enter the occupation'), findsOneWidget);

    await fillContact(tester);
    await next(tester);
    await next(tester);
    expect(find.text('Choose Savings or Current'), findsOneWidget);
    expect(find.text('Choose a branch'), findsOneWidget);
  });

  testWidgets('the ID step checks the Ghana Card format and the picture',
      (tester) async {
    await pumpFlow(tester);
    await toIdStep(tester);

    await tapKey(tester, 'documentType');
    await tester.tap(find.text('Ghana Card').last);
    await tester.pumpAndSettle();
    await tester.enterText(key('idNumber'), 'GHA-1234');
    await next(tester);

    expect(find.text('A Ghana Card number looks like GHA-123456789-0'),
        findsOneWidget);
    expect(find.text('Choose a picture of the ID document'), findsOneWidget);
  });

  testWidgets('a file that is not an image is refused with a reason',
      (tester) async {
    await pumpFlow(
      tester,
      pickImage: () async => (null, "That file isn't a JPEG or PNG image."),
    );
    await toIdStep(tester);

    await tapKey(tester, 'chooseImage');

    expect(key('imageProblem'), findsOneWidget);
    expect(key('chosenImage'), findsNothing);
  });

  testWidgets('registers the member, then sends the ID document',
      (tester) async {
    await pumpFlow(tester);
    await toReviewWithId(tester);

    expect(find.text('Ama Mensah'), findsOneWidget);
    expect(find.text('Shares and Savings'), findsOneWidget);
    expect(find.text('GHA-123456789-0'), findsOneWidget);

    await next(tester);

    final body = backend.addBodies.single;
    expect(body['firstName'], 'Ama');
    expect(body['dob'], '1990-07-04');
    expect(body['accountType'], 'SAVINGS');
    expect(body['branchId'], 'b-tarkwa');
    expect(body['idempotencyKey'], isA<String>());

    final upload = backend.uploads.single;
    expect(upload.fields['memberId'], FakeMemberBackend.newMemberId);
    expect(upload.fields['documentType'], 'ECOWAS_CARD');
    expect(upload.fields['idNumber'], 'GHA-123456789-0');

    expect(key('registered'), findsOneWidget);
    expect(find.text('ID sent for verification'), findsOneWidget);
  });

  testWidgets('the ID step can be skipped', (tester) async {
    await pumpFlow(tester);
    await toIdStep(tester);

    await tapKey(tester, 'skipId');
    expect(find.text('Not added. Upload it later.'), findsOneWidget);

    await next(tester);

    expect(backend.addBodies, hasLength(1));
    expect(backend.uploads, isEmpty);
    expect(find.text('ID not added'), findsOneWidget);
  });

  testWidgets(
      'a failed upload keeps the member and retries only the ID document',
      (tester) async {
    final members = FakeMemberBackend()
      ..uploadAnswers.add((
        409,
        errorBody(409, 'This ID number is already registered to another '
            'member'),
      ));
    await pumpFlow(tester, memberBackend: members);
    await toReviewWithId(tester);

    await next(tester);

    expect(key('finishId'), findsOneWidget);
    expect(find.text('This ID number is already registered to another '
        'member.'), findsOneWidget);

    await tester.enterText(key('idNumber'), 'GHA-987654321-0');
    await tapKey(tester, 'retryUpload');

    expect(members.addBodies, hasLength(1), reason: 'not registered twice');
    expect(members.uploads, hasLength(2));
    expect(members.uploads.last.fields['idNumber'], 'GHA-987654321-0');
    expect(key('registered'), findsOneWidget);
  });

  testWidgets('after a failed upload, the ID can be left for later',
      (tester) async {
    final members = FakeMemberBackend()..uploadAnswers.add((500, '{}'));
    await pumpFlow(tester, memberBackend: members);
    await toReviewWithId(tester);
    await next(tester);

    await tapKey(tester, 'uploadLater');

    expect(find.text('ID not added'), findsOneWidget);
  });

  testWidgets('an upload whose answer was lost counts once the backend has it',
      (tester) async {
    final members = FakeMemberBackend()
      ..uploadAnswers.addAll([
        null,
        (
          409,
          errorBody(
              409, 'A KYC document has already been submitted for this member'),
        ),
      ]);
    await pumpFlow(tester, memberBackend: members);
    await toReviewWithId(tester);
    await next(tester);
    expect(find.textContaining("isn't clear whether the ID"), findsOneWidget);

    await tapKey(tester, 'retryUpload');

    expect(find.text('ID sent for verification'), findsOneWidget);
  });

  testWidgets('a taken phone number points back to Contact and work',
      (tester) async {
    final members = FakeMemberBackend()
      ..addAnswers.add((
        409,
        errorBody(409, 'A member with this phone number already exists.'),
      ));
    await pumpFlow(tester, memberBackend: members);
    await toReviewWithId(tester);

    await next(tester);
    expect(find.text('Another member already uses this phone number.'),
        findsOneWidget);

    await tapKey(tester, 'fixStep');

    expect(key('contact'), findsOneWidget);
    expect(members.uploads, isEmpty);
  });

  testWidgets('a retry after a lost answer reuses the idempotency key',
      (tester) async {
    final members = FakeMemberBackend()..addAnswers.add(null);
    await pumpFlow(tester, memberBackend: members);
    await toIdStep(tester);
    await tapKey(tester, 'skipId');

    await next(tester);
    expect(find.textContaining("isn't clear whether the member"),
        findsOneWidget);
    await next(tester);

    expect(members.addBodies, hasLength(2));
    expect(members.addBodies[1]['idempotencyKey'],
        members.addBodies[0]['idempotencyKey']);
    expect(key('registered'), findsOneWidget);
  });

  testWidgets('editing after a refused registration uses a new key',
      (tester) async {
    final members = FakeMemberBackend()
      ..addAnswers.add((
        409,
        errorBody(409, 'A member with this phone number already exists.'),
      ));
    await pumpFlow(tester, memberBackend: members);
    await toIdStep(tester);
    await tapKey(tester, 'skipId');
    await next(tester);

    await tapKey(tester, 'fixStep');
    await tester.enterText(key('phone'), '0209876543');
    await next(tester);
    await next(tester);
    await tapKey(tester, 'skipId');
    await next(tester);

    expect(members.addBodies, hasLength(2));
    expect(members.addBodies[1]['phoneNumber'], '0209876543');
    expect(members.addBodies[1]['idempotencyKey'],
        isNot(members.addBodies[0]['idempotencyKey']));
  });

  testWidgets('leaving with details entered asks first', (tester) async {
    await pumpFlow(tester);
    await tester.enterText(key('firstName'), 'Ama');

    await tapKey(tester, 'back');
    expect(find.text('Discard this registration?'), findsOneWidget);

    await tapKey(tester, 'discard');
    expect(closed, 1);
  });

  testWidgets('a branch list that fails to load can be retried',
      (tester) async {
    final members = FakeMemberBackend(branchesStatus: 500);
    await pumpFlow(tester, memberBackend: members);
    await fillPersonal(tester);
    await next(tester);
    await fillContact(tester);
    await next(tester);

    expect(key('branchesError'), findsOneWidget);
    members.branchesStatus = 200;
    await tapKey(tester, 'retryBranches');

    expect(key('branch'), findsOneWidget);
    expect(members.branchCalls, 2);
  });

  testWidgets('Register another starts a fresh form', (tester) async {
    await pumpFlow(tester);
    await toIdStep(tester);
    await tapKey(tester, 'skipId');
    await next(tester);

    await tapKey(tester, 'registerAnother');

    expect(key('personal'), findsOneWidget);
    expect(find.text('Ama'), findsNothing);
  });
}
