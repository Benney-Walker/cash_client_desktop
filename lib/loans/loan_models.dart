import 'package:flutter/foundation.dart';

import '../common/money.dart';

/// How a product's processing fee is worked out (`LoanFeeType`).
enum LoanFeeType {
  flat('FLAT', 'Fixed amount'),
  percentage('PERCENTAGE', 'Percentage of the loan');

  const LoanFeeType(this.backendName, this.label);

  final String backendName;
  final String label;

  static LoanFeeType? parse(Object? value) {
    for (final t in values) {
      if (t.backendName == value) return t;
    }
    return null;
  }
}

/// A loan product (`LoanProductResponse`). Rates and percentages are kept
/// in hundredths of a percent so the arithmetic is exact: 24.5% is 2450.
@immutable
class LoanProduct {
  const LoanProduct({
    required this.id,
    required this.name,
    required this.ratePercentHundredths,
    required this.minAmount,
    required this.maxAmount,
    required this.maxTermMonths,
    required this.feeType,
    required this.feeValue,
    required this.guarantorsRequired,
    required this.active,
  });

  final int id;
  final String name;

  /// Yearly flat interest rate, in hundredths of a percent.
  final int ratePercentHundredths;
  final Money minAmount;
  final Money maxAmount;
  final int maxTermMonths;
  final LoanFeeType feeType;

  /// For [LoanFeeType.flat] an amount in pesewas; for
  /// [LoanFeeType.percentage] hundredths of a percent.
  final int feeValue;
  final int guarantorsRequired;
  final bool active;

  String get rateLabel => '${_percent(ratePercentHundredths)}% a year';

  String get feeLabel => switch (feeType) {
        LoanFeeType.flat when feeValue == 0 => 'No processing fee',
        LoanFeeType.flat => '${Money.pesewas(feeValue)} processing fee',
        LoanFeeType.percentage => '${_percent(feeValue)}% processing fee',
      };

  /// The processing fee on [amount], as the backend works it out
  /// (`LoanRules.processingFee`: a percentage rounded half up).
  Money feeFor(Money amount) => switch (feeType) {
        LoanFeeType.flat => Money.pesewas(feeValue),
        LoanFeeType.percentage =>
          Money.pesewas(_divideHalfUp(amount.pesewas * feeValue, 10000)),
      };

  static LoanProduct? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final id = json['id'];
    final name = json['name'];
    final rate = _hundredths(json['interestRatePercent']);
    final min = Money.fromJson(json['minAmount']);
    final max = Money.fromJson(json['maxAmount']);
    final term = json['maxTermMonths'];
    final feeType = LoanFeeType.parse(json['processingFeeType']);
    if (id is! int ||
        name is! String ||
        rate == null ||
        min == null ||
        max == null ||
        term is! int ||
        feeType == null) {
      return null;
    }
    final feeValue = feeType == LoanFeeType.flat
        ? Money.fromJson(json['processingFeeValue'])?.pesewas
        : _hundredths(json['processingFeeValue']);
    return LoanProduct(
      id: id,
      name: name,
      ratePercentHundredths: rate,
      minAmount: min,
      maxAmount: max,
      maxTermMonths: term,
      feeType: feeType,
      feeValue: feeValue ?? 0,
      guarantorsRequired: (json['guarantorsRequired'] as num?)?.toInt() ?? 0,
      active: json['active'] == true,
    );
  }
}

/// What a product edit sends (`LoanProductRequest`).
@immutable
class LoanProductDraft {
  const LoanProductDraft({
    required this.name,
    required this.ratePercentHundredths,
    required this.minAmount,
    required this.maxAmount,
    required this.maxTermMonths,
    required this.feeType,
    required this.feeValue,
    required this.guarantorsRequired,
    required this.active,
  });

  final String name;
  final int ratePercentHundredths;
  final Money minAmount;
  final Money maxAmount;
  final int maxTermMonths;
  final LoanFeeType feeType;

  /// Pesewas for a flat fee, hundredths of a percent for a percentage.
  final int feeValue;
  final int guarantorsRequired;
  final bool active;

