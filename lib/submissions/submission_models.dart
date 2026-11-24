import 'package:flutter/foundation.dart';

import '../common/money.dart';

export '../common/money.dart';

/// A collector's daily submission status (`CollectorSubmissionStatus`).
enum SubmissionStatus {
  submitted('SUBMITTED', 'Waiting'),
  approved('APPROVED', 'Approved');

  const SubmissionStatus(this.backendName, this.label);

  final String backendName;
  final String label;

  static SubmissionStatus? parse(Object? value) {
    for (final s in values) {
      if (s.backendName == value) return s;
    }
    return null;
  }
}

String? _text(Object? value) =>
    value is String && value.trim().isNotEmpty ? value : null;

DateTime? _time(Object? value) => DateTime.tryParse(_text(value) ?? '');

/// One payment a collector recorded during the day
/// (`CollectorPaymentResponse`).
@immutable
class SubmissionPayment {
  const SubmissionPayment({
    required this.transactionId,
    required this.amount,
    required this.accountNumber,
    required this.memberName,
    this.type,
    this.completed = true,
    this.failureReason,
    this.createdAt,
  });

  final String transactionId;
  final Money amount;
  final String accountNumber;
  final String memberName;

  /// `SAVINGS` or `SHARES`.
  final String? type;

  /// False for a payment the backend couldn't apply (`FAILED`); its cash
  /// isn't part of the expected amount.
  final bool completed;
  final String? failureReason;

  /// When the collector recorded it, on the phone.
  final DateTime? createdAt;

  String get typeLabel => switch (type) {
        'SHARES' => 'Shares',
        'SAVINGS' => 'Savings',
        _ => type ?? '',
      };

  static SubmissionPayment? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final id = _text(json['transactionId']);
    final amount = Money.fromJson(json['amount']);
    if (id == null || amount == null) return null;
    return SubmissionPayment(
      transactionId: id,
      amount: amount,
      accountNumber: _text(json['accountNumber']) ?? '',
      memberName: _text(json['memberName']) ?? '',
      type: _text(json['type']),
      completed: json['status'] != 'FAILED',
      failureReason: _text(json['failureReason']),
      createdAt: _time(json['createdAt']),
    );
  }
}

/// A collector's day, as handed in (`CollectorSubmissionResponse`). The
/// list leaves [payments] empty; the details carry them.
@immutable
class CollectorSubmission {
  const CollectorSubmission({
    required this.submissionId,
    required this.collectorStaffId,
    required this.collectorName,
    required this.status,
    required this.expectedAmount,
    required this.paymentCount,
    this.branchName,
    this.submittedAt,
    this.failedCount = 0,
    this.failedAmount = Money.zero,
    this.countedAmount,
    this.overageAmount,
    this.approvedByStaffId,
    this.approvedAt,
    this.payments = const [],
  });

  final String submissionId;
  final String collectorStaffId;
  final String collectorName;
  final String? branchName;
  final SubmissionStatus status;
  final DateTime? submittedAt;
  final int paymentCount;

  /// The cash the collector should hand in: their completed payments.
  final Money expectedAmount;
  final int failedCount;
  final Money failedAmount;

  /// Set once approved.
  final Money? countedAmount;
  final Money? overageAmount;
  final String? approvedByStaffId;
  final DateTime? approvedAt;
  final List<SubmissionPayment> payments;

  bool get waiting => status == SubmissionStatus.submitted;

  static CollectorSubmission? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final id = _text(json['submissionId']);
    final status = SubmissionStatus.parse(json['status']);
    final expected = Money.fromJson(json['expectedAmount']);
    if (id == null || status == null || expected == null) return null;
    final payments = json['payments'];
    final count = json['paymentCount'];
    final failed = json['failedCount'];
    return CollectorSubmission(
      submissionId: id,
      collectorStaffId: _text(json['collectorStaffId']) ?? '',
      collectorName: _text(json['collectorName']) ?? 'Collector',
      branchName: _text(json['branchName']),
      status: status,
      submittedAt: _time(json['submittedAt']),
      paymentCount: count is int ? count : 0,
      expectedAmount: expected,
      failedCount: failed is int ? failed : 0,
      failedAmount: Money.fromJson(json['failedAmount']) ?? Money.zero,
      countedAmount: Money.fromJson(json['countedAmount']),
      overageAmount: Money.fromJson(json['overageAmount']),
      approvedByStaffId: _text(json['approvedByStaffId']),
      approvedAt: _time(json['approvedAt']),
      payments: payments is List
          ? payments
              .map(SubmissionPayment.fromJson)
              .whereType<SubmissionPayment>()
              .toList()
          : const [],
    );
  }
}

/// A note or coin in the cash-count helper (owner decision 24 November
/// 2026: every cedi note, plus the 50 and 20 pesewa coins).
enum Denomination {
  cedis200(20000, 'GH₵ 200'),
  cedis100(10000, 'GH₵ 100'),
  cedis50(5000, 'GH₵ 50'),
  cedis20(2000, 'GH₵ 20'),
  cedis10(1000, 'GH₵ 10'),
  cedis5(500, 'GH₵ 5'),
  cedis2(200, 'GH₵ 2'),
  cedis1(100, 'GH₵ 1'),
  pesewas50(50, '50 p'),
  pesewas20(20, '20 p');

  const Denomination(this.pesewas, this.label);

  final int pesewas;
  final String label;
}

/// How many of each note and coin were counted.
@immutable
class CashCount {
  const CashCount([this.counts = const {}]);

  final Map<Denomination, int> counts;

  int countOf(Denomination d) => counts[d] ?? 0;

  CashCount withCount(Denomination d, int count) =>
      CashCount({...counts, d: count < 0 ? 0 : count});

  Money subtotal(Denomination d) => Money.pesewas(d.pesewas * countOf(d));

  Money get total => Money.pesewas(
        Denomination.values.fold(0, (sum, d) => sum + d.pesewas * countOf(d)),
      );

  bool get isEmpty => counts.values.every((c) => c == 0);
}
