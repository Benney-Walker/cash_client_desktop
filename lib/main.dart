import 'package:flutter/material.dart';

import 'auth/auth_api.dart';
import 'auth/auth_gate.dart';
import 'auth/session_manager.dart';
import 'config/app_config.dart';
import 'settings/app_info.dart';
import 'settings/theme_controller.dart';
import 'settings/theme_mode_store.dart';
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

  // No stored session to restore: staff sign in each time the app opens.
  final sessions = SessionManager(
    api: AuthApi(baseUrl: AppConfig.apiBaseUrl),
  );

  runApp(CashClientApp(
    sessions: sessions,
    theme: theme,
    sidebar: sidebar,
    appInfo: appInfo,
  ));
}

class CashClientApp extends StatelessWidget {
  const CashClientApp({
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
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: theme,
      builder: (context, _) => MaterialApp(
        title: 'Cash Client',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: theme.mode,
        home: AuthGate(
          sessions: sessions,
          theme: theme,
          sidebar: sidebar,
          appInfo: appInfo,
        ),
      ),
    );
  }
}