  Map<String, Object?> toJson() => {
        'name': name,
        'interestRatePercent': ratePercentHundredths / 100,
        'minAmount': minAmount.toJson(),
        'maxAmount': maxAmount.toJson(),
        'maxTermMonths': maxTermMonths,
        'processingFeeType': feeType.backendName,
        'processingFeeValue': feeValue / 100,
        'guarantorsRequired': guarantorsRequired,
        'active': active,
      };
}

/// What a loan costs, worked out the way the backend does (`LoanRules`):
/// flat interest = amount × yearly rate × months ÷ 12, rounded half up to
/// the pesewa; each installment but the last carries the amount and the
/// interest divided by the months, rounded down; the last takes the rest.
@immutable
class LoanQuote {
  const LoanQuote({
    required this.amount,
    required this.months,
    required this.interest,
    required this.fee,
    required this.monthly,
    required this.lastInstallment,
  });

  final Money amount;
  final int months;
  final Money interest;
  final Money fee;

  /// Every installment but the last.
  final Money monthly;
  final Money lastInstallment;

  Money get toRepay => amount + interest;

  /// What reaches the member's account: the loan less the fee.
  Money get paidIn => amount - fee;

  static LoanQuote of(LoanProduct product, Money amount, int months) {
    final interest = Money.pesewas(_divideHalfUp(
      amount.pesewas * product.ratePercentHundredths * months,
      10000 * 12,
    ));
    final principalEach = amount.pesewas ~/ months;
    final interestEach = interest.pesewas ~/ months;
    final lastPrincipal = amount.pesewas - principalEach * (months - 1);
    final lastInterest = interest.pesewas - interestEach * (months - 1);
    return LoanQuote(
      amount: amount,
      months: months,
      interest: interest,
      fee: product.feeFor(amount),
      monthly: Money.pesewas(principalEach + interestEach),
      lastInstallment: Money.pesewas(lastPrincipal + lastInterest),
    );
  }
}

/// Where an application stands (`ApplicationStatus`).
enum LoanApplicationStatus {
  pending('PENDING', 'Waiting'),
  approved('APPROVED', 'Approved'),
  rejected('REJECTED', 'Rejected');

  const LoanApplicationStatus(this.backendName, this.label);

  final String backendName;
  final String label;

  static LoanApplicationStatus? parse(Object? value) {
    for (final s in values) {
      if (s.backendName == value) return s;
    }
    return null;
  }
}

/// A loan application (`LoanApplicationResponse`).
@immutable
class LoanApplicationRecord {
  const LoanApplicationRecord({
    required this.id,
    required this.memberId,
    required this.memberName,
    required this.productId,
    required this.productName,
    required this.requestedAmount,
    required this.termMonths,
    required this.status,
    this.branchName,
    this.approvedAmount,
    this.purpose,
    this.rejectionReason,
    this.appliedBy,
    this.reviewedBy,
    this.createdAt,
    this.reviewedAt,
    this.guarantors = const [],
    this.loanId,
  });

  final String id;
  final String memberId;
  final String memberName;
  final String? branchName;
  final int productId;
  final String productName;
  final Money requestedAmount;
  final int termMonths;
  final Money? approvedAmount;
  final String? purpose;
  final LoanApplicationStatus status;
  final String? rejectionReason;
  final String? appliedBy;
  final String? reviewedBy;
  final DateTime? createdAt;
  final DateTime? reviewedAt;

  /// Names of the guarantors. Only the single-application read includes
  /// them; lists leave them out.
  final List<String> guarantors;
  final String? loanId;

