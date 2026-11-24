import 'package:cash_client_desktop/common/money.dart';
import 'package:cash_client_desktop/loans/loan_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  final salary = LoanProduct.fromJson(productJson())!;

  test('products read the backend shape', () {
    expect(salary.ratePercentHundredths, 2400);
    expect(salary.rateLabel, '24% a year');
    expect(salary.feeLabel, '2% processing fee');
    expect(salary.guarantorsRequired, 1);
    final flat = LoanProduct.fromJson(
        productJson(feeType: 'FLAT', fee: 10, rate: 24.5))!;
    expect(flat.feeLabel, 'GH₵ 10.00 processing fee');
    expect(flat.rateLabel, '24.5% a year');
    expect(flat.feeFor(Money.pesewas(100000)), Money.pesewas(1000));
  });

  group('the quote matches the backend (LoanRules)', () {
    test('flat interest, installments rounded down, the last takes the rest',
        () {
      final q = LoanQuote.of(salary, Money.pesewas(200000), 6);
      // 2,000 × 24% × 6 / 12 = 240.00
      expect(q.interest, Money.pesewas(24000));
      expect(q.toRepay, Money.pesewas(224000));
      // (333.33 + 40.00) five times, then 333.35 + 40.00
      expect(q.monthly, Money.pesewas(37333));
      expect(q.lastInstallment, Money.pesewas(37335));
      expect(
        q.monthly.pesewas * 5 + q.lastInstallment.pesewas,
        q.toRepay.pesewas,
      );
      // 2% fee, taken from the payout.
      expect(q.fee, Money.pesewas(4000));
      expect(q.paidIn, Money.pesewas(196000));
    });

    test('interest rounds half up to the pesewa', () {
      final odd = LoanProduct.fromJson(productJson(rate: 17.5))!;
      // 1,234.56 × 17.5% × 7 / 12 = 126.0291… → 126.03
      final q = LoanQuote.of(odd, Money.pesewas(123456), 7);
      expect(q.interest, Money.pesewas(12603));
      // 2% of 1,234.56 = 24.6912 → 24.69
      expect(q.fee, Money.pesewas(2469));
    });

    test('one month is one payment', () {
      final q = LoanQuote.of(salary, Money.pesewas(60000), 1);
      expect(q.lastInstallment, q.toRepay);
    });
  });

  test('applications, loans and portfolio rows read the backend shape', () {
    final a = LoanApplicationRecord.fromJson(loanApplicationJson(
      guarantors: [
        {'memberId': 'm-9', 'name': 'Kofi Mensah'},
      ],
    ))!;
    expect(a.status, LoanApplicationStatus.pending);
    expect(a.requestedAmount, Money.pesewas(200000));
    expect(a.guarantors, ['Kofi Mensah']);

    final loan = LoanDetails.fromJson(loanJson())!;
    expect(loan.installments, hasLength(2));
    expect(loan.nextDue!.number, 2);
    expect(loan.ratePercent, '24');
    expect(loan.closed, isFalse);

    const draft = LoanProductDraft(
      name: 'X',
      ratePercentHundredths: 2450,
      minAmount: Money.pesewas(50000),
      maxAmount: Money.pesewas(500000),
      maxTermMonths: 12,
      feeType: LoanFeeType.flat,
      feeValue: 1000,
      guarantorsRequired: 0,
      active: true,
    );
    expect(draft.toJson()['interestRatePercent'], 24.5);
    expect(draft.toJson()['processingFeeValue'], 10.0);
    expect(draft.toJson()['minAmount'], 500.0);
  });
}
