import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../api/api_call.dart';
import '../api/api_exception.dart';
import '../api/endpoint.dart';
import '../api/paged.dart';
import '../common/money.dart';
import '../members/member_api.dart' show commonFailureMessage;
import 'loan_models.dart';

export '../api/paged.dart';
export 'loan_models.dart';

/// The backend's loans (owner decisions 2026-11-24 on the backend):
/// Administrators and Agents read and apply for a member of any branch;
/// products and reviews are under `/api/admin` (Administrators).
class LoanApi {
  LoanApi({
    required String baseUrl,
    required http.Client client,
    this.timeout = const Duration(seconds: 20),
  })  : _baseUrl = baseUrl,
        _client = client;

  static const productsPath = '/api/loan/v1/products';
  static const applicationsPath = '/api/loan/v1/applications';
  static const memberLoansPath = '/api/loan/v1/members';
  static const loanPath = '/api/loan/v1/loans';
  static const adminProductsPath = '/api/admin/v1/loan-products';
  static const adminApplicationsPath = '/api/admin/v1/loan-applications';
  static const portfolioPath = '/api/report/v1/loan-portfolio';
  static const pageSize = 20;

  final String _baseUrl;
  final http.Client _client;
  final Duration timeout;

  static const _accept = {'Accept': 'application/json'};
  static const _json = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  Future<Object?> _get(String path, [Map<String, String>? query]) async {
    final response = await sendChecked(
      () => _client.get(apiUri(_baseUrl, path, query), headers: _accept),
      timeout: timeout,
    );
    return decodeJson(response.body);
  }