  static LoanApplicationRecord? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final id = _text(json['id']);
    final memberId = _text(json['memberId']);
    final productId = json['productId'];
    final amount = Money.fromJson(json['requestedAmount']);
    final term = json['termMonths'];
    final status = LoanApplicationStatus.parse(json['status']);
    if (id == null ||
        memberId == null ||
        productId is! int ||
        amount == null ||
        term is! int ||
        status == null) {
      return null;
    }
    final guarantors = json['guarantors'];
    return LoanApplicationRecord(
      id: id,
      memberId: memberId,
      memberName: _text(json['memberName']) ?? 'Member',
      branchName: _text(json['branchName']),
      productId: productId,
      productName: _text(json['productName']) ?? 'Loan',
      requestedAmount: amount,
      termMonths: term,
      approvedAmount: Money.fromJson(json['approvedAmount']),
      purpose: _text(json['purpose']),
      status: status,
      rejectionReason: _text(json['rejectionReason']),
      appliedBy: _text(json['appliedBy']),
      reviewedBy: _text(json['reviewedBy']),
      createdAt: DateTime.tryParse(_text(json['createdAt']) ?? ''),
      reviewedAt: DateTime.tryParse(_text(json['reviewedAt']) ?? ''),
      guarantors: [
        if (guarantors is List)
          for (final g in guarantors)
            if (g is Map && _text(g['name']) != null) _text(g['name'])!,
      ],
      loanId: _text(json['loanId']),
    );
  }
}

/// What an application sends (`LoanApplicationRequest`).
@immutable
class NewLoanApplication {
  const NewLoanApplication({
    required this.memberId,
    required this.productId,
    required this.amount,
    required this.termMonths,
    this.guarantorMemberIds = const [],
    this.purpose,
  });

  final String memberId;
  final int productId;
  final Money amount;
  final int termMonths;
  final List<String> guarantorMemberIds;
  final String? purpose;

  Map<String, Object?> toJson() => {
        'memberId': memberId,
        'productId': productId,
        'amount': amount.toJson(),
        'termMonths': termMonths,
        'guarantorMemberIds': guarantorMemberIds,
        if (purpose != null && purpose!.isNotEmpty) 'purpose': purpose,
      };
}

/// An installment's state (`ScheduleStatus`).
enum InstallmentStatus {
  pending('PENDING', 'Due later'),
  paid('PAID', 'Paid'),
  overdue('OVERDUE', 'Overdue');

  const InstallmentStatus(this.backendName, this.label);

  final String backendName;
  final String label;

  static InstallmentStatus? parse(Object? value) {
    for (final s in values) {
      if (s.backendName == value) return s;
    }
    return null;
  }
}

@immutable
class Installment {
  const Installment({
    required this.number,
    required this.dueDate,
    required this.amount,
    required this.paid,
    required this.remaining,
    required this.status,
  });

  final int number;
  final DateTime dueDate;
  final Money amount;
  final Money paid;
  final Money remaining;
  final InstallmentStatus status;

  static Installment? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final number = json['number'];
    final due = DateTime.tryParse(_text(json['dueDate']) ?? '');
    final amount = Money.fromJson(json['amount']);
    final status = InstallmentStatus.parse(json['status']);
    if (number is! int || due == null || amount == null || status == null) {
      return null;
    }
    return Installment(
      number: number,
      dueDate: due,
      amount: amount,
      paid: Money.fromJson(json['paid']) ?? Money.zero,
      remaining: Money.fromJson(json['remaining']) ?? Money.zero,
      status: status,
    );
  }
}

/// A loan that was paid out (`LoanResponse`), with its installments when
/// read on its own.
@immutable
class LoanDetails {
  const LoanDetails({
    required this.id,
    required this.memberId,
    required this.memberName,
    required this.productName,
    required this.amount,
    required this.totalToRepay,
    required this.termMonths,
    required this.closed,
    required this.paid,
    required this.outstanding,
    required this.overdue,
    this.accountNumber,
    this.ratePercent,
    this.totalInterest,
    this.processingFee,
    this.disbursementDate,
    this.maturityDate,
    this.installments = const [],
  });

  final String id;
  final String memberId;
  final String memberName;
  final String productName;
  final String? accountNumber;
  final Money amount;
  final String? ratePercent;
  final Money? totalInterest;
  final Money totalToRepay;
  final Money? processingFee;
  final int termMonths;
  final DateTime? disbursementDate;
  final DateTime? maturityDate;

