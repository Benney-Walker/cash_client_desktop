import 'package:flutter/material.dart';

import 'auth/login_screen.dart';
import 'config/app_config.dart';
import 'settings/app_info.dart';
import 'settings/theme_controller.dart';
import 'settings/theme_mode_store.dart';
import 'shell/app_shell.dart';
import 'shell/sidebar_controller.dart';
import 'shell/sidebar_state_store.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  // Preferences and package info use platform channels, which need the
  // binding first.
  WidgetsFlutterBinding.ensureInitialized();

  // Read the saved light/dark choice and sidebar state before the first
  // frame, so the app doesn't open one way and then change.
  final theme = ThemeController(PrefsThemeModeStore());
  final sidebar = SidebarController(PrefsSidebarStateStore());
  final (_, _, appInfo) =
      await (theme.load(), sidebar.load(), AppInfo.load()).wait;

  runApp(CashClientApp(theme: theme, sidebar: sidebar, appInfo: appInfo));
}

class CashClientApp extends StatelessWidget {
  const CashClientApp({
    super.key,
    required this.theme,
    required this.sidebar,
    required this.appInfo,
  });

  final ThemeController theme;
  final SidebarController sidebar;
  final AppInfo appInfo;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: theme,
      builder: (context, _) => MaterialApp(
        title: 'Cash Client',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: theme.mode,
        // Sign-in isn't connected yet, so the app opens straight on the
        // shell. A sign-in gate will sit in front of it once the backend's
        // auth contract for the desktop app is confirmed. Until then the
        // sign-in screen can be reviewed with PREVIEW_LOGIN.
        home: AppConfig.previewLogin
            ? LoginScreen(appInfo: appInfo, onSignIn: _previewSignIn)
            : AppShell(theme: theme, sidebar: sidebar, appInfo: appInfo),
      ),
    );
  }
}

/// Stand-in for the backend while previewing: waits briefly so the
/// "Signing in…" state is visible, then reports that sign-in isn't connected.
Future<String?> _previewSignIn(String staffId, String password) async {
  await Future<void>.delayed(const Duration(milliseconds: 800));
  return "Sign-in isn't connected to the backend yet.";
}
