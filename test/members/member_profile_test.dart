import 'package:cash_client_desktop/members/member_models.dart';
import 'package:cash_client_desktop/members/member_profile.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  group('MemberProfile.fromJson', () {
    test('reads the full details, accounts and ID status', () {
      final member = MemberProfile.fromJson(FakeMemberBackend.profileJson(
        kycStatus: 'REJECTED',
        canUpload: true,
      ))!;

      expect(member.fullName, 'Ama Mensah');
      expect(member.limited, isFalse);
      expect(member.dateOfBirth, DateTime(1990, 7, 4));
      expect(member.registeredBy, 'STF0012');
      expect(member.registeredOn, DateTime(2026, 11, 16, 10, 15, 30, 123));
      expect(member.branchName, 'Tarkwa');
      expect(member.status, MembershipStatus.pending);
      expect(member.accounts.map((a) => a.typeLabel), ['Shares', 'Savings']);
      expect(member.accounts.first.status, AccountState.inactive);
      expect(member.kyc!.state, KycState.rejected);
      expect(member.kyc!.documentType, KycDocumentType.ghanaCard);
      expect(member.kyc!.rejectionReason, 'The picture is blurred');
      expect(member.kyc!.canUpload, isTrue);
    });

    test('a limited view has no personal details and no ID status', () {
      final member = MemberProfile.fromJson(
          FakeMemberBackend.profileJson(limited: true))!;

      expect(member.limited, isTrue);
      expect(member.phoneNumber, '0241234567');
      expect(member.dateOfBirth, isNull);
      expect(member.residentialAddress, isNull);
      expect(member.kyc, isNull);
      expect(member.accounts, hasLength(2));
    });

    test("today's backend, without branch, detail level or kyc, still reads",
        () {
      final json = FakeMemberBackend.profileJson(withKyc: false)
        ..remove('branchId')
        ..remove('branchName')
        ..remove('detailLevel');

      final member = MemberProfile.fromJson(json)!;

      expect(member.limited, isFalse);
      expect(member.kyc, isNull);
      expect(member.branchName, isNull);
    });

    test('an unknown kyc status is treated as not reported', () {
      final json = FakeMemberBackend.profileJson()
        ..['kyc'] = {'status': 'SOMETHING_NEW', 'canUpload': true};

      expect(MemberProfile.fromJson(json)!.kyc, isNull);
    });

    test('a body without an id or name is refused', () {
      expect(MemberProfile.fromJson({'memberId': 'x'}), isNull);
      expect(MemberProfile.fromJson('nope'), isNull);
    });
  });

  group('MemberSearchPage.fromJson', () {
    test('reads the results and skips broken ones', () {
      final page = MemberSearchPage.fromJson({
        'items': [
          FakeMemberBackend.summaryJson('m1', 'Ama'),
          {'firstName': 'No id'},
        ],
        'page': 0,
        'size': 20,
        'total': 7,
      })!;

      expect(page.items.single.fullName, 'Ama Mensah');
      expect(page.items.single.status, MembershipStatus.active);
      expect(page.total, 7);
    });

    test('a body without items, page or total is refused', () {
      expect(MemberSearchPage.fromJson({'items': []}), isNull);
    });
  });
}
