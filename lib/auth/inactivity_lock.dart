import 'dart:async';

import 'package:flutter/foundation.dart';

/// Locks the app after a stretch without mouse or keyboard activity.
///
/// Owner decisions: lock after 20 minutes (changed from 10 on 13 November
/// 2026) and ask for the password again; the lock screen is option L1, a
/// card over the dimmed app.
///
/// Activity is reported with [recordActivity]. A periodic check compares the
/// time since the last activity with [timeout]; the clock is injectable so
/// tests don't have to wait 20 minutes.
class InactivityLock extends ChangeNotifier {
  InactivityLock({
    this.timeout = defaultTimeout,
    this.checkEvery = const Duration(seconds: 15),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  static const defaultTimeout = Duration(minutes: 20);

  final Duration timeout;
  final Duration checkEvery;
  final DateTime Function() _now;

  Timer? _timer;
  DateTime? _lastActivity;
  bool _locked = false;

  bool get locked => _locked;
  bool get running => _timer != null;

  /// Starts watching, counting from now. Called when someone signs in.
  void start() {
    _lastActivity = _now();
    _timer?.cancel();
    _timer = Timer.periodic(checkEvery, (_) => check());
  }

  /// Stops watching and clears any lock. Called when the session ends.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _lastActivity = null;
    if (_locked) {
      _locked = false;
      notifyListeners();
    }
  }

  /// Mouse or keyboard input happened. Ignored while locked, so moving the
  /// mouse over the lock screen doesn't count.
  void recordActivity() {
    if (_locked || !running) return;
    _lastActivity = _now();
  }

  /// Locks if the time since the last activity has reached [timeout].
  void check() {
    final last = _lastActivity;
    if (_locked || last == null) return;
    if (_now().difference(last) >= timeout) {
      _locked = true;
      notifyListeners();
    }
  }

  /// The password was confirmed; carry on, counting from now.
  void unlock() {
    if (!_locked) return;
    _locked = false;
    _lastActivity = _now();
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
