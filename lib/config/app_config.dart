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

  /// Where the Collectors map gets its tiles. OpenStreetMap by default
  /// (owner decision 24 November 2026): free, no key, fine for a few office
  /// staff under its usage policy, which needs the credit below. A keyed
  /// provider (MapTiler, Stadia) can be set at build time with
  /// `--dart-define=MAP_TILE_URL=...` and `MAP_ATTRIBUTION=...`.
  static const mapTileUrl = String.fromEnvironment(
    'MAP_TILE_URL',
    defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  );

  static const mapAttribution = String.fromEnvironment(
    'MAP_ATTRIBUTION',
    defaultValue: '© OpenStreetMap contributors',
  );

  /// Sent with tile requests, as OpenStreetMap's policy asks, so the app
  /// can be identified.
  static const mapUserAgentPackage = 'com.bynexlabs.cash_client_desktop';
}
