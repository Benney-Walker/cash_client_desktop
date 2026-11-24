import 'package:url_launcher/url_launcher.dart';

import '../api/endpoint.dart';

/// The backend's password reset page (owner decision, backend roadmap
/// 24 November 2026): a public web page at `/password-reset` on the same
/// server as the API. It runs the three reset steps (staff ID, SMS code,
/// new password); new staff use it to set their first password.
///
/// [staffId], when typed, is filled in on the page. Throws an
/// `ApiException` (`notConfigured`) when the build has no server address.
Uri passwordResetUri(String baseUrl, {String staffId = ''}) {
  final id = staffId.trim();
  return apiUri(
    baseUrl,
    '/password-reset',
    id.isEmpty ? null : {'staffId': id},
  );
}

/// Opens [uri] in the staff member's browser. Returns false when no
/// browser could be opened.
typedef OpenInBrowser = Future<bool> Function(Uri uri);

/// The real [OpenInBrowser]: the system's default browser.
Future<bool> openUrlInBrowser(Uri uri) async {
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}
