import 'package:flutter/foundation.dart';

import '../common/money.dart';
import '../members/member_profile.dart';

export '../common/money.dart';

/// The four counter transactions (owner decision 24 November 2026), all
/// open to Administrators and Agents for a member of any branch.
enum TransactionKind {
  withdrawal(
    tab: 'Withdraw',
    label: 'Withdrawal',
    path: '/api/transaction/v1/withdrawal',
  ),
  deposit(
    tab: 'Deposit',
    label: 'Deposit',
    path: '/api/transaction/v1/deposit',
  ),
  sharePurchase(
    tab: 'Buy shares',
    label: 'Share purchase',
    path: '/api/transaction/v1/share-purchase',
  ),
  transfer(
    tab: 'Transfer',
    label: 'Transfer',
    path: '/api/transaction/v1/transfer',
  );

  const TransactionKind({
    required this.tab,
    required this.label,
    required this.path,
  });

  /// The tab's label on the transaction form.
  final String tab;

  /// The name on the review, the result and the receipt.
  final String label;
  final String path;
}

/// An account as the counter sees it (`AccountBalanceResponse` from
/// `GET /api/transaction/v1/account/{accountNumber}`).
@immutable
class AccountDetails {
  const AccountDetails({
    required this.accountNumber,
    required this.type,
    required this.currentBalance,
    required this.availableBalance,
    required this.memberName,
    this.status,
    this.memberId,
  });

  final String accountNumber;

  /// `SAVINGS`, `CURRENT` or `SHARES`.
  final String type;
  final AccountState? status;
  final Money currentBalance;
  final Money availableBalance;
  final String? memberId;
  final String memberName;

  bool get isShares => type == 'SHARES';
  bool get canTransact => status == AccountState.active;

  String get typeLabel =>
      type.isEmpty ? 'Account' : type[0] + type.substring(1).toLowerCase();

  static AccountDetails? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final number = json['accountNumber'];
    final type = json['accountType'];
    final current = Money.fromJson(json['currentBalance']);
    final available = Money.fromJson(json['availableBalance']);
    final name = json['memberName'];
    if (number is! String ||
        number.isEmpty ||
        type is! String ||
        current == null ||
        available == null) {
      return null;
    }
    return AccountDetails(
      accountNumber: number,
      type: type,
      status: AccountState.parse(json['status']),
      currentBalance: current,
      availableBalance: available,
      memberId: json['memberId'] is String ? json['memberId'] as String : null,
      memberName: name is String && name.trim().isNotEmpty ? name : 'Member',
    );
  }
}

/// A recorded transaction (`TransactionResponse`).
@immutable
class TransactionRecord {
  const TransactionRecord({
    required this.transactionId,
    required this.type,
    required this.amount,
    required this.accountNumber,
    this.counterpartyAccountNumber,
    this.fee,
    this.shareAmount,
    this.status,
    this.description,
    this.staffId,
    this.createdAt,
  });

  final String transactionId;

  /// The backend's `TransactionType`, such as `DEPOSIT` or `TRANSFER`.
  final String type;
  final Money amount;
  final String accountNumber;
  final String? counterpartyAccountNumber;
  final Money? fee;

  /// For a first deposit: the part that went to the shares account.
  final Money? shareAmount;
  final String? status;
  final String? description;
  final String? staffId;
  final DateTime? createdAt;

  static const _labels = {
    'DEPOSIT': 'Deposit',
    'WITHDRAWAL': 'Withdrawal',
    'TRANSFER': 'Transfer',
    'SHARES': 'Share purchase',
    'FEE': 'Fee',
    'LOAN_PAYMENT': 'Loan payment',
    'LOAN_DISBURSEMENT': 'Loan payout',
    'COLLECTOR_HANDOVER': 'Collector handover',
    'COLLECTOR_SHORTAGE_REPAYMENT': 'Shortage repayment',
  };

  String get typeLabel => _labels[type] ?? type;

  /// Money into [account] is positive, money out of it negative. A
  /// transfer is out of its source and into its counterparty; a first
  /// deposit's share part lands in the shares account.
  Money signedFor(String account) {
    switch (type) {
      case 'WITHDRAWAL':
      case 'FEE':
      case 'LOAN_PAYMENT':
        return Money.zero - amount - (fee ?? Money.zero);
      case 'TRANSFER':
        return account == accountNumber ? Money.zero - amount : amount;
      case 'DEPOSIT':
        final share = shareAmount;
        if (share != null && share.isPositive) {
          return account == accountNumber ? amount - share : share;
        }
        return amount;
      default:
        return amount;
    }
  }

  static TransactionRecord? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final id = json['transactionId'];
    final type = json['transactionType'];
    final amount = Money.fromJson(json['amount']);
    final account = json['accountNumber'];
    if (id is! String || type is! String || amount == null || account is! String) {
      return null;
    }
    String? text(String key) {
      final value = json[key];
      return value is String && value.trim().isNotEmpty ? value : null;
    }

