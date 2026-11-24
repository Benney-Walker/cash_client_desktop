import 'dart:convert';
import 'dart:typed_data';

import 'package:cash_client_desktop/api/apis.dart';
import 'package:cash_client_desktop/approvals/approval_api.dart';
import 'package:cash_client_desktop/auth/auth_api.dart';
import 'package:cash_client_desktop/auth/auth_session.dart';
import 'package:cash_client_desktop/branches/branch_api.dart';
import 'package:cash_client_desktop/collectors/collector_api.dart';
import 'package:cash_client_desktop/dashboard/dashboard_api.dart';
import 'package:cash_client_desktop/loans/loan_api.dart';
import 'package:cash_client_desktop/members/member_api.dart';
import 'package:cash_client_desktop/settings/app_info.dart';
import 'package:cash_client_desktop/settings/theme_mode_store.dart';
import 'package:cash_client_desktop/shell/sidebar_state_store.dart';
import 'package:cash_client_desktop/staff/staff_api.dart';
import 'package:cash_client_desktop/submissions/submission_api.dart';
import 'package:cash_client_desktop/transactions/transaction_api.dart';
import 'package:cash_client_desktop/transactions/transaction_models.dart';
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

  /// The roles each sign-in gets; change it to simulate an administrator
  /// changing them between sign-ins.
  List<String> loginRoles;
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

/// A signed-in agent, for widget tests that need one.
const agentSession = AuthSession(
  staffId: 'STF0020',
  staffName: 'EFUA ASANTE',
  roles: ['AGENT'],
  accessToken: 'access-token',
  refreshToken: 'refresh-token',
);

/// A signed-in administrator, for widget tests that need a session.
const adminSession = AuthSession(
  staffId: 'STF0012',
  staffName: 'KOFI MENSAH',
  roles: ['ADMINISTRATOR'],
  accessToken: 'access-token',
  refreshToken: 'refresh-token',
);

/// A page as the backend sends it (Spring's `PagedModel`), with
/// [MemberApi.pageSize] items a page.
String pagedJson(
  List<Map<String, dynamic>> content, {
  int page = 0,
  int? total,
  int size = MemberApi.pageSize,
}) {
  final all = total ?? content.length;
  return jsonEncode({
    'content': content,
    'page': {
      'size': size,
      'number': page,
      'totalElements': all,
      'totalPages': all == 0 ? 0 : (all + size - 1) ~/ size,
    },
  });
}

/// The branch list a fake backend sends.
String defaultBranchesJson() => jsonEncode([
      {'id': 'b-tarkwa', 'name': 'Tarkwa', 'location': 'Tarkwa Market'},
      {'id': 'b-accra', 'name': 'Accra'},
    ]);

/// A staff backend: lists [branches] and answers add-staff with
/// [addStatus] and [addBody]. [requests] collects what the app sent.
/// A staff record as the backend sends it (`StaffResponse`).
Map<String, Object?> staffJson(
  String staffId,
  String firstName,
  String lastName, {
  List<String> roles = const ['AGENT'],
  String status = 'ACTIVE',
  String branchName = 'Tarkwa Market',
  String? lockedAt,
  String? deviceRegisteredAt,
}) =>
    {
      'staffId': staffId,
      'firstName': firstName,
      'middleName': null,
      'lastName': lastName,
      'dateOfBirth': '1990-05-04',
      'phoneNumber': '+233241234567',
      'email': '${firstName.toLowerCase()}@example.com',
      'residentialAddress': 'Hse 4, Tarkwa',
      'branchId': 'b-1',
      'branchName': branchName,
      'deviceRegisteredAt': deviceRegisteredAt,
      'lockedAt': lockedAt,
      'status': status,
      'roles': roles,
    };

/// A staff backend: add-staff, the branch list, and the staff list with
/// its actions. The actions change [staff] the way the backend does. Set
/// [actionStatus] to make every action fail with that status and
/// [actionMessage].
class FakeStaffBackend {
  FakeStaffBackend({
    this.branchesStatus = 200,
    this.addStatus = 200,
    this.addBody = '',
    List<Map<String, Object?>>? staff,
  }) : staff = staff ?? defaultStaff();

  int branchesStatus;
  int addStatus;
  String addBody;
  int listStatus = 200;
  int? actionStatus;
  String actionMessage = 'Not allowed';

  /// When false, reading a record back after a release fails.
  bool detailsWork = true;

  final requests = <http.Request>[];
  final List<Map<String, Object?>> staff;

  String branches = defaultBranchesJson();

  static List<Map<String, Object?>> defaultStaff() => [
        staffJson('STF0012', 'Kofi', 'Mensah', roles: ['ADMINISTRATOR']),
        staffJson('STF0020', 'Efua', 'Asante'),
        staffJson('STF0031', 'Yaw', 'Boateng',
            roles: ['COLLECTOR'], deviceRegisteredAt: '2026-11-02T09:15:00'),
        staffJson('STF0044', 'Akosua', 'Darko',
            roles: ['COLLECTOR'], lockedAt: '2026-11-23T16:40:00'),
        staffJson('STF0050', 'Kwame', 'Owusu', status: 'INACTIVE'),
      ];

  Map<String, Object?>? _find(String id) {
    for (final s in staff) {
      if (s['staffId'] == id) return s;
    }
    return null;
  }

  http.Response _record(Map<String, Object?> s) =>
      http.Response(jsonEncode(s), 200);

