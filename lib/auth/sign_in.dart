import '../api/api_exception.dart';

/// Thrown when someone who is neither an administrator nor an agent signs
/// in. Collectors use the mobile app.
class NotOfficeStaffException implements Exception {
  const NotOfficeStaffException();
}

/// What to tell the staff member when sign-in fails.
String signInErrorMessage(Object error) {
  if (error is NotOfficeStaffException) {
    return 'This app is for administrators and agents. Collectors use the '
        'mobile app.';
  }
  if (error is ApiException) {
    return switch (error.failure) {
      // The backend says "Invalid ID or password" for a wrong staff ID, a
      // wrong password and an inactive account alike, on purpose.
      ApiFailure.unauthorized => 'Wrong staff ID or password.',
      ApiFailure.forbidden => "Your account can't sign in to this app.",
      ApiFailure.network =>
        "Couldn't reach the server. Check your connection and try again.",
      ApiFailure.validation =>
        error.message ?? 'Check your staff ID and password.',
      ApiFailure.server =>
        'The server had a problem. Try again in a few minutes.',
      ApiFailure.notConfigured =>
        'This build has no server address. It needs to be rebuilt with '
            'API_BASE_URL.',
      ApiFailure.unexpectedResponse =>
        "The server sent a response the app didn't understand. Try again.",
    };
  }
  return 'Something went wrong. Try again.';
}

/// Shown on the sign-in screen after the backend ended the session, so the
/// staff member knows why they're back there.
const sessionEndedNotice =
    'Your session has ended. Sign in again to continue.';
