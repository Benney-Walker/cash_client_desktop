import 'package:cash_client_desktop/settings/theme_mode_store.dart';
import 'package:flutter/material.dart';

/// Keeps the light/dark choice in memory instead of on disk.
class MemoryThemeModeStore implements ThemeModeStore {
  MemoryThemeModeStore([this.mode]);

  ThemeMode? mode;
  bool failSaves = false;

  @override
  Future<ThemeMode?> read() async => mode;

  @override
  Future<void> save(ThemeMode mode) async {
    if (failSaves) throw StateError('disk full');
    this.mode = mode;
  }
}
