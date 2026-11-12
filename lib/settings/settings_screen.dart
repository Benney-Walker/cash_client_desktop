import 'package:flutter/material.dart';

import '../shell/section_page.dart';
import 'theme_controller.dart';

/// Settings for this computer. For now that's only the light/dark choice;
/// account details and sign-out come with sign-in.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.theme});

  final ThemeController theme;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return SectionPage(
      title: 'Settings',
      maxContentWidth: 560,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Appearance', style: textTheme.titleMedium),
          const SizedBox(height: 12),
          ListenableBuilder(
            listenable: theme,
            builder: (context, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<ThemeMode>(
                  key: const Key('settings.themeMode'),
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.system,
                      label: Text('System'),
                      icon: Icon(Icons.brightness_auto_outlined),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      label: Text('Light'),
                      icon: Icon(Icons.light_mode_outlined),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      label: Text('Dark'),
                      icon: Icon(Icons.dark_mode_outlined),
                    ),
                  ],
                  selected: {theme.mode},
                  onSelectionChanged: (selection) =>
                      theme.setMode(selection.single),
                ),
                const SizedBox(height: 12),
                Text(
                  _describe(theme.mode),
                  key: const Key('settings.themeModeHint'),
                  style: textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _describe(ThemeMode mode) => switch (mode) {
        ThemeMode.system => "Matches your computer's light or dark setting.",
        ThemeMode.light => 'Always light.',
        ThemeMode.dark => 'Always dark.',
      };
}
