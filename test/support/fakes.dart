import 'package:cash_client_desktop/settings/app_info.dart';
import 'package:cash_client_desktop/settings/theme_mode_store.dart';
import 'package:cash_client_desktop/shell/sidebar_state_store.dart';
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

/// Keeps the sidebar state in memory instead of on disk.
class MemorySidebarStateStore implements SidebarStateStore {
  MemorySidebarStateStore({this.remember, this.expanded});

  bool? remember;
  bool? expanded;
  bool failReads = false;
  bool failSaves = false;

  @override
  Future<bool?> readRemember() async {
    if (failReads) throw StateError('unreadable');
    return remember;
  }

  @override
  Future<void> saveRemember(bool remember) async {
    if (failSaves) throw StateError('disk full');
    this.remember = remember;
  }

  @override
  Future<bool?> readExpanded() async {
    if (failReads) throw StateError('unreadable');
    return expanded;
  }

  @override
  Future<void> saveExpanded(bool expanded) async {
    if (failSaves) throw StateError('disk full');
    this.expanded = expanded;
  }

  @override
  Future<void> clearExpanded() async {
    if (failSaves) throw StateError('disk full');
    expanded = null;
  }
}

const testAppInfo = AppInfo(
  version: '1.0.0',
  buildNumber: '1',
  apiBaseUrl: 'https://api.test.example',
);
