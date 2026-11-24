import 'package:flutter/material.dart';

import '../api/apis.dart';
import '../approvals/approvals_page.dart';
import '../auth/auth_session.dart';
import '../auth/profile_controller.dart';
import '../common/brand_mark.dart';
import '../common/gradient_backdrop.dart';
import '../collectors/collectors_page.dart';
import '../config/app_config.dart';
import '../dashboard/dashboard_page.dart';
import '../members/members_page.dart';
import '../settings/app_info.dart';
import '../settings/settings_screen.dart';
import '../settings/theme_controller.dart';
import '../staff/staff_page.dart';
import '../submissions/submissions_page.dart';
import '../theme/app_gradients.dart';
import '../transactions/transactions_page.dart';
import 'app_section.dart';
import 'section_page.dart';
import 'sidebar_controller.dart';

/// The main window layout: a collapsible sidebar on the light gradient panel
/// (option D3) and the selected section's page beside it.
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.session,
    this.profile,
    required this.onSignOut,
    required this.apis,
    required this.theme,
    required this.sidebar,
    required this.appInfo,
    this.showMapTiles = true,
  });

  final AuthSession session;

  /// The signed-in staff member's profile, for their branch.
  final ProfileController? profile;
  final VoidCallback onSignOut;
  final Apis apis;
  final ThemeController theme;
  final SidebarController sidebar;
  final AppInfo appInfo;

  /// Off in tests, so the Collectors map downloads no tiles.
  final bool showMapTiles;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const double _expandedWidth = 248;

  AppSection _section = AppSection.dashboard;

  /// The Approvals tab to open, set when a dashboard card leads there.
  int _approvalsTab = 0;

  void _openFromDashboard(DashboardTarget target) {
    final (section, tab) = switch (target) {
      DashboardTarget.submissions => (AppSection.submissions, 0),
      DashboardTarget.idDocuments => (AppSection.approvals, 0),
      DashboardTarget.memberUpdates => (AppSection.approvals, 1),
      DashboardTarget.loanApplications => (AppSection.loans, 0),
      DashboardTarget.pendingMembers => (AppSection.members, 0),
    };
    setState(() {
      _section = section;
      _approvalsTab = tab;
    });
  }

  bool get _isAdministrator =>
      widget.session.role == StaffRole.administrator;

  List<AppSection> get _sections => AppSection.visibleTo(widget.session.role);

  String? get _branchName => widget.profile?.branchName;

  /// Agents' branch, for the "… branch only" chip on pages the backend
  /// limits to it (option B2). Null for Administrators, who see every
  /// branch, and until the profile is read.
  String? get _scopeBranch => _isAdministrator ? null : _branchName;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(
        [widget.sidebar, if (widget.profile != null) widget.profile!],
      ),
      builder: (context, _) => _buildLayout(widget.sidebar.expanded),
    );
  }

  Widget _buildLayout(bool expanded) {
    final sections = _sections;
    // A section this role can't use (only possible if the session changed
    // underneath) falls back to the dashboard.
    final current =
        sections.contains(_section) ? _section : AppSection.dashboard;
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
              selectedIndex: sections.indexOf(current),
              onDestinationSelected: (index) => setState(() {
                _section = sections[index];
                _approvalsTab = 0;
              }),
              destinations: [
                for (final section in sections)
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
          Expanded(child: _page(current)),
        ],
      ),
    );
  }

  Widget _railIcon(IconData icon, String label, bool expanded) =>
      expanded ? Icon(icon) : Tooltip(message: label, child: Icon(icon));

  Widget _page(AppSection section) => switch (section) {
        AppSection.members => MembersPage(
            api: widget.apis.members,
            branchApi: widget.apis.branches,
            approvalApi: widget.apis.approvals,
            isAdministrator: _isAdministrator,
          ),
        AppSection.approvals => ApprovalsPage(
            key: ValueKey('approvals-$_approvalsTab'),
            api: widget.apis.approvals,
            isAdministrator: _isAdministrator,
            initialTab: _approvalsTab,
          ),
        AppSection.collectors => CollectorsPage(
            api: widget.apis.collectors,
            staffApi: widget.apis.staff,
            scopeBranch: _scopeBranch,
            showTiles: widget.showMapTiles,
          ),
        AppSection.dashboard => DashboardPage(
            api: widget.apis.dashboard,
            branchApi: widget.apis.branches,
            staffName: widget.session.staffName,
            isAdministrator: _isAdministrator,
            scopeBranch: _scopeBranch,
            onOpen: _openFromDashboard,
          ),
        AppSection.transactions => TransactionsPage(
            api: widget.apis.transactions,
            memberApi: widget.apis.members,
            staffId: widget.session.staffId,
            creditUnionName: AppConfig.creditUnionName,
          ),
        AppSection.submissions => SubmissionsPage(
            api: widget.apis.submissions,
            scopeBranch: _scopeBranch,
          ),
        AppSection.staff => StaffPage(
            session: widget.session,
            api: widget.apis.staff,
            branchApi: widget.apis.branches,
            scopeBranch: _scopeBranch,
          ),
        AppSection.settings => SettingsScreen(
            session: widget.session,
            branchName: _branchName,
            onSignOut: widget.onSignOut,
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
