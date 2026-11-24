import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../api/api_call.dart';
import '../api/api_exception.dart';
import '../api/endpoint.dart';
import '../auth/staff_profile.dart';
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

  final String _baseUrl;
  final http.Client _client;
  final Duration timeout;

  /// `POST /api/staff/v1/add-staff` (Administrator only). The backend
  /// answers an empty 200 and texts the new staff member their staff ID.
  ///
  /// Throws [ApiException]: `validation` (400) for a field the backend
  /// rejects, `conflict` (409) for an existing staff member, phone number or
  /// email, a branch that already has an active agent, or an unknown branch,
  /// and `forbidden` (403) for anyone but an administrator.
  Future<void> addStaff(NewStaff staff) async {
    await sendChecked(
      () => _client.post(
        apiUri(_baseUrl, '/api/staff/v1/add-staff'),
        headers: const {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(staff.toJson()),
      ),
      timeout: timeout,
    );
  }

  static const _staff = '/api/staff/v1';

  Future<StaffMember> _member(Future<http.Response> Function() request) async {
    final response = await sendChecked(request, timeout: timeout);
    return StaffMember.fromJson(decodeJson(response.body)) ??
        (throw unexpectedOk());
  }

  Future<http.Response> _postEmpty(String path) => _client.post(
        apiUri(_baseUrl, path),
        headers: const {'Accept': 'application/json'},
      );

  Future<http.Response> _putJson(String path, Object body) => _client.put(
        apiUri(_baseUrl, path),
        headers: const {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(body),
      );

  /// `GET /api/staff/v1/all-staff`: everyone for an Administrator, their
  /// own branch for an Agent. Sorted here by name.
  Future<List<StaffMember>> listStaff() async {
    final response = await sendChecked(
      () => _client.get(
        apiUri(_baseUrl, '$_staff/all-staff'),
        headers: const {'Accept': 'application/json'},
      ),
      timeout: timeout,
    );
    final json = decodeJson(response.body);
    if (json is! List) throw unexpectedOk();
    return json.map(StaffMember.fromJson).whereType<StaffMember>().toList()
      ..sort((a, b) =>
          a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()));
  }

  /// `GET /api/staff/v1/me`: the signed-in staff member's own profile, with
  /// their branch and current roles.
  Future<StaffProfile> fetchMe() async {
    final response = await sendChecked(
      () => _client.get(
        apiUri(_baseUrl, '$_staff/me'),
        headers: const {'Accept': 'application/json'},
      ),
      timeout: timeout,
    );
    return StaffProfile.fromJson(decodeJson(response.body)) ??
        (throw unexpectedOk());
  }

  /// `GET /api/staff/v1/staff-details/{staffId}`.
  Future<StaffMember> fetchStaff(String staffId) => _member(
        () => _client.get(
          apiUri(_baseUrl, '$_staff/staff-details/${Uri.encodeComponent(staffId)}'),
          headers: const {'Accept': 'application/json'},
        ),
      );

  /// `PUT /api/staff/v1/update-staff/{staffId}` (Administrators).
  Future<StaffMember> updateProfile(String staffId, StaffProfileUpdate update) =>
      _member(() => _putJson(
            '$_staff/update-staff/${Uri.encodeComponent(staffId)}',
            update.toJson(),
          ));

  /// `PUT /api/staff/v1/update-roles/{staffId}` (Administrators): replaces
  /// the roles. The backend keeps at least one active Administrator, one
  /// active Agent per branch, and refuses removing your own Administrator
  /// role.
  Future<StaffMember> updateRoles(String staffId, Set<StaffRoleOption> roles) =>
      _member(() => _putJson(
            '$_staff/update-roles/${Uri.encodeComponent(staffId)}',
            {
              'roles': [
                for (final r in StaffRoleOption.values)
                  if (roles.contains(r)) r.backendName,
              ],
            },
          ));

  /// `POST /api/staff/v1/deactivate/{staffId}` (Administrators): signs them
  /// out everywhere.
  Future<StaffMember> deactivate(String staffId) => _member(
      () => _postEmpty('$_staff/deactivate/${Uri.encodeComponent(staffId)}'));

  /// `POST /api/staff/v1/reactivate/{staffId}` (Administrators).
  Future<StaffMember> reactivate(String staffId) => _member(
      () => _postEmpty('$_staff/reactivate/${Uri.encodeComponent(staffId)}'));

  /// `POST /api/admin/v1/staff/{staffId}/unlock` (Administrators): clears a
  /// lock from 5 wrong passwords.
  Future<StaffMember> unlock(String staffId) => _member(() => _postEmpty(
      '/api/admin/v1/staff/${Uri.encodeComponent(staffId)}/unlock'));

  /// `POST /api/staff/v1/collectors/{staffId}/release-device`: frees a
  /// collector's registered phone and signs them out everywhere; their next
  /// sign-in registers the new phone. Agents for their own branch,
  /// Administrators for all. Answers 204.
  Future<void> releaseDevice(String staffId) async {
    final http.Response response;
    try {
      response = await _postEmpty(
        '$_staff/collectors/${Uri.encodeComponent(staffId)}/release-device',
      ).timeout(timeout);
    } on TimeoutException {
      throw const ApiException(ApiFailure.network);
    } on http.ClientException {
      throw const ApiException(ApiFailure.network);
    }
    if (response.statusCode != 204 && response.statusCode != 200) {
      throw ApiException.fromResponse(response.statusCode, response.body);
    }
  }
}

/// A message for a failed staff action. The backend's 409 reasons are
/// written for staff ("You cannot deactivate your own account", "Branch
/// Tarkwa already has an active agent", …), so they're shown as they are,
/// with clearer words for the duplicate checks.
String staffActionErrorMessage(Object error) {
  if (error is! ApiException) return 'Something went wrong. Try again.';
  final message = error.message?.trim() ?? '';
  final lower = message.toLowerCase();
  if (error.failure == ApiFailure.conflict) {
    if (lower.contains('phone number already')) {
      return 'Another staff member already uses this phone number.';
    }
    if (lower.contains('email already')) {
      return 'Another staff member already uses this email address.';
    }
    if (lower.contains('staff already exist')) {
      return 'Another staff member has this name and date of birth.';
    }
  }
  if (error.failure == ApiFailure.notFound) {
    return 'This staff member no longer exists.';
  }
  if ((error.failure == ApiFailure.conflict ||
          error.failure == ApiFailure.validation ||
          error.failure == ApiFailure.forbidden) &&
      message.isNotEmpty) {
    return message.endsWith('.') ? message : '$message.';
  }
  return switch (error.failure) {
    ApiFailure.forbidden => 'Only administrators can do this.',
    ApiFailure.network =>
      "Couldn't reach the server. Check your connection and try again.",
    ApiFailure.server => 'The server had a problem. Try again in a few minutes.',
    ApiFailure.notConfigured =>
      'This build has no server address. It needs to be rebuilt with '
          'API_BASE_URL.',
    ApiFailure.unauthorized => 'Your session has ended. Sign in again.',
    _ => "The server sent a response the app didn't understand.",
  };
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
