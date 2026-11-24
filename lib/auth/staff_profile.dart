import 'package:flutter/foundation.dart';

/// The signed-in staff member's own profile, from `GET /api/staff/v1/me`
/// (`StaffResponse`): what the login response doesn't give, chiefly the
/// branch, plus the roles as they stand in the database now.
@immutable
class StaffProfile {
  const StaffProfile({
    required this.staffId,
    required this.roles,
    this.fullName,
    this.branchId,
    this.branchName,
  });

  final String staffId;

  /// The backend's role names (`ADMINISTRATOR`, `AGENT`, `COLLECTOR`).
  final Set<String> roles;
  final String? fullName;
  final String? branchId;
  final String? branchName;

  static StaffProfile? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final id = _text(json['staffId']);
    final roles = json['roles'];
    if (id == null || roles is! List) return null;
    final name = [
      _text(json['firstName']),
      _text(json['middleName']),
      _text(json['lastName']),
    ].whereType<String>().join(' ');
    return StaffProfile(
      staffId: id,
      roles: {for (final r in roles) if (r is String) r},
      fullName: name.isEmpty ? null : name,
      branchId: _text(json['branchId']),
      branchName: _text(json['branchName']),
    );
  }
}

String? _text(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;
