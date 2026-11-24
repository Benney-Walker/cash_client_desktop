import 'package:flutter/foundation.dart';

/// An amount in Ghana cedis, held as whole pesewas so sums and display
/// never pick up floating-point noise. The backend sends and takes amounts
/// as JSON numbers with at most 2 decimal places (`MoneyRules`).
@immutable
class Money implements Comparable<Money> {
  const Money.pesewas(this.pesewas);

  static const zero = Money.pesewas(0);

  final int pesewas;

  /// Reads a JSON number (or a numeric string), rounded to the pesewa.
  static Money? fromJson(Object? value) {
    final number = switch (value) {
      num n => n,
      String s => num.tryParse(s.trim()),
      _ => null,
    };
    if (number == null || !number.isFinite) return null;
    return Money.pesewas((number * 100).round());
  }

  /// Reads what a staff member typed: digits with an optional point and at
  /// most 2 decimals, commas allowed ("1,250.5"). Null when it isn't an
  /// amount.
  static Money? parse(String text) {
    final cleaned = text.trim().replaceAll(',', '');
    final match = RegExp(r'^(\d+)(?:\.(\d{0,2}))?$').firstMatch(cleaned);
    if (match == null) return null;
    final cedis = int.parse(match.group(1)!);
    final decimals = (match.group(2) ?? '').padRight(2, '0');
    return Money.pesewas(cedis * 100 + int.parse(decimals));
  }

  bool get isPositive => pesewas > 0;

  Money operator +(Money other) => Money.pesewas(pesewas + other.pesewas);
  Money operator -(Money other) => Money.pesewas(pesewas - other.pesewas);
  bool operator <(Money other) => pesewas < other.pesewas;
  bool operator <=(Money other) => pesewas <= other.pesewas;
  bool operator >(Money other) => pesewas > other.pesewas;
  bool operator >=(Money other) => pesewas >= other.pesewas;

  /// The value to send: a JSON number such as 1250.5. A double prints its
  /// shortest exact form, which the backend reads as an exact decimal.
  double toJson() => pesewas / 100;

  /// "1,250.00" (no currency).
  String get plain {
    final negative = pesewas < 0;
    final abs = pesewas.abs();
    final cedis = (abs ~/ 100).toString();
    final grouped = cedis.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    final decimals = (abs % 100).toString().padLeft(2, '0');
    return '${negative ? '−' : ''}$grouped.$decimals';
  }

  /// "GH₵ 1,250.00".
  @override
  String toString() => 'GH₵ $plain';

  @override
  int compareTo(Money other) => pesewas.compareTo(other.pesewas);

  @override
  bool operator ==(Object other) =>
      other is Money && other.pesewas == pesewas;

  @override
  int get hashCode => pesewas.hashCode;
}
