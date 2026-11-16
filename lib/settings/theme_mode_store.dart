import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Remembers the light/dark choice on this computer.
///
/// It's a device setting, not tied to the signed-in staff member, so it
/// stays when they sign out. It isn't sensitive, so plain preferences are fine.
/// Session tokens, once sign-in is added, belong in secure storage instead.
abstract interface class ThemeModeStore {
  /// The saved choice, or null if none has been made.
  Future<ThemeMode?> read();
  Future<void> save(ThemeMode mode);
}

class PrefsThemeModeStore implements ThemeModeStore {
  PrefsThemeModeStore([SharedPreferencesAsync? prefs])
      : _prefs = prefs ?? SharedPreferencesAsync();

  static const _key = 'theme_mode';

  final SharedPreferencesAsync _prefs;

  @override
  Future<ThemeMode?> read() async =>
      themeModeFromName(await _prefs.getString(_key));

  @override
  Future<void> save(ThemeMode mode) => _prefs.setString(_key, mode.name);
}

/// Stored as the enum's name (`system`, `light`, `dark`). Anything else,
/// such as a value from a future version, is ignored.
ThemeMode? themeModeFromName(String? name) {
  for (final mode in ThemeMode.values) {
    if (mode.name == name) return mode;
  }
  return null;
}
