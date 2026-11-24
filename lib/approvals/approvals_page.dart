import 'package:flutter/material.dart';

import '../common/dates.dart';
import '../common/glass_card.dart';
import '../common/gradient_backdrop.dart';
import '../common/gradient_button.dart';
import '../common/step_flow.dart';
import '../theme/app_gradients.dart';
import 'approval_api.dart';
import 'review_queue.dart';
import 'review_widgets.dart';

/// The Approvals section (option K2, owner decisions 24 November 2026): two
/// tabs, ID documents and Member updates, each a queue beside its review
/// pane.
///
/// Reviewing is Administrator-only on the backend (`/api/admin/**`), so an
/// Agent sees an explanation instead. Agents follow their own update
/// requests on each member's details.
class ApprovalsPage extends StatefulWidget {
  const ApprovalsPage({
    super.key,
    required this.api,
    required this.isAdministrator,
  });

  final ApprovalApi api;
  final bool isAdministrator;

  @override
  State<ApprovalsPage> createState() => _ApprovalsPageState();
}

class _ApprovalsPageState extends State<ApprovalsPage>
    with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 2, vsync: this)
    ..addListener(() {
      if (mounted) setState(() {});
    });
  int? _kycWaiting;
  int? _updatesWaiting;

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  static String _label(String name, int? count) =>
      count == null || count == 0 ? name : '$name ($count)';

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Stack(
      key: const Key('page.approvals'),
      children: [
        const Positioned.fill(child: PageGlows()),
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 28, 32, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Approvals',
                style: textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              if (!widget.isAdministrator)
                const Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(width: 560, child: _AgentsNote()),
                )
              else ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: TabBar(
                    controller: _tabs,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    tabs: [
                      Tab(
                        key: const Key('approvals.tab.kyc'),
                        text: _label('ID documents', _kycWaiting),
                      ),
                      Tab(
                        key: const Key('approvals.tab.updates'),
                        text: _label('Member updates', _updatesWaiting),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  // Both tabs stay alive, so switching keeps each list and
                  // its selection.
                  child: IndexedStack(
                    index: _tabs.index,
                    children: [
                      ReviewQueue<KycReviewStatus, KycRecord>(
                        keyPrefix: 'kyc',
                        statuses: KycReviewStatus.values,
                        statusLabel: (s) => s.label,
                        statusKey: (s) => s.name,
                        load: (s, page) => widget.api.listKyc(s, page: page),
                        idOf: (r) => r.memberId,
                        titleOf: (r) => r.memberName,
                        subtitleOf: (r) => [
                          r.documentType?.label,
                          if (r.submittedAt != null) dateAndTime(r.submittedAt!),
                        ].whereType<String>().join(' · '),
                        pane: (r, onReviewed) => KycReviewPane(
                          api: widget.api,
                          record: r,
                          onReviewed: onReviewed,
                        ),
                        emptyText: (s) => switch (s) {
                          KycReviewStatus.manualReview =>
                            'No ID documents need review.',
                          KycReviewStatus.pending =>
                            'No ID documents are waiting for the automatic '
                                'check.',
                          KycReviewStatus.verified =>
                            'No verified ID documents yet.',
                          KycReviewStatus.rejected =>
                            'No rejected ID documents.',
                        },
                        nothingSelected: 'Choose a member on the left to see '
                            'their ID picture and approve or reject it.',
                        nothingSelectedIcon: Icons.badge_outlined,
                        onWaitingCount: (n) =>
                            setState(() => _kycWaiting = n),
                      ),
                      ReviewQueue<MemberUpdateStatus,
                          MemberUpdateRequestRecord>(
                        keyPrefix: 'upd',
                        statuses: MemberUpdateStatus.values,
                        statusLabel: (s) => s.label,
                        statusKey: (s) => s.name,
                        load: (s, page) =>
                            widget.api.listUpdates(s, page: page),
                        idOf: (r) => r.requestId,
                        titleOf: (r) => r.memberName,
                        subtitleOf: (r) => [
                          r.branchName,
                          if (r.requestedBy != null) 'by ${r.requestedBy}',
                          if (r.requestedAt != null) dateAndTime(r.requestedAt!),
                        ].whereType<String>().join(' · '),
                        pane: (r, onReviewed) => MemberUpdateReviewPane(
                          api: widget.api,
                          request: r,
                          onReviewed: onReviewed,
                        ),
                        emptyText: (s) => switch (s) {
                          MemberUpdateStatus.pending =>
                            'No member updates are waiting.',
                          MemberUpdateStatus.approved =>
                            'No approved member updates yet.',
                          MemberUpdateStatus.rejected =>
                            'No rejected member updates.',
                        },
                        nothingSelected: 'Choose a request on the left to '
                            'compare the new details with the current ones.',
                        nothingSelectedIcon: Icons.edit_note_outlined,
                        onWaitingCount: (n) =>
                            setState(() => _updatesWaiting = n),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _AgentsNote extends StatelessWidget {
  const _AgentsNote();

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      key: const Key('approvals.agentsNote'),
      title: 'For administrators',
      icon: Icons.verified_user_outlined,
      child: Text(
        'Administrators review ID documents and member updates here. To '
        "change a member's phone number, address or occupation, open the "
        'member and choose "Request a change"; the request and its outcome '
        'show on that member.',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}

/// Approve and Reject, shared by both panes: busy state, the error, and
/// the rejection dialog.
mixin _ReviewActions<W extends StatefulWidget> on State<W> {
  bool busy = false;
  String? error;

  Future<void> runReview(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => error = approvalErrorMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget actionRow({
    required String keyPrefix,
    required String approveLabel,
    required VoidCallback onApprove,
    required VoidCallback onReject,
  }) {
    return Row(
      children: [
        GradientButton(
          key: Key('$keyPrefix.approve'),
          onPressed: busy ? null : onApprove,
          child: busy
              ? SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppGradients.of(context).onButton,
                  ),
                )
              : Text(approveLabel),
        ),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          key: Key('$keyPrefix.reject'),
          onPressed: busy ? null : onReject,
          icon: const Icon(Icons.close),
          label: const Text('Reject'),
        ),
      ],
    );
  }
}

StatusPill _kycStatusPill(KycReviewStatus status) => switch (status) {
      KycReviewStatus.manualReview => const StatusPill(
          label: 'Needs review', tone: StatusTone.warning),
      KycReviewStatus.pending => const StatusPill(
          label: 'Waiting for the automatic check',
          tone: StatusTone.neutral,
          icon: Icons.hourglass_empty,
        ),
      KycReviewStatus.verified =>
        const StatusPill(label: 'Verified', tone: StatusTone.success),
      KycReviewStatus.rejected =>
        const StatusPill(label: 'Rejected', tone: StatusTone.danger),
    };

/// One ID document: the picture, its details and, while it can still be
/// reviewed, Approve and Reject.
class KycReviewPane extends StatefulWidget {
  const KycReviewPane({
    super.key,
    required this.api,
    required this.record,
    required this.onReviewed,
  });

  final ApprovalApi api;
  final KycRecord record;
  final OnReviewed onReviewed;

  @override
  State<KycReviewPane> createState() => _KycReviewPaneState();
}

class _KycReviewPaneState extends State<KycReviewPane>
    with _ReviewActions<KycReviewPane> {
  KycRecord get _r => widget.record;

  Future<void> _approve() => runReview(() async {
        await widget.api.approveKyc(_r.memberId);
        widget.onReviewed(
            "${_r.memberName}'s ID approved. They and their accounts are "
            'now active.');
      });

  Future<void> _reject() async {
    final reason = await askRejectionReason(
      context,
      title: "Reject ${_r.memberName}'s ID document?",
      explanation: 'The member stays pending with inactive accounts. The '
          'staff member who registered them sees this reason and can upload '
          'a new document.',
      presets: RejectionReasons.idDocument,
    );
    if (reason == null) return;
    await runReview(() async {
      await widget.api.rejectKyc(_r.memberId, reason);
      widget.onReviewed("${_r.memberName}'s ID rejected.");
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final reasonLabel = switch (_r.status) {
      KycReviewStatus.rejected => 'Rejection reason',
      _ => 'Why it needs review',
    };
    final rows = <(String, String?)>[
      ('Document', _r.documentType?.label),
      ('ID number', _r.idNumber),
      ('Registered by', _r.registeredBy),
      (
        'Submitted',
        _r.submittedAt == null ? null : dateAndTime(_r.submittedAt!),
      ),
      (reasonLabel, _r.reason),
      (
        'Reviewed by',
        _r.automatic ? 'Automatic check' : _r.reviewedBy,
      ),
      (
        'Verified',
        _r.verifiedAt == null ? null : dateAndTime(_r.verifiedAt!),
      ),
    ];
    final err = error;

    return ListView(
      key: const Key('kyc.pane'),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _r.memberName,
                key: const Key('kyc.name'),
                style: textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            _kycStatusPill(_r.status),
          ],
        ),
        const SizedBox(height: 16),
        KycPictureViewer(api: widget.api, memberId: _r.memberId),
        const SizedBox(height: 16),
        GlassCard(
          key: const Key('kyc.details'),
          title: 'Details',
          icon: Icons.badge_outlined,
          child: Column(
            children: [
              for (final (label, value) in rows)
                if (value != null)
                  ReviewRow(
                    key: Key('kyc.field.$label'),
                    label: label,
                    value: value,
                  ),
            ],
          ),
        ),
        if (_r.status.reviewable) ...[
          const SizedBox(height: 16),
          const InfoNote(
            text: 'Approving verifies the document and activates the member '
                'and their accounts. Check the name and ID number against the '
                'picture first.',
          ),
          if (err != null) ...[
            const SizedBox(height: 12),
            ErrorBanner(key: const Key('kyc.error'), message: err),
          ],
          const SizedBox(height: 16),
          actionRow(
            keyPrefix: 'kyc',
            approveLabel: 'Approve',
            onApprove: _approve,
            onReject: _reject,
          ),
        ],
      ],
    );
  }
}

/// One member update request: current and proposed values side by side and,
/// while it's waiting, Approve and Reject.
class MemberUpdateReviewPane extends StatefulWidget {
  const MemberUpdateReviewPane({
    super.key,
    required this.api,
    required this.request,
    required this.onReviewed,
  });

  final ApprovalApi api;
  final MemberUpdateRequestRecord request;
  final OnReviewed onReviewed;

  @override
  State<MemberUpdateReviewPane> createState() =>
      _MemberUpdateReviewPaneState();
}

class _MemberUpdateReviewPaneState extends State<MemberUpdateReviewPane>
    with _ReviewActions<MemberUpdateReviewPane> {
  MemberUpdateRequestRecord get _r => widget.request;

  Future<void> _approve() => runReview(() async {
        await widget.api.approveUpdate(_r.requestId);
        widget.onReviewed(
            "${_r.memberName}'s new details saved. The member gets an SMS.");
      });

  Future<void> _reject() async {
    final reason = await askRejectionReason(
      context,
      title: "Reject the change to ${_r.memberName}'s details?",
      explanation: "The member's details stay as they are. "
          '${_r.requestedBy ?? 'The staff member who asked'} sees this '
          'reason on the member.',
      presets: RejectionReasons.memberUpdate,
    );
    if (reason == null) return;
    await runReview(() async {
      await widget.api.rejectUpdate(_r.requestId, reason);
      widget.onReviewed("Change to ${_r.memberName}'s details rejected.");
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final pill = switch (_r.status) {
      MemberUpdateStatus.pending =>
        const StatusPill(label: 'Waiting', tone: StatusTone.warning),
      MemberUpdateStatus.approved =>
        const StatusPill(label: 'Approved', tone: StatusTone.success),
      MemberUpdateStatus.rejected =>
        const StatusPill(label: 'Rejected', tone: StatusTone.danger),
    };
    final fields = [
      ('Phone number', _r.current.phoneNumber, _r.proposed.phoneNumber),
      ('Address', _r.current.residentialAddress, _r.proposed.residentialAddress),
      ('Occupation', _r.current.occupation, _r.proposed.occupation),
    ];
    final header = textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant);
    final pending = _r.status == MemberUpdateStatus.pending;
    final err = error;

    return ListView(
      key: const Key('upd.pane'),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _r.memberName,
                key: const Key('upd.name'),
                style: textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            pill,
          ],
        ),
        const SizedBox(height: 16),
        GlassCard(
          key: const Key('upd.compare'),
          title: pending ? 'Proposed change' : 'Requested change',
          icon: Icons.compare_arrows,
          child: Table(
            columnWidths: const {
              0: FixedColumnWidth(140),
              1: FlexColumnWidth(),
              2: FlexColumnWidth(),
            },
            children: [
              TableRow(children: [
                const SizedBox.shrink(),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(pending ? 'Now' : 'Member now', style: header),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(pending ? 'New' : 'Requested', style: header),
                ),
              ]),
              for (final (label, now, next) in fields)
                TableRow(
                  key: ValueKey('upd.row.$label'),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(label, style: header),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(now ?? '—', style: textTheme.bodyMedium),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      // The backend's "current" values are the member's
                      // values today, so after a review they can't show
                      // what changed; only a waiting request says "No
                      // change".
                      child: pending && now == next
                          ? Text(
                              'No change',
                              style: textTheme.bodyMedium
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            )
                          : Text(
                              next ?? '—',
                              key: Key('upd.new.$label'),
                              style: textTheme.bodyMedium?.copyWith(
                                fontWeight: now == next
                                    ? FontWeight.w400
                                    : FontWeight.w600,
                              ),
                            ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        GlassCard(
          key: const Key('upd.details'),
          title: 'Request',
          icon: Icons.history,
          child: Column(
            children: [
              if (_r.branchName != null)
                ReviewRow(label: 'Branch', value: _r.branchName!),
              if (_r.requestedBy != null)
                ReviewRow(
                  label: 'Requested by',
                  value: [
                    _r.requestedBy!,
                    if (_r.requestedAt != null) dateAndTime(_r.requestedAt!),
                  ].join(' · '),
                ),
              if (_r.reviewedBy != null)
                ReviewRow(
                  label: 'Reviewed by',
                  value: [
                    _r.reviewedBy!,
                    if (_r.reviewedAt != null) dateAndTime(_r.reviewedAt!),
                  ].join(' · '),
                ),
              if (_r.rejectionReason != null)
                ReviewRow(
                  key: const Key('upd.field.reason'),
                  label: 'Rejection reason',
                  value: _r.rejectionReason!,
                ),
            ],
          ),
        ),
        if (pending) ...[
          const SizedBox(height: 16),
          const InfoNote(
            text: 'Approving saves the new details on the member and texts '
                'them. Confirm a new phone number with the member first.',
          ),
          if (err != null) ...[
            const SizedBox(height: 12),
            ErrorBanner(key: const Key('upd.error'), message: err),
          ],
          const SizedBox(height: 16),
          actionRow(
            keyPrefix: 'upd',
            approveLabel: 'Approve',
            onApprove: _approve,
            onReject: _reject,
          ),
        ],
      ],
    );
  }
}
