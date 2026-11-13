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
}
