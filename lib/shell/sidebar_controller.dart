import 'package:flutter/foundation.dart';

import 'sidebar_state_store.dart';

/// Whether the sidebar is expanded, and whether that is remembered between
/// launches.
///
/// Remembering is on by default. Reopening the layout the way the user left
/// it is the usual desktop behaviour (editors, mail clients, file managers do
/// the same), and the Settings switch lets anyone turn it off. With it off,
/// the sidebar always opens expanded.
class SidebarController extends ChangeNotifier {
  SidebarController(this._store);

  final SidebarStateStore _store;
  bool _remember = true;
  bool _expanded = true;

  bool get remember => _remember;
  bool get expanded => _expanded;

  /// Reads the saved choices. Called before the first frame so the sidebar
  /// doesn't open one way and then jump to the other.
  Future<void> load() async {
    try {
      _remember = await _store.readRemember() ?? true;
      if (_remember) {
        _expanded = await _store.readExpanded() ?? true;
      }
    } catch (_) {
      // Unreadable preferences fall back to the defaults: remember on,
      // sidebar expanded. Not worth stopping the app for.
      _remember = true;
      _expanded = true;
    }
    notifyListeners();
  }

  /// Expands or collapses the sidebar, saving the state if it's remembered.
  Future<void> setExpanded(bool expanded) async {
    if (expanded == _expanded) return;
    _expanded = expanded;
    notifyListeners();
    if (!_remember) return;
    try {
      await _store.saveExpanded(expanded);
    } catch (_) {
      // The change still applies now; it just won't survive a restart.
    }
  }

  Future<void> toggle() => setExpanded(!_expanded);

  /// Turns remembering on or off. Turning it on saves the current state;
  /// turning it off forgets the saved one, so the next launch opens expanded.
  Future<void> setRemember(bool remember) async {
    if (remember == _remember) return;
    _remember = remember;
    notifyListeners();
    try {
      await _store.saveRemember(remember);
      if (remember) {
        await _store.saveExpanded(_expanded);
      } else {
        await _store.clearExpanded();
      }
    } catch (_) {
      // As above: applies for now, may not be remembered.
    }
  }
}
