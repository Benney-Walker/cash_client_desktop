import 'package:flutter/foundation.dart';

import '../common/money.dart';
import '../dashboard/dashboard_models.dart' show transactionTypeLabel, TypeTotal;

export '../dashboard/dashboard_models.dart' show transactionTypeLabel, TypeTotal;

/// One row of the transactions report: a day, a branch, a type
/// (`TransactionReport.Row`).
@immutable
class TransactionRow {
  const TransactionRow({
    required this.date,
    required this.type,
    required this.count,
    required this.amount,
    required this.fees,
    this.branchName,
  });

  final DateTime date;
  final String? branchName;
  final String type;
  final int count;
  final Money amount;
  final Money fees;

  String get typeLabel => transactionTypeLabel(type);

  static TransactionRow? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final date = DateTime.tryParse(_text(json['date']) ?? '');
    final type = _text(json['type']);
    final amount = Money.fromJson(json['amount']);
    if (date == null || type == null || amount == null) return null;
    return TransactionRow(
      date: date,
      branchName: _text(json['branchName']),
      type: type,
      count: _int(json['count']),
      amount: amount,
      fees: Money.fromJson(json['fees']) ?? Money.zero,
    );
  }
}

/// The transactions report (`TransactionReport`).
@immutable
class TransactionReportData {
  const TransactionReportData({
    required this.rows,
    required this.totals,
    required this.count,
    required this.amount,
    required this.fees,
  });

  final List<TransactionRow> rows;
  final List<TypeTotal> totals;
  final int count;
  final Money amount;
  final Money fees;

  static TransactionReportData? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final rows = json['rows'];
    final totals = json['totals'];
    if (rows is! List || totals is! List) return null;
    return TransactionReportData(
      rows: rows.map(TransactionRow.fromJson).whereType<TransactionRow>().toList(),
      totals: totals.map(TypeTotal.fromJson).whereType<TypeTotal>().toList(),
      count: _int(json['count']),
      amount: Money.fromJson(json['amount']) ?? Money.zero,
      fees: Money.fromJson(json['fees']) ?? Money.zero,
    );
  }
}

/// A collector's day in the collections report
/// (`CollectorCollectionsReport.Day`).
@immutable
class CollectorDayRow {
  const CollectorDayRow({
    required this.date,
    required this.collectorName,
    required this.payments,
    required this.amount,
    required this.failedPayments,
    this.branchName,
  });

  final DateTime date;
  final String collectorName;
  final String? branchName;
  final int payments;
  final Money amount;
  final int failedPayments;

  static CollectorDayRow? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final date = DateTime.tryParse(_text(json['date']) ?? '');
    final amount = Money.fromJson(json['amount']);
    if (date == null || amount == null) return null;
    return CollectorDayRow(
      date: date,
      collectorName: _text(json['collectorName']) ?? _text(json['collectorStaffId']) ?? '—',
      branchName: _text(json['branchName']),
      payments: _int(json['payments']),
      amount: amount,
      failedPayments: _int(json['failedPayments']),
    );
  }
}

/// A handed-in day in the collections report
/// (`CollectorCollectionsReport.Submission`).
@immutable
class HandoverRow {
  const HandoverRow({
    required this.collectorName,
    required this.expected,
    required this.status,
    this.submittedAt,
    this.counted,
    this.surplus,
    this.approvedBy,
  });

  final DateTime? submittedAt;
  final String collectorName;
  final Money expected;
  final Money? counted;
  final Money? surplus;

  /// `SUBMITTED` or `APPROVED`.
  final String status;
  final String? approvedBy;

  bool get approved => status == 'APPROVED';

  static HandoverRow? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final expected = Money.fromJson(json['expected']);
    if (expected == null) return null;
    return HandoverRow(
      submittedAt: DateTime.tryParse(_text(json['submittedAt']) ?? ''),
      collectorName: _text(json['collectorName']) ?? _text(json['collectorStaffId']) ?? '—',
      expected: expected,
      counted: Money.fromJson(json['counted']),
      surplus: Money.fromJson(json['surplus']),
      status: _text(json['status']) ?? 'SUBMITTED',
      approvedBy: _text(json['approvedBy']),
    );
  }
}

/// The collector collections report (`CollectorCollectionsReport`).
@immutable
class CollectionsReportData {
  const CollectionsReportData({
    required this.days,
    required this.handovers,
    required this.collected,
    required this.expected,
    required this.counted,
    required this.surplus,
  });

  final List<CollectorDayRow> days;
  final List<HandoverRow> handovers;
  final Money collected;
  final Money expected;
  final Money counted;
  final Money surplus;

  static CollectionsReportData? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final days = json['days'];
    final submissions = json['submissions'];
    if (days is! List || submissions is! List) return null;
    return CollectionsReportData(
      days: days.map(CollectorDayRow.fromJson).whereType<CollectorDayRow>().toList(),
      handovers: submissions.map(HandoverRow.fromJson).whereType<HandoverRow>().toList(),
      collected: Money.fromJson(json['collected']) ?? Money.zero,
      expected: Money.fromJson(json['expected']) ?? Money.zero,
      counted: Money.fromJson(json['counted']) ?? Money.zero,
      surplus: Money.fromJson(json['surplus']) ?? Money.zero,
    );
  }
}

