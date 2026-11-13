import 'package:flutter/foundation.dart';

/// The two roles the desktop app is for. Values match the backend's `Roles`
/// enum (`ADMINISTRATOR`, `AGENT`).
enum StaffRole {
  administrator('ADMINISTRATOR', 'Administrator'),
  agent('AGENT', 'Agent');

  const StaffRole(this.backendName, this.label);

  final String backendName;
  final String label;
}

/// The signed-in staff member, as returned by the backend's login endpoint.
///
/// Kept in memory only: staff sign in each time the app opens (owner
/// decision 13 November 2026), so nothing here is ever written to disk.
@immutable
class AuthSession {
  const AuthSession({
    required this.staffId,
    required this.staffName,
    required this.roles,
    required this.accessToken,
    required this.refreshToken,
  });

  /// What the staff member typed to sign in. The login response doesn't
  /// echo it back, so it's kept from the request.
  final String staffId;
  final String staffName;
  final List<String> roles;
  final String accessToken;
  final String refreshToken;

  /// The role the desktop app works as, or null for anyone else (such as a
  /// collector), who isn't allowed in.
  ///
  /// Someone with both roles is treated as an administrator (owner decision
  /// 13 November 2026), the wider of the two scopes. This only shapes the
  /// app; the backend checks the real roles on every request.
  StaffRole? get role {
    if (roles.contains(StaffRole.administrator.backendName)) {
      return StaffRole.administrator;
    }
    if (roles.contains(StaffRole.agent.backendName)) return StaffRole.agent;
    return null;
  }

  /// Parses the login response body. Returns null if a required field is
  /// missing or has the wrong type.
  static AuthSession? fromLoginResponse(
    String staffId,
    Map<String, dynamic> json,
  ) {
    final staffName = json['staffName'];
    final roles = json['roles'];
    final accessToken = json['authToken'];
    final refreshToken = json['refreshToken'];
    if (staffName is! String ||
        roles is! List ||
        accessToken is! String ||
        accessToken.isEmpty ||
        refreshToken is! String ||
        refreshToken.isEmpty) {
      return null;
    }
    return AuthSession(
      staffId: staffId,
      staffName: staffName,
      roles: List.unmodifiable(roles.whereType<String>()),
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
  }

  /// The same session with a new access token, after a refresh.
  AuthSession withAccessToken(String accessToken) => AuthSession(
        staffId: staffId,
        staffName: staffName,
        roles: roles,
        accessToken: accessToken,
        refreshToken: refreshToken,
      );
}
