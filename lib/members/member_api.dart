import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../api/api_call.dart';
import '../api/api_exception.dart';
import '../api/endpoint.dart';
import 'member_models.dart';

/// Calls the backend's member endpoints (`MemberController`, open to
/// administrators and agents). [client] should be the app's
/// `AuthenticatedClient`.
class MemberApi {
  MemberApi({
    required String baseUrl,
    required http.Client client,
    this.timeout = const Duration(seconds: 20),
    this.uploadTimeout = const Duration(seconds: 60),
  })  : _baseUrl = baseUrl,
        _client = client;

  static const addMemberPath = '/api/member/v1/add-member';
  static const kycUploadPath = '/api/member/v1/kyc-document-upload';

  final String _baseUrl;
  final http.Client _client;
  final Duration timeout;

  /// Longer than [timeout]: an ID image can be up to 5 MB.
  final Duration uploadTimeout;

  /// `POST /api/member/v1/add-member`. The member starts as PENDING, with a
  /// shares account and the chosen account, all inactive until their ID is
  /// verified. Returns the new member's id, which the ID upload needs.
  ///
  /// Throws [ApiException]: `validation` (400) for a field the backend
  /// rejects, `conflict` (409) for a phone number another member has or an
  /// unknown branch, and `network` when the outcome is unknown.
  Future<String> registerMember(
    NewMember member, {
    required String idempotencyKey,
  }) async {
    final response = await sendChecked(
      () => _client.post(
        apiUri(_baseUrl, addMemberPath),
        headers: const {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(member.toJson(idempotencyKey: idempotencyKey)),
      ),
      timeout: timeout,
    );
    final json = decodeJson(response.body);
    // The backend answers {"status": "success", "Id": "<uuid>"}.
    final id = json is Map<String, dynamic> ? (json['Id'] ?? json['id']) : null;
    if (id is! String || id.isEmpty) throw unexpectedOk();
    return id;
  }

  /// `POST /api/member/v1/kyc-document-upload` (multipart). Sends the ID
  /// document for review; the member's accounts are activated once it's
  /// verified.
  ///
  /// Throws [ApiException]: `validation` (400) for an ID number in the wrong
  /// format or a file that isn't a JPEG or PNG, `conflict` (409) for an ID
  /// number another member has or a document already sent for this member,
  /// and `network` when the outcome is unknown.
  Future<void> uploadKycDocument({
    required String memberId,
    required KycDocument document,
  }) async {
    http.MultipartRequest build() => http.MultipartRequest(
          'POST',
          apiUri(_baseUrl, kycUploadPath),
        )
          ..headers['Accept'] = 'application/json'
          ..fields['memberId'] = memberId
          ..fields['documentType'] = document.type.backendName
          ..fields['idNumber'] = document.idNumber
          ..files.add(
            http.MultipartFile.fromBytes(
              'file',
              document.image.bytes,
              filename: document.image.fileName,
              contentType: MediaType.parse(document.image.type.mimeType),
            ),
          );

    Future<http.Response> send() async =>
        http.Response.fromStream(await _client.send(build()));

    final response = await _sendOrThrow(send);
    if (response.statusCode == 401) {
      // A multipart body can't be replayed by AuthenticatedClient, but it
      // has refreshed the token by now, so one fresh attempt is enough.
      await sendChecked(send, timeout: uploadTimeout);
      return;
    }
    if (response.statusCode != 200) {
      throw ApiException.fromResponse(response.statusCode, response.body);
    }
  }

  Future<http.Response> _sendOrThrow(
    Future<http.Response> Function() send,
  ) async {
    try {
      return await send().timeout(uploadTimeout);
    } on TimeoutException {
      throw const ApiException(ApiFailure.network);
    } on http.ClientException {
      throw const ApiException(ApiFailure.network);
    }
  }
}

/// The steps of Register member, so a failure can point to the one that
/// needs fixing.
enum RegisterMemberStep { personal, contactAndWork, account, idDocument, review }

/// A message for a failed add-member call, and the step to fix it in.
/// [afterUnknownOutcome] is true when an earlier attempt of this same
/// registration ended without an answer, so a "phone number already
/// exists" is most likely that attempt having worked.
(String, RegisterMemberStep?) registerErrorMessage(
  Object error, {
  bool afterUnknownOutcome = false,
}) {
  if (error is! ApiException) {
    return ('Something went wrong. Try again.', null);
  }
  final message = error.message ?? '';
  final lower = message.toLowerCase();
  switch (error.failure) {
    case ApiFailure.conflict:
      if (lower.contains('phone number')) {
        return (
          afterUnknownOutcome
              ? 'A member with this phone number already exists. The '
                  'connection dropped on the last try, so this member was '
                  'probably registered then. Search for them before trying '
                  'again.'
              : 'Another member already uses this phone number.',
          RegisterMemberStep.contactAndWork,
        );
      }
      if (lower.contains('branch')) {
        return (
          "That branch couldn't be found. Choose another.",
          RegisterMemberStep.account,
        );
      }
    case ApiFailure.validation:
      if (lower.contains('phone number')) {
        return (
          'The phone number must be 10 digits starting with 0.',
          RegisterMemberStep.contactAndWork,
        );
      }
      if (lower.contains('date of birth')) {
        return (
          'The date of birth must be a real date, as yyyy-mm-dd.',
          RegisterMemberStep.personal,
        );
      }
      if (lower.contains('account type')) {
        return (
          'Choose Savings or Current.',
          RegisterMemberStep.account,
        );
      }
    case ApiFailure.network:
      return (
        "Couldn't reach the server, so it isn't clear whether the member "
            'was registered. Try again.',
        null,
      );
    default:
      break;
  }
  return (commonFailureMessage(error, action: 'register members'), null);
}

/// A message for a failed ID document upload.
String kycErrorMessage(Object error) {
  if (error is! ApiException) return 'Something went wrong. Try again.';
  final message = error.message ?? '';
  final lower = message.toLowerCase();
  if (error.statusCode == 413) {
    return 'The ID image must be 5 MB or smaller. Choose a smaller one.';
  }
  switch (error.failure) {
    case ApiFailure.conflict:
      if (lower.contains('another member')) {
        return 'This ID number is already registered to another member.';
      }
    case ApiFailure.network:
      return "Couldn't reach the server, so it isn't clear whether the ID "
          'document was received. Try again.';
    default:
      break;
  }
  return commonFailureMessage(error, action: 'upload ID documents');
}

/// Messages every request shares. [action] completes "Only administrators
/// and agents can …".
String commonFailureMessage(ApiException error, {required String action}) {
  final message = error.message ?? '';
  return switch (error.failure) {
    ApiFailure.forbidden => 'Only administrators and agents can $action.',
    ApiFailure.network =>
      "Couldn't reach the server. Check your connection and try again.",
    ApiFailure.server => 'The server had a problem. Try again in a few minutes.',
    ApiFailure.notConfigured =>
      'This build has no server address. It needs to be rebuilt with '
          'API_BASE_URL.',
    ApiFailure.unauthorized => 'Your session has ended. Sign in again.',
    ApiFailure.validation =>
      message.isEmpty ? 'The server rejected one of the details.' : message,
    ApiFailure.conflict => message.isEmpty
        ? 'This clashes with an existing record.'
        : message,
    ApiFailure.notFound || ApiFailure.unexpectedResponse => message.isEmpty
        ? "The server sent a response the app didn't understand."
        : message,
  };
}
