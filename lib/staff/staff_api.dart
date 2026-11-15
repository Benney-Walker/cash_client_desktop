import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../api/api_exception.dart';
import '../api/endpoint.dart';
import 'staff_models.dart';

/// Calls the backend's staff endpoints. [client] should be the app's
/// `AuthenticatedClient`, which adds the token and refreshes it when it
/// expires.
class StaffApi {
  StaffApi({
    required String baseUrl,
    required http.Client client,
    this.timeout = const Duration(seconds: 20),
  })  : _baseUrl = baseUrl,
        _client = client;

  /// The branch list endpoint doesn't exist on the backend yet. This is the
  /// contract proposed in CASH_CLIENT_DESKTOP.md section 16; change it here
  /// if the backend settles on another path.
  static const branchesPath = '/api/branch/v1/all';

  final String _baseUrl;
  final http.Client _client;
  final Duration timeout;

  /// `GET /api/branch/v1/all` (proposed): every branch, by name.
  Future<List<Branch>> fetchBranches() async {
    final response = await _send(
      () => _client.get(
        apiUri(_baseUrl, branchesPath),
        headers: const {'Accept': 'application/json'},
      ),
    );
    final json = _decode(response.body);
    if (json is! List) throw _unexpected();
    final branches = json.map(Branch.fromJson).whereType<Branch>().toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return branches;
  }

  /// `POST /api/staff/v1/add-staff` (Administrator only). The backend
  /// answers an empty 200 and texts the new staff member their staff ID.
  ///
  /// Throws [ApiException]: `validation` (400) for a field the backend
  /// rejects, `conflict` (409) for an existing staff member, phone number or
  /// email, a branch that already has an active agent, or an unknown branch,
  /// and `forbidden` (403) for anyone but an administrator.
  Future<void> addStaff(NewStaff staff) async {
    await _send(
      () => _client.post(
        apiUri(_baseUrl, '/api/staff/v1/add-staff'),
        headers: const {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(staff.toJson()),
      ),
    );
  }

  /// Runs a request and turns transport problems and non-200 answers into
  /// [ApiException]s. `AuthenticatedClient` throws its own [ApiException]
  /// when the session has ended; that passes straight through.
  Future<http.Response> _send(Future<http.Response> Function() request) async {
    final http.Response response;
    try {
      response = await request().timeout(timeout);
    } on TimeoutException {
      throw const ApiException(ApiFailure.network);
    } on http.ClientException {
      throw const ApiException(ApiFailure.network);
    }
    if (response.statusCode != 200) {
      throw ApiException.fromResponse(response.statusCode, response.body);
    }
    return response;
  }

  static Object? _decode(String body) {
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }

  static ApiException _unexpected() =>
      const ApiException(ApiFailure.unexpectedResponse, statusCode: 200);
}

/// Which step of Add staff a failure belongs to, so the review step can
/// offer to go back and fix it. Null means no particular step.
enum AddStaffStep { personal, contact, roleAndBranch, review }

/// A message for a failed add-staff call, and the step to fix it in.
///
/// The backend's 409 messages are matched by their text, which is all it
/// sends. Anything unrecognised is shown as the backend wrote it.
(String, AddStaffStep?) addStaffErrorMessage(Object error) {
  if (error is! ApiException) {
    return ('Something went wrong. Try again.', null);
  }
  final message = error.message ?? '';
  final lower = message.toLowerCase();
  switch (error.failure) {
    case ApiFailure.conflict:
      if (lower.contains('phone number')) {
        return (
          'Another staff member already uses this phone number.',
          AddStaffStep.contact,
        );
      }
      if (lower.contains('email')) {
        return (
          'Another staff member already uses this email address.',
          AddStaffStep.contact,
        );
      }
      if (lower.contains('active agent')) {
        return (
          '$message. A branch can have only one active agent.',
          AddStaffStep.roleAndBranch,
        );
      }
      if (lower.contains('branch not found')) {
        return (
          "That branch doesn't exist any more. Choose another.",
          AddStaffStep.roleAndBranch,
        );
      }
      if (lower.contains('staff already exist')) {
        return (
          'A staff member with this name and date of birth already exists. '
              'If the connection dropped while adding them, they were '
              'probably added.',
          AddStaffStep.personal,
        );
      }
      return (
        message.isEmpty
            ? 'This staff member clashes with an existing record.'
            : message,
        null,
      );
    case ApiFailure.validation:
      return (
        message.isEmpty ? 'The server rejected one of the details.' : message,
        null,
      );
    case ApiFailure.forbidden:
      return ('Only administrators can add staff.', null);
    case ApiFailure.network:
      return (
        "Couldn't reach the server. Check your connection and try again.",
        null,
      );
    case ApiFailure.server:
      return ('The server had a problem. Try again in a few minutes.', null);
    case ApiFailure.notConfigured:
      return (
        'This build has no server address. It needs to be rebuilt with '
            'API_BASE_URL.',
        null,
      );
    case ApiFailure.unauthorized:
      return ('Your session has ended. Sign in again.', null);
    case ApiFailure.notFound:
    case ApiFailure.unexpectedResponse:
      return (
        message.isEmpty
            ? "The server sent a response the app didn't understand."
            : message,
        null,
      );
  }
}
