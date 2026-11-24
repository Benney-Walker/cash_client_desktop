import 'package:http/http.dart' as http;

import '../api/api_call.dart';
import '../api/endpoint.dart';
import '../api/paged.dart';
import '../common/dates.dart';
import 'dashboard_models.dart';

export 'dashboard_models.dart';

/// What the dashboard reads. There are no dashboard endpoints on the
/// backend, so every figure comes from an existing one: the report
/// endpoints for money and loans, and the total of a list for each
/// waiting count. The backend scopes each to an Agent's branch where it
/// applies.
class DashboardApi {
  DashboardApi({
    required String baseUrl,
    required http.Client client,
    this.timeout = const Duration(seconds: 20),
  })  : _baseUrl = baseUrl,
        _client = client;

  static const transactionsReportPath = '/api/report/v1/transactions';
  static const collectionsReportPath = '/api/report/v1/collector-collections';
  static const loanPortfolioPath = '/api/report/v1/loan-portfolio';
  static const submissionsPath = '/api/transaction/v1/collector-submissions';
  static const kycReviewsPath = '/api/admin/v1/kyc-reviews';
  static const memberUpdatesPath = '/api/admin/v1/member-update-requests';
  static const loanApplicationsPath = '/api/loan/v1/applications';
  static const membersPath = '/api/member/v1/members';

  final String _baseUrl;
  final http.Client _client;
  final Duration timeout;

  Future<Object?> _get(String path, Map<String, String> query) async {
    final response = await sendChecked(
      () => _client.get(
        apiUri(_baseUrl, path, query),
        headers: const {'Accept': 'application/json'},
      ),
      timeout: timeout,
    );
    return decodeJson(response.body);
  }

  static Map<String, String> _range(DateTime from, DateTime to, String? branchId) =>
      {
        'from': isoDate(from),
        'to': isoDate(to),
        if (branchId != null) 'branchId': branchId,
      };

  /// `GET /api/report/v1/transactions`.
  Future<TransactionSummary> transactions(
    DateTime from,
    DateTime to, {
    String? branchId,
  }) async =>
      TransactionSummary.fromJson(
        await _get(transactionsReportPath, _range(from, to, branchId)),
      ) ??
      (throw unexpectedOk());

  /// `GET /api/report/v1/collector-collections`.
  Future<CollectionsSummary> collections(
    DateTime from,
    DateTime to, {
    String? branchId,
  }) async =>
      CollectionsSummary.fromJson(
        await _get(collectionsReportPath, _range(from, to, branchId)),
      ) ??
      (throw unexpectedOk());

  /// `GET /api/report/v1/loan-portfolio`.
  Future<LoanPortfolioSummary> loanPortfolio({String? branchId}) async =>
      LoanPortfolioSummary.fromJson(
        await _get(loanPortfolioPath, {if (branchId != null) 'branchId': branchId}),
      ) ??
      (throw unexpectedOk());

  /// The total of a paged list, read with a page of one.
  Future<int> _count(String path, Map<String, String> query) async {
    final page = PagedResult.fromJson(
      await _get(path, {...query, 'page': '0', 'size': '1'}),
      (entry) => entry,
    );
    return page?.totalElements ?? (throw unexpectedOk());
  }

  /// Collectors' handed-in days still waiting to be counted.
  Future<int> submissionsWaiting() =>
      _count(submissionsPath, {'status': 'SUBMITTED'});

  /// ID documents needing manual review (Administrators).
  Future<int> idDocumentsToReview() =>
      _count(kycReviewsPath, {'status': 'MANUAL_REVIEW'});

  /// Member update requests waiting (Administrators).
  Future<int> memberUpdatesWaiting() =>
      _count(memberUpdatesPath, {'status': 'PENDING'});

  /// Loan applications waiting for an Administrator.
  Future<int> loanApplicationsWaiting() =>
      _count(loanApplicationsPath, {'status': 'PENDING'});

  /// Members registered but not yet active (their ID isn't verified).
  /// Agents: their branch; Administrators: [branchId] or every branch.
  Future<int> pendingMembers({String? branchId}) => _count(membersPath, {
        'status': 'PENDING',
        if (branchId != null) 'branchId': branchId,
      });
}
