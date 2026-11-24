import '../api/api_exception.dart';

/// Thrown when someone who is neither an administrator nor an agent signs
/// in. Collectors use the mobile app.
class NotOfficeStaffException implements Exception {
  const NotOfficeStaffException();
}

/// What to tell the staff member when sign-in fails.
String signInErrorMessage(Object error) {
  if (error is NotOfficeStaffException) return _notOfficeStaff;
  if (error is ApiException) {
    return switch (error.failure) {
      // The backend says "Invalid ID or password" for a wrong staff ID, a
      // wrong password and an inactive account alike, on purpose.
      ApiFailure.unauthorized => 'Wrong staff ID or password. Too many wrong '
          'passwords in a row lock the account.',
      // 403 is either a locked account or a collector account, which signs
      // in through the collector app.
      ApiFailure.forbidden =>
        isAccountLocked(error) ? lockedAccountMessage(error) : _notOfficeStaff,
      ApiFailure.network =>
        "Couldn't reach the server. Check your connection and try again.",
      ApiFailure.validation =>
        error.message ?? 'Check your staff ID and password.',
      ApiFailure.notFound || ApiFailure.conflict =>
        error.message ?? 'Something went wrong. Try again.',
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

/// True when sign-in was refused because the account is locked: the backend
/// locks it after 5 wrong passwords in a row, until an administrator
/// unlocks it (backend decision D29, 24 November 2026). Resetting the
/// password doesn't unlock it.
bool isAccountLocked(Object error) =>
    error is ApiException &&
    error.failure == ApiFailure.forbidden &&
    (error.message ?? '').toLowerCase().contains('locked');

/// The backend's own words for a locked account, such as "This account is
/// locked after 5 wrong passwords. Ask an administrator to unlock it."
String lockedAccountMessage(Object error) {
  final message = error is ApiException ? error.message?.trim() : null;
  if (message == null || message.isEmpty) {
    return 'This account is locked after too many wrong passwords. Ask an '
        'administrator to unlock it.';
  }
  return message.endsWith('.') ? message : '$message.';
}

const _notOfficeStaff =
    'This app is for administrators and agents. Collectors use the mobile '
    'app.';

/// Shown on the sign-in screen after the backend ended the session, so the
/// staff member knows why they're back there.
const sessionEndedNotice =
    'Your session has ended. Sign in again to continue.';
