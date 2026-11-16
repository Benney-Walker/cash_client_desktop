import 'package:flutter/material.dart';

import '../branches/branch_api.dart';
import '../common/glass_card.dart';
import '../common/gradient_backdrop.dart';
import '../common/gradient_button.dart';
import 'kyc_image_picker.dart';
import 'member_api.dart';
import 'member_details_pane.dart';
import 'member_search_pane.dart';
import 'register_member_flow.dart';

/// The Members section (design P2): find a member on the left, their
/// details on the right, and "Register member" at the top. Administrators
/// and agents both use it; what each may see is decided by the backend
/// (CASH_CLIENT_DESKTOP.md section 18).
class MembersPage extends StatefulWidget {
  const MembersPage({
    super.key,
    required this.api,
    required this.branchApi,
    this.pickImage = pickKycImageFile,
    this.acceptDrops = true,
  });

  final MemberApi api;
  final BranchApi branchApi;

  /// Replaced in tests, with [acceptDrops] off (no drag-and-drop plugin
  /// there).
  final PickKycImage pickImage;
  final bool acceptDrops;

  @override
  State<MembersPage> createState() => _MembersPageState();
}

class _MembersPageState extends State<MembersPage> {
  bool _registering = false;
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    if (_registering) {
      return RegisterMemberFlow(
        api: widget.api,
        branchApi: widget.branchApi,
        pickImage: widget.pickImage,
        acceptDrops: widget.acceptDrops,
        onClose: () => setState(() => _registering = false),
        onViewMember: (memberId) => setState(() {
          _registering = false;
          _selectedId = memberId;
        }),
      );
    }

    final textTheme = Theme.of(context).textTheme;
    final selected = _selectedId;

    return Stack(
      key: const Key('page.members'),
      children: [
        const Positioned.fill(child: PageGlows()),
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 28, 32, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Members',
                      style: textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
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
                ],
              ),
              const SizedBox(height: 20),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 380,
                      child: MemberSearchPane(
                        api: widget.api,
                        selectedId: selected,
                        onSelect: (id) => setState(() => _selectedId = id),
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: selected == null
                          ? const _NothingSelected()
                          : MemberDetailsPane(
                              key: ValueKey(selected),
                              api: widget.api,
                              memberId: selected,
                              pickImage: widget.pickImage,
                              acceptDrops: widget.acceptDrops,
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NothingSelected extends StatelessWidget {
  const _NothingSelected();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Align(
      alignment: Alignment.topLeft,
      child: GlassCard(
        key: const Key('members.nothingSelected'),
        title: 'Member details',
        icon: Icons.person_search_outlined,
        child: Text(
          'Search by name, phone number or account number, then choose a '
          'member to see their details and accounts.',
          style: textTheme.bodyMedium,
        ),
      ),
    );
  }
}
