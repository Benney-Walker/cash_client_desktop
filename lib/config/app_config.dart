/// Build-time settings, passed with `--dart-define`.
///
/// ```
/// flutter run -d windows --dart-define=API_BASE_URL=http://localhost:8080
/// ```
///
/// The backend address is fixed per build and can't be changed in the app,
/// so nobody at the computer can point it at another server (owner
/// decision). Release builds must use an `https://` address. Settings shows
/// the address so support can tell which server a build talks to.
abstract final class AppConfig {
  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// The credit union's name, printed at the top of receipts. Set with
  /// `--dart-define=CREDIT_UNION_NAME=...`; without it receipts say
  /// "Cash Client". (Asked of the backend in CASH_CLIENT_DESKTOP.md
  /// section 21, so it can come from one place.)
  static const creditUnionName = String.fromEnvironment(
    'CREDIT_UNION_NAME',
    defaultValue: 'Cash Client',
  );
}
