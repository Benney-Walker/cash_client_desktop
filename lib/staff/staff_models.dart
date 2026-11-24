import 'package:flutter/foundation.dart';

import '../branches/branch.dart';
import '../common/dates.dart';

export '../branches/branch.dart';
export '../common/dates.dart';

/// The three staff roles, with the backend's names (`Roles` enum).
enum StaffRoleOption {
  administrator('ADMINISTRATOR', 'Administrator', 'All branches'),
  agent('AGENT', 'Agent', 'One active agent per branch'),
  collector('COLLECTOR', 'Collector', 'Uses the mobile app only');

  const StaffRoleOption(this.backendName, this.label, this.hint);

  final String backendName;
  final String label;
  final String hint;

  /// Applies a tap on [tapped] to [current], following the backend's rule
  /// that a collector can't have any other role
  /// (`StaffService.requireValidRoleCombination`). Choosing Collector clears
  /// the others; choosing Administrator or Agent clears Collector.
  static Set<StaffRoleOption> toggle(
    Set<StaffRoleOption> current,
    StaffRoleOption tapped,
  ) {
    final next = {...current};
    if (next.contains(tapped)) {
      next.remove(tapped);
      return next;
    }
    if (tapped == collector) return {collector};
    next
      ..remove(collector)
      ..add(tapped);
    return next;
  }
}

/// What the Add staff steps collect, sent to `POST /api/staff/v1/add-staff`.
///
/// There's no password: the backend generates a default one and the staff
/// member sets their own through password reset (owner decision 15 November
/// 2026, recorded for the backend in CASH_CLIENT_DESKTOP.md section 16).
@immutable
class NewStaff {
  const NewStaff({
    required this.firstName,
    this.middleName,
    required this.lastName,
    required this.dateOfBirth,
    required this.phoneNumber,
    required this.email,
    required this.residentialAddress,
    required this.roles,
    required this.branch,
  });

  final String firstName;
  final String? middleName;
  final String lastName;
  final DateTime dateOfBirth;
  final String phoneNumber;
  final String email;
  final String residentialAddress;
  final Set<StaffRoleOption> roles;
  final Branch branch;

  String get fullName => [firstName, middleName, lastName]
      .whereType<String>()
      .where((part) => part.isNotEmpty)
      .join(' ');

  /// Roles in a fixed order, for display and for the request.
  List<StaffRoleOption> get orderedRoles =>
      StaffRoleOption.values.where(roles.contains).toList();

  Map<String, Object?> toJson() => {
        'firstName': firstName,
        // The backend stores a blank middle name itself when none is sent.
        if (middleName != null && middleName!.isNotEmpty)
          'middleName': middleName,
        'lastName': lastName,
        'dateOfBirth': isoDate(dateOfBirth),
        'phoneNumber': phoneNumber,
        'email': email,
        'residentialAddress': residentialAddress,
        'roles': [for (final role in orderedRoles) role.backendName],
        'branchId': branch.id,
      };
}

/// Whether a staff account can sign in (`StaffStatus`).
enum StaffAccountStatus {
  active('ACTIVE', 'Active'),
  inactive('INACTIVE', 'Inactive');

  const StaffAccountStatus(this.backendName, this.label);

  final String backendName;
  final String label;

  static StaffAccountStatus? parse(Object? value) {
    for (final s in values) {
      if (s.backendName == value) return s;
    }
    return null;
  }
}

