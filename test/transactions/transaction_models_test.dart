import 'package:cash_client_desktop/members/member_profile.dart';
import 'package:cash_client_desktop/transactions/transaction_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  group('AccountDetails', () {
    test('reads the backend\'s account and balances', () {
      final account = AccountDetails.fromJson(
          FakeTransactionBackend.accountJson('2004567', available: 1250.5))!;

      expect(account.memberName, 'Ama Mensah');
      expect(account.typeLabel, 'Savings');
      expect(account.status, AccountState.active);
      expect(account.canTransact, isTrue);
      expect(account.availableBalance, const Money.pesewas(125050));
    });

    test('an inactive account cannot transact', () {
      final account = AccountDetails.fromJson(FakeTransactionBackend.accountJson(
          '2004567',
          status: 'INACTIVE'))!;

      expect(account.canTransact, isFalse);
    });
  });

  group('TransactionRecord', () {
    test('reads a transaction and signs it for the account viewed', () {
      final withdrawal = TransactionRecord.fromJson(
          FakeTransactionBackend.recordJson(amount: 100, fee: 2))!;
      final transfer = TransactionRecord.fromJson(FakeTransactionBackend
          .recordJson(type: 'TRANSFER', amount: 50, counterparty: '3001111'))!;
      final first = TransactionRecord.fromJson(FakeTransactionBackend.recordJson(
          type: 'DEPOSIT', amount: 150, share: 50))!;

      expect(withdrawal.typeLabel, 'Withdrawal');
      expect(withdrawal.createdAt, DateTime(2026, 11, 24, 10, 15, 30));
      expect(withdrawal.signedFor('2004567'), const Money.pesewas(-10200));
      expect(transfer.signedFor('2004567'), const Money.pesewas(-5000));
      expect(transfer.signedFor('3001111'), const Money.pesewas(5000));
      expect(first.signedFor('2004567'), const Money.pesewas(10000));
      expect(first.signedFor('1001234'), const Money.pesewas(5000));
    });
  });

  group('CounterSettings.withdrawalFee', () {
    test('flat', () {
      final settings =
          CounterSettings.fromJson(FakeTransactionBackend.settingsJson())!;

      expect(settings.withdrawalFee(const Money.pesewas(100000)),
          const Money.pesewas(200));
    });

    test('percentage, rounded half up like the backend', () {
      final settings = CounterSettings.fromJson(FakeTransactionBackend
          .settingsJson(feeType: 'PERCENTAGE', feeValue: 1.5))!;

      // 1.5% of 10.10 = 0.1515 → 0.15; of 10.30 = 0.1545 → 0.15;
      // of 10.50 = 0.1575 → 0.16; of 1.00 = 0.015 → 0.02 (half up).
      expect(settings.withdrawalFee(const Money.pesewas(1010)),
          const Money.pesewas(15));
      expect(settings.withdrawalFee(const Money.pesewas(1050)),
          const Money.pesewas(16));
      expect(settings.withdrawalFee(const Money.pesewas(100)),
          const Money.pesewas(2));
    });

    test('off', () {
      final settings = CounterSettings.fromJson(
          FakeTransactionBackend.settingsJson(feeEnabled: false))!;

      expect(settings.withdrawalFee(const Money.pesewas(100000)), Money.zero);
    });
  });

  group('TransactionDraft.toJson', () {
    final savings = AccountDetails.fromJson(
        FakeTransactionBackend.accountJson('2004567'))!;
    final other = AccountDetails.fromJson(
        FakeTransactionBackend.accountJson('3001111', member: 'Kofi'))!;

    test('a withdrawal carries the key, account and amount', () {
      final draft = TransactionDraft(
        kind: TransactionKind.withdrawal,
        account: savings,
        amount: const Money.pesewas(25050),
        description: '  School fees ',
      );

      expect(draft.toJson(idempotencyKey: 'k1'), {
        'idempotencyKey': 'k1',
        'accountNumber': '2004567',
        'amount': 250.5,
        'description': 'School fees',
      });
    });

    test('a transfer names both accounts and leaves out an empty note', () {
      final draft = TransactionDraft(
        kind: TransactionKind.transfer,
        account: savings,
        toAccount: other,
        amount: const Money.pesewas(5000),
        description: ' ',
      );

      expect(draft.toJson(idempotencyKey: 'k2'), {
        'idempotencyKey': 'k2',
        'fromAccountNumber': '2004567',
        'toAccountNumber': '3001111',
        'amount': 50.0,
      });
    });
  });

  test('account numbers are masked to their last 4 digits', () {
    expect(maskedAccount('2004567'), '•••• 4567');
    expect(maskedAccount('123'), '123');
  });
}
