import 'package:cash_client_desktop/api/api_exception.dart';
import 'package:cash_client_desktop/members/member_api.dart';
import 'package:cash_client_desktop/members/member_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  final member = NewMember(
    firstName: 'Ama',
    lastName: 'Mensah',
    dateOfBirth: DateTime(1990, 7, 4),
    phoneNumber: '0241234567',
    residentialAddress: 'Hse 3, Tarkwa',
    occupation: 'Trader',
    accountType: MemberAccountType.savings,
    branch: const Branch(id: 'b-tarkwa', name: 'Tarkwa'),
  );

  final document = KycDocument(
    type: KycDocumentType.ghanaCard,
    idNumber: 'GHA-123456789-0',
    image: KycImage.check('card.png', pngBytes).$1!,
  );

  ApiException conflict(String message) =>
      ApiException(ApiFailure.conflict, message: message, statusCode: 409);
  ApiException badRequest(String message) =>
      ApiException(ApiFailure.validation, message: message, statusCode: 400);

  group('registerMember', () {
    test('posts the details with the key and returns the new id', () async {
      final backend = FakeMemberBackend();

      final id = await backend.api.registerMember(member, idempotencyKey: 'k1');

      expect(id, FakeMemberBackend.newMemberId);
      expect(backend.addBodies.single['dob'], '1990-07-04');
      expect(backend.addBodies.single['branchId'], 'b-tarkwa');
      expect(backend.addBodies.single['idempotencyKey'], 'k1');
    });

    test('a 200 without an id is an unexpected response', () async {
      final backend = FakeMemberBackend()
        ..addAnswers.add((200, '{"status":"success"}'));

      await expectLater(
        backend.api.registerMember(member, idempotencyKey: 'k1'),
        throwsA(isA<ApiException>().having(
            (e) => e.failure, 'failure', ApiFailure.unexpectedResponse)),
      );
    });

    test('a dropped connection is a network failure', () async {
      final backend = FakeMemberBackend()..addAnswers.add(null);

      await expectLater(
        backend.api.registerMember(member, idempotencyKey: 'k1'),
        throwsA(isA<ApiException>()
            .having((e) => e.failure, 'failure', ApiFailure.network)),
      );
    });

    test('a taken phone number is a conflict with the backend message',
        () async {
      final backend = FakeMemberBackend()
        ..addAnswers.add((
          409,
          errorBody(409, 'A member with this phone number already exists.'),
        ));

      await expectLater(
        backend.api.registerMember(member, idempotencyKey: 'k1'),
        throwsA(isA<ApiException>()
            .having((e) => e.failure, 'failure', ApiFailure.conflict)
            .having((e) => e.message, 'message', contains('phone number'))),
      );
    });
  });

  group('uploadKycDocument', () {
    test('sends the member, document type, ID number and image', () async {
      final backend = FakeMemberBackend();

      await backend.api.uploadKycDocument(
        memberId: 'm-1',
        document: document,
      );

      final upload = backend.uploads.single;
      expect(upload.fields, {
        'memberId': 'm-1',
        'documentType': 'ECOWAS_CARD',
        'idNumber': 'GHA-123456789-0',
      });
      expect(upload.fileField, 'file');
      expect(upload.fileName, 'card.png');
      expect(upload.contentType, 'image/png');
      expect(upload.fileBytes, pngBytes);
    });

    test('tries once more after a 401, with a fresh request', () async {
      final backend = FakeMemberBackend()
        ..uploadAnswers.add((401, errorBody(401, 'Expired')));

      await backend.api.uploadKycDocument(memberId: 'm-1', document: document);

      expect(backend.uploads, hasLength(2));
      expect(backend.uploads.last.fileBytes, pngBytes);
    });

    test('a refused ID number is a conflict', () async {
      final backend = FakeMemberBackend()
        ..uploadAnswers.add((
          409,
          errorBody(409, 'This ID number is already registered to another '
              'member'),
        ));

      await expectLater(
        backend.api.uploadKycDocument(memberId: 'm-1', document: document),
        throwsA(isA<ApiException>()
            .having((e) => e.failure, 'failure', ApiFailure.conflict)),
      );
    });
  });

  group('registerErrorMessage', () {
    test('points a taken phone number to Contact and work', () {
      final (message, step) = registerErrorMessage(
          conflict('A member with this phone number already exists.'));

      expect(message, 'Another member already uses this phone number.');
      expect(step, RegisterMemberStep.contactAndWork);
    });

    test('after a lost answer, a taken phone number is probably this member',
        () {
      final (message, _) = registerErrorMessage(
        conflict('A member with this phone number already exists.'),
        afterUnknownOutcome: true,
      );

      expect(message, contains('probably registered'));
    });

    test('maps branch, date and account type problems to their steps', () {
      expect(
          registerErrorMessage(conflict('Branch information cannot be found'))
              .$2,
          RegisterMemberStep.account);
      expect(
          registerErrorMessage(
                  badRequest('Invalid date of birth; expected yyyy-MM-dd'))
              .$2,
          RegisterMemberStep.personal);
      expect(
          registerErrorMessage(
                  badRequest('Account type must be SAVINGS or CURRENT'))
              .$2,
          RegisterMemberStep.account);
      expect(registerErrorMessage(badRequest('Invalid phone number')).$2,
          RegisterMemberStep.contactAndWork);
    });

    test('says the outcome is unknown when the connection drops', () {
      final (message, step) =
          registerErrorMessage(const ApiException(ApiFailure.network));

      expect(message, contains("isn't clear whether the member"));
      expect(step, isNull);
    });

    test('shows other backend messages as written', () {
      expect(registerErrorMessage(badRequest('firstName: must not be blank')).$1,
          'firstName: must not be blank');
    });
  });

  group('kycErrorMessage', () {
    test('explains the common upload problems', () {
      expect(
        kycErrorMessage(
            conflict('This ID number is already registered to another member')),
        'This ID number is already registered to another member.',
      );
      expect(
        kycErrorMessage(const ApiException(ApiFailure.unexpectedResponse,
            message: 'The KYC document must be 5 MB or smaller',
            statusCode: 413)),
        contains('5 MB'),
      );
      expect(
        kycErrorMessage(
            badRequest('Ghana Card number must look like GHA-123456789-0')),
        'Ghana Card number must look like GHA-123456789-0',
      );
      expect(kycErrorMessage(const ApiException(ApiFailure.network)),
          contains("isn't clear whether the ID"));
    });
  });
}
