import 'dart:typed_data';

import 'package:cash_client_desktop/common/uuid.dart';
import 'package:cash_client_desktop/members/member_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  final member = NewMember(
    firstName: 'Ama',
    middleName: '',
    lastName: 'Mensah',
    dateOfBirth: DateTime(1990, 7, 4),
    phoneNumber: '0241234567',
    residentialAddress: 'Hse 3, Tarkwa',
    occupation: 'Trader',
    accountType: MemberAccountType.savings,
    branch: const Branch(id: 'b-tarkwa', name: 'Tarkwa'),
  );

  group('NewMember.toJson', () {
    test('matches the backend MemberDetails fields', () {
      expect(member.toJson(idempotencyKey: 'key-1'), {
        'firstName': 'Ama',
        'lastName': 'Mensah',
        'dob': '1990-07-04',
        'phoneNumber': '0241234567',
        'residentialAddress': 'Hse 3, Tarkwa',
        'occupation': 'Trader',
        'accountType': 'SAVINGS',
        'branchId': 'b-tarkwa',
        'idempotencyKey': 'key-1',
      });
    });

    test('sends the middle name only when there is one', () {
      final withMiddle = NewMember(
        firstName: 'Ama',
        middleName: 'Serwaa',
        lastName: 'Mensah',
        dateOfBirth: DateTime(1990, 7, 4),
        phoneNumber: '0241234567',
        residentialAddress: 'Hse 3, Tarkwa',
        occupation: 'Trader',
        accountType: MemberAccountType.current,
        branch: const Branch(id: 'b-tarkwa', name: 'Tarkwa'),
      );

      final json = withMiddle.toJson(idempotencyKey: 'k');

      expect(json['middleName'], 'Serwaa');
      expect(json['accountType'], 'CURRENT');
      expect(withMiddle.fullName, 'Ama Serwaa Mensah');
      expect(member.fullName, 'Ama Mensah');
    });
  });

  group('KycDocumentType', () {
    test('uses the backend names', () {
      expect(KycDocumentType.ghanaCard.backendName, 'ECOWAS_CARD');
      expect(KycDocumentType.voterCard.backendName, 'VOTER_CARD');
    });

    test('Ghana Card numbers follow GHA-#########-#', () {
      const card = KycDocumentType.ghanaCard;
      expect(card.problemWith('GHA-123456789-0'), isNull);
      expect(card.problemWith(' gha-123456789-0 '), isNull);
      expect(card.problemWith('GHA-12345678-0'), isNotNull);
      expect(card.problemWith('123456789'), isNotNull);
      expect(card.problemWith(''), 'Enter the ID number');
    });

    test('voter card numbers only need to be present and short', () {
      const voter = KycDocumentType.voterCard;
      expect(voter.problemWith('7712345678'), isNull);
      expect(voter.problemWith('   '), 'Enter the ID number');
      expect(voter.problemWith('X' * 51), 'Use at most 50 characters');
    });

    test('normalises the way the backend does', () {
      expect(KycDocumentType.normalize('  gha-123456789-0 '),
          'GHA-123456789-0');
    });
  });

  group('KycImage.check', () {
    test('accepts PNG and JPEG by their first bytes', () {
      final (png, pngProblem) = KycImage.check('card.png', pngBytes);
      final (jpeg, jpegProblem) = KycImage.check('card.jpg', jpegBytes);

      expect(pngProblem, isNull);
      expect(png!.type, KycImageType.png);
      expect(jpegProblem, isNull);
      expect(jpeg!.type, KycImageType.jpeg);
    });

    test('goes by the content, not the file name', () {
      final (image, problem) = KycImage.check('card.png', jpegBytes);

      expect(problem, isNull);
      expect(image!.type, KycImageType.jpeg);
    });

    test('refuses other files, empty files and files over 5 MB', () {
      expect(KycImage.check('card.pdf', Uint8List.fromList([0x25, 0x50])).$2,
          contains("isn't a JPEG or PNG"));
      expect(KycImage.check('empty.png', Uint8List(0)).$2, contains('empty'));

      final big = Uint8List(KycImage.maxBytes + 1)
        ..setAll(0, pngBytes.sublist(0, 8));
      expect(KycImage.check('big.png', big).$2, contains('5 MB'));

      final atLimit = Uint8List(KycImage.maxBytes)
        ..setAll(0, pngBytes.sublist(0, 8));
      expect(KycImage.check('ok.png', atLimit).$2, isNull);
    });

    test('labels the size', () {
      final image = KycImage.check(
        'card.png',
        Uint8List(1536 * 1024)..setAll(0, pngBytes.sublist(0, 8)),
      ).$1!;

      expect(image.sizeLabel, '1.5 MB');
      expect(KycImage.check('s.png', pngBytes).$1!.sizeLabel, '1 KB');
    });
  });

  test('newUuid makes distinct version 4 UUIDs', () {
    final pattern = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );
    final keys = List.generate(50, (_) => newUuid());

    expect(keys.every(pattern.hasMatch), isTrue);
    expect(keys.toSet(), hasLength(50));
  });
}
