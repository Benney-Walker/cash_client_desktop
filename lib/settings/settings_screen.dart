import 'package:flutter/material.dart';

import '../auth/auth_session.dart';
import '../common/gradient_backdrop.dart';
import '../common/gradient_icon_tile.dart';
import '../common/gradient_switch.dart';
import '../common/initials_avatar.dart';
import '../common/names.dart';
import '../shell/section_page.dart';
import '../shell/sidebar_controller.dart';
import '../theme/app_gradients.dart';
import '../theme/app_theme.dart';
import 'app_info.dart';
import 'theme_controller.dart';

/// Settings, laid out as one column of section cards (option A), styled as
/// frosted glass cards over soft gradient glows (option S3).
///
/// The agreed order is Account, Password, Appearance, About. Password reset
/// is kept out of the app for now (owner decision 13 November 2026), so
/// there's no Password card.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.session,
    required this.onSignOut,
    required this.theme,
    required this.sidebar,
    required this.appInfo,
  });

  final AuthSession session;
  final VoidCallback onSignOut;
  final ThemeController theme;
  final SidebarController sidebar;
  final AppInfo appInfo;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(child: PageGlows()),
        SectionPage(
          title: 'Settings',
          maxContentWidth: 560,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SettingsCard(
                key: const Key('settings.account'),
                title: 'Account',
                icon: Icons.person_outline,
                child: _AccountSection(session: session, onSignOut: onSignOut),
              ),
              const SizedBox(height: 16),
              _SettingsCard(
                key: const Key('settings.appearance'),
                title: 'Appearance',
                icon: Icons.palette_outlined,
                child: _AppearanceSection(theme: theme, sidebar: sidebar),
              ),
              const SizedBox(height: 16),
              _SettingsCard(
                key: const Key('settings.about'),
                title: 'About',
                icon: Icons.info_outline,
                child: _AboutSection(appInfo: appInfo),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A frosted card: semi-transparent so the page glows show through, with a
/// gradient icon tile beside the title.
class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final gradients = AppGradients.of(context);

    return Card(
      color: gradients.glassCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        side: BorderSide(color: gradients.glassCardBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                GradientIconTile(icon: icon),
                const SizedBox(width: 10),
                Text(title, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

/// Who is signed in, and Sign out.
///
/// The login response gives the name, staff ID and roles, but not the
/// branch, and there's no endpoint for staff to read their own profile, so
/// the branch isn't shown yet.
class _AccountSection extends StatelessWidget {
  const _AccountSection({required this.session, required this.onSignOut});

  final AuthSession session;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final role = session.role;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            InitialsAvatar(name: session.staffName),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName(session.staffName),
                    key: const Key('settings.staffName'),
                    style: textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    [if (role != null) role.label, session.staffId]
                        .join(' · '),
                    key: const Key('settings.staffDetails'),
                    style: textTheme.bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Not a primary action, so an outlined button rather than the
        // gradient one. No confirmation: signing back in is quick.
        OutlinedButton.icon(
          key: const Key('settings.signOut'),
          onPressed: onSignOut,
          icon: const Icon(Icons.logout),
          label: const Text('Sign out'),
        ),
      ],
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
          // The whole row toggles the switch, not just the knob, and screen
          // readers hear the label and the switch as one control.
          builder: (context, _) => MergeSemantics(
            child: ListTile(
              key: const Key('settings.rememberSidebar'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Remember sidebar state'),
              subtitle: const Text('Reopen with the sidebar as you left it'),
              trailing: GradientSwitch(
                value: sidebar.remember,
                onChanged: sidebar.setRemember,
              ),
              onTap: () => sidebar.setRemember(!sidebar.remember),
            ),
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
