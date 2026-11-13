import 'package:shared_preferences/shared_preferences.dart';

/// Saves the sidebar's collapsed/expanded state and whether to remember it.
///
/// Like the light/dark choice, this is a setting for the computer rather than
/// for the signed-in staff member, and it isn't sensitive.
abstract interface class SidebarStateStore {
  /// Whether to remember the sidebar state, or null if never chosen.
  Future<bool?> readRemember();
  Future<void> saveRemember(bool remember);

  /// The last saved state (true = expanded), or null if none is saved.
  Future<bool?> readExpanded();
  Future<void> saveExpanded(bool expanded);
  Future<void> clearExpanded();
}

class PrefsSidebarStateStore implements SidebarStateStore {
  PrefsSidebarStateStore([SharedPreferencesAsync? prefs])
      : _prefs = prefs ?? SharedPreferencesAsync();

  static const _rememberKey = 'sidebar_remember';
  static const _expandedKey = 'sidebar_expanded';

  final SharedPreferencesAsync _prefs;

  @override
  Future<bool?> readRemember() => _prefs.getBool(_rememberKey);

  @override
  Future<void> saveRemember(bool remember) =>
      _prefs.setBool(_rememberKey, remember);

  @override
  Future<bool?> readExpanded() => _prefs.getBool(_expandedKey);

  @override
  Future<void> saveExpanded(bool expanded) =>
      _prefs.setBool(_expandedKey, expanded);

  @override
  Future<void> clearExpanded() => _prefs.remove(_expandedKey);
}
