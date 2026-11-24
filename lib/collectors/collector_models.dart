import 'package:flutter/foundation.dart';

import '../common/money.dart';

/// The payment a location point was taken for
/// (`LocationPointResponse.Payment`).
@immutable
class PointPayment {
  const PointPayment({
    required this.type,
    required this.amount,
    this.transactionId,
    this.status,
    this.memberName,
    this.accountNumber,
  });

  final String? transactionId;

  /// `DEPOSIT`, `SHARES`, …
  final String type;
  final Money amount;

  /// `COMPLETED`, `FAILED`, …
  final String? status;
  final String? memberName;
  final String? accountNumber;

  bool get failed => status == 'FAILED';

  String get typeLabel => switch (type) {
        'DEPOSIT' => 'Deposit',
        'SHARES' => 'Shares',
        'WITHDRAWAL' => 'Withdrawal',
        _ => type,
      };

  static PointPayment? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final type = json['type'];
    final amount = Money.fromJson(json['amount']);
    if (type is! String || amount == null) return null;
    return PointPayment(
      transactionId: _text(json['transactionId']),
      type: type,
      amount: amount,
      status: _text(json['status']),
      memberName: _text(json['memberName']),
      accountNumber: _text(json['accountNumber']),
    );
  }
}

/// One point on a collector's day (`LocationPointResponse`). Times are the
/// backend's local times (Africa/Accra), shown as they are.
@immutable
class LocationPoint {
  const LocationPoint({
    required this.latitude,
    required this.longitude,
    required this.recordedAt,
    this.accuracyMeters,
    this.batteryPercent,
    this.atPayment = false,
    this.receivedAt,
    this.payment,
  });

  final double latitude;
  final double longitude;
  final DateTime recordedAt;
  final double? accuracyMeters;
  final int? batteryPercent;

  /// Taken when a payment was recorded (`trigger` PAYMENT) rather than the
  /// regular 5-minute point.
  final bool atPayment;
  final DateTime? receivedAt;

  /// The payment, once it has reached the backend. A payment recorded
  /// offline can arrive after its point, so a payment point may have none.
  final PointPayment? payment;

  /// Sent well after it was taken: the phone was offline.
  bool get sentLater {
    final received = receivedAt;
    return received != null &&
        received.difference(recordedAt) > const Duration(minutes: 10);
  }

  static LocationPoint? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final lat = _number(json['latitude']);
    final lng = _number(json['longitude']);
    final recorded = DateTime.tryParse(_text(json['recordedAt']) ?? '');
    if (lat == null || lng == null || recorded == null) return null;
    return LocationPoint(
      latitude: lat,
      longitude: lng,
      recordedAt: recorded,
      accuracyMeters: _number(json['accuracyMeters']),
      batteryPercent: _number(json['batteryPercent'])?.round(),
      atPayment: json['trigger'] == 'PAYMENT',
      receivedAt: DateTime.tryParse(_text(json['receivedAt']) ?? ''),
      payment: PointPayment.fromJson(json['payment']),
    );
  }
}

/// A collector's totals for one day, from the collector collections report
/// (`CollectorCollectionsReport.Day`).
@immutable
class CollectorDayTotal {
  const CollectorDayTotal({
    required this.collectorStaffId,
    required this.payments,
    required this.amount,
    this.failedPayments = 0,
  });

  final String collectorStaffId;
  final int payments;
  final Money amount;
  final int failedPayments;

  static CollectorDayTotal? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final id = _text(json['collectorStaffId']);
    final payments = _number(json['payments']);
    final amount = Money.fromJson(json['amount']);
    if (id == null || payments == null || amount == null) return null;
    return CollectorDayTotal(
      collectorStaffId: id,
      payments: payments.round(),
      amount: amount,
      failedPayments: _number(json['failedPayments'])?.round() ?? 0,
    );
  }
}

String? _text(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;

double? _number(Object? value) => switch (value) {
      num n => n.toDouble(),
      String s => double.tryParse(s),
      _ => null,
    };