  late final http.Client _client = MockClient((request) async {
    requests.add(request);
    final path = request.url.path;
    final id = Uri.decodeComponent(request.url.pathSegments.last);
    if (path.endsWith(BranchApi.branchesPath)) {
      return http.Response(
        branchesStatus == 200 ? branches : errorBody(branchesStatus, 'Not found'),
        branchesStatus,
      );
    }
    if (path.endsWith('/api/staff/v1/add-staff')) {
      return http.Response(addBody, addStatus);
    }
    if (path.endsWith('/api/staff/v1/all-staff')) {
      return listStatus == 200
          ? http.Response(jsonEncode(staff), 200)
          : http.Response(errorBody(listStatus, 'Failed'), listStatus);
    }
    if (path.contains('/api/staff/v1/staff-details/')) {
      final s = _find(id);
      if (s == null || !detailsWork) {
        return http.Response(errorBody(404, 'Not found'), 404);
      }
      return _record(s);
    }

    // Actions. The release path ends in "release-device", the unlock path
    // in "unlock"; the staff ID is the segment before.
    final segments = request.url.pathSegments;
    final actionId = path.endsWith('/release-device') || path.endsWith('/unlock')
        ? Uri.decodeComponent(segments[segments.length - 2])
        : id;
    final s = _find(actionId);
    if (s == null) return http.Response(errorBody(404, 'Not found'), 404);
    final failing = actionStatus;
    if (failing != null) {
      return http.Response(errorBody(failing, actionMessage), failing);
    }
    if (path.contains('/update-staff/')) {
      s.addAll((jsonDecode(request.body) as Map<String, dynamic>)
        ..remove('middleName'));
      return _record(s);
    }
    if (path.contains('/update-roles/')) {
      s['roles'] = (jsonDecode(request.body) as Map<String, dynamic>)['roles'];
      return _record(s);
    }
    if (path.contains('/deactivate/')) {
      s['status'] = 'INACTIVE';
      return _record(s);
    }
    if (path.contains('/reactivate/')) {
      s['status'] = 'ACTIVE';
      return _record(s);
    }
    if (path.endsWith('/unlock')) {
      s['lockedAt'] = null;
      return _record(s);
    }
    if (path.endsWith('/release-device')) {
      s['deviceRegisteredAt'] = null;
      return http.Response('', 204);
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

  /// The paths of the requests other than the list and branch reads.
  List<String> get actionPaths => [
        for (final r in requests)
          if (!r.url.path.endsWith('/all-staff') &&
              !r.url.path.endsWith(BranchApi.branchesPath))
            '${r.method} ${r.url.path}',
      ];
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
/// A member update request as the backend sends it
/// (`MemberUpdateProposalResponse`).
Map<String, dynamic> updateRequestJson({
  String requestId = 'req-1',
  String memberId = FakeMemberBackend.newMemberId,
  String memberName = 'Ama Mensah',
  String status = 'PENDING',
  Map<String, dynamic>? current,
  Map<String, dynamic>? proposed,
  String requestedBy = 'STF0020',
  String? reviewedBy,
  String? rejectionReason,
}) {
  Map<String, dynamic> values(Map<String, dynamic>? from, String phone,
          String address, String job) =>
      {
        'phoneNumber': from?['phoneNumber'] ?? phone,
        'residentialAddress': from?['residentialAddress'] ?? address,
        'occupation': from?['occupation'] ?? job,
      };
  return {
    'requestId': requestId,
    'memberId': memberId,
    'memberName': memberName,
    'branchName': 'Tarkwa',
    'status': status,
    'current': values(current, '0241234567', 'Hse 3, Tarkwa', 'Trader'),
    'proposed': values(proposed, '0559998887', 'Hse 3, Tarkwa', 'Trader'),
    'requestedByStaffId': requestedBy,
    'requestedAt': '2026-11-24T09:30:00',
    'reviewedByStaffId': reviewedBy,
    'reviewedAt': reviewedBy == null ? null : '2026-11-24T11:00:00',
    'rejectionReason': rejectionReason,
  };
}

/// An ID document record as the backend sends it (`KycRecordResponse`).
Map<String, dynamic> kycRecordJson(
  String memberId,
  String firstName, {
  String status = 'MANUAL_REVIEW',
  String? reason = 'The name could not be read',
}) =>
    {
      'memberId': memberId,
      'firstName': firstName,
      'lastName': 'Owusu',
      'documentType': 'ECOWAS_CARD',
      'idNumber': 'GHA-123456789-0',
      'status': status,
      'reason': reason,
      'verificationMethod': null,
      'reviewedByStaffId': null,
      'registeredByStaffId': 'STF0020',
      'submittedAt': '2026-11-22T10:15:00',
      'verifiedAt': null,
    };

/// The Administrators' review backend: the ID document queue, the ID
/// picture, member update requests, and approve/reject for both. Reviews
/// change the records the way the backend does. Set [actionStatus] to make
/// every review fail with that status and [actionMessage].
class FakeApprovalBackend {
  FakeApprovalBackend({List<Map<String, dynamic>>? kyc, List<Map<String, dynamic>>? updates})
      : kyc = kyc ??
            [
              kycRecordJson('m-1', 'Ama'),
              kycRecordJson('m-2', 'Kojo'),
              kycRecordJson('m-3', 'Esi', status: 'VERIFIED', reason: null),
            ],
        updates = updates ??
            [
              updateRequestJson(requestId: 'req-1', memberId: 'm-1'),
              updateRequestJson(
                requestId: 'req-2',
                memberId: 'm-4',
                memberName: 'Yaw Mensah',
                status: 'REJECTED',
                reviewedBy: 'STF0012',
                rejectionReason: 'Wrong number',
              ),
            ];

  final List<Map<String, dynamic>> kyc;
  final List<Map<String, dynamic>> updates;
  int listStatus = 200;
  int pictureStatus = 200;
  int? actionStatus;
  String actionMessage = 'Not allowed';

  /// A tiny valid PNG (1x1).
  static final pictureBytes = Uint8List.fromList(const [
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
    0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
    0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
    0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
  ]);

  final requests = <http.Request>[];

  /// Each review request, as "METHOD path".
  List<String> get actionPaths => [
        for (final r in requests)
          if (r.method == 'POST') 'POST ${r.url.path}',
      ];

  int get pictureCalls =>
      requests.where((r) => r.url.path.contains('/kyc-document/')).length;

  late final http.Client _client = MockClient((request) async {
    requests.add(request);
    final path = request.url.path;
    final q = request.url.queryParameters;
    final segments = request.url.pathSegments;
    if (path.endsWith(ApprovalApi.kycReviewsPath)) {
      if (listStatus != 200) {
        return http.Response(errorBody(listStatus, 'Failed'), listStatus);
      }
      final status = q['status'] ?? 'MANUAL_REVIEW';
      final size = int.parse(q['size'] ?? '20');
      final page = int.parse(q['page'] ?? '0');
      final matching = kyc.where((r) => r['status'] == status).toList();
      return http.Response(
        pagedJson(matching.skip(page * size).take(size).toList(),
            page: page, total: matching.length, size: size),
        200,
      );
    }
    if (path.contains('${ApprovalApi.kycDocumentPath}/')) {
      if (pictureStatus != 200) {
        return http.Response(errorBody(pictureStatus, 'Nope'), pictureStatus);
      }
      return http.Response.bytes(pictureBytes, 200,
          headers: {'content-type': 'image/png'});
    }
    if (path.endsWith(ApprovalApi.updatesPath)) {
      if (listStatus != 200) {
        return http.Response(errorBody(listStatus, 'Failed'), listStatus);
      }
      final status = q['status'] ?? 'PENDING';
      final size = int.parse(q['size'] ?? '20');
      final matching = updates.where((r) => r['status'] == status).toList();
      return http.Response(
        pagedJson(matching.take(size).toList(),
            total: matching.length, size: size),
        200,
      );
    }
    final failing = actionStatus;
    if (failing != null) {
      return http.Response(errorBody(failing, actionMessage), failing);
    }
    if (path.contains('${ApprovalApi.kycApprovePath}/') ||
        path.contains('${ApprovalApi.kycRejectPath}/')) {
      final record = kyc.where((r) => r['memberId'] == segments.last).firstOrNull;
      if (record == null) return http.Response(errorBody(404, 'Nope'), 404);
      final approve = path.contains(ApprovalApi.kycApprovePath);
      record['status'] = approve ? 'VERIFIED' : 'REJECTED';
      if (!approve) {
        record['reason'] =
            (jsonDecode(request.body) as Map<String, dynamic>)['reason'];
      }
      return http.Response('{"status":"success"}', 200);
    }
    if (path.startsWith('${ApprovalApi.updatesPath}/')) {
      final id = segments[segments.length - 2];
      final record = updates.where((r) => r['requestId'] == id).firstOrNull;
      if (record == null) return http.Response(errorBody(404, 'Nope'), 404);
      final approve = segments.last == 'approve';
      record['status'] = approve ? 'APPROVED' : 'REJECTED';
      record['reviewedByStaffId'] = 'STF0012';
      if (!approve) {
        record['rejectionReason'] =
            (jsonDecode(request.body) as Map<String, dynamic>)['reason'];
      }
      return http.Response(jsonEncode(record), 200);
    }
    return http.Response(errorBody(404, 'Not found'), 404);
  });

  late final ApprovalApi api = ApprovalApi(baseUrl: testBaseUrl, client: _client);

  /// The JSON body of the last request to [pathPart].
  Map<String, dynamic> lastBody(String pathPart) => jsonDecode(
        requests.lastWhere((r) => r.url.path.contains(pathPart)).body,
      ) as Map<String, dynamic>;
}

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

  /// Contact changes: each direct edit or request takes the next answer
  /// from [contactAnswers]; when those run out it succeeds (a direct edit
  /// updates [profiles], a request answers a waiting record).
  /// [dropNextContact] makes the next one lose its connection.
  /// [contactCalls] records ("PUT"/"POST", body).
  final contactAnswers = <(int, String)>[];
  final contactCalls = <(String, Map<String, dynamic>)>[];

  /// The signed-in staff member's own requests, newest first.
  List<Map<String, dynamic>> myRequests = [];
  int myRequestsStatus = 200;

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
          {String status = 'ACTIVE', String? phone = '0201112223'}) =>
      {
        'memberId': id,
        'firstName': first,
        'middleName': null,
        'lastName': 'Mensah',
        'phoneNumber': phone,
        'branchId': 'b-tarkwa',
        'branchName': 'Tarkwa',
        'membershipStatus': status,
        'accounts': [
          {'accountNumber': '1009$id', 'accountType': 'SHARES', 'status': 'ACTIVE'},
        ],
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
      final total = searchTotal ?? searchResults.length;
      return _stream(200, pagedJson(searchResults, page: page, total: total));
    }
    if (path.contains('${MemberApi.memberDetailsPath}/')) {
      detailCalls++;
      final id = path.split('/').last;
      final profile = profiles[id];
      return profile == null
          ? _stream(404, errorBody(404, 'The requested resource was not found'))
          : _stream(200, jsonEncode(profile));
    }
    if (path.contains('${MemberApi.adminUpdateMemberPath}/') ||
        (path.contains('${MemberApi.updateRequestsPath}/') &&
            request.method == 'POST')) {
      final id = path.split('/').last;
      final sent = jsonDecode(await body.bytesToString()) as Map<String, dynamic>;
      contactCalls.add((request.method, sent));
      if (_dropNext) {
        _dropNext = false;
        throw http.ClientException('connection dropped');
      }
      final answer = contactAnswers.isEmpty ? null : contactAnswers.removeAt(0);
      if (answer != null) return _stream(answer.$1, answer.$2);
      final profile = profiles[id] ?? profileJson(id: id);
      if (request.method == 'PUT') {
        profile.addAll(sent);
        profiles[id] = profile;
        return _stream(200, jsonEncode(profile));
      }
      return _stream(
        200,
        jsonEncode(updateRequestJson(
          memberId: id,
          current: profile,
          proposed: sent,
        )),
      );
    }
    if (path.endsWith('${MemberApi.updateRequestsPath}/mine')) {
      if (myRequestsStatus != 200) {
        return _stream(myRequestsStatus, errorBody(myRequestsStatus, 'Nope'));
      }
      return _stream(200, pagedJson(myRequests, size: 100));
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

  bool _dropNext = false;

  /// Makes the next contact change lose its connection.
  void dropNextContact() => _dropNext = true;

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
    transactions: FakeTransactionBackend().api,
    submissions: FakeSubmissionBackend().api,
    approvals: FakeApprovalBackend().api,
    dashboard: FakeDashboardBackend().api,
    collectors: FakeCollectorBackend().api,
    loans: FakeLoanBackend().api,
  );
}

/// A loan product as the backend sends it (`LoanProductResponse`).
Map<String, dynamic> productJson({
  int id = 1,
  String name = 'Salary advance',
  num rate = 24.00,
  num min = 500,
  num max = 5000,
  int maxTerm = 12,
  String feeType = 'PERCENTAGE',
  num fee = 2.00,
  int guarantors = 1,
  bool active = true,
}) =>
    {
      'id': id,
      'name': name,
      'interestRatePercent': rate,
      'minAmount': min,
      'maxAmount': max,
      'maxTermMonths': maxTerm,
      'processingFeeType': feeType,
      'processingFeeValue': fee,
      'guarantorsRequired': guarantors,
      'active': active,
      'updatedAt': '2026-11-24T08:00:00',
      'updatedBy': 'STF0012',
    };

/// A loan application as the backend sends it (`LoanApplicationResponse`).
Map<String, dynamic> loanApplicationJson({
  String id = 'app-1',
  String memberId = 'm-1',
  String memberName = 'Ama Owusu',
  int productId = 1,
  String productName = 'Salary advance',
  num amount = 2000,
  int term = 6,
  String status = 'PENDING',
  List<Map<String, dynamic>>? guarantors,
  String? rejectionReason,
  num? approvedAmount,
}) =>
    {
      'id': id,
      'memberId': memberId,
      'memberName': memberName,
      'branchName': 'Tarkwa',
      'productId': productId,
      'productName': productName,
      'requestedAmount': amount,
      'termMonths': term,
      'approvedAmount': approvedAmount,
      'purpose': 'School fees',
      'status': status,
      'rejectionReason': rejectionReason,
      'appliedBy': 'STF0020',
      'reviewedBy': status == 'PENDING' ? null : 'STF0012',
      'createdAt': '2026-11-24T09:00:00',
      'reviewedAt': status == 'PENDING' ? null : '2026-11-24T10:00:00',
      'guarantors': guarantors,
      'loanId': status == 'APPROVED' ? 'loan-1' : null,
    };

/// A loan as the backend sends it (`LoanResponse`).
Map<String, dynamic> loanJson({
  String id = 'loan-1',
  String memberId = 'm-1',
  String status = 'ACTIVE',
  num outstanding = 1866.65,
  num overdue = 0,
}) =>
    {
      'id': id,
      'applicationId': 'app-0',
      'memberId': memberId,
      'memberName': 'Ama Owusu',
      'accountNumber': '2004567891',
      'productName': 'Salary advance',
      'amount': 2000,
      'interestRatePercent': 24.00,
      'totalInterest': 240,
      'totalToRepay': 2240,
      'processingFee': 40,
      'termMonths': 6,
      'disbursementDate': '2026-10-24',
      'maturityDate': '2027-04-24',
      'status': status,
      'paid': 373.33,
      'outstanding': outstanding,
      'overdue': overdue,
      'installments': [
        {'number': 1, 'dueDate': '2026-11-24', 'amount': 373.33, 'paid': 373.33, 'remaining': 0, 'status': 'PAID'},
        {'number': 2, 'dueDate': '2026-12-24', 'amount': 373.33, 'paid': 0, 'remaining': 373.33, 'status': 'PENDING'},
      ],
    };

/// The loan endpoints: products (and the Administrators' edits),
/// applications (apply, list, read, approve, reject), a member's loans, one
/// loan, and the portfolio's active loans. Reviews change the records the
/// way the backend does. [actionStatus] makes applying and reviewing fail
/// with that status and [actionMessage]; [dropApply] loses the next
/// apply's answer.
class FakeLoanBackend {
  FakeLoanBackend();

  final requests = <http.Request>[];
  int? actionStatus;
  String actionMessage = 'Not allowed';
  bool dropApply = false;

  List<Map<String, dynamic>> products = [
    productJson(),
    productJson(id: 2, name: 'Emergency loan', rate: 30, min: 100, max: 1000,
        maxTerm: 3, feeType: 'FLAT', fee: 10, guarantors: 0, active: false),
  ];
  final applications = <Map<String, dynamic>>[
    loanApplicationJson(guarantors: [
      {'memberId': 'm-9', 'name': 'Kofi Mensah'},
    ]),
    loanApplicationJson(id: 'app-2', memberId: 'm-2', memberName: 'Kojo Addo',
        amount: 800, term: 3, status: 'REJECTED', rejectionReason: 'Too soon'),
  ];
  final memberLoans = <String, List<Map<String, dynamic>>>{
    'm-1': [loanJson()],
  };
  List<Map<String, dynamic>> portfolio = [
    {
      'loanId': 'loan-1',
      'memberId': 'm-1',
      'memberName': 'Ama Owusu',
      'branchName': 'Tarkwa',
      'productName': 'Salary advance',
      'disbursementDate': '2026-10-24',
      'amount': 2000,
      'totalToRepay': 2240,
      'paid': 373.33,
      'outstanding': 1866.65,
      'overdue': 0,
      'nextDueDate': '2026-12-24',
    },
    {
      'loanId': 'loan-2',
      'memberId': 'm-5',
      'memberName': 'Esi Boateng',
      'branchName': 'Accra',
      'productName': 'Salary advance',
      'disbursementDate': '2026-08-01',
      'amount': 1000,
      'totalToRepay': 1100,
      'paid': 200,
      'outstanding': 900,
      'overdue': 183.33,
      'nextDueDate': '2026-11-01',
    },
  ];

  /// The JSON body of the last request whose path ends with [ending].
  Map<String, dynamic>? lastBody(String ending) {
    final r = requests.lastWhere((r) => r.url.path.endsWith(ending));
    return r.body.isEmpty ? null : jsonDecode(r.body) as Map<String, dynamic>;
  }

  List<String> get posts => [
        for (final r in requests)
          if (r.method != 'GET') '${r.method} ${r.url.path}',
      ];

  late final http.Client _client = MockClient((request) async {
    requests.add(request);
    final path = request.url.path;
    final segments = request.url.pathSegments;
    final q = request.url.queryParameters;
    http.Response json(Object body, [int status = 200]) =>
        http.Response(jsonEncode(body), status);

    if (path == LoanApi.productsPath) return json(products);
    if (path.startsWith(LoanApi.adminProductsPath)) {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final isNew = request.method == 'POST';
      final id = isNew ? products.length + 1 : int.parse(segments.last);
      final saved = productJson(
        id: id,
        name: body['name'] as String,
        rate: body['interestRatePercent'] as num,
        min: body['minAmount'] as num,
        max: body['maxAmount'] as num,
        maxTerm: body['maxTermMonths'] as int,
        feeType: body['processingFeeType'] as String,
        fee: body['processingFeeValue'] as num,
        guarantors: body['guarantorsRequired'] as int,
        active: body['active'] as bool,
      );
      products = [...products.where((p) => p['id'] != id), saved];
      return json(saved, isNew ? 201 : 200);
    }
    if (path == LoanApi.applicationsPath && request.method == 'POST') {
      if (dropApply) {
        dropApply = false;
        throw http.ClientException('connection dropped');
      }
      final failing = actionStatus;
      if (failing != null) return http.Response(errorBody(failing, actionMessage), failing);
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final created = loanApplicationJson(
        id: 'app-${applications.length + 1}',
        memberId: body['memberId'] as String,
        productId: body['productId'] as int,
        amount: body['amount'] as num,
        term: body['termMonths'] as int,
      );
      applications.insert(0, created);
      return json(created, 201);
    }
    if (path == LoanApi.applicationsPath) {
      final matching = applications.where((a) =>
          (q['status'] == null || a['status'] == q['status']) &&
          (q['memberId'] == null || a['memberId'] == q['memberId'])).toList();
      return http.Response(pagedJson(matching), 200);
    }
    if (path.startsWith('${LoanApi.applicationsPath}/')) {
      final a = applications.where((a) => a['id'] == segments.last).firstOrNull;
      return a == null ? http.Response(errorBody(404, 'Loan application not found'), 404) : json(a);
    }
    if (path.startsWith('${LoanApi.memberLoansPath}/')) {
      return json(memberLoans[segments[segments.length - 2]] ?? []);
    }
    if (path.startsWith('${LoanApi.loanPath}/')) {
      for (final loans in memberLoans.values) {
        for (final l in loans) {
          if (l['id'] == segments.last) return json(l);
        }
      }
      return json(loanJson(id: segments.last));
    }
    if (path == LoanApi.portfolioPath) {
      return json({'loans': portfolio, 'activeLoans': portfolio.length});
    }
    if (path.startsWith('${LoanApi.adminApplicationsPath}/')) {
      final failing = actionStatus;
      if (failing != null) return http.Response(errorBody(failing, actionMessage), failing);
      final id = segments[segments.length - 2];
      final a = applications.where((a) => a['id'] == id).first;
      final approve = segments.last == 'approve';
      a['status'] = approve ? 'APPROVED' : 'REJECTED';
      a['reviewedBy'] = 'STF0012';
      if (approve) {
        final body = request.body.isEmpty ? null : jsonDecode(request.body) as Map<String, dynamic>;
        a['approvedAmount'] = body?['approvedAmount'] ?? a['requestedAmount'];
        a['loanId'] = 'loan-9';
      } else {
        a['rejectionReason'] = (jsonDecode(request.body) as Map<String, dynamic>)['reason'];
      }
      return json(a);
    }
    return http.Response(errorBody(404, 'Not found'), 404);
  });

  late final LoanApi api = LoanApi(baseUrl: testBaseUrl, client: _client);
}

/// A location point as the backend sends it (`LocationPointResponse`).
Map<String, dynamic> pointJson(
  String time, {
  double lat = 5.3000,
  double lng = -1.9900,
  bool payment = false,
  Map<String, dynamic>? paid,
  int battery = 80,
  String? receivedTime,
}) =>
    {
      'latitude': lat,
      'longitude': lng,
      'accuracyMeters': 12.4,
      'batteryPercent': battery,
      'trigger': payment ? 'PAYMENT' : 'EVERY_5_MIN',
      'recordedAt': '2026-11-25T$time:00',
      'receivedAt': '2026-11-25T${receivedTime ?? time}:05',
      'payment': paid,
    };

/// A payment placed on a point.
Map<String, dynamic> paidJson(num amount, {String member = 'Ama Owusu', String status = 'COMPLETED'}) =>
    {
      'transactionId': 'tx-$amount',
      'type': 'DEPOSIT',
      'amount': amount,
      'status': status,
      'memberName': member,
      'accountNumber': '2004567891',
    };

/// The Collectors endpoints: each collector's trail (by staff ID) and the
/// collector collections report's days.
class FakeCollectorBackend {
  FakeCollectorBackend();

  final requests = <http.Request>[];
  int trailStatus = 200;
  int reportStatus = 200;

  /// Points by collector staff ID; anyone else has none.
  final trails = <String, List<Map<String, dynamic>>>{
    'STF0031': [
      pointJson('08:05', lat: 5.300, lng: -1.990, battery: 92),
      pointJson('08:10', lat: 5.301, lng: -1.989),
      pointJson('09:12', lat: 5.302, lng: -1.988, payment: true, paid: paidJson(100)),
      pointJson('09:17', lat: 5.303, lng: -1.987),
      pointJson('09:40', lat: 5.304, lng: -1.986, payment: true,
          paid: paidJson(50, member: 'Kofi Addo', status: 'FAILED')),
      pointJson('10:02', lat: 5.305, lng: -1.985, payment: true,
          receivedTime: '11:30'),
      pointJson('17:30', lat: 5.306, lng: -1.984, battery: 41),
    ],
  };

  List<Map<String, dynamic>> days = [
    {
      'date': '2026-11-25',
      'collectorStaffId': 'STF0031',
      'collectorName': 'Yaw Boateng',
      'branchName': 'Tarkwa Market',
      'payments': 12,
      'amount': 1250.00,
      'failedPayments': 1,
      'failedAmount': 50.00,
    },
  ];

  List<String> get trailDates => [
        for (final r in requests)
          if (r.url.path.startsWith(CollectorApi.locationsPath))
            '${r.url.pathSegments.last} ${r.url.queryParameters['date']}',
      ];

  late final http.Client _client = MockClient((request) async {
    requests.add(request);
    final path = request.url.path;
    if (path.startsWith('${CollectorApi.locationsPath}/')) {
      if (trailStatus != 200) {
        return http.Response(
            errorBody(trailStatus, 'This collector is from another branch'),
            trailStatus);
      }
      return http.Response(
          jsonEncode(trails[request.url.pathSegments.last] ?? []), 200);
    }
    if (path.endsWith(CollectorApi.collectionsReportPath)) {
      if (reportStatus != 200) {
        return http.Response(errorBody(reportStatus, 'Boom'), reportStatus);
      }
      return http.Response(
        jsonEncode({
          'days': days,
          'submissions': [],
          'collected': 0,
          'expected': 0,
          'counted': 0,
          'surplus': 0,
        }),
        200,
      );
    }
    return http.Response(errorBody(404, 'Not found'), 404);
  });

  late final CollectorApi api = CollectorApi(baseUrl: testBaseUrl, client: _client);
}

/// The endpoints the dashboard reads: the three reports and the lists it
/// counts. [failing] lists path endings that answer 500.
class FakeDashboardBackend {
  FakeDashboardBackend();

  final requests = <http.Request>[];
  final failing = <String>{};

  /// Totals by type, as the transactions report sends them.
  List<Map<String, dynamic>> totals = [
    {'type': 'DEPOSIT', 'count': 4, 'amount': 1500.00, 'fees': 0},
    {'type': 'WITHDRAWAL', 'count': 2, 'amount': 300.00, 'fees': 4.00},
  ];

  /// The list totals by path ending.
  final counts = <String, int>{
    DashboardApi.submissionsPath: 3,
    DashboardApi.kycReviewsPath: 2,
    DashboardApi.memberUpdatesPath: 1,
    DashboardApi.loanApplicationsPath: 1,
    DashboardApi.membersPath: 4,
  };

  /// The query of the last request to [path].
  Map<String, String> lastQuery(String path) =>
      requests.lastWhere((r) => r.url.path.endsWith(path)).url.queryParameters;

  int callsTo(String path) =>
      requests.where((r) => r.url.path.endsWith(path)).length;

  late final http.Client _client = MockClient((request) async {
    requests.add(request);
    final path = request.url.path;
    if (path.endsWith(BranchApi.branchesPath)) {
      return http.Response(defaultBranchesJson(), 200);
    }
    if (failing.any(path.endsWith)) {
      return http.Response(errorBody(500, 'Boom'), 500);
    }
    if (path.endsWith(DashboardApi.transactionsReportPath)) {
      final count = totals.fold<num>(0, (n, t) => n + (t['count'] as num));
      final amount = totals.fold<num>(0, (n, t) => n + (t['amount'] as num));
      final fees = totals.fold<num>(0, (n, t) => n + (t['fees'] as num));
      return http.Response(
        jsonEncode({
          'from': request.url.queryParameters['from'],
          'to': request.url.queryParameters['to'],
          'branchId': null,
          'branchName': null,
          'rows': [],
          'totals': totals,
          'count': count,
          'amount': amount,
          'fees': fees,
        }),
        200,
      );
    }
    if (path.endsWith(DashboardApi.collectionsReportPath)) {
      return http.Response(
        jsonEncode({
          'days': [],
          'submissions': [],
          'collected': 860.00,
          'expected': 860.00,
          'counted': 860.00,
          'surplus': 0,
        }),
        200,
      );
    }
    if (path.endsWith(DashboardApi.loanPortfolioPath)) {
      return http.Response(
        jsonEncode({
          'asOf': '2026-11-25T10:00:00',
          'loans': [],
          'activeLoans': 5,
          'overdueLoans': 1,
          'amountLent': 12000.00,
          'outstanding': 8000.00,
          'overdue': 450.00,
        }),
        200,
      );
    }
    for (final entry in counts.entries) {
      if (path.endsWith(entry.key)) {
        return http.Response(pagedJson([], total: entry.value, size: 1), 200);
      }
    }
    return http.Response(errorBody(404, 'Not found'), 404);
  });

  late final DashboardApi api = DashboardApi(baseUrl: testBaseUrl, client: _client);
  late final BranchApi branchApi = BranchApi(baseUrl: testBaseUrl, client: _client);
}

/// A daily-submissions backend. Approve takes the next answer from
/// [approveAnswers]; when those run out it approves (refusing a short count
/// as the backend does). An answer of null means the connection drops.
class FakeSubmissionBackend {
  final waiting = <Map<String, dynamic>>[];
  final approved = <Map<String, dynamic>>[];
  final approveAnswers = <(int, String)?>[];

  /// (submissionId, countedAmount) of every approval sent.
  final approvals = <(String, num)>[];
  final listCalls = <(String, int)>[];

  static Map<String, dynamic> submissionJson(
    String id, {
    String collector = 'Yaw Owusu',
    num expected = 2310,
    String status = 'SUBMITTED',
    int failedCount = 0,
    num failedAmount = 0,
    num? counted,
    num? overage,
  }) =>
      {
        'submissionId': id,
        'collectorStaffId': 'STF0031',
        'collectorName': collector,
        'branchName': 'Tarkwa',
        'status': status,
        'submittedAt': '2026-11-24T16:40:00',
        'paymentCount': 2,
        'expectedAmount': expected,
        'failedCount': failedCount,
        'failedAmount': failedAmount,
        'countedAmount': counted,
        'overageAmount': overage,
        'approvedByStaffId': status == 'APPROVED' ? 'STF0012' : null,
        'approvedAt': status == 'APPROVED' ? '2026-11-24T17:00:00' : null,
        'payments': [
          {
            'transactionId': 'p1',
            'type': 'SAVINGS',
            'accountNumber': '2004567',
            'memberName': 'Ama Mensah',
            'amount': 50,
            'status': 'COMPLETED',
            'failureReason': null,
            'createdAt': '2026-11-24T09:12:00',
          },
          {
            'transactionId': 'p2',
            'type': 'SHARES',
            'accountNumber': '1001234',
            'memberName': 'Kofi Boateng',
            'amount': 20,
            'status': 'FAILED',
            'failureReason': 'Account is INACTIVE',
            'createdAt': '2026-11-24T10:30:00',
          },
        ],
      };

  Map<String, dynamic>? _find(String id) {
    for (final s in [...waiting, ...approved]) {
      if (s['submissionId'] == id) return s;
    }
    return null;
  }

  late final http.Client _client = MockClient((request) async {
    final path = request.url.path;
    if (!path.startsWith(SubmissionApi.path)) {
      return http.Response(errorBody(404, 'Not found'), 404);
    }
    final rest = path.substring(SubmissionApi.path.length);
    if (rest.isEmpty) {
      final status = request.url.queryParameters['status'] ?? 'SUBMITTED';
      final page = int.parse(request.url.queryParameters['page'] ?? '0');
      listCalls.add((status, page));
      final rows = status == 'APPROVED' ? approved : waiting;
      return http.Response(
        pagedJson(rows, page: page, size: SubmissionApi.pageSize),
        200,
      );
    }
    final parts = rest.split('/').where((p) => p.isNotEmpty).toList();
    final submission = _find(parts.first);
    if (submission == null) {
      return http.Response(errorBody(404, 'Submission not found'), 404);
    }
    if (parts.length == 2 && parts[1] == 'approve') {
      final counted = (jsonDecode(request.body) as Map)['countedAmount'] as num;
      approvals.add((parts.first, counted));
      if (approveAnswers.isNotEmpty) {
        final answer = approveAnswers.removeAt(0);
        if (answer == null) throw http.ClientException('connection dropped');
        return http.Response(answer.$2, answer.$1);
      }
      final expected = submission['expectedAmount'] as num;
      if (counted < expected) {
        return http.Response(
          errorBody(409, 'The cash counted is short of the expected amount'),
          409,
        );
      }
      final done = {
        ...submission,
        'status': 'APPROVED',
        'countedAmount': counted,
        'overageAmount': counted - expected,
        'approvedByStaffId': 'STF0012',
        'approvedAt': '2026-11-24T17:00:00',
      };
      waiting.removeWhere((s) => s['submissionId'] == parts.first);
      approved.insert(0, done);
      return http.Response(jsonEncode(done), 200);
    }
    return http.Response(jsonEncode(submission), 200);
  });

  late final SubmissionApi api =
      SubmissionApi(baseUrl: testBaseUrl, client: _client);
}

/// A counter backend: accounts by number, their history, the (proposed)
/// settings, and the four transaction endpoints. Each transaction call
/// takes the next answer from [sendAnswers]; when those run out it records
/// the transaction (200). An answer of null means the connection drops.
class FakeTransactionBackend {
  FakeTransactionBackend({this.settings});

  /// The settings endpoint's answer, or null for 404 (not built yet).
  Map<String, dynamic>? settings;

  final accounts = <String, Map<String, dynamic>>{};
  final history = <String, List<Map<String, dynamic>>>{};
  final sendAnswers = <(int, String)?>[];

  /// (path, body) of every transaction sent.
  final sent = <(String, Map<String, dynamic>)>[];
  int accountCalls = 0;

  static Map<String, dynamic> accountJson(
    String number, {
    String type = 'SAVINGS',
    String status = 'ACTIVE',
    num available = 1250,
    String member = 'Ama Mensah',
  }) =>
      {
        'accountNumber': number,
        'accountType': type,
        'status': status,
        'currentBalance': available,
        'availableBalance': available,
        'memberId': 'm-ama',
        'memberName': member,
      };

  static Map<String, dynamic> recordJson({
    String id = 'tx-1',
    String type = 'WITHDRAWAL',
    num amount = 100,
    String account = '2004567',
    String? counterparty,
    num? fee,
    num? share,
    String? description,
  }) =>
      {
        'transactionId': id,
        'idempotencyKey': 'k',
        'transactionType': type,
        'amount': amount,
        'accountNumber': account,
        'counterpartyAccountNumber': counterparty,
        'feeAmount': fee,
        'shareAmount': share,
        'status': 'COMPLETED',
        'description': description,
        'initiatedByStaffId': 'STF0012',
        'createdAt': '2026-11-24T10:15:30',
        'postedAt': '2026-11-24T10:15:30',
      };

  static Map<String, dynamic> settingsJson({
    bool feeEnabled = true,
    String feeType = 'FLAT',
    num feeValue = 2,
  }) =>
      {
        'initialShareAmount': 50,
        'minFirstDeposit': 100,
        'withdrawalMinBalance': 20,
        'withdrawalDailyLimit': 10000,
        'withdrawalFeeEnabled': feeEnabled,
        'withdrawalFeeType': feeType,
        'withdrawalFeeValue': feeValue,
      };

  late final http.Client _client = MockClient((request) async {
    final path = request.url.path;
    if (path == TransactionApi.settingsPath) {
      final answer = settings;
      return answer == null
          ? http.Response(errorBody(404, 'Not found'), 404)
          : http.Response(jsonEncode(answer), 200);
    }
    if (path.startsWith('${TransactionApi.accountPath}/')) {
      accountCalls++;
      final account = accounts[path.split('/').last];
      return account == null
          ? http.Response(errorBody(404, 'Account not found'), 404)
          : http.Response(jsonEncode(account), 200);
    }
    if (path.startsWith('${TransactionApi.historyPath}/')) {
      final rows = history[path.split('/').last] ?? const [];
      return http.Response(pagedJson(rows, size: TransactionApi.historyPageSize), 200);
    }
    for (final kind in TransactionKind.values) {
      if (path == kind.path) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        sent.add((path, body));
        final answer = sendAnswers.isEmpty
            ? (
                200,
                jsonEncode(recordJson(
                  type: switch (kind) {
                    TransactionKind.withdrawal => 'WITHDRAWAL',
                    TransactionKind.deposit => 'DEPOSIT',
                    TransactionKind.sharePurchase => 'SHARES',
                    TransactionKind.transfer => 'TRANSFER',
                  },
                  amount: body['amount'] as num,
                  account: (body['accountNumber'] ?? body['fromAccountNumber'])
                      as String,
                  counterparty: body['toAccountNumber'] as String?,
                  fee: kind == TransactionKind.withdrawal ? 2 : null,
                  description: body['description'] as String?,
                )),
              )
            : sendAnswers.removeAt(0);
        if (answer == null) throw http.ClientException('connection dropped');
        return http.Response(answer.$2, answer.$1);
      }
    }
    return http.Response(errorBody(404, 'Not found'), 404);
  });

  late final TransactionApi api =
      TransactionApi(baseUrl: testBaseUrl, client: _client);
}
