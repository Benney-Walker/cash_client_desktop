import 'package:flutter/material.dart';

import '../settings/settings_screen.dart';
import '../settings/theme_controller.dart';
import 'app_section.dart';
import 'section_page.dart';

/// The main window layout: a collapsible sidebar on the left and the selected
/// section's page beside it.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.theme});

  final ThemeController theme;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const double _expandedWidth = 248;

  AppSection _section = AppSection.dashboard;

  // Starts expanded: the window opens maximised, so there's room for labels.
  bool _expanded = true;

  void _toggleSidebar() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NavigationRail(
            key: const Key('shell.sidebar'),
            extended: _expanded,
            minExtendedWidth: _expandedWidth,
            // Labels show beside the icons when expanded. Collapsed, the rail
            // is icons only and each icon has a tooltip instead.
            labelType: NavigationRailLabelType.none,
            leading: _SidebarHeader(
              expanded: _expanded,
              onToggle: _toggleSidebar,
            ),
            selectedIndex: _section.index,
            onDestinationSelected: (index) =>
                setState(() => _section = AppSection.values[index]),
            destinations: [
              for (final section in AppSection.values)
                NavigationRailDestination(
                  icon: _railIcon(section.icon, section.label),
                  selectedIcon: _railIcon(section.selectedIcon, section.label),
                  label: Text(section.label),
                ),
            ],
          ),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(child: _page(_section)),
        ],
      ),
    );
  }

  Widget _railIcon(IconData icon, String label) =>
      _expanded ? Icon(icon) : Tooltip(message: label, child: Icon(icon));

  Widget _page(AppSection section) => switch (section) {
        AppSection.settings => SettingsScreen(theme: widget.theme),
        _ => SectionPlaceholder(
            key: Key('page.${section.name}'),
            section: section,
          ),
      };
}

/// The app name and the collapse/expand button at the top of the sidebar.
class _SidebarHeader extends StatelessWidget {
  const _SidebarHeader({required this.expanded, required this.onToggle});

  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final toggle = IconButton(
      key: const Key('shell.toggleSidebar'),
      tooltip: expanded ? 'Collapse sidebar' : 'Expand sidebar',
      onPressed: onToggle,
      icon: Icon(expanded ? Icons.menu_open : Icons.menu),
    );

    if (!expanded) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: toggle,
      );
    }

    // The rail centres its leading widget, so the header is given the full
    // expanded width to keep the name on the left with the toggle at the end.
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 8, 12),
      child: SizedBox(
        width: _AppShellState._expandedWidth - 28,
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Cash Client',
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: textTheme.titleMedium?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            toggle,
          ],
        ),
      ),
    );
  }
}
