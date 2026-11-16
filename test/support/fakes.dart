import 'dart:convert';
import 'dart:typed_data';

import 'package:cash_client_desktop/api/apis.dart';
import 'package:cash_client_desktop/auth/auth_api.dart';
import 'package:cash_client_desktop/auth/auth_session.dart';
import 'package:cash_client_desktop/branches/branch_api.dart';
import 'package:cash_client_desktop/members/member_api.dart';
import 'package:cash_client_desktop/settings/app_info.dart';
import 'package:cash_client_desktop/settings/theme_mode_store.dart';
import 'package:cash_client_desktop/shell/sidebar_state_store.dart';
import 'package:cash_client_desktop/staff/staff_api.dart';
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
String loginBody({
  List<String> roles = const ['ADMINISTRATOR'],
  String refreshToken = 'refresh-token',
}) =>
    jsonEncode({
      'staffName': 'KOFI MENSAH',
      'roles': roles,
      'authToken': 'access-token',
      'refreshToken': refreshToken,
    });

/// The backend's standard error body.
String errorBody(int status, String message, {Map<String, String>? errors}) =>
    jsonEncode({
      'timestamp': '2026-11-13T12:00:00Z',
      'status': status,
      'error': 'Error',
      'message': message,
      'path': '/api/auth/v1/staff-login',
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

  /// The refresh tokens sent to the logout endpoint, in order.
  final loggedOut = <String>[];

  /// The refresh tokens sent to the refresh endpoint, in order.
  final refreshedWith = <String>[];

  int _logins = 0;

  late final AuthApi api = AuthApi(
    baseUrl: testBaseUrl,
    client: MockClient((request) async {
      if (request.url.path.endsWith('/logout')) {
        loggedOut.add((jsonDecode(request.body) as Map)['refreshToken'] as String);
        return http.Response('', 204);
      }
      if (request.url.path.endsWith('/refresh-staff-token')) {
        calls++;
        refreshedWith
            .add((jsonDecode(request.body) as Map)['refreshToken'] as String);
        if (delay > Duration.zero) await Future<void>.delayed(delay);
        if (offline) throw http.ClientException('no connection');
        final (status, body) = refresh;
        return http.Response(body, status);
      }
      // Each sign-in gets its own refresh token: refresh-token, then
      // refresh-token-2, and so on.
      _logins++;
      return http.Response(
        loginBody(
          roles: loginRoles,
          refreshToken: _logins == 1 ? 'refresh-token' : 'refresh-token-$_logins',
        ),
        200,
      );
    }),
  );

  /// An older backend: the new access token as the bare response body, and
  /// the refresh token kept.
  static (int, String) issues(String token) => (200, token);

  /// The current backend: a new access token and a replacement refresh
  /// token (rotation).
  static (int, String) rotates(String accessToken, String refreshToken) => (
        200,
        jsonEncode({'authToken': accessToken, 'refreshToken': refreshToken}),
      );

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

/// The branch list a fake backend sends.
String defaultBranchesJson() => jsonEncode([
      {'id': 'b-tarkwa', 'name': 'Tarkwa', 'location': 'Tarkwa Market'},
      {'id': 'b-accra', 'name': 'Accra'},
    ]);

/// A staff backend: lists [branches] and answers add-staff with
/// [addStatus] and [addBody]. [requests] collects what the app sent.
class FakeStaffBackend {
  FakeStaffBackend({
    this.branchesStatus = 200,
    this.addStatus = 200,
    this.addBody = '',
  });

  int branchesStatus;
  int addStatus;
  String addBody;
  final requests = <http.Request>[];

  String branches = defaultBranchesJson();

  late final http.Client _client = MockClient((request) async {
    requests.add(request);
    if (request.url.path.endsWith(BranchApi.branchesPath)) {
      return http.Response(
        branchesStatus == 200 ? branches : errorBody(branchesStatus, 'Not found'),
        branchesStatus,
      );
    }
    if (request.url.path.endsWith('/api/staff/v1/add-staff')) {
      return http.Response(addBody, addStatus);
    }
    return http.Response(errorBody(404, 'Not found'), 404);
  });

  late final StaffApi api = StaffApi(baseUrl: testBaseUrl, client: _client);
  late final BranchApi branchApi =
      BranchApi(baseUrl: testBaseUrl, client: _client);

  /// The JSON body of the last add-staff request.
  Map<String, dynamic> get lastAdd => jsonDecode(
        requests.lastWhere((r) => r.url.path.endsWith('/add-staff')).body,
      ) as Map<String, dynamic>;
}

/// What a fake member backend saw of one upload.
class SeenUpload {
  SeenUpload(this.fields, this.fileField, this.fileName, this.fileBytes,
      this.contentType);

  final Map<String, String> fields;
  final String? fileField;
  final String? fileName;
  final List<int> fileBytes;
  final String? contentType;
}

/// A member backend. Each call to add-member or the ID upload takes the
/// next answer from [addAnswers] or [uploadAnswers]; when those run out it
/// answers 200. An answer of null means the connection drops.
class FakeMemberBackend {
  FakeMemberBackend({this.branchesStatus = 200});

  int branchesStatus;
  String branches = defaultBranchesJson();
  final addAnswers = <(int, String)?>[];
  final uploadAnswers = <(int, String)?>[];

  final addBodies = <Map<String, dynamic>>[];
  final uploads = <SeenUpload>[];
  int branchCalls = 0;

  /// Member details by id; an unknown id gets 404.
  final profiles = <String, Map<String, dynamic>>{};
  int detailCalls = 0;

  /// What search answers: these results (whatever the query) or, when
  /// [searchStatus] isn't 200, an error. [searches] records (query, page).
  int searchStatus = 200;
  List<Map<String, dynamic>> searchResults = [];
  int? searchTotal;
  final searches = <(String, int)>[];

  /// A member's details in the backend's shape (section 18).
  static Map<String, dynamic> profileJson({
    String id = newMemberId,
    String kycStatus = 'NOT_SUBMITTED',
    bool canUpload = true,
    bool limited = false,
    bool withKyc = true,
  }) =>
      {
        'memberId': id,
        'firstName': 'Ama',
        'middleName': null,
        'lastName': 'Mensah',
        'phoneNumber': '0241234567',
        if (!limited) ...{
          'dateOfBirth': '1990-07-04',
          'residentialAddress': 'Hse 3, Tarkwa',
          'occupation': 'Trader',
          'registeredByStaffId': 'STF0012',
          'createdAt': '2026-11-16T10:15:30.123',
        },
        'membershipStatus': 'PENDING',
        'branchId': 'b-tarkwa',
        'branchName': 'Tarkwa',
        'detailLevel': limited ? 'LIMITED' : 'FULL',
        if (withKyc && !limited)
          'kyc': {
            'status': kycStatus,
            'documentType': kycStatus == 'NOT_SUBMITTED' ? null : 'ECOWAS_CARD',
            'rejectionReason':
                kycStatus == 'REJECTED' ? 'The picture is blurred' : null,
            'canUpload': canUpload,
          },
        'accounts': [
          {'accountNumber': '1001234', 'accountType': 'SHARES', 'status': 'INACTIVE'},
          {'accountNumber': '2004567', 'accountType': 'SAVINGS', 'status': 'INACTIVE'},
        ],
      };

  static Map<String, dynamic> summaryJson(String id, String first,
          {String status = 'ACTIVE', String phone = '0201112223'}) =>
      {
        'memberId': id,
        'firstName': first,
        'middleName': null,
        'lastName': 'Mensah',
        'phoneNumber': phone,
        'branchName': 'Tarkwa',
        'membershipStatus': status,
      };

  static const newMemberId = '7b0c3c3e-1a4f-4c5e-9d0e-2f6a1b8c9d10';
  static String addOk([String id = newMemberId]) =>
      jsonEncode({'status': 'success', 'Id': id});
  static const uploadOk =
      '{"status":"success","message":"reviewing Kyc information"}';

  late final http.Client _client = MockClient.streaming((request, body) async {
    final path = request.url.path;
    if (path.endsWith(BranchApi.branchesPath)) {
      branchCalls++;
      return _stream(
        branchesStatus,
        branchesStatus == 200 ? branches : errorBody(branchesStatus, 'Nope'),
      );
    }
    if (path.endsWith(MemberApi.addMemberPath)) {
      final text = await body.bytesToString();
      addBodies.add(jsonDecode(text) as Map<String, dynamic>);
      final answer = addAnswers.isEmpty ? (200, addOk()) : addAnswers.removeAt(0);
      if (answer == null) throw http.ClientException('connection dropped');
      return _stream(answer.$1, answer.$2);
    }
    if (path.endsWith(MemberApi.searchPath)) {
      final query = request.url.queryParameters['query'] ?? '';
      final page = int.parse(request.url.queryParameters['page'] ?? '0');
      searches.add((query, page));
      if (searchStatus != 200) {
        return _stream(searchStatus, errorBody(searchStatus, 'Not found'));
      }
      return _stream(
        200,
        jsonEncode({
          'items': searchResults,
          'page': page,
          'size': MemberApi.pageSize,
          'total': searchTotal ?? searchResults.length,
        }),
      );
    }
    if (path.contains('${MemberApi.memberDetailsPath}/')) {
      detailCalls++;
      final id = path.split('/').last;
      final profile = profiles[id];
      return profile == null
          ? _stream(404, errorBody(404, 'The requested resource was not found'))
          : _stream(200, jsonEncode(profile));
    }
    if (path.endsWith(MemberApi.kycUploadPath)) {
      uploads.add(await _readMultipart(request, body));
      final answer =
          uploadAnswers.isEmpty ? (200, uploadOk) : uploadAnswers.removeAt(0);
      if (answer == null) throw http.ClientException('connection dropped');
      return _stream(answer.$1, answer.$2);
    }
    return _stream(404, errorBody(404, 'Not found'));
  });

  late final MemberApi api = MemberApi(baseUrl: testBaseUrl, client: _client);
  late final BranchApi branchApi =
      BranchApi(baseUrl: testBaseUrl, client: _client);

  static http.StreamedResponse _stream(int status, String body) =>
      http.StreamedResponse(Stream.value(utf8.encode(body)), status);

  /// A small multipart reader, enough for the fields and one file the app
  /// sends.
  static Future<SeenUpload> _readMultipart(
    http.BaseRequest request,
    http.ByteStream body,
  ) async {
    final bytes = await body.toBytes();
    final type = request.headers['content-type'] ?? '';
    final boundary = RegExp(r'boundary=(.+)$').firstMatch(type)!.group(1)!;
    final text = latin1.decode(bytes);
    final fields = <String, String>{};
    String? fileField;
    String? fileName;
    String? contentType;
    var fileBytes = <int>[];
    for (final part in text.split('--$boundary')) {
      final split = part.indexOf('\r\n\r\n');
      if (split < 0) continue;
      final headers = part.substring(0, split);
      var content = part.substring(split + 4);
      if (content.endsWith('\r\n')) {
        content = content.substring(0, content.length - 2);
      }
      final name = RegExp(r'name="([^"]*)"').firstMatch(headers)?.group(1);
      final file = RegExp(r'filename="([^"]*)"').firstMatch(headers)?.group(1);
      if (name == null) continue;
      if (file != null) {
        fileField = name;
        fileName = file;
        contentType = RegExp(r'content-type: (\S+)', caseSensitive: false)
            .firstMatch(headers)
            ?.group(1);
        fileBytes = latin1.encode(content);
      } else {
        fields[name] = content;
      }
    }
    return SeenUpload(fields, fileField, fileName, fileBytes, contentType);
  }
}

/// A tiny but valid-looking PNG header, enough for the type check.
final pngBytes = Uint8List.fromList(
    [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3, 4]);

/// The start of a JPEG file.
final jpegBytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 5, 6, 7]);

/// APIs on fake backends, for widget tests that only need the app to start.
Apis fakeApis() {
  final staff = FakeStaffBackend();
  return Apis(
    staff: staff.api,
    members: FakeMemberBackend().api,
    branches: staff.branchApi,
  );
}
