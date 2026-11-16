import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_exception.dart';

/// Runs [request] and turns transport problems and non-200 answers into
/// [ApiException]s: a timeout or dropped connection is `network`, anything
/// but 200 goes through [ApiException.fromResponse].
///
/// `AuthenticatedClient` throws its own [ApiException] when the session has
/// ended; that passes straight through.
Future<http.Response> sendChecked(
  Future<http.Response> Function() request, {
  required Duration timeout,
}) async {
  final http.Response response;
  try {
    response = await request().timeout(timeout);
  } on TimeoutException {
    throw const ApiException(ApiFailure.network);
  } on http.ClientException {
    throw const ApiException(ApiFailure.network);
  }
  if (response.statusCode != 200) {
    throw ApiException.fromResponse(response.statusCode, response.body);
  }
  return response;
}

/// The decoded JSON in [body], or null when it isn't JSON.
Object? decodeJson(String body) {
  try {
    return jsonDecode(body);
  } on FormatException {
    return null;
  }
}

/// For a 200 whose body isn't what the endpoint promises.
ApiException unexpectedOk() =>
    const ApiException(ApiFailure.unexpectedResponse, statusCode: 200);