  /// `CLOSED_PAID`: every installment is paid.
  final bool closed;
  final Money paid;
  final Money outstanding;
  final Money overdue;
  final List<Installment> installments;

  Installment? get nextDue => installments
      .where((i) => i.status != InstallmentStatus.paid)
      .firstOrNull;

  static LoanDetails? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final id = _text(json['id']);
    final memberId = _text(json['memberId']);
    final amount = Money.fromJson(json['amount']);
    final total = Money.fromJson(json['totalToRepay']);
    final term = json['termMonths'];
    if (id == null || memberId == null || amount == null || total == null) {
      return null;
    }
    final installments = json['installments'];
    final rate = json['interestRatePercent'];
    return LoanDetails(
      id: id,
      memberId: memberId,
      memberName: _text(json['memberName']) ?? 'Member',
      productName: _text(json['productName']) ?? 'Loan',
      accountNumber: _text(json['accountNumber']),
      amount: amount,
      ratePercent: rate is num ? _percent((rate * 100).round()) : null,
      totalInterest: Money.fromJson(json['totalInterest']),
      totalToRepay: total,
      processingFee: Money.fromJson(json['processingFee']),
      termMonths: term is int ? term : 0,
      disbursementDate:
          DateTime.tryParse(_text(json['disbursementDate']) ?? ''),
      maturityDate: DateTime.tryParse(_text(json['maturityDate']) ?? ''),
      closed: json['status'] == 'CLOSED_PAID',
      paid: Money.fromJson(json['paid']) ?? Money.zero,
      outstanding: Money.fromJson(json['outstanding']) ?? Money.zero,
      overdue: Money.fromJson(json['overdue']) ?? Money.zero,
      installments: [
        if (installments is List)
          ...installments.map(Installment.fromJson).whereType<Installment>(),
      ],
    );
  }
}

/// One active loan in the portfolio report (`LoanPortfolioReport.Loan`).
@immutable
class PortfolioLoan {
  const PortfolioLoan({
    required this.loanId,
    required this.memberName,
    required this.productName,
    required this.amount,
    required this.outstanding,
    required this.overdue,
    this.branchName,
    this.disbursementDate,
    this.nextDueDate,
  });

  final String loanId;
  final String memberName;
  final String? branchName;
  final String productName;
  final Money amount;
  final Money outstanding;
  final Money overdue;
  final DateTime? disbursementDate;
  final DateTime? nextDueDate;

  bool get isOverdue => overdue.isPositive;

  static PortfolioLoan? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final id = _text(json['loanId']);
    final amount = Money.fromJson(json['amount']);
    if (id == null || amount == null) return null;
    return PortfolioLoan(
      loanId: id,
      memberName: _text(json['memberName']) ?? 'Member',
      branchName: _text(json['branchName']),
      productName: _text(json['productName']) ?? 'Loan',
      amount: amount,
      outstanding: Money.fromJson(json['outstanding']) ?? Money.zero,
      overdue: Money.fromJson(json['overdue']) ?? Money.zero,
      disbursementDate:
          DateTime.tryParse(_text(json['disbursementDate']) ?? ''),
      nextDueDate: DateTime.tryParse(_text(json['nextDueDate']) ?? ''),
    );
  }
}

/// [value] ÷ [by], rounded half up (both positive).
int _divideHalfUp(int value, int by) => (value * 2 + by) ~/ (by * 2);

/// A percentage from the backend (24.50) in hundredths (2450).
int? _hundredths(Object? value) => switch (value) {
      num n => (n * 100).round(),
      String s => num.tryParse(s) == null ? null : (num.parse(s) * 100).round(),
      _ => null,
    };

/// 2450 → "24.5", 2400 → "24".
String _percent(int hundredths) {
  final whole = hundredths ~/ 100;
  final rest = hundredths % 100;
  if (rest == 0) return '$whole';
  final decimals = rest.toString().padLeft(2, '0').replaceAll(RegExp(r'0$'), '');
  return '$whole.$decimals';
}

String? _text(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;