/// One loan in the portfolio report (`LoanPortfolioReport.Loan`).
@immutable
class PortfolioRow {
  const PortfolioRow({
    required this.memberName,
    required this.productName,
    required this.amount,
    required this.totalToRepay,
    required this.paid,
    required this.outstanding,
    required this.overdue,
    this.branchName,
    this.disbursementDate,
    this.nextDueDate,
  });

  final String memberName;
  final String? branchName;
  final String productName;
  final DateTime? disbursementDate;
  final Money amount;
  final Money totalToRepay;
  final Money paid;
  final Money outstanding;
  final Money overdue;
  final DateTime? nextDueDate;

  static PortfolioRow? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final amount = Money.fromJson(json['amount']);
    if (amount == null) return null;
    return PortfolioRow(
      memberName: _text(json['memberName']) ?? '—',
      branchName: _text(json['branchName']),
      productName: _text(json['productName']) ?? '—',
      disbursementDate: DateTime.tryParse(_text(json['disbursementDate']) ?? ''),
      amount: amount,
      totalToRepay: Money.fromJson(json['totalToRepay']) ?? Money.zero,
      paid: Money.fromJson(json['paid']) ?? Money.zero,
      outstanding: Money.fromJson(json['outstanding']) ?? Money.zero,
      overdue: Money.fromJson(json['overdue']) ?? Money.zero,
      nextDueDate: DateTime.tryParse(_text(json['nextDueDate']) ?? ''),
    );
  }
}

/// The loan portfolio report (`LoanPortfolioReport`).
@immutable
class PortfolioReportData {
  const PortfolioReportData({
    required this.loans,
    required this.activeLoans,
    required this.overdueLoans,
    required this.amountLent,
    required this.outstanding,
    required this.overdue,
    this.asOf,
  });

  final DateTime? asOf;
  final List<PortfolioRow> loans;
  final int activeLoans;
  final int overdueLoans;
  final Money amountLent;
  final Money outstanding;
  final Money overdue;

  static PortfolioReportData? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final loans = json['loans'];
    if (loans is! List) return null;
    return PortfolioReportData(
      asOf: DateTime.tryParse(_text(json['asOf']) ?? ''),
      loans: loans.map(PortfolioRow.fromJson).whereType<PortfolioRow>().toList(),
      activeLoans: _int(json['activeLoans']),
      overdueLoans: _int(json['overdueLoans']),
      amountLent: Money.fromJson(json['amountLent']) ?? Money.zero,
      outstanding: Money.fromJson(json['outstanding']) ?? Money.zero,
      overdue: Money.fromJson(json['overdue']) ?? Money.zero,
    );
  }
}

/// The audit log's actions (`AuditAction`) with plain names, for the
/// filter and the list. An action the app doesn't know yet is shown as the
/// backend names it.
const auditActionLabels = <String, String>{
  'LOGIN_SUCCEEDED': 'Signed in',
  'LOGIN_FAILED': 'Sign-in failed',
  'STAFF_LOCKED': 'Account locked',
  'STAFF_UNLOCKED': 'Account unlocked',
  'PERMISSION_DENIED': 'Request refused',
  'STAFF_CREATED': 'Staff added',
  'STAFF_PROFILE_UPDATED': 'Staff details changed',
  'STAFF_ROLES_CHANGED': 'Staff roles changed',
  'STAFF_DEACTIVATED': 'Staff deactivated',
  'STAFF_REACTIVATED': 'Staff reactivated',
  'STAFF_PASSWORD_RESET': 'Password reset',
  'MEMBER_REGISTERED': 'Member registered',
  'MEMBER_CONTACT_UPDATED': 'Member contact details changed',
  'MEMBER_UPDATE_REQUESTED': 'Member change requested',
  'MEMBER_UPDATE_APPROVED': 'Member change approved',
  'MEMBER_UPDATE_REJECTED': 'Member change rejected',
  'KYC_SUBMITTED': 'ID document uploaded',
  'KYC_RESUBMITTED': 'ID document uploaded again',
  'KYC_AUTO_VERIFIED': 'ID verified automatically',
  'KYC_SENT_TO_MANUAL_REVIEW': 'ID sent for review',
  'KYC_APPROVED': 'ID approved',
  'KYC_REJECTED': 'ID rejected',
  'KYC_DOCUMENT_VIEWED': 'ID picture viewed',
  'FINANCIAL_SETTINGS_UPDATED': 'Financial settings changed',
  'COLLECTOR_DEVICE_REGISTERED': 'Collector phone registered',
  'COLLECTOR_DEVICE_RELEASED': 'Collector phone released',
  'ACCOUNT_STATEMENT_GENERATED': 'Statement made',
  'LOAN_PRODUCT_CREATED': 'Loan product added',
  'LOAN_PRODUCT_UPDATED': 'Loan product changed',
  'LOAN_APPLICATION_SUBMITTED': 'Loan applied for',
  'LOAN_APPROVED': 'Loan approved and paid out',
  'LOAN_REJECTED': 'Loan rejected',
};

