import 'package:flutter/foundation.dart';

import '../api/api_exception.dart';
import 'session_manager.dart';
import 'staff_profile.dart';

/// Keeps the signed-in staff member's own profile (`GET /api/staff/v1/me`)
/// for the branch shown on the Account card, the lock card and Agents'
/// branch pages (Phase 6, owner decisions 24 November 2026).
///
/// It reads the profile once per sign-in (unlocking signs in again), not on
/// a timer: the backend reads roles from the database on every request, so
/// a changed role is enforced there at once whatever the app shows. When a
/// request is refused with 403, [checkRoles] reads the profile again, and if
/// the roles differ from the ones the session started with, the staff member
/// is signed out with [SessionManager.rolesChangedNotice] (owner decision:
/// sign them out).
class ProfileController extends ChangeNotifier {
  ProfileController({
    required SessionManager sessions,
    required Future<StaffProfile> Function() fetch,
  })  : _sessions = sessions,
        _fetch = fetch {
    _sessions.addListener(_onSession);
    _onSession();
  }

  final SessionManager _sessions;
  final Future<StaffProfile> Function() _fetch;

  StaffProfile? _profile;
  int? _loadedFor;
  bool _checking = false;

  /// Null until it's read, when signed out, or if it couldn't be read (then
  /// the branch simply isn't shown).
  StaffProfile? get profile => _profile;

  String? get branchName => _profile?.branchName;

  void _onSession() {
    final session = _sessions.session;
    if (session == null) {
      _loadedFor = null;
      if (_profile != null) {
        _profile = null;
        notifyListeners();
      }
      return;
    }
    // A token refresh replaces the session too; only a new sign-in reads
    // the profile again.
    final signIn = _sessions.signInCount;
    if (_loadedFor == signIn) return;
    _loadedFor = signIn;
    if (_profile != null && _profile!.staffId != session.staffId) {
      _profile = null;
      notifyListeners();
    }
    _read(signIn);
  }

  Future<void> _read(int signIn) async {
    try {
      final profile = await _fetch();
      if (_sessions.signInCount != signIn || _sessions.session == null) return;
      if (_signOutIfRolesChanged(profile)) return;
      _profile = profile;
      notifyListeners();
    } on ApiException catch (e) {
      if (_sessions.signInCount != signIn) return;
      // `/api/staff/**` refuses anyone who's no longer an administrator or
      // agent.
      if (e.failure == ApiFailure.forbidden) {
        _sessions.signOut(notice: SessionManager.rolesChangedNotice);
      }
    } catch (_) {
      // No profile: the branch isn't shown.
    }
  }

  /// After a 403: reads the profile again and signs out if the roles
  /// changed. Calls while one is running are ignored, which also covers the
  /// profile request's own 403.
  Future<void> checkRoles() async {
    if (_checking || _sessions.session == null) return;
    _checking = true;
    try {
      await _read(_sessions.signInCount);
    } finally {
      _checking = false;
    }
  }

  bool _signOutIfRolesChanged(StaffProfile profile) {
    final session = _sessions.session;
    if (session == null) return true;
    if (setEquals(profile.roles, session.roles.toSet())) return false;
    _sessions.signOut(notice: SessionManager.rolesChangedNotice);
    return true;
  }

  @override
  void dispose() {
    _sessions.removeListener(_onSession);
    super.dispose();
  }
}
