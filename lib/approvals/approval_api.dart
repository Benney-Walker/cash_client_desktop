import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../api/api_call.dart';
import '../api/api_exception.dart';
import '../api/endpoint.dart';
import '../api/paged.dart';
import '../members/member_api.dart' show commonFailureMessage;
import 'approval_models.dart';

export '../api/paged.dart';
export 'approval_models.dart';

/// The Administrators' review queues: ID documents (`/api/admin/v1/kyc-*`)
/// and member update requests (`/api/admin/v1/member-update-requests`).
/// Everything under `/api/admin` is Administrator-only on the backend.
class ApprovalApi {
  ApprovalApi({
    required String baseUrl,
    required http.Client client,
    this.timeout = const Duration(seconds: 20),
  })  : _baseUrl = baseUrl,
        _client = client;

  static const kycReviewsPath = '/api/admin/v1/kyc-reviews';
  static const kycDocumentPath = '/api/member/v1/kyc-document';
  static const kycApprovePath = '/api/admin/v1/manual-kyc-approval';
  static const kycRejectPath = '/api/admin/v1/manual-kyc-rejection';
  static const updatesPath = '/api/admin/v1/member-update-requests';
  static const pageSize = 20;

  final String _baseUrl;
  final http.Client _client;
  final Duration timeout;

  static const _accept = {'Accept': 'application/json'};
  static const _json = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  /// `GET /api/admin/v1/kyc-reviews`: ID documents in [status], oldest
  /// first so the list works as a queue.
  Future<PagedResult<KycRecord>> listKyc(
    KycReviewStatus status, {
    int page = 0,
  }) async {
    final response = await sendChecked(
      () => _client.get(
        apiUri(_baseUrl, kycReviewsPath, {
          'status': status.backendName,
          'page': '$page',
          'size': '$pageSize',
        }),
        headers: _accept,
      ),
      timeout: timeout,
    );
    return PagedResult.fromJson(decodeJson(response.body), KycRecord.fromJson) ??
        (throw unexpectedOk());
  }

  /// `GET /api/member/v1/kyc-document/{memberId}`: the ID picture's bytes
  /// (JPEG or PNG). The backend records every view in the audit log, so the
  /// app fetches it once per opened record and never stores it.
  Future<Uint8List> fetchKycPicture(String memberId) async {
    final response = await sendChecked(
      () => _client.get(
        apiUri(_baseUrl, '$kycDocumentPath/${Uri.encodeComponent(memberId)}'),
        headers: const {'Accept': 'image/png, image/jpeg'},
      ),
      timeout: timeout,
    );
    if (response.bodyBytes.isEmpty) throw unexpectedOk();
    return response.bodyBytes;
  }

  /// `POST /api/admin/v1/manual-kyc-approval/{memberId}`: verifies the
  /// document and activates the member and their accounts.
  Future<void> approveKyc(String memberId) async {
    await sendChecked(
      () => _client.post(
        apiUri(_baseUrl, '$kycApprovePath/${Uri.encodeComponent(memberId)}'),
        headers: _accept,
      ),
      timeout: timeout,
    );
  }

  /// `POST /api/admin/v1/manual-kyc-rejection/{memberId}` with `{reason}`:
  /// the member stays pending and the staff member who registered them can
  /// upload a clearer document.
  Future<void> rejectKyc(String memberId, String reason) async {
    await sendChecked(
      () => _client.post(
        apiUri(_baseUrl, '$kycRejectPath/${Uri.encodeComponent(memberId)}'),
        headers: _json,
        body: jsonEncode({'reason': reason}),
      ),
      timeout: timeout,
    );
  }

  /// `GET /api/admin/v1/member-update-requests`: requests in [status],
  /// newest first.
  Future<PagedResult<MemberUpdateRequestRecord>> listUpdates(
    MemberUpdateStatus status, {
    int page = 0,
    int size = pageSize,
  }) async {
    final response = await sendChecked(
      () => _client.get(
        apiUri(_baseUrl, updatesPath, {
          'status': status.backendName,
          'page': '$page',
          'size': '$size',
        }),
        headers: _accept,
      ),
      timeout: timeout,
    );
    return PagedResult.fromJson(
          decodeJson(response.body),
          MemberUpdateRequestRecord.fromJson,
        ) ??
        (throw unexpectedOk());
  }

  /// `POST .../{requestId}/approve`: applies the change and texts the
  /// member.
  Future<MemberUpdateRequestRecord> approveUpdate(String requestId) =>
      _review(
        () => _client.post(
          apiUri(
              _baseUrl, '$updatesPath/${Uri.encodeComponent(requestId)}/approve'),
          headers: _accept,
        ),
      );

  /// `POST .../{requestId}/reject` with `{reason}`, which the staff member
  /// who asked sees.
  Future<MemberUpdateRequestRecord> rejectUpdate(
    String requestId,
    String reason,
  ) =>
      _review(
        () => _client.post(
          apiUri(
              _baseUrl, '$updatesPath/${Uri.encodeComponent(requestId)}/reject'),
          headers: _json,
          body: jsonEncode({'reason': reason}),
        ),
      );

  Future<MemberUpdateRequestRecord> _review(
    Future<http.Response> Function() request,
  ) async {
    final response = await sendChecked(request, timeout: timeout);
    return MemberUpdateRequestRecord.fromJson(decodeJson(response.body)) ??
        (throw unexpectedOk());
  }
}

/// A message for a failed review action or list. The backend's 409 reasons
/// ("This member's KYC is VERIFIED and can't be reviewed", "This request
/// was already approved") mean someone else got there first.
String approvalErrorMessage(Object error) {
  if (error is! ApiException) return 'Something went wrong. Try again.';
  final lower = (error.message ?? '').toLowerCase();
  switch (error.failure) {
    case ApiFailure.conflict:
      if (lower.contains("can't be reviewed") ||
          lower.contains('already approved') ||
          lower.contains('already rejected')) {
        return 'This was already reviewed, probably by another '
            'administrator. Refresh the list.';
      }
      if (lower.contains('phone number')) {
        return 'Another member now uses this phone number, so the change '
            "can't be applied. Reject it with that reason.";
      }
    case ApiFailure.notFound:
      return 'This record no longer exists. Refresh the list.';
    case ApiFailure.forbidden:
      return 'Only administrators review ID documents and member updates.';
    case ApiFailure.network:
      return "Couldn't reach the server, so it isn't clear whether this went "
          'through. Refresh the list before trying again.';
    default:
      break;
  }
  return commonFailureMessage(error, action: 'review');
}
