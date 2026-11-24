import 'package:flutter/material.dart';

import '../auth/auth_session.dart';

/// The sections in the sidebar, top to bottom.
///
/// Names come from the confirmed responsibilities in CASH_CLIENT_DESKTOP.md.
/// The grouping and order are a first proposal for review. Both roles see
/// every section except those marked [administratorsOnly] (Phase 6, owner
/// decisions 24 November 2026). The sidebar only affects presentation; the
/// backend decides what a staff member can actually see and do.
enum AppSection {
  dashboard('Dashboard', Icons.space_dashboard_outlined, Icons.space_dashboard),
  members('Members', Icons.people_outline, Icons.people),
  transactions('Transactions', Icons.payments_outlined, Icons.payments),
  approvals(
    'Approvals',
    Icons.verified_user_outlined,
    Icons.verified_user,
    administratorsOnly: true,
  ),
  collectors('Collectors', Icons.badge_outlined, Icons.badge),
  submissions(
    'Daily submissions',
    Icons.fact_check_outlined,
    Icons.fact_check,
  ),
  loans('Loans', Icons.request_quote_outlined, Icons.request_quote),
  reports('Reports', Icons.insert_chart_outlined, Icons.insert_chart),
  staff('Staff', Icons.groups_outlined, Icons.groups),
  settings('Settings', Icons.settings_outlined, Icons.settings);

  const AppSection(
    this.label,
    this.icon,
    this.selectedIcon, {
    this.administratorsOnly = false,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;

  /// Hidden from Agents: the backend keeps the section's endpoints to
  /// Administrators (`/api/admin/**`). Owner decision 24 November 2026.
  final bool administratorsOnly;

  /// The sections [role] sees, in sidebar order. Presentation only: the
  /// backend checks the real roles on every request.
  static List<AppSection> visibleTo(StaffRole? role) => [
        for (final s in values)
          if (!s.administratorsOnly || role == StaffRole.administrator) s,
      ];
}
