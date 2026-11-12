import 'package:flutter/material.dart';

import '../shell/section_page.dart';
import '../shell/sidebar_controller.dart';
import 'app_info.dart';
import 'theme_controller.dart';

/// Settings, laid out as one column of section cards (option A, chosen by
/// the owner).
///
/// The agreed order is Account, Password, Appearance, About. Account and
/// Password need sign-in, so they'll be added above Appearance when sign-in
/// is built.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
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
    return SectionPage(
      title: 'Settings',
      maxContentWidth: 560,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SettingsCard(
            key: const Key('settings.appearance'),
            title: 'Appearance',
            child: _AppearanceSection(theme: theme, sidebar: sidebar),
          ),
          const SizedBox(height: 16),
          _SettingsCard(
            key: const Key('settings.about'),
            title: 'About',
            child: _AboutSection(appInfo: appInfo),
          ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _AppearanceSection extends StatelessWidget {
  const _AppearanceSection({required this.theme, required this.sidebar});

  final ThemeController theme;
  final SidebarController sidebar;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
              const SizedBox(height: 8),
              Text(
                _describe(theme.mode),
                key: const Key('settings.themeModeHint'),
                style: textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Divider(),
        ListenableBuilder(
          listenable: sidebar,
          // The whole row toggles the switch, not just the knob.
          builder: (context, _) => SwitchListTile(
            key: const Key('settings.rememberSidebar'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Remember sidebar state'),
            subtitle: const Text('Reopen with the sidebar as you left it'),
            value: sidebar.remember,
            onChanged: sidebar.setRemember,
          ),
        ),
      ],
    );
  }

  static String _describe(ThemeMode mode) => switch (mode) {
        ThemeMode.system => "Matches your computer's light or dark setting.",
        ThemeMode.light => 'Always light.',
        ThemeMode.dark => 'Always dark.',
      };
}

class _AboutSection extends StatelessWidget {
  const _AboutSection({required this.appInfo});

  final AppInfo appInfo;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AboutRow(
          key: const Key('settings.version'),
          label: 'Version',
          value: appInfo.versionLabel,
        ),
        const SizedBox(height: 8),
        _AboutRow(
          key: const Key('settings.server'),
          label: 'Server',
          value: appInfo.serverLabel,
        ),
      ],
    );
  }
}

class _AboutRow extends StatelessWidget {
  const _AboutRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Text(
            label,
            style:
                textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
        // Selectable so the server address can be copied into a support
        // message.
        Expanded(child: SelectableText(value, style: textTheme.bodyMedium)),
      ],
    );
  }
}
