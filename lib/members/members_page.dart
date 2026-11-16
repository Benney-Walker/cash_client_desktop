import 'package:flutter/material.dart';

import '../branches/branch_api.dart';
import '../common/gradient_button.dart';
import '../shell/section_page.dart';
import 'member_api.dart';
import 'register_member_flow.dart';

/// The Members section. For now: a "Register member" button above a
/// placeholder for the member list, which isn't built yet. Administrators
/// and agents can both register members (CASH_CLIENT_DESKTOP.md section 4).
class MembersPage extends StatefulWidget {
  const MembersPage({
    super.key,
    required this.api,
    required this.branchApi,
  });

  final MemberApi api;
  final BranchApi branchApi;

  @override
  State<MembersPage> createState() => _MembersPageState();
}

class _MembersPageState extends State<MembersPage> {
  bool _registering = false;

  @override
  Widget build(BuildContext context) {
    if (_registering) {
      return RegisterMemberFlow(
        api: widget.api,
        branchApi: widget.branchApi,
        onClose: () => setState(() => _registering = false),
      );
    }

    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return SectionPage(
      key: const Key('page.members'),
      title: 'Members',
      maxContentWidth: 640,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GradientButton(
            key: const Key('members.register'),
            onPressed: () => setState(() => _registering = true),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.person_add_alt_1_outlined),
                SizedBox(width: 8),
                Text('Register member'),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Card(
            key: const Key('members.listPlaceholder'),
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
                        Text('Member list not built yet',
                            style: textTheme.titleMedium),
                        const SizedBox(height: 4),
                        Text(
                          'Searching, viewing and editing members will be '
                          'added in a later step.',
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
