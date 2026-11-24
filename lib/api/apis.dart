import 'package:http/http.dart' as http;

import '../approvals/approval_api.dart';
import '../branches/branch_api.dart';
import '../dashboard/dashboard_api.dart';
import '../members/member_api.dart';
import '../staff/staff_api.dart';
import '../submissions/submission_api.dart';
import '../transactions/transaction_api.dart';

/// The backend APIs the signed-in app uses, passed down together so each new
/// one doesn't add a parameter to every screen on the way.
class Apis {
  const Apis({
    required this.staff,
    required this.members,
    required this.branches,
    required this.transactions,
    required this.submissions,
    required this.approvals,
    required this.dashboard,
  });

  /// Every API on [baseUrl] through [client], which should be the app's
  /// `AuthenticatedClient`.
  factory Apis.connect({
    required String baseUrl,
    required http.Client client,
  }) =>
      Apis(
        staff: StaffApi(baseUrl: baseUrl, client: client),
        members: MemberApi(baseUrl: baseUrl, client: client),
        branches: BranchApi(baseUrl: baseUrl, client: client),
        transactions: TransactionApi(baseUrl: baseUrl, client: client),
        submissions: SubmissionApi(baseUrl: baseUrl, client: client),
        approvals: ApprovalApi(baseUrl: baseUrl, client: client),
        dashboard: DashboardApi(baseUrl: baseUrl, client: client),
      );

  final StaffApi staff;
  final MemberApi members;
  final BranchApi branches;
  final TransactionApi transactions;
  final SubmissionApi submissions;
  final ApprovalApi approvals;
  final DashboardApi dashboard;
}
