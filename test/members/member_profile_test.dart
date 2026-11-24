import 'dart:convert';

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

  group('member search page', () {
    test('reads the backend\'s PagedModel and skips broken rows', () {
      final page = PagedResult.fromJson(
        jsonDecode(pagedJson([
          FakeMemberBackend.summaryJson('m1', 'Ama', phone: null),
          {'firstName': 'No id'},
        ], total: 45)),
        MemberSummary.fromJson,
      )!;

      final ama = page.items.single;
      expect(ama.fullName, 'Ama Mensah');
      expect(ama.status, MembershipStatus.active);
      expect(ama.phoneNumber, isNull, reason: 'hidden for another branch');
      expect(ama.branchId, 'b-tarkwa');
      expect(ama.accounts.single.typeLabel, 'Shares');
      expect(page.totalElements, 45);
      expect(page.totalPages, 3);
      expect(page.hasMore, isTrue);
    });

    test('the last page has no more', () {
      final page = PagedResult.fromJson(
        jsonDecode(pagedJson(const [], page: 2, total: 45)),
        MemberSummary.fromJson,
      )!;

      expect(page.hasMore, isFalse);
    });

    test('a body that is not a page is refused', () {
      expect(
        PagedResult.fromJson({'items': [], 'total': 0}, MemberSummary.fromJson),
        isNull,
      );
      expect(
        PagedResult.fromJson(
          {'content': [], 'page': {'number': 0}},
          MemberSummary.fromJson,
        ),
        isNull,
      );
    });
  });
}
