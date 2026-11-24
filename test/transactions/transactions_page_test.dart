import 'package:cash_client_desktop/transactions/receipt.dart';
import 'package:cash_client_desktop/transactions/transactions_page.dart';
import 'package:cash_client_desktop/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  late FakeTransactionBackend backend;
  late FakeMemberBackend members;
  late List<ReceiptData> printed;

  Map<String, dynamic> ama() => {
        ...FakeMemberBackend.summaryJson('m-ama', 'Ama'),
        'accounts': [
          {'accountNumber': '1001234', 'accountType': 'SHARES', 'status': 'ACTIVE'},
          {'accountNumber': '2004567', 'accountType': 'SAVINGS', 'status': 'ACTIVE'},
        ],
      };

  Future<void> pumpPage(
    WidgetTester tester, {
    bool withSettings = true,
    String savingsStatus = 'ACTIVE',
  }) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    printed = [];
    backend = FakeTransactionBackend(
      settings: withSettings ? FakeTransactionBackend.settingsJson() : null,
    )
      ..accounts['2004567'] = FakeTransactionBackend.accountJson('2004567',
          status: savingsStatus)
      ..accounts['1001234'] =
          FakeTransactionBackend.accountJson('1001234', type: 'SHARES')
      ..accounts['3001111'] =
          FakeTransactionBackend.accountJson('3001111', member: 'Kofi Boateng')
      ..history['2004567'] = [
        FakeTransactionBackend.recordJson(id: 'old', type: 'DEPOSIT', amount: 200),
      ];
    members = FakeMemberBackend()..searchResults = [ama()];

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: TransactionsPage(
          api: backend.api,
          memberApi: members.api,
          staffId: 'STF0012',
          creditUnionName: 'Penco Credit Union',
          printReceipt: (data) async => printed.add(data),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Finder key(String name) => find.byKey(Key('tx.$name'));

  Future<void> tap(WidgetTester tester, String name) async {
    await tester.ensureVisible(key(name));
    await tester.tap(key(name));
    await tester.pumpAndSettle();
  }

  Future<void> chooseAccount(WidgetTester tester, String number) async {
    await tester.enterText(key('search'), 'Ama');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    await tap(tester, 'account.$number');
  }

  Future<void> reviewWithdrawal(WidgetTester tester, String amount) async {
    await tester.enterText(key('amount'), amount);
    await tap(tester, 'review');
  }

  testWidgets('starts by asking for an account', (tester) async {
    await pumpPage(tester);

    expect(key('nothingChosen'), findsOneWidget);
    expect(key('form'), findsNothing);
  });

  testWidgets('choosing an account shows its balance and history',
      (tester) async {
    await pumpPage(tester);

    await chooseAccount(tester, '2004567');

    expect(find.text('GH₵ 1,250.00'), findsWidgets);
    expect(find.text('+200.00'), findsOneWidget);
    expect(key('form'), findsOneWidget);
  });

  testWidgets('a withdrawal shows the fee, sends one key, then a receipt',
      (tester) async {
    await pumpPage(tester);
    await chooseAccount(tester, '2004567');

    await reviewWithdrawal(tester, '100');

    expect(key('reviewCard'), findsOneWidget);
    expect(find.text('GH₵ 2.00'), findsOneWidget);
    expect(find.text('GH₵ 102.00'), findsOneWidget);

    await tap(tester, 'confirm');

    final (path, body) = backend.sent.single;
    expect(path, '/api/transaction/v1/withdrawal');
    expect(body['accountNumber'], '2004567');
    expect(body['amount'], 100.0);
    expect(body['idempotencyKey'], isA<String>());
    expect(key('done'), findsOneWidget);

    await tap(tester, 'print');

    final receipt = printed.single;
    expect(receipt.creditUnionName, 'Penco Credit Union');
    final labels = receipt.rows.map((r) => r.$1).toList();
    expect(labels, containsAll(['Reference', 'Amount', 'Fee', 'Served by']));
    expect(labels.any((l) => l.toLowerCase().contains('balance')), isFalse,
        reason: 'no balance on paper');
    expect(receipt.rows.firstWhere((r) => r.$1 == 'Account').$2, '•••• 4567');
  });

  testWidgets('without the settings endpoint the fee is explained in words',
      (tester) async {
    await pumpPage(tester, withSettings: false);
    await chooseAccount(tester, '2004567');

    await reviewWithdrawal(tester, '100');

    expect(find.text('Added on top by the system'), findsOneWidget);
  });

  testWidgets('a refused withdrawal shows the backend\'s reason; retry keeps '
      'the key', (tester) async {
    await pumpPage(tester);
    await chooseAccount(tester, '2004567');
    backend.sendAnswers.add((
      409,
      errorBody(409, 'This would go over the daily withdrawal limit of GHS '
          '10,000.00'),
    ));
    await reviewWithdrawal(tester, '100');

    await tap(tester, 'confirm');
    expect(find.textContaining('daily withdrawal limit'), findsOneWidget);

    await tap(tester, 'confirm');

    expect(backend.sent, hasLength(2));
    expect(backend.sent[1].$2['idempotencyKey'],
        backend.sent[0].$2['idempotencyKey']);
    expect(key('done'), findsOneWidget);
  });

  testWidgets('a lost answer keeps the same key and blocks going back',
      (tester) async {
    await pumpPage(tester);
    await chooseAccount(tester, '2004567');
    backend.sendAnswers.add(null);
    await reviewWithdrawal(tester, '100');

    await tap(tester, 'confirm');

    expect(find.textContaining("isn't clear whether this went through"),
        findsOneWidget);
    expect(tester.widget<OutlinedButton>(key('back')).onPressed, isNull);
    expect(key('checkHistory'), findsOneWidget);

    await tap(tester, 'confirm');

    expect(backend.sent[1].$2['idempotencyKey'],
        backend.sent[0].$2['idempotencyKey']);
    expect(key('done'), findsOneWidget);
  });

  testWidgets('going back to change the amount makes a new key',
      (tester) async {
    await pumpPage(tester);
    await chooseAccount(tester, '2004567');
    backend.sendAnswers.add((409, errorBody(409, 'Insufficient balance')));
    await reviewWithdrawal(tester, '100');
    await tap(tester, 'confirm');

    await tap(tester, 'back');
    await reviewWithdrawal(tester, '50');
    await tap(tester, 'confirm');

    expect(backend.sent[1].$2['amount'], 50.0);
    expect(backend.sent[1].$2['idempotencyKey'],
        isNot(backend.sent[0].$2['idempotencyKey']));
  });

  testWidgets('a transfer finds the receiving account first', (tester) async {
    await pumpPage(tester);
    await chooseAccount(tester, '2004567');
    await tap(tester, 'kind.transfer');

    await tester.enterText(key('amount'), '50');
    await tap(tester, 'review');
    expect(find.text('Find the receiving account first'), findsOneWidget);

    await tester.enterText(key('toAccount'), '3001111');
    await tap(tester, 'findTo');
    expect(find.textContaining('Kofi Boateng'), findsOneWidget);

    await tap(tester, 'review');
    await tap(tester, 'confirm');

    final (path, body) = backend.sent.single;
    expect(path, '/api/transaction/v1/transfer');
    expect(body['fromAccountNumber'], '2004567');
    expect(body['toAccountNumber'], '3001111');
  });

  testWidgets('a transfer to the same account is refused before sending',
      (tester) async {
    await pumpPage(tester);
    await chooseAccount(tester, '2004567');
    await tap(tester, 'kind.transfer');

    await tester.enterText(key('toAccount'), '2004567');
    await tap(tester, 'findTo');

    expect(find.textContaining("That's the same account"), findsOneWidget);
  });

  testWidgets('buying shares from a savings account goes to the shares '
      'account', (tester) async {
    await pumpPage(tester);
    await chooseAccount(tester, '2004567');
    await tap(tester, 'kind.sharePurchase');

    await reviewWithdrawal(tester, '30');
    await tap(tester, 'confirm');

    final (path, body) = backend.sent.single;
    expect(path, '/api/transaction/v1/share-purchase');
    expect(body['accountNumber'], '1001234');
  });

  testWidgets('a shares account only offers buying shares', (tester) async {
    await pumpPage(tester);
    await chooseAccount(tester, '1001234');

    expect(tester.widget<ChoiceChip>(key('kind.withdrawal')).onSelected,
        isNull);
    expect(tester.widget<ChoiceChip>(key('kind.sharePurchase')).selected,
        isTrue);
  });

  testWidgets('an inactive account explains why money can\'t move',
      (tester) async {
    await pumpPage(tester, savingsStatus: 'INACTIVE');
    await chooseAccount(tester, '2004567');

    expect(key('inactive'), findsOneWidget);
    await tester.enterText(key('amount'), '100');
    await tap(tester, 'review');
    expect(key('reviewCard'), findsNothing);
  });

  testWidgets('an amount must be a positive number with 2 decimals at most',
      (tester) async {
    await pumpPage(tester);
    await chooseAccount(tester, '2004567');

    await reviewWithdrawal(tester, '0');
    expect(find.text('The amount must be more than zero'), findsOneWidget);

    await reviewWithdrawal(tester, '10.555');
    expect(find.text('Enter an amount, such as 250 or 250.50'), findsOneWidget);
  });

  testWidgets('New transaction keeps the account and clears the form',
      (tester) async {
    await pumpPage(tester);
    await chooseAccount(tester, '2004567');
    await reviewWithdrawal(tester, '100');
    await tap(tester, 'confirm');

    await tap(tester, 'new');

    expect(key('form'), findsOneWidget);
    expect(key('accountCard'), findsOneWidget);
    expect(find.text('100'), findsNothing);
  });
}
