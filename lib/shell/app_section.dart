import 'package:flutter/material.dart';

/// The sections in the sidebar, top to bottom.
///
/// Names come from the confirmed responsibilities in CASH_CLIENT_DESKTOP.md.
/// The grouping and order are a first proposal for review. None of the
/// sections has screens yet, and which ones each role sees will be decided
/// once sign-in exists and the backend's permissions are confirmed. Until
/// then every section is listed. The sidebar only affects presentation; the
/// backend decides what a staff member can actually see and do.
enum AppSection {
  dashboard('Dashboard', Icons.space_dashboard_outlined, Icons.space_dashboard),
  members('Members', Icons.people_outline, Icons.people),
  withdrawals('Withdrawals', Icons.payments_outlined, Icons.payments),
  collectors('Collectors', Icons.badge_outlined, Icons.badge),
  submissions(
    'Daily submissions',
    Icons.fact_check_outlined,
    Icons.fact_check,
  ),
  loans('Loans', Icons.request_quote_outlined, Icons.request_quote),
  staff('Staff', Icons.groups_outlined, Icons.groups),
  settings('Settings', Icons.settings_outlined, Icons.settings);

  const AppSection(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
