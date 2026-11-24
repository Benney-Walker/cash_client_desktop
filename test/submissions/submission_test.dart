import 'package:cash_client_desktop/api/api_exception.dart';
import 'package:cash_client_desktop/submissions/submission_api.dart';
import 'package:cash_client_desktop/submissions/submission_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  group('CollectorSubmission.fromJson', () {
    test('reads the day, its totals and payments', () {
      final s = CollectorSubmission.fromJson(FakeSubmissionBackend
          .submissionJson('s1', failedCount: 1, failedAmount: 20))!;

      expect(s.collectorName, 'Yaw Owusu');
      expect(s.waiting, isTrue);
      expect(s.expectedAmount, const Money.pesewas(231000));
      expect(s.failedAmount, const Money.pesewas(2000));
      expect(s.submittedAt, DateTime(2026, 11, 24, 16, 40));
      expect(s.payments.map((p) => p.typeLabel), ['Savings', 'Shares']);
      expect(s.payments.last.completed, isFalse);
      expect(s.payments.last.failureReason, 'Account is INACTIVE');
    });

    test('an approved day carries the count and surplus', () {
      final s = CollectorSubmission.fromJson(FakeSubmissionBackend
          .submissionJson('s1', status: 'APPROVED', counted: 2320, overage: 10))!;

      expect(s.waiting, isFalse);
      expect(s.countedAmount, const Money.pesewas(232000));
      expect(s.overageAmount, const Money.pesewas(1000));
      expect(s.approvedByStaffId, 'STF0012');
    });
  });

  group('CashCount', () {
    test('adds notes and the two coins', () {
      final count = const CashCount()
          .withCount(Denomination.cedis200, 5)
          .withCount(Denomination.cedis100, 8)
          .withCount(Denomination.cedis50, 6)
          .withCount(Denomination.cedis20, 5)
          .withCount(Denomination.cedis10, 1)
          .withCount(Denomination.pesewas50, 3)
          .withCount(Denomination.pesewas20, 1);

      expect(count.total, const Money.pesewas(221170));
      expect(count.subtotal(Denomination.cedis200), const Money.pesewas(100000));
    });

    test('lists every cedi note and only the 50p and 20p coins', () {
      expect(Denomination.values.map((d) => d.label), [
        'GH₵ 200', 'GH₵ 100', 'GH₵ 50', 'GH₵ 20', 'GH₵ 10', 'GH₵ 5',
        'GH₵ 2', 'GH₵ 1', '50 p', '20 p',
      ]);
    });

    test('a negative count is treated as none', () {
      expect(const CashCount().withCount(Denomination.cedis1, -4).total,
          Money.zero);
    });
  });

  group('SubmissionApi', () {
    test('lists by status and page', () async {
      final backend = FakeSubmissionBackend()
        ..approved.add(FakeSubmissionBackend.submissionJson('s9',
            status: 'APPROVED', counted: 2310, overage: 0));

      final page = await backend.api.list(SubmissionStatus.approved);

      expect(backend.listCalls.single, ('APPROVED', 0));
      expect(page.items.single.submissionId, 's9');
    });

    test('approves with the counted amount as a number', () async {
      final backend = FakeSubmissionBackend()
        ..waiting.add(FakeSubmissionBackend.submissionJson('s1'));

      final result =
          await backend.api.approve('s1', const Money.pesewas(231050));

      expect(backend.approvals.single, ('s1', 2310.5));
      expect(result.waiting, isFalse);
      expect(result.overageAmount, const Money.pesewas(50));
    });

    test('messages: the backend\'s reasons, and a lost answer', () {
      expect(
        approveErrorMessage(const ApiException(ApiFailure.conflict,
            message: 'The cash counted is GHS 5.00 short', statusCode: 409)),
        'The cash counted is GHS 5.00 short.',
      );
      expect(approveErrorMessage(const ApiException(ApiFailure.network)),
          contains('Approve again with the same count'));
      expect(
        submissionLoadErrorMessage(const ApiException(ApiFailure.forbidden,
            message: 'You are not assigned to a branch', statusCode: 403)),
        'You are not assigned to a branch.',
      );
    });
  });
}
