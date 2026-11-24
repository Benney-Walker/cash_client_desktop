import 'package:flutter/material.dart';

import '../api/apis.dart';
import '../config/app_config.dart';
import '../settings/app_info.dart';
import '../settings/theme_controller.dart';
import '../shell/app_shell.dart';
import '../shell/sidebar_controller.dart';
import 'login_screen.dart';
import 'password_reset_link.dart';
import 'profile_controller.dart';
import 'session_manager.dart';
import 'sign_in.dart';

/// Shows the sign-in screen or the signed-in app, and switches between them
/// whenever the session changes, including when the backend ends it.
class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    required this.sessions,
    this.profile,
    required this.apis,
    required this.theme,
    required this.sidebar,
    required this.appInfo,
    this.baseUrl = AppConfig.apiBaseUrl,
    this.openInBrowser = openUrlInBrowser,
  });

  final SessionManager sessions;
  final ProfileController? profile;
  final Apis apis;
  final ThemeController theme;
  final SidebarController sidebar;
  final AppInfo appInfo;

  /// The server whose password reset page "Forgot password?" opens.
  final String baseUrl;

  /// Replaced in tests; the real one opens the default browser.
  final OpenInBrowser openInBrowser;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  void initState() {
    super.initState();
    widget.sessions.addListener(_onSessionChanged);
  }

  @override
  void didUpdateWidget(AuthGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessions != widget.sessions) {
      oldWidget.sessions.removeListener(_onSessionChanged);
      widget.sessions.addListener(_onSessionChanged);
    }
  }

  @override
  void dispose() {
    widget.sessions.removeListener(_onSessionChanged);
    super.dispose();
  }

  void _onSessionChanged() {
    // This widget is the bottom screen, so swapping it for the sign-in
    // screen isn't enough when dialogs or other screens are open on top.
    // Close them, so nobody keeps using a screen after the session ended.
    if (widget.sessions.session == null && mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  Future<String?> _signIn(String staffId, String password) async {
    try {
      await widget.sessions.signIn(staffId: staffId, password: password);
      return null;
    } catch (error) {
      return signInErrorMessage(error);
    }
  }

  Future<String?> _forgotPassword(String staffId) async {
    final Uri uri;
    try {
      uri = passwordResetUri(widget.baseUrl, staffId: staffId);
    } catch (_) {
      return "Password reset can't be opened: this build has no server "
          'address. It needs to be rebuilt with API_BASE_URL.';
    }
    final opened = await widget.openInBrowser(uri);
    return opened
        ? null
        : "Couldn't open your browser. To reset your password, go to $uri";
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.sessions,
      builder: (context, _) {
        final sessions = widget.sessions;
        final session = sessions.session;
        if (session == null) {
          return LoginScreen(
            appInfo: widget.appInfo,
            onSignIn: _signIn,
            onForgotPassword: _forgotPassword,
            notice: sessions.signInNotice,
          );
        }
        // Signing out shows the sign-in screen in its place, so nothing from
        // one staff member's session (such as the open section) carries over
        // to the next.
        return AppShell(
          session: session,
          profile: widget.profile,
          onSignOut: sessions.signOut,
          apis: widget.apis,
          theme: widget.theme,
          sidebar: widget.sidebar,
          appInfo: widget.appInfo,
        );
      },
    );
  }
}
