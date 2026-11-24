import 'package:cash_client_desktop/common/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads JSON numbers and strings to the pesewa', () {
    expect(Money.fromJson(1250), const Money.pesewas(125000));
    expect(Money.fromJson(12.5), const Money.pesewas(1250));
    expect(Money.fromJson(0.1 + 0.2), const Money.pesewas(30));
    expect(Money.fromJson('20.00'), const Money.pesewas(2000));
    expect(Money.fromJson(null), isNull);
    expect(Money.fromJson('abc'), isNull);
  });

  test('parses what staff type, with at most 2 decimals', () {
    expect(Money.parse('250'), const Money.pesewas(25000));
    expect(Money.parse('250.5'), const Money.pesewas(25050));
    expect(Money.parse(' 1,250.05 '), const Money.pesewas(125005));
    expect(Money.parse('250.'), const Money.pesewas(25000));
    expect(Money.parse('250.505'), isNull);
    expect(Money.parse('-5'), isNull);
    expect(Money.parse(''), isNull);
  });

  test('formats in GH₵ with grouping and 2 decimals', () {
    expect(const Money.pesewas(125000).toString(), 'GH₵ 1,250.00');
    expect(const Money.pesewas(5).plain, '0.05');
    expect(const Money.pesewas(123456789).plain, '1,234,567.89');
    expect(const Money.pesewas(-2050).plain, '−20.50');
  });

  test('sends an exact JSON number', () {
    expect(const Money.pesewas(25050).toJson(), 250.5);
    expect(const Money.pesewas(1234).toJson().toString(), '12.34');
  });

  test('adds and compares', () {
    expect(const Money.pesewas(100) + const Money.pesewas(250),
        const Money.pesewas(350));
    expect(const Money.pesewas(100).compareTo(const Money.pesewas(50)), 1);
    expect(Money.zero.isPositive, isFalse);
  });
}
