import 'package:cash_client_desktop/api/api_exception.dart';
import 'package:cash_client_desktop/transactions/transaction_api.dart';
import 'package:cash_client_desktop/transactions/transaction_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  late FakeTransactionBackend backend;

  setUp(() {
    backend = FakeTransactionBackend()
      ..accounts['2004567'] = FakeTransactionBackend.accountJson('2004567')
      ..history['2004567'] = [
        FakeTransactionBackend.recordJson(id: 'a'),
        FakeTransactionBackend.recordJson(id: 'b', type: 'DEPOSIT'),
      ];
  });

  test('looks up an account; an unknown one is notFound', () async {
    final account = await backend.api.fetchAccount(' 2004567 ');

    expect(account.accountNumber, '2004567');
    await expectLater(
      backend.api.fetchAccount('999'),
      throwsA(isA<ApiException>()
          .having((e) => e.failure, 'failure', ApiFailure.notFound)),
    );
  });

  test('reads the history page', () async {
    final page = await backend.api.fetchHistory('2004567');

    expect(page.items.map((r) => r.transactionId), ['a', 'b']);
    expect(page.hasMore, isFalse);
  });

  test('settings are null until the backend offers them', () async {
    expect(await backend.api.fetchSettings(), isNull);

    backend.settings = FakeTransactionBackend.settingsJson();
    final settings = await backend.api.fetchSettings();
    expect(settings!.minFirstDeposit, const Money.pesewas(10000));
  });

  test('sends the draft to its endpoint with the key', () async {
    final account = await backend.api.fetchAccount('2004567');
    final record = await backend.api.send(
      TransactionDraft(
        kind: TransactionKind.deposit,
        account: account,
        amount: const Money.pesewas(20000),
      ),
      idempotencyKey: 'key-1',
    );

    final (path, body) = backend.sent.single;
    expect(path, '/api/transaction/v1/deposit');
    expect(body, {
      'idempotencyKey': 'key-1',
      'accountNumber': '2004567',
      'amount': 200.0,
    });
    expect(record.typeLabel, 'Deposit');
  });

  group('transactionErrorMessage', () {
    test('shows the backend\'s reasons as written', () {
      expect(
        transactionErrorMessage(const ApiException(ApiFailure.conflict,
            message: 'Insufficient balance: the account must keep at least '
                'GHS 20.00',
            statusCode: 409)),
        'Insufficient balance: the account must keep at least GHS 20.00.',
      );
    });

    test('a lost answer is an unknown outcome, not a failure', () {
      expect(transactionErrorMessage(const ApiException(ApiFailure.network)),
          contains("isn't clear whether this went through"));
    });

    test('an unknown account is explained', () {
      expect(accountErrorMessage(const ApiException(ApiFailure.notFound)),
          'No account has that number.');
    });
  });
}
