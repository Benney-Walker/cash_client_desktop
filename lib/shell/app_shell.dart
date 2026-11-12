import 'package:flutter/material.dart';

import '../common/brand_mark.dart';
import '../common/gradient_backdrop.dart';
import '../settings/app_info.dart';
import '../settings/settings_screen.dart';
import '../settings/theme_controller.dart';
import '../theme/app_gradients.dart';
import 'app_section.dart';
import 'section_page.dart';
import 'sidebar_controller.dart';

/// The main window layout: a collapsible sidebar on the light gradient panel
/// (option D3) and the selected section's page beside it.
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.theme,
    required this.sidebar,
    required this.appInfo,
  });

  final ThemeController theme;
  final SidebarController sidebar;
  final AppInfo appInfo;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const double _expandedWidth = 248;

  AppSection _section = AppSection.dashboard;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.sidebar,
      builder: (context, _) => _buildLayout(widget.sidebar.expanded),
    );
  }

  Widget _buildLayout(bool expanded) {
    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The gradient's own edge separates the sidebar from the page, so
          // there's no divider line.
          GradientBackdrop(
            child: NavigationRail(
              key: const Key('shell.sidebar'),
              extended: expanded,
              minExtendedWidth: _expandedWidth,
              // Labels show beside the icons when expanded. Collapsed, the
              // rail is icons only and each icon has a tooltip instead.
              labelType: NavigationRailLabelType.none,
              leading: _SidebarHeader(
                expanded: expanded,
                onToggle: widget.sidebar.toggle,
              ),
              selectedIndex: _section.index,
              onDestinationSelected: (index) =>
                  setState(() => _section = AppSection.values[index]),
              destinations: [
                for (final section in AppSection.values)
                  NavigationRailDestination(
                    icon: _railIcon(section.icon, section.label, expanded),
                    selectedIcon: _railIcon(
                      section.selectedIcon,
                      section.label,
                      expanded,
                    ),
                    label: Text(section.label),
                  ),
              ],
            ),
          ),
          Expanded(child: _page(_section)),
        ],
      ),
    );
  }

  Widget _railIcon(IconData icon, String label, bool expanded) =>
      expanded ? Icon(icon) : Tooltip(message: label, child: Icon(icon));

  Widget _page(AppSection section) => switch (section) {
        AppSection.settings => SettingsScreen(
            theme: widget.theme,
            sidebar: widget.sidebar,
            appInfo: widget.appInfo,
          ),
        _ => SectionPlaceholder(
            key: Key('page.${section.name}'),
            section: section,
          ),
      };
}

/// The "CC" tile, the app name and the collapse/expand button at the top of
/// the sidebar.
class _SidebarHeader extends StatelessWidget {
  const _SidebarHeader({required this.expanded, required this.onToggle});

  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final gradients = AppGradients.of(context);
    final textTheme = Theme.of(context).textTheme;

    final toggle = IconButton(
      key: const Key('shell.toggleSidebar'),
      tooltip: expanded ? 'Collapse sidebar' : 'Expand sidebar',
      color: gradients.panelTextSecondary,
      onPressed: onToggle,
      icon: Icon(expanded ? Icons.menu_open : Icons.menu),
    );

    if (!expanded) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: [
            const BrandMark(size: 32),
            const SizedBox(height: 8),
            toggle,
          ],
        ),
      );
    }

    // The rail centres its leading widget, so the header is given the full
    // expanded width to keep the name on the left with the toggle at the end.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: SizedBox(
        width: _AppShellState._expandedWidth - 24,
        child: Row(
          children: [
            const BrandMark(size: 32),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Cash Client',
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: textTheme.titleMedium?.copyWith(
                  color: gradients.panelText,
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