/// What an audit entry is about (`AuditTargetType`).
const auditTargetLabels = <String, String>{
  'STAFF': 'Staff',
  'MEMBER': 'Member',
  'SETTINGS': 'Settings',
  'ACCOUNT': 'Account',
  'LOAN_PRODUCT': 'Loan product',
  'LOAN_APPLICATION': 'Loan application',
  'REQUEST': 'Request',
};

/// One audit log entry (`AuditLogEntryResponse`).
@immutable
class AuditEntry {
  const AuditEntry({
    required this.id,
    required this.occurredAt,
    required this.action,
    this.actorStaffId,
    this.targetType,
    this.targetId,
    this.details,
  });

  final int id;

  /// In UTC, as the backend sends it (an instant); shown in local time.
  final DateTime occurredAt;
  final String action;

  /// Null for the system's own actions and unverified sign-in attempts.
  final String? actorStaffId;
  final String? targetType;
  final String? targetId;
  final String? details;

  String get actionLabel => auditActionLabels[action] ?? action;

  String? get targetLabel {
    final type = targetType;
    if (type == null) return null;
    final name = auditTargetLabels[type] ?? type;
    return targetId == null ? name : '$name $targetId';
  }

  static AuditEntry? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final id = json['id'];
    final at = DateTime.tryParse(_text(json['occurredAt']) ?? '');
    final action = _text(json['action']);
    if (id is! num || at == null || action == null) return null;
    return AuditEntry(
      id: id.toInt(),
      occurredAt: at,
      action: action,
      actorStaffId: _text(json['actorStaffId']),
      targetType: _text(json['targetType']),
      targetId: _text(json['targetId']),
      details: _text(json['details']),
    );
  }
}

/// What the audit log is narrowed to. Every filter is optional.
@immutable
class AuditFilter {
  const AuditFilter({
    this.from,
    this.to,
    this.actorStaffId,
    this.action,
    this.targetType,
    this.targetId,
  });

  /// First and last day, both included.
  final DateTime? from;
  final DateTime? to;
  final String? actorStaffId;
  final String? action;
  final String? targetType;
  final String? targetId;

  /// The backend's query: instants, with `to` exclusive, so the last day
  /// counts in full. Days are Accra days, which are UTC days (GMT, no
  /// daylight saving).
  Map<String, String> toQuery() => {
        if (from != null)
          'from': '${_day(from!)}T00:00:00Z',
        if (to != null)
          'to': '${_day(to!.add(const Duration(days: 1)))}T00:00:00Z',
        if (actorStaffId != null && actorStaffId!.isNotEmpty)
          'actorStaffId': actorStaffId!,
        if (action != null) 'action': action!,
        if (targetType != null) 'targetType': targetType!,
        if (targetId != null && targetId!.isNotEmpty) 'targetId': targetId!,
      };

  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// One general ledger account in the trial balance
/// (`TrialBalanceResponse.Line`).
@immutable
class TrialBalanceLine {
  const TrialBalanceLine({
    required this.accountCode,
    required this.name,
    required this.totalDebits,
    required this.totalCredits,
    required this.balance,
    this.category,
  });

  final String accountCode;
  final String name;
  final String? category;
  final Money totalDebits;
  final Money totalCredits;

  /// On the account's normal side, so positive is the usual case.
  final Money balance;

  static TrialBalanceLine? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final code = _text(json['accountCode']);
    final name = _text(json['name']);
    if (code == null || name == null) return null;
    return TrialBalanceLine(
      accountCode: code,
      name: name,
      category: _text(json['category']),
      totalDebits: Money.fromJson(json['totalDebits']) ?? Money.zero,
      totalCredits: Money.fromJson(json['totalCredits']) ?? Money.zero,
      balance: Money.fromJson(json['balance']) ?? Money.zero,
    );
  }
}

/// The trial balance (`TrialBalanceResponse`).
@immutable
class TrialBalance {
  const TrialBalance({
    required this.lines,
    required this.totalDebits,
    required this.totalCredits,
    required this.balanced,
  });

  final List<TrialBalanceLine> lines;
  final Money totalDebits;
  final Money totalCredits;

  /// False only if the ledger is broken.
  final bool balanced;

  static TrialBalance? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final accounts = json['accounts'];
    if (accounts is! List) return null;
    return TrialBalance(
      lines: accounts.map(TrialBalanceLine.fromJson).whereType<TrialBalanceLine>().toList(),
      totalDebits: Money.fromJson(json['totalDebits']) ?? Money.zero,
      totalCredits: Money.fromJson(json['totalCredits']) ?? Money.zero,
      balanced: json['balanced'] == true,
    );
  }
}

int _int(Object? value) => value is num ? value.toInt() : 0;

String? _text(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;
