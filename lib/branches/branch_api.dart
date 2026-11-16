import 'package:http/http.dart' as http;

import '../api/api_call.dart';
import '../api/endpoint.dart';
import 'branch.dart';

/// Reads the branch list, for the branch pickers in Add staff and Register
/// member. [client] should be the app's `AuthenticatedClient`.
class BranchApi {
  BranchApi({
    required String baseUrl,
    required http.Client client,
    this.timeout = const Duration(seconds: 20),
  })  : _baseUrl = baseUrl,
        _client = client;

  /// The branch list endpoint doesn't exist on the backend yet. This is the
  /// contract in CASH_CLIENT_DESKTOP.md section 16 (each branch's id and
  /// name); change it here if the backend settles on another path.
  static const branchesPath = '/api/branch/v1/all';

  final String _baseUrl;
  final http.Client _client;
  final Duration timeout;

  /// `GET /api/branch/v1/all` (proposed): every branch, sorted by name.
  Future<List<Branch>> fetchBranches() async {
    final response = await sendChecked(
      () => _client.get(
        apiUri(_baseUrl, branchesPath),
        headers: const {'Accept': 'application/json'},
      ),
      timeout: timeout,
    );
    final json = decodeJson(response.body);
    if (json is! List) throw unexpectedOk();
    return json.map(Branch.fromJson).whereType<Branch>().toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }
}
