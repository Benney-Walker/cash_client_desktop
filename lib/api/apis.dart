import 'package:http/http.dart' as http;

import '../branches/branch_api.dart';
import '../members/member_api.dart';
import '../staff/staff_api.dart';

/// The backend APIs the signed-in app uses, passed down together so each new
/// one doesn't add a parameter to every screen on the way.
class Apis {
  const Apis({
    required this.staff,
    required this.members,
    required this.branches,
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
      );

  final StaffApi staff;
  final MemberApi members;
  final BranchApi branches;
}
