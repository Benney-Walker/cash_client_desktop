import 'package:flutter/material.dart';

import '../auth/auth_session.dart';
import '../branches/branch_api.dart';
import '../common/gradient_button.dart';
import '../shell/section_page.dart';
import 'add_staff_flow.dart';
import 'staff_api.dart';

/// The Staff section. For now: an "Add staff" button for administrators
/// above a placeholder for the staff list, which isn't built yet (owner
/// decision 15 November 2026).
///
/// Hiding the button from agents is only presentation: the backend refuses
/// add-staff from anyone but an administrator.
class StaffPage extends StatefulWidget {
  const StaffPage({
    super.key,
    required this.session,
    required this.api,
    required this.branchApi,
  });

  final AuthSession session;
  final StaffApi api;
  final BranchApi branchApi;

  @override
  State<StaffPage> createState() => _StaffPageState();
}

class _StaffPageState extends State<StaffPage> {
  bool _adding = false;

  @override
  Widget build(BuildContext context) {
    if (_adding) {
      return AddStaffFlow(
        api: widget.api,
        branchApi: widget.branchApi,
        onClose: () => setState(() => _adding = false),
      );
    }

    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final isAdministrator = widget.session.role == StaffRole.administrator;

    return SectionPage(
      key: const Key('page.staff'),
      title: 'Staff',
      maxContentWidth: 640,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isAdministrator) ...[
            GradientButton(
              key: const Key('staff.add'),
              onPressed: () => setState(() => _adding = true),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.person_add_alt_1_outlined),
                  SizedBox(width: 8),
                  Text('Add staff'),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
          Card(
            key: const Key('staff.listPlaceholder'),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.construction_outlined,
                      color: scheme.onSurfaceVariant),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Staff list not built yet',
                            style: textTheme.titleMedium),
                        const SizedBox(height: 4),
                        Text(
                          'The list of staff will be added in a later step.',
                          style: textTheme.bodyMedium
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
