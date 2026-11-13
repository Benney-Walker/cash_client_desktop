import 'dart:convert';

import 'package:cash_client_desktop/auth/auth_api.dart';
import 'package:cash_client_desktop/auth/auth_session.dart';
import 'package:cash_client_desktop/settings/app_info.dart';
import 'package:cash_client_desktop/settings/theme_mode_store.dart';
import 'package:cash_client_desktop/shell/sidebar_state_store.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Keeps the light/dark choice in memory instead of on disk.
class MemoryThemeModeStore implements ThemeModeStore {
  MemoryThemeModeStore([this.mode]);

  ThemeMode? mode;
  bool failSaves = false;

  @override
  Future<ThemeMode?> read() async => mode;

  @override
  Future<void> save(ThemeMode mode) async {
    if (failSaves) throw StateError('disk full');
    this.mode = mode;
  }
}

/// Keeps the sidebar state in memory instead of on disk.
class MemorySidebarStateStore implements SidebarStateStore {
  MemorySidebarStateStore({this.remember, this.expanded});

  bool? remember;
  bool? expanded;
  bool failReads = false;
  bool failSaves = false;

  @override
  Future<bool?> readRemember() async {
    if (failReads) throw StateError('unreadable');
    return remember;
  }

  @override
  Future<void> saveRemember(bool remember) async {
    if (failSaves) throw StateError('disk full');
    this.remember = remember;
  }

  @override
  Future<bool?> readExpanded() async {
    if (failReads) throw StateError('unreadable');
    return expanded;
  }

  @override
  Future<void> saveExpanded(bool expanded) async {
    if (failSaves) throw StateError('disk full');
    this.expanded = expanded;
  }

  @override
  Future<void> clearExpanded() async {
    if (failSaves) throw StateError('disk full');
    expanded = null;
  }
}

const testAppInfo = AppInfo(
  version: '1.0.0',
  buildNumber: '1',
  apiBaseUrl: 'https://api.test.example',
);

const testBaseUrl = 'https://api.example.test';

/// A login response body in the backend's shape.
String loginBody({List<String> roles = const ['ADMINISTRATOR']}) =>
    jsonEncode({
      'staffName': 'KOFI MENSAH',
      'roles': roles,
      'authToken': 'access-token',
      'refreshToken': 'refresh-token',
    });

/// The backend's standard error body.
String errorBody(int status, String message, {Map<String, String>? errors}) =>
    jsonEncode({
      'timestamp': '2026-11-13T12:00:00Z',
      'status': status,
      'error': 'Error',
      'message': message,
      'path': '/api/auth/v1/login',
      if (errors != null) 'errors': errors,
    });

/// An [AuthApi] whose login endpoint always answers with [status] and
/// [body]. [requests] collects what the app sent.
AuthApi fakeAuthApi(
  int status,
  String body, {
  List<http.Request>? requests,
}) {
  return AuthApi(
    baseUrl: testBaseUrl,
    client: MockClient((request) async {
      requests?.add(request);
      return http.Response(body, status,
          headers: {'content-type': 'application/json'});
    }),
  );
}

/// An [AuthApi] for session tests. Login always succeeds with [loginRoles];
/// the refresh endpoint answers with [refresh] each time it's called.
/// [calls] counts the refresh calls. [delay] holds each answer back, so tests
/// can make requests overlap.
class FakeRefreshApi {
  FakeRefreshApi(
    this.refresh, {
    this.delay = Duration.zero,
    this.loginRoles = const ['ADMINISTRATOR'],
  });

  /// Status and body to answer with. Change it between calls if needed.
  (int, String) refresh;
  final Duration delay;
  final List<String> loginRoles;
  int calls = 0;

  /// When true, the refresh call fails as if there were no connection.
  bool offline = false;

  late final AuthApi api = AuthApi(
    baseUrl: testBaseUrl,
    client: MockClient((request) async {
      if (request.url.path.endsWith('/refresh-token')) {
        calls++;
        if (delay > Duration.zero) await Future<void>.delayed(delay);
        if (offline) throw http.ClientException('no connection');
        final (status, body) = refresh;
        return http.Response(body, status);
      }
      return http.Response(loginBody(roles: loginRoles), 200);
    }),
  );

  /// The backend sends the new access token as the bare response body.
  static (int, String) issues(String token) => (200, token);

  static (int, String) refuses() =>
      (401, errorBody(401, 'Invalid refresh token'));
}

/// A signed-in administrator, for widget tests that need a session.
const adminSession = AuthSession(
  staffId: 'STF0012',
  staffName: 'KOFI MENSAH',
  roles: ['ADMINISTRATOR'],
  accessToken: 'access-token',
  refreshToken: 'refresh-token',
);
