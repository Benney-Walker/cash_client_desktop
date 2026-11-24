import 'dart:convert';

import 'package:http/http.dart' as http;

import '../api/api_call.dart';
import '../api/api_exception.dart';
import '../api/endpoint.dart';
import '../api/paged.dart';
import '../members/member_api.dart' show commonFailureMessage;
import 'submission_models.dart';

export '../api/paged.dart';

/// Collectors' daily submissions, office side
/// (`/api/transaction/v1/collector-submissions`). Agents see and approve
/// their own branch's collectors; Administrators every branch.
class SubmissionApi {
  SubmissionApi({
    required String baseUrl,
    required http.Client client,
    this.timeout = const Duration(seconds: 20),
  })  : _baseUrl = baseUrl,
        _client = client;

  static const path = '/api/transaction/v1/collector-submissions';
  static const pageSize = 20;

  final String _baseUrl;
  final http.Client _client;
  final Duration timeout;

  /// Submissions with [status], newest first.
  Future<PagedResult<CollectorSubmission>> list(
    SubmissionStatus status, {
    int page = 0,
  }) async {
    final response = await sendChecked(
      () => _client.get(
        apiUri(_baseUrl, path, {
          'status': status.backendName,
          'page': '$page',
          'size': '$pageSize',
        }),
        headers: const {'Accept': 'application/json'},
      ),
      timeout: timeout,
    );
    return PagedResult.fromJson(
          decodeJson(response.body),
          CollectorSubmission.fromJson,
        ) ??
        (throw unexpectedOk());
  }

  /// One submission with its payments.
  Future<CollectorSubmission> fetch(String submissionId) async {
    final response = await sendChecked(
      () => _client.get(
        apiUri(_baseUrl, '$path/${Uri.encodeComponent(submissionId)}'),
        headers: const {'Accept': 'application/json'},
      ),
      timeout: timeout,
    );
    return CollectorSubmission.fromJson(decodeJson(response.body)) ??
        (throw unexpectedOk());
  }

  /// Approves with the cash [counted]. Final: moves the cash to Cash on
  /// Hand, records any surplus, and signs the collector out until tomorrow.
  ///
  /// Safe to retry: approving again with the same amount returns the same
  /// approval. Throws [ApiException]: `conflict` (409) for a count below the
  /// expected cash, or one already approved with another amount.
  Future<CollectorSubmission> approve(
    String submissionId,
    Money counted,
  ) async {
    final response = await sendChecked(
      () => _client.post(
        apiUri(_baseUrl, '$path/${Uri.encodeComponent(submissionId)}/approve'),
        headers: const {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'countedAmount': counted.toJson()}),
      ),
      timeout: timeout,
    );
    return CollectorSubmission.fromJson(decodeJson(response.body)) ??
        (throw unexpectedOk());
  }
}

/// A message for a failed list or details call.
String submissionLoadErrorMessage(Object error) {
  if (error is ApiException && error.failure == ApiFailure.notFound) {
    return 'This submission no longer exists.';
  }
  if (error is ApiException && error.failure == ApiFailure.forbidden) {
    final message = error.message?.trim() ?? '';
    // "You are not assigned to a branch", "This submission is from another
    // branch".
    if (message.isNotEmpty) {
      return message.endsWith('.') ? message : '$message.';
    }
  }
  if (error is ApiException) {
    return commonFailureMessage(error, action: 'review submissions');
  }
  return 'Something went wrong. Try again.';
}

/// A message for a failed approval. The backend's 409s ("The cash counted
/// is GHS 5.00 short …", "already approved with GHS …") are shown as they
/// are.
String approveErrorMessage(Object error) {
  if (error is! ApiException) return 'Something went wrong. Try again.';
  final message = error.message?.trim() ?? '';
  return switch (error.failure) {
    ApiFailure.network =>
      "Couldn't reach the server, so it isn't clear whether this was "
          'approved. Approve again with the same count: it is only '
          'recorded once.',
    ApiFailure.conflict || ApiFailure.validation || ApiFailure.forbidden
        when message.isNotEmpty =>
      message.endsWith('.') ? message : '$message.',
    _ => submissionLoadErrorMessage(error),
  };
}