  /// `GET /api/loan/v1/products`: Agents get the active ones,
  /// Administrators all. Sorted by name.
  Future<List<LoanProduct>> products() async {
    final json = await _get(productsPath);
    if (json is! List) throw unexpectedOk();
    return json.map(LoanProduct.fromJson).whereType<LoanProduct>().toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  /// `POST /api/admin/v1/loan-products` (Administrators).
  Future<LoanProduct> createProduct(LoanProductDraft draft) =>
      _product(() => _client.post(
            apiUri(_baseUrl, adminProductsPath),
            headers: _json,
            body: jsonEncode(draft.toJson()),
          ));

  /// `PUT /api/admin/v1/loan-products/{id}` (Administrators): replaces the
  /// terms, including switching it off.
  Future<LoanProduct> updateProduct(int id, LoanProductDraft draft) =>
      _product(() => _client.put(
            apiUri(_baseUrl, '$adminProductsPath/$id'),
            headers: _json,
            body: jsonEncode(draft.toJson()),
          ));

  Future<LoanProduct> _product(Future<http.Response> Function() call) async {
    final response = await _send(call, okStatuses: const {200, 201});
    return LoanProduct.fromJson(decodeJson(response.body)) ??
        (throw unexpectedOk());
  }

  /// `POST /api/loan/v1/applications` (answers 201).
  Future<LoanApplicationRecord> apply(NewLoanApplication application) async {
    final response = await _send(
      () => _client.post(
        apiUri(_baseUrl, applicationsPath),
        headers: _json,
        body: jsonEncode(application.toJson()),
      ),
      okStatuses: const {200, 201},
    );
    return LoanApplicationRecord.fromJson(decodeJson(response.body)) ??
        (throw unexpectedOk());
  }

  /// `GET /api/loan/v1/applications?status=`, newest first.
  Future<PagedResult<LoanApplicationRecord>> applications(
    LoanApplicationStatus status, {
    int page = 0,
  }) async =>
      PagedResult.fromJson(
        await _get(applicationsPath, {
          'status': status.backendName,
          'page': '$page',
          'size': '$pageSize',
        }),
        LoanApplicationRecord.fromJson,
      ) ??
      (throw unexpectedOk());

  /// A member's applications, newest first (first page only).
  Future<List<LoanApplicationRecord>> memberApplications(String memberId) async {
    final page = PagedResult.fromJson(
      await _get(applicationsPath, {
        'memberId': memberId,
        'page': '0',
        'size': '$pageSize',
      }),
      LoanApplicationRecord.fromJson,
    );
    return page?.items ?? (throw unexpectedOk());
  }

  /// `GET /api/loan/v1/applications/{id}`, with its guarantors.
  Future<LoanApplicationRecord> application(String id) async =>
      LoanApplicationRecord.fromJson(
        await _get('$applicationsPath/${Uri.encodeComponent(id)}'),
      ) ??
      (throw unexpectedOk());

  /// `GET /api/loan/v1/members/{memberId}/loans`, newest first.
  Future<List<LoanDetails>> memberLoans(String memberId) async {
    final json =
        await _get('$memberLoansPath/${Uri.encodeComponent(memberId)}/loans');
    if (json is! List) throw unexpectedOk();
    return json.map(LoanDetails.fromJson).whereType<LoanDetails>().toList();
  }

  /// `GET /api/loan/v1/loans/{loanId}`, with its installments.
  Future<LoanDetails> loan(String loanId) async =>
      LoanDetails.fromJson(
        await _get('$loanPath/${Uri.encodeComponent(loanId)}'),
      ) ??
      (throw unexpectedOk());

  /// The active loans, from `GET /api/report/v1/loan-portfolio` (an Agent's
  /// branch, or every branch for an Administrator).
  Future<List<PortfolioLoan>> activeLoans() async {
    final json = await _get(portfolioPath);
    final loans = json is Map<String, dynamic> ? json['loans'] : null;
    if (loans is! List) throw unexpectedOk();
    return loans.map(PortfolioLoan.fromJson).whereType<PortfolioLoan>().toList();
  }

  /// `POST /api/admin/v1/loan-applications/{id}/approve`: pays the loan
  /// into the member's savings or current account at once, less the fee.
  /// [amount] approves less than was asked; null approves it in full.
  Future<LoanApplicationRecord> approve(String id, {Money? amount}) async {
    final response = await sendChecked(
      () => _client.post(
        apiUri(_baseUrl,
            '$adminApplicationsPath/${Uri.encodeComponent(id)}/approve'),
        headers: _json,
        body: amount == null ? null : jsonEncode({'approvedAmount': amount.toJson()}),
      ),
      timeout: timeout,
    );
    return LoanApplicationRecord.fromJson(decodeJson(response.body)) ??
        (throw unexpectedOk());
  }

  /// `POST /api/admin/v1/loan-applications/{id}/reject` with `{reason}`.
  Future<LoanApplicationRecord> reject(String id, String reason) async {
    final response = await sendChecked(
      () => _client.post(
        apiUri(_baseUrl,
            '$adminApplicationsPath/${Uri.encodeComponent(id)}/reject'),
        headers: _json,
        body: jsonEncode({'reason': reason}),
      ),
      timeout: timeout,
    );
    return LoanApplicationRecord.fromJson(decodeJson(response.body)) ??
        (throw unexpectedOk());
  }

  /// Like [sendChecked], but accepting any of [okStatuses] (creating
  /// answers 201 Created). Sends once.
  Future<http.Response> _send(
    Future<http.Response> Function() call, {
    required Set<int> okStatuses,
  }) async {
    final http.Response response;
    try {
      response = await call().timeout(timeout);
    } on TimeoutException {
      throw const ApiException(ApiFailure.network);
    } on http.ClientException {
      throw const ApiException(ApiFailure.network);
    }
    if (!okStatuses.contains(response.statusCode)) {
      throw ApiException.fromResponse(response.statusCode, response.body);
    }
    return response;
  }
}

/// A message for a failed loan call. The backend's 400 and 409 reasons are
/// written for staff ("This member already has a loan being repaid; one
/// loan at a time", "A member needs 6 months of membership before a loan…"),
/// so they're shown as they are.
String loanErrorMessage(Object error, {bool afterUnknownOutcome = false}) {
  if (error is! ApiException) return 'Something went wrong. Try again.';
  final message = (error.message ?? '').trim();
  final lower = message.toLowerCase();
  switch (error.failure) {
    case ApiFailure.conflict:
      if (afterUnknownOutcome && lower.contains('waiting for review')) {
        return 'This member already has an application waiting. The '
            'connection dropped on the last try, so it was probably sent '
            'then. Check Applications before trying again.';
      }
      if (lower.contains('already approved') || lower.contains('already rejected')) {
        return 'This application was already reviewed, probably by another '
            'administrator. Refresh the list.';
      }
      if (message.isNotEmpty) return _sentence(message);
    case ApiFailure.validation:
      if (message.isNotEmpty) return _sentence(message);
    case ApiFailure.notFound:
      return message.isEmpty ? "That couldn't be found." : _sentence(message);
    case ApiFailure.forbidden:
      return 'Only administrators can do this.';
    case ApiFailure.network:
      return "Couldn't reach the server, so it isn't clear whether this went "
          'through. Refresh before trying again.';
    default:
      break;
  }
  return commonFailureMessage(error, action: 'use loans');
}

String _sentence(String message) =>
    message.endsWith('.') ? message : '$message.';