String? _text(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;

/// A staff member as the backend sends them (`StaffResponse`).
@immutable
class StaffMember {
  const StaffMember({
    required this.staffId,
    required this.firstName,
    required this.lastName,
    required this.roles,
    this.middleName,
    this.dateOfBirth,
    this.phoneNumber,
    this.email,
    this.residentialAddress,
    this.branchId,
    this.branchName,
    this.status,
    this.lockedAt,
    this.deviceRegisteredAt,
  });

  final String staffId;
  final String firstName;

  /// The backend stores a blank middle name as a space; that reads as none.
  final String? middleName;
  final String lastName;
  final DateTime? dateOfBirth;
  final String? phoneNumber;
  final String? email;
  final String? residentialAddress;
  final String? branchId;
  final String? branchName;
  final StaffAccountStatus? status;
  final Set<StaffRoleOption> roles;

  /// When 5 wrong passwords locked the account; null when it isn't locked.
  final DateTime? lockedAt;

  /// When a collector's phone was registered; null when none is.
  final DateTime? deviceRegisteredAt;

  String get fullName => [firstName, middleName, lastName]
      .whereType<String>()
      .where((part) => part.isNotEmpty)
      .join(' ');

  bool get isLocked => lockedAt != null;
  bool get isActive => status == StaffAccountStatus.active;
  bool get isCollector => roles.contains(StaffRoleOption.collector);
  bool get hasRegisteredPhone => deviceRegisteredAt != null;

  /// Roles in a fixed order, for display.
  List<StaffRoleOption> get orderedRoles =>
      StaffRoleOption.values.where(roles.contains).toList();

  String get rolesLabel => orderedRoles.map((r) => r.label).join(' and ');

  /// The phone number in the local form the edit form and the backend's
  /// check expect (0 and 9 digits), whether it's stored that way or as
  /// +233.
  String get localPhoneNumber {
    final phone = (phoneNumber ?? '').replaceAll(' ', '');
    if (phone.startsWith('+233') && phone.length == 13) {
      return '0${phone.substring(4)}';
    }
    return phone;
  }

  /// This record with no registered phone, for after a release when the
  /// record couldn't be read back.
  StaffMember withoutRegisteredPhone() => StaffMember(
        staffId: staffId,
        firstName: firstName,
        middleName: middleName,
        lastName: lastName,
        dateOfBirth: dateOfBirth,
        phoneNumber: phoneNumber,
        email: email,
        residentialAddress: residentialAddress,
        branchId: branchId,
        branchName: branchName,
        status: status,
        roles: roles,
        lockedAt: lockedAt,
      );

  static StaffMember? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final id = _text(json['staffId']);
    final first = _text(json['firstName']);
    final last = _text(json['lastName']);
    if (id == null || first == null || last == null) return null;
    final roles = json['roles'];
    return StaffMember(
      staffId: id,
      firstName: first,
      middleName: _text(json['middleName']),
      lastName: last,
      dateOfBirth: parseIsoDate(_text(json['dateOfBirth']) ?? ''),
      phoneNumber: _text(json['phoneNumber']),
      email: _text(json['email']),
      residentialAddress: _text(json['residentialAddress']),
      branchId: _text(json['branchId']),
      branchName: _text(json['branchName']),
      status: StaffAccountStatus.parse(json['status']),
      roles: {
        if (roles is List)
          for (final r in StaffRoleOption.values)
            if (roles.contains(r.backendName)) r,
      },
      lockedAt: DateTime.tryParse(_text(json['lockedAt']) ?? ''),
      deviceRegisteredAt:
          DateTime.tryParse(_text(json['deviceRegisteredAt']) ?? ''),
    );
  }
}

/// The editable profile, sent to `PUT /api/staff/v1/update-staff/{id}`
/// (`StaffUpdateRequest`). The branch and roles aren't part of it.
@immutable
class StaffProfileUpdate {
  const StaffProfileUpdate({
    required this.firstName,
    this.middleName,
    required this.lastName,
    required this.dateOfBirth,
    required this.phoneNumber,
    required this.email,
    required this.residentialAddress,
  });

  final String firstName;
  final String? middleName;
  final String lastName;
  final DateTime dateOfBirth;
  final String phoneNumber;
  final String email;
  final String residentialAddress;

  Map<String, Object?> toJson() => {
        'firstName': firstName,
        if (middleName != null && middleName!.isNotEmpty)
          'middleName': middleName,
        'lastName': lastName,
        'dateOfBirth': isoDate(dateOfBirth),
        'phoneNumber': phoneNumber,
        'email': email,
        'residentialAddress': residentialAddress,
      };
}
