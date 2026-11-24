import 'package:cash_client_desktop/api/api_exception.dart';
import 'package:cash_client_desktop/auth/password_reset_link.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  test('points at the backend\'s reset page with the staff ID filled in', () {
    final uri = passwordResetUri(testBaseUrl, staffId: ' STF0012 ');

    expect(uri.toString(), '$testBaseUrl/password-reset?staffId=STF0012');
  });

  test('leaves the staff ID out when none was typed', () {
    expect(passwordResetUri(testBaseUrl).toString(),
        '$testBaseUrl/password-reset');
  });

  test('keeps a path prefix on the server address', () {
    expect(
      passwordResetUri('https://example.test/bank/').toString(),
      'https://example.test/bank/password-reset',
    );
  });

  test('a build with no server address is refused', () {
    expect(
      () => passwordResetUri(''),
      throwsA(isA<ApiException>()
          .having((e) => e.failure, 'failure', ApiFailure.notConfigured)),
    );
  });
}
