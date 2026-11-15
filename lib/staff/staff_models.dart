import 'package:flutter/foundation.dart';

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

/// A branch, as offered in the branch step.
@immutable
class Branch {
  const Branch({required this.id, required this.name, this.location});

  final String id;
  final String name;
  final String? location;

  static Branch? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final id = json['id'];
    final name = json['name'];
    final location = json['location'];
    if (id is! String || id.isEmpty || name is! String || name.isEmpty) {
      return null;
    }
    return Branch(
      id: id,
      name: name,
      location: location is String && location.isNotEmpty ? location : null,
    );
  }

  @override
  bool operator ==(Object other) => other is Branch && other.id == id;

  @override
  int get hashCode => id.hashCode;
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

/// `yyyy-MM-dd`, the format the backend parses dates of birth in.
String isoDate(DateTime date) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${date.year.toString().padLeft(4, '0')}-${two(date.month)}'
      '-${two(date.day)}';
}

/// Parses `yyyy-MM-dd`, or returns null. Rejects dates that don't exist,
/// such as 2026-02-30.
DateTime? parseIsoDate(String text) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(text.trim());
  if (match == null) return null;
  final year = int.parse(match[1]!);
  final month = int.parse(match[2]!);
  final day = int.parse(match[3]!);
  final date = DateTime(year, month, day);
  if (date.year != year || date.month != month || date.day != day) {
    return null;
  }
  return date;
}
