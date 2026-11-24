import 'package:flutter/foundation.dart';

import '../common/money.dart';

/// Which days the dashboard's money figures add up (owner decision 24
/// November 2026: today, with a switch to this week or this month).
enum DashboardPeriod {
  today('Today', 'today'),
  week('This week', 'this week'),
  month('This month', 'this month');

  const DashboardPeriod(this.label, this.inSentence);

  final String label;

  /// For sentences: "GH₵ 100.00 deposited today".
  final String inSentence;

  /// The first and last day counted, both included. A week starts on
  /// Monday; a month on its first day. Both end today.
  (DateTime, DateTime) range(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    return switch (this) {
      DashboardPeriod.today => (today, today),
      DashboardPeriod.week => (
          today.subtract(Duration(days: today.weekday - DateTime.monday)),
          today,
        ),
      DashboardPeriod.month => (DateTime(today.year, today.month), today),
    };
  }
}

/// A plain name for a backend transaction type (`TransactionType`).
String transactionTypeLabel(String type) => switch (type) {
      'DEPOSIT' => 'Deposits',
      'WITHDRAWAL' => 'Withdrawals',
      'TRANSFER' => 'Transfers',
      'SHARES' => 'Share purchases',
      'FEE' => 'Fees',
      'LOAN_PAYMENT' => 'Loan repayments',
      'LOAN_DISBURSEMENT' => 'Loans paid out',
      'COLLECTOR_HANDOVER' => 'Collector cash handed in',
      'COLLECTOR_SHORTAGE_REPAYMENT' => 'Shortage repayments',
      _ => type,
    };

/// One transaction type's total for the period.
@immutable
class TypeTotal {
  const TypeTotal({
    required this.type,
    required this.count,
    required this.amount,
    required this.fees,
  });

  final String type;
  final int count;
  final Money amount;
  final Money fees;

  String get label => transactionTypeLabel(type);

  static TypeTotal? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final type = json['type'];
    final count = json['count'];
    final amount = Money.fromJson(json['amount']);
    if (type is! String || count is! num || amount == null) return null;
    return TypeTotal(
      type: type,
      count: count.toInt(),
      amount: amount,
      fees: Money.fromJson(json['fees']) ?? Money.zero,
    );
  }
}

/// The transactions report for the period (`TransactionReport`): only its
/// totals; the dashboard doesn't need the daily rows.
@immutable
class TransactionSummary {
  const TransactionSummary({
    required this.byType,
    required this.count,
    required this.amount,
    required this.fees,
  });

  final List<TypeTotal> byType;
  final int count;
  final Money amount;
  final Money fees;

  Money _total(String type) =>
      byType.where((t) => t.type == type).firstOrNull?.amount ?? Money.zero;

  Money get deposits => _total('DEPOSIT');
  Money get withdrawals => _total('WITHDRAWAL');

  static TransactionSummary? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final totals = json['totals'];
    final count = json['count'];
    if (totals is! List || count is! num) return null;
    return TransactionSummary(
      byType: totals.map(TypeTotal.fromJson).whereType<TypeTotal>().toList()
        ..sort((a, b) => b.amount.compareTo(a.amount)),
      count: count.toInt(),
      amount: Money.fromJson(json['amount']) ?? Money.zero,
      fees: Money.fromJson(json['fees']) ?? Money.zero,
    );
  }
}

/// The collector collections report's totals (`CollectorCollectionsReport`).
@immutable
class CollectionsSummary {
  const CollectionsSummary({
    required this.collected,
    required this.expected,
    required this.counted,
    required this.surplus,
  });

  /// What collectors recorded in the field.
  final Money collected;

  /// What their handed-in days expected, and what the office counted.
  final Money expected;
  final Money counted;
  final Money surplus;

  static CollectionsSummary? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final collected = Money.fromJson(json['collected']);
    if (collected == null) return null;
    return CollectionsSummary(
      collected: collected,
      expected: Money.fromJson(json['expected']) ?? Money.zero,
      counted: Money.fromJson(json['counted']) ?? Money.zero,
      surplus: Money.fromJson(json['surplus']) ?? Money.zero,
    );
  }
}

/// The loan portfolio's totals now (`LoanPortfolioReport`). Not tied to
/// the period: it's what's lent and owed today.
@immutable
class LoanPortfolioSummary {
  const LoanPortfolioSummary({
    required this.activeLoans,
    required this.overdueLoans,
    required this.amountLent,
    required this.outstanding,
    required this.overdue,
  });

  final int activeLoans;
  final int overdueLoans;
  final Money amountLent;
  final Money outstanding;
  final Money overdue;

  static LoanPortfolioSummary? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final active = json['activeLoans'];
    final overdueLoans = json['overdueLoans'];
    if (active is! num || overdueLoans is! num) return null;
    return LoanPortfolioSummary(
      activeLoans: active.toInt(),
      overdueLoans: overdueLoans.toInt(),
      amountLent: Money.fromJson(json['amountLent']) ?? Money.zero,
      outstanding: Money.fromJson(json['outstanding']) ?? Money.zero,
      overdue: Money.fromJson(json['overdue']) ?? Money.zero,
    );
  }
}