    return TransactionRecord(
      transactionId: id,
      type: type,
      amount: amount,
      accountNumber: account,
      counterpartyAccountNumber: text('counterpartyAccountNumber'),
      fee: Money.fromJson(json['feeAmount']),
      shareAmount: Money.fromJson(json['shareAmount']),
      status: text('status'),
      description: text('description'),
      staffId: text('initiatedByStaffId'),
      // LocalDateTime in the credit union's time, such as 2026-11-24T10:15:30.
      createdAt: DateTime.tryParse(text('createdAt') ?? ''),
    );
  }
}

/// The rules the counter needs to explain a transaction before it's sent:
/// the withdrawal fee, minimum balance, daily limit and the first deposit.
///
/// The backend keeps them in `financial_settings` but has no endpoint to
/// read them yet (asked in CASH_CLIENT_DESKTOP.md section 21); until it
/// does, the review step says a fee is added without its amount.
@immutable
class CounterSettings {
  const CounterSettings({
    required this.initialShareAmount,
    required this.minFirstDeposit,
    required this.withdrawalMinBalance,
    required this.withdrawalDailyLimit,
    required this.withdrawalFeeEnabled,
    required this.withdrawalFeePercentage,
    required this.withdrawalFeeValue,
  });

  final Money initialShareAmount;
  final Money minFirstDeposit;
  final Money withdrawalMinBalance;
  final Money withdrawalDailyLimit;
  final bool withdrawalFeeEnabled;

  /// True for a percentage fee, false for a flat one.
  final bool withdrawalFeePercentage;

  /// GHS for a flat fee; a percentage, such as 1.5, otherwise.
  final double withdrawalFeeValue;

  /// The fee on a withdrawal of [amount], worked out as the backend does
  /// (`FeeRules.withdrawalFee`): flat, or a percentage rounded half up to
  /// the pesewa.
  Money withdrawalFee(Money amount) {
    if (!withdrawalFeeEnabled) return Money.zero;
    if (!withdrawalFeePercentage) {
      return Money.pesewas((withdrawalFeeValue * 100).round());
    }
    // pesewas × percent / 100, half up. Work in hundredths of a percent to
    // stay in integers.
    final hundredths = (withdrawalFeeValue * 100).round();
    final raw = amount.pesewas * hundredths;
    return Money.pesewas((raw + 5000) ~/ 10000);
  }

  static CounterSettings? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final share = Money.fromJson(json['initialShareAmount']);
    final first = Money.fromJson(json['minFirstDeposit']);
    final minBalance = Money.fromJson(json['withdrawalMinBalance']);
    final limit = Money.fromJson(json['withdrawalDailyLimit']);
    final enabled = json['withdrawalFeeEnabled'];
    final type = json['withdrawalFeeType'];
    final value = json['withdrawalFeeValue'];
    if (share == null ||
        first == null ||
        minBalance == null ||
        limit == null ||
        enabled is! bool ||
        (type != 'FLAT' && type != 'PERCENTAGE') ||
        value is! num) {
      return null;
    }
    return CounterSettings(
      initialShareAmount: share,
      minFirstDeposit: first,
      withdrawalMinBalance: minBalance,
      withdrawalDailyLimit: limit,
      withdrawalFeeEnabled: enabled,
      withdrawalFeePercentage: type == 'PERCENTAGE',
      withdrawalFeeValue: value.toDouble(),
    );
  }
}

/// What the staff member is about to send.
@immutable
class TransactionDraft {
  const TransactionDraft({
    required this.kind,
    required this.account,
    required this.amount,
    this.toAccount,
    this.description,
  });

  final TransactionKind kind;

  /// The account the money comes from or goes to; for a share purchase, the
  /// member's shares account.
  final AccountDetails account;

  /// For a transfer: the receiving account.
  final AccountDetails? toAccount;
  final Money amount;
  final String? description;

  /// The request body, with the [idempotencyKey] of this confirm step.
  Map<String, Object?> toJson({required String idempotencyKey}) => {
        'idempotencyKey': idempotencyKey,
        if (kind == TransactionKind.transfer) ...{
          'fromAccountNumber': account.accountNumber,
          'toAccountNumber': toAccount!.accountNumber,
        } else
          'accountNumber': account.accountNumber,
        'amount': amount.toJson(),
        if (description != null && description!.trim().isNotEmpty)
          'description': description!.trim(),
      };
}

/// An account number shown with only its last 4 digits, as the backend's
/// member SMS does: "•••• 4567".
String maskedAccount(String accountNumber) {
  final n = accountNumber.trim();
  if (n.length <= 4) return n;
  return '•••• ${n.substring(n.length - 4)}';
}
