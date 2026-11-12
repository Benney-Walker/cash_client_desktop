import 'package:flutter/material.dart';

import 'settings/theme_controller.dart';
import 'settings/theme_mode_store.dart';
import 'shell/app_shell.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  // Preferences use a platform channel, which needs the binding first.
  WidgetsFlutterBinding.ensureInitialized();

  // Read the light/dark choice before the first frame so the app doesn't
  // open in one theme and switch to the other.
  final theme = ThemeController(PrefsThemeModeStore());
  await theme.load();

  runApp(CashClientApp(theme: theme));
}

class CashClientApp extends StatelessWidget {
  const CashClientApp({super.key, required this.theme});

  final ThemeController theme;

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
        // Sign-in isn't built yet, so the app opens straight on the shell.
        // A sign-in gate will sit in front of it once the backend's auth
        // contract for the desktop app is confirmed.
        home: AppShell(theme: theme),
      ),
    );
  }
}
