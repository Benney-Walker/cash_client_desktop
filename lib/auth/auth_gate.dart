import 'package:flutter/material.dart';

import '../settings/app_info.dart';
import '../settings/theme_controller.dart';
import '../shell/app_shell.dart';
import '../shell/sidebar_controller.dart';
import 'login_screen.dart';
import 'session_manager.dart';
import 'sign_in.dart';

/// Shows the sign-in screen or the signed-in app, and switches between them
/// whenever the session changes, including when the backend ends it.
class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    required this.sessions,
    required this.theme,
    required this.sidebar,
    required this.appInfo,
  });

  final SessionManager sessions;
  final ThemeController theme;
  final SidebarController sidebar;
  final AppInfo appInfo;

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
            notice: sessions.sessionEndedByServer ? sessionEndedNotice : null,
          );
        }
        // Signing out shows the sign-in screen in its place, so nothing from
        // one staff member's session (such as the open section) carries over
        // to the next.
        return AppShell(
          session: session,
          onSignOut: sessions.signOut,
          theme: widget.theme,
          sidebar: widget.sidebar,
          appInfo: widget.appInfo,
        );
      },
    );
  }
}
