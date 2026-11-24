import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../api/api_call.dart';
import '../api/api_exception.dart';
import '../api/endpoint.dart';
import '../api/paged.dart';
import '../common/dates.dart';
import '../members/member_api.dart' show commonFailureMessage;
import 'report_models.dart';

export '../api/paged.dart';
export 'report_models.dart';

/// Reports, statements, the audit log and the trial balance. Reports are
/// for Administrators (every branch or one) and Agents (their branch);
/// statements for Administrators (any member) and Agents (their branch's
/// members); the audit log and trial balance for Administrators.
class ReportApi {
  ReportApi({
    required String baseUrl,
    required http.Client client,
    this.timeout = const Duration(seconds: 30),
  })  : _baseUrl = baseUrl,
        _client = client;

  static const transactionsPath = '/api/report/v1/transactions';
  static const collectionsPath = '/api/report/v1/collector-collections';
  static const portfolioPath = '/api/report/v1/loan-portfolio';
  static const statementPath = '/api/transaction/v1/statement';
  static const auditLogPath = '/api/admin/v1/audit-log';
  static const trialBalancePath = '/api/admin/ledger/v1/trial-balance';
  static const auditPageSize = 50;

  final String _baseUrl;
  final http.Client _client;
  final Duration timeout;

  Future<http.Response> _get(
    String path,
    Map<String, String>? query, {
    String accept = 'application/json',
  }) =>
      sendChecked(
        () => _client.get(apiUri(_baseUrl, path, query), headers: {'Accept': accept}),
        timeout: timeout,
      );

  Future<Object?> _json(String path, [Map<String, String>? query]) async =>
      decodeJson((await _get(path, query)).body);

  Future<Uint8List> _pdf(String path, Map<String, String>? query) async {
    final bytes = (await _get(path, query, accept: 'application/pdf')).bodyBytes;
    // A PDF starts with "%PDF".
    if (bytes.length < 4 || bytes[0] != 0x25 || bytes[1] != 0x50) {
      throw unexpectedOk();
    }
    return bytes;
  }

  static Map<String, String> _range(DateTime from, DateTime to, String? branchId) => {
        'from': isoDate(from),
        'to': isoDate(to),
        if (branchId != null) 'branchId': branchId,
      };

  Future<TransactionReportData> transactions(DateTime from, DateTime to, {String? branchId}) async =>
      TransactionReportData.fromJson(await _json(transactionsPath, _range(from, to, branchId))) ??
      (throw unexpectedOk());

  Future<Uint8List> transactionsPdf(DateTime from, DateTime to, {String? branchId}) =>
      _pdf('$transactionsPath/pdf', _range(from, to, branchId));

  Future<CollectionsReportData> collections(DateTime from, DateTime to, {String? branchId}) async =>
      CollectionsReportData.fromJson(await _json(collectionsPath, _range(from, to, branchId))) ??
      (throw unexpectedOk());

  Future<Uint8List> collectionsPdf(DateTime from, DateTime to, {String? branchId}) =>
      _pdf('$collectionsPath/pdf', _range(from, to, branchId));

  Future<PortfolioReportData> portfolio({String? branchId}) async =>
      PortfolioReportData.fromJson(
        await _json(portfolioPath, {if (branchId != null) 'branchId': branchId}),
      ) ??
      (throw unexpectedOk());

  Future<Uint8List> portfolioPdf({String? branchId}) =>
      _pdf('$portfolioPath/pdf', {if (branchId != null) 'branchId': branchId});

  /// `GET /api/transaction/v1/statement/{accountNumber}?from=&to=`: the
  /// account's statement as a PDF. The backend records it in the audit log.
  Future<Uint8List> statementPdf(String accountNumber, DateTime from, DateTime to) =>
      _pdf(
        '$statementPath/${Uri.encodeComponent(accountNumber.trim())}',
        {'from': isoDate(from), 'to': isoDate(to)},
      );

  /// `GET /api/admin/v1/audit-log`, newest first.
  Future<PagedResult<AuditEntry>> auditLog(AuditFilter filter, {int page = 0}) async =>
      PagedResult.fromJson(
        await _json(auditLogPath, {
          ...filter.toQuery(),
          'page': '$page',
          'size': '$auditPageSize',
        }),
        AuditEntry.fromJson,
      ) ??
      (throw unexpectedOk());

  /// `GET /api/admin/ledger/v1/trial-balance`.
  Future<TrialBalance> trialBalance() async =>
      TrialBalance.fromJson(await _json(trialBalancePath)) ?? (throw unexpectedOk());
}

/// A message for a failed report call.
String reportErrorMessage(Object error) {
  if (error is! ApiException) return 'Something went wrong. Try again.';
  final message = (error.message ?? '').trim();
  switch (error.failure) {
    case ApiFailure.forbidden:
      return message.isEmpty
          ? "You can't see this report."
          : (message.endsWith('.') ? message : '$message.');
    case ApiFailure.notFound:
      return message.isEmpty
          ? "That account couldn't be found."
          : (message.endsWith('.') ? message : '$message.');
    case ApiFailure.validation:
      if (message.isNotEmpty) return message.endsWith('.') ? message : '$message.';
    default:
      break;
  }
  return commonFailureMessage(error, action: 'see reports');
}
