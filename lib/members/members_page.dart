import 'package:flutter/material.dart';

import '../approvals/approval_api.dart';
import '../branches/branch_api.dart';
import '../loans/loan_api.dart';
import '../loans/loan_application_flow.dart';
import '../reports/report_api.dart';
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
    this.approvalApi,
    this.loanApi,
    this.reportApi,
    this.isAdministrator = false,
    this.pickImage = pickKycImageFile,
    this.acceptDrops = true,
  });

  final MemberApi api;
  final BranchApi branchApi;

  /// For Administrators, to say when a member has a change waiting in
  /// Approvals.
  final ApprovalApi? approvalApi;

  /// For the member's Loans card and "Apply for a loan".
  final LoanApi? loanApi;

  /// For "Statement" beside each of a member's accounts.
  final ReportApi? reportApi;

  /// Administrators edit contact details directly; Agents send a request
  /// (owner decision 24 November 2026).
  final bool isAdministrator;

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

  /// Set while "Apply for a loan" is open from a member's details.
  PickedMember? _applyingFor;

  /// Bumped to reload the details after an application.
  int _detailsRun = 0;

  @override
  Widget build(BuildContext context) {
    final applyingFor = _applyingFor;
    final loanApi = widget.loanApi;
    if (applyingFor != null && loanApi != null) {
      return LoanApplicationFlow(
        api: loanApi,
        memberApi: widget.api,
        member: applyingFor,
        closeLabel: 'Members',
        onClose: () => setState(() {
          _applyingFor = null;
          _detailsRun++;
        }),
      );
    }
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
                              key: ValueKey('$selected-$_detailsRun'),
                              api: widget.api,
                              memberId: selected,
                              approvalApi: widget.approvalApi,
                              loanApi: widget.loanApi,
                              reportApi: widget.reportApi,
                              onApplyForLoan: widget.loanApi == null
                                  ? null
                                  : (m) => setState(() => _applyingFor = m),
                              isAdministrator: widget.isAdministrator,
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
