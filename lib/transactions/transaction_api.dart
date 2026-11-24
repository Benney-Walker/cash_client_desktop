import 'dart:convert';

import 'package:http/http.dart' as http;

import '../api/api_call.dart';
import '../api/api_exception.dart';
import '../api/endpoint.dart';
import '../api/paged.dart';
import '../members/member_api.dart' show commonFailureMessage;
import 'transaction_models.dart';

export '../api/paged.dart';

/// The counter's backend calls (`TransactionController`, Administrators and
/// Agents). [client] should be the app's `AuthenticatedClient`, which
/// resends the identical body (same idempotency key) after a token refresh.
class TransactionApi {
  TransactionApi({
    required String baseUrl,
    required http.Client client,
    this.timeout = const Duration(seconds: 20),
  })  : _baseUrl = baseUrl,
        _client = client;

  static const accountPath = '/api/transaction/v1/account';
  static const historyPath = '/api/transaction/v1/history';

  /// Proposed in CASH_CLIENT_DESKTOP.md section 21; not on the backend yet.
  static const settingsPath = '/api/transaction/v1/settings';

  static const historyPageSize = 10;

  final String _baseUrl;
  final http.Client _client;
  final Duration timeout;

  Future<http.Response> _get(String path, [Map<String, String>? query]) =>
      sendChecked(
        () => _client.get(
          apiUri(_baseUrl, path, query),
          headers: const {'Accept': 'application/json'},
        ),
        timeout: timeout,
      );

  /// `GET /api/transaction/v1/account/{accountNumber}`: the account's
  /// member, type, status and balances. 404 for an unknown account.
  Future<AccountDetails> fetchAccount(String accountNumber) async {
    final response =
        await _get('$accountPath/${Uri.encodeComponent(accountNumber.trim())}');
    return AccountDetails.fromJson(decodeJson(response.body)) ??
        (throw unexpectedOk());
  }

  /// `GET /api/transaction/v1/history/{accountNumber}`, newest first.
  Future<PagedResult<TransactionRecord>> fetchHistory(
    String accountNumber, {
    int page = 0,
  }) async {
    final response = await _get(
      '$historyPath/${Uri.encodeComponent(accountNumber.trim())}',
      {'page': '$page', 'size': '$historyPageSize'},
    );
    return PagedResult.fromJson(
          decodeJson(response.body),
          TransactionRecord.fromJson,
        ) ??
        (throw unexpectedOk());
  }

  /// The withdrawal fee and limits, or null while the backend doesn't offer
  /// them (404) or sends something else. Never throws: the counter works
  /// without them.
  Future<CounterSettings?> fetchSettings() async {
    try {
      final response = await _get(settingsPath);
      return CounterSettings.fromJson(decodeJson(response.body));
    } catch (_) {
      return null;
    }
  }

  /// Sends [draft] with the confirm step's [idempotencyKey]. A retry with
  /// the same key gets the original result instead of a second transaction.
  ///
  /// Throws [ApiException]: `validation` (400) or `conflict` (409) with the
  /// backend's reason, and `network` when the outcome is unknown.
  Future<TransactionRecord> send(
    TransactionDraft draft, {
    required String idempotencyKey,
  }) async {
    final response = await sendChecked(
      () => _client.post(
        apiUri(_baseUrl, draft.kind.path),
        headers: const {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(draft.toJson(idempotencyKey: idempotencyKey)),
      ),
      timeout: timeout,
    );
    return TransactionRecord.fromJson(decodeJson(response.body)) ??
        (throw unexpectedOk());
  }
}

/// A message for a failed account lookup.
String accountErrorMessage(Object error) {
  if (error is ApiException && error.failure == ApiFailure.notFound) {
    return 'No account has that number.';
  }
  if (error is ApiException) {
    return commonFailureMessage(error, action: 'look up accounts');
  }
  return 'Something went wrong. Try again.';
}

/// A message for a failed transaction. The backend's 400 and 409 reasons
/// are already written for staff ("Insufficient balance: the account must
/// keep at least GHS 20.00 …"), so they're shown as they are.
String transactionErrorMessage(Object error) {
  if (error is! ApiException) return 'Something went wrong. Try again.';
  final message = error.message?.trim() ?? '';
  return switch (error.failure) {
    ApiFailure.network =>
      "Couldn't reach the server, so it isn't clear whether this went "
          'through. Try again: the same request is sent, so it can\'t be '
          'recorded twice. Or check the account\'s history first.',
    ApiFailure.notFound => 'That account no longer exists.',
    ApiFailure.validation || ApiFailure.conflict when message.isNotEmpty =>
      message.endsWith('.') ? message : '$message.',
    _ => commonFailureMessage(error, action: 'record transactions'),
  };
}
