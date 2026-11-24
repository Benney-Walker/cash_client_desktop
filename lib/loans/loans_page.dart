import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../approvals/review_queue.dart';
import '../approvals/review_widgets.dart' show askRejectionReason;
import '../common/branch_chip.dart';
import '../common/dates.dart';
import '../common/glass_card.dart';
import '../common/gradient_backdrop.dart';
import '../common/gradient_button.dart';
import '../common/money.dart';
import '../common/step_flow.dart';
import '../members/member_api.dart';
import '../theme/app_gradients.dart';
import 'loan_api.dart';
import 'loan_application_flow.dart';
import 'loan_widgets.dart';
import 'products_tab.dart';

/// Common reasons offered when rejecting a loan application (pick one or
/// type your own, as for ID documents and member updates).
const loanRejectionReasons = [
  "The member can't afford the repayments.",
  "The guarantors aren't suitable.",
  "The member's saving history is too short.",
  "This product doesn't cover the purpose.",
];

/// The Loans section (option L1, owner decisions 24 November 2026): three
/// tabs, Applications (Administrators approve or reject there), Active
/// loans (from the loan portfolio) and Products (Administrators edit), and
/// "New application" for everyone.
class LoansPage extends StatefulWidget {
  const LoansPage({
    super.key,
    required this.api,
    required this.memberApi,
    required this.isAdministrator,
    this.scopeBranch,
  });

  final LoanApi api;
  final MemberApi memberApi;
  final bool isAdministrator;

  /// An Agent's branch: Active loans is limited to it (option B2).
  final String? scopeBranch;

  @override
  State<LoansPage> createState() => _LoansPageState();
}

class _LoansPageState extends State<LoansPage>
    with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 3, vsync: this)
    ..addListener(() {
      if (mounted) setState(() {});
    });
  bool _applying = false;
  int? _waiting;

  /// Products, for working out what each application costs.
  List<LoanProduct> _products = const [];

  /// Bumped to rebuild the Applications list after a new application.
  int _applicationsRun = 0;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    try {
      final products = await widget.api.products();
      if (mounted) setState(() => _products = products);
    } catch (_) {
      // Without products the panes leave out the repayment figures.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_applying) {
      return LoanApplicationFlow(
        api: widget.api,
        memberApi: widget.memberApi,
        onClose: () => setState(() {
          _applying = false;
          _applicationsRun++;
        }),
      );
    }

    return Stack(
      key: const Key('page.loans'),
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
                    // Only Active loans is limited to an Agent's branch.
                    child: PageTitle(
                      'Loans',
                      scopeBranch: _tabs.index == 1 ? widget.scopeBranch : null,
                    ),
                  ),
                  GradientButton(
                    key: const Key('loans.apply'),
                    onPressed: () => setState(() => _applying = true),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add),
                        SizedBox(width: 8),
                        Text('New application'),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: TabBar(
                  controller: _tabs,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: [
                    Tab(
                      key: const Key('loans.tab.applications'),
                      text: _waiting == null || _waiting == 0
                          ? 'Applications'
                          : 'Applications ($_waiting)',
                    ),
                    const Tab(key: Key('loans.tab.active'), text: 'Active loans'),
                    const Tab(key: Key('loans.tab.products'), text: 'Products'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: IndexedStack(
                  index: _tabs.index,
                  children: [
                    ReviewQueue<LoanApplicationStatus, LoanApplicationRecord>(
                      key: ValueKey('applications-$_applicationsRun'),
                      keyPrefix: 'loanApp',
                      statuses: LoanApplicationStatus.values,
                      statusLabel: (s) => s.label,
                      statusKey: (s) => s.name,
                      load: (s, page) => widget.api.applications(s, page: page),
                      idOf: (a) => a.id,
                      titleOf: (a) => a.memberName,
                      subtitleOf: (a) => [
                        amountAndTerm(a.requestedAmount, a.termMonths),
                        a.productName,
                        if (a.branchName != null) a.branchName!,
                      ].join(' · '),
                      pane: (a, onReviewed) => LoanApplicationPane(
                        api: widget.api,
                        memberApi: widget.memberApi,
                        application: a,
                        product: _products
                            .where((p) => p.id == a.productId)
                            .firstOrNull,
                        isAdministrator: widget.isAdministrator,
                        onReviewed: onReviewed,
                      ),
                      emptyText: (s) => switch (s) {
                        LoanApplicationStatus.pending =>
                          'No loan applications are waiting.',
                        LoanApplicationStatus.approved =>
                          'No approved applications yet.',
                        LoanApplicationStatus.rejected =>
                          'No rejected applications.',
                      },
                      nothingSelected: 'Choose an application on the left to '
                          'see what the member asked for and what it costs.',
                      nothingSelectedIcon: Icons.request_quote_outlined,
                      onWaitingCount: (n) => setState(() => _waiting = n),
                    ),
                    _ActiveLoansTab(api: widget.api),
                    ProductsTab(
                      api: widget.api,
                      isAdministrator: widget.isAdministrator,
                      onChanged: _loadProducts,
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

/// One application: what was asked for, what it costs, the guarantors and,
/// for Administrators while it waits, Approve (with the payout confirmed)
/// and Reject.
class LoanApplicationPane extends StatefulWidget {
  const LoanApplicationPane({
    super.key,
    required this.api,
    required this.memberApi,
    required this.application,
    required this.product,
    required this.isAdministrator,
    required this.onReviewed,
  });

  final LoanApi api;
  final MemberApi memberApi;
  final LoanApplicationRecord application;
  final LoanProduct? product;
  final bool isAdministrator;
  final OnReviewed onReviewed;

  @override
  State<LoanApplicationPane> createState() => _LoanApplicationPaneState();
}

class _LoanApplicationPaneState extends State<LoanApplicationPane> {
  late LoanApplicationRecord _a = widget.application;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFull();
  }

  /// The list leaves out the guarantors; the single read has them.
  Future<void> _loadFull() async {
    try {
      final full = await widget.api.application(_a.id);
      if (mounted) setState(() => _a = full);
    } catch (_) {
      // Keep what the list gave.
    }
  }

  Future<void> _approve() async {
    final product = widget.product;
    final amount = await showDialog<Money>(
      context: context,
      builder: (_) => ApproveLoanDialog(
        application: _a,
        product: product,
        memberApi: widget.memberApi,
      ),
    );
    if (amount == null) return;
    await _run(() async {
      await widget.api.approve(
        _a.id,
        amount: amount == _a.requestedAmount ? null : amount,
      );
      widget.onReviewed(
          "${_a.memberName}'s loan of $amount approved and paid into their "
          'account.');
    });
  }

  Future<void> _reject() async {
    final who = _a.appliedBy ?? 'The staff member who applied';
    final reason = await askRejectionReason(
      context,
      title: "Reject ${_a.memberName}'s loan application?",
      explanation: 'No money moves. $who sees this reason, and the member '
          'can apply again later.',
      presets: loanRejectionReasons,
    );
    if (reason == null) return;
    await _run(() async {
      await widget.api.reject(_a.id, reason);
      widget.onReviewed("${_a.memberName}'s loan application rejected.");
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = loanErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final product = widget.product;
    final pending = _a.status == LoanApplicationStatus.pending;
    final quoteAmount = _a.approvedAmount ?? _a.requestedAmount;
    final error = _error;

    final pill = switch (_a.status) {
      LoanApplicationStatus.pending =>
        const StatusPill(label: 'Waiting', tone: StatusTone.warning),
      LoanApplicationStatus.approved =>
        const StatusPill(label: 'Approved and paid in', tone: StatusTone.success),
      LoanApplicationStatus.rejected =>
        const StatusPill(label: 'Rejected', tone: StatusTone.danger),
    };

    return ListView(
      key: const Key('loanApp.pane'),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _a.memberName,
                key: const Key('loanApp.name'),
                style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            pill,
          ],
        ),
        const SizedBox(height: 16),
        GlassCard(
          key: const Key('loanApp.details'),
          title: _a.productName,
          icon: Icons.request_quote_outlined,
          child: Column(
            children: [
              LoanRow(
                label: 'Asked for',
                value: amountAndTerm(_a.requestedAmount, _a.termMonths),
                strong: true,
              ),
              if (_a.approvedAmount != null &&
                  _a.approvedAmount != _a.requestedAmount)
                LoanRow(
                  key: const Key('loanApp.approvedAmount'),
                  label: 'Approved',
                  value: _a.approvedAmount.toString(),
                  strong: true,
                ),
              if (product != null) ...[
                LoanRow(label: 'Product terms', value: product.rateLabel),
                LoanRow(label: '', value: product.feeLabel),
              ],
              if (_a.branchName != null)
                LoanRow(label: 'Branch', value: _a.branchName!),
              LoanRow(
                key: const Key('loanApp.guarantors'),
                label: 'Guarantors',
                value: _a.guarantors.isEmpty ? 'None' : _a.guarantors.join(', '),
              ),
              if (_a.purpose != null) LoanRow(label: 'Purpose', value: _a.purpose!),
              if (_a.appliedBy != null)
                LoanRow(
                  label: 'Applied by',
                  value: [
                    _a.appliedBy!,
                    if (_a.createdAt != null) dateAndTime(_a.createdAt!),
                  ].join(' · '),
                ),
              if (_a.reviewedBy != null)
                LoanRow(
                  label: 'Reviewed by',
                  value: [
                    _a.reviewedBy!,
                    if (_a.reviewedAt != null) dateAndTime(_a.reviewedAt!),
                  ].join(' · '),
                ),
              if (_a.rejectionReason != null)
                LoanRow(
                  key: const Key('loanApp.reason'),
                  label: 'Rejection reason',
                  value: _a.rejectionReason!,
                ),
            ],
          ),
        ),
        if (product != null) ...[
          const SizedBox(height: 16),
          GlassCard(
            key: const Key('loanApp.quote'),
            title: pending ? 'What it would cost' : 'What it costs',
            icon: Icons.calculate_outlined,
            child: LoanQuoteRows(
              quote: LoanQuote.of(product, quoteAmount, _a.termMonths),
              keyPrefix: 'loanApp.quote',
            ),
          ),
        ],
        if (pending && widget.isAdministrator) ...[
          const SizedBox(height: 16),
          const InfoNote(
            text: 'Approving pays the loan into the member\'s savings or '
                'current account at once, less the processing fee. You can '
                'approve a lower amount than was asked.',
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            ErrorBanner(key: const Key('loanApp.error'), message: error),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              GradientButton(
                key: const Key('loanApp.approve'),
                onPressed: _busy ? null : _approve,
                child: _busy
                    ? SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppGradients.of(context).onButton,
                        ),
                      )
                    : const Text('Approve…'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                key: const Key('loanApp.reject'),
                onPressed: _busy ? null : _reject,
                icon: const Icon(Icons.close),
                label: const Text('Reject'),
              ),
            ],
          ),
        ],
        if (pending && !widget.isAdministrator) ...[
          const SizedBox(height: 16),
          const InfoNote(
            key: Key('loanApp.agentNote'),
            text: 'An administrator approves or rejects this application.',
          ),
        ],
      ],
    );
  }
}

/// Confirms an approval with the payout (owner decision: approving pays
/// money out, so it asks first). The amount can be lowered to the
/// product's minimum. Returns the amount to approve, or null.
class ApproveLoanDialog extends StatefulWidget {
  const ApproveLoanDialog({
    super.key,
    required this.application,
    required this.product,
    required this.memberApi,
  });

  final LoanApplicationRecord application;
  final LoanProduct? product;
  final MemberApi memberApi;

  @override
  State<ApproveLoanDialog> createState() => _ApproveLoanDialogState();
}

class _ApproveLoanDialogState extends State<ApproveLoanDialog> {
  late final _amount =
      TextEditingController(text: widget.application.requestedAmount.plain.replaceAll(',', ''));
  String? _error;
  String? _account;

  @override
  void initState() {
    super.initState();
    _loadAccount();
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  /// Best effort: the account the loan goes into, the member's savings or
  /// current account.
  Future<void> _loadAccount() async {
    try {
      final member = await widget.memberApi.fetchMember(widget.application.memberId);
      final account = member.accounts
          .where((a) => (a.type ?? '').toUpperCase() != 'SHARES')
          .firstOrNull;
      if (mounted && account != null) {
        setState(() => _account = '${account.typeLabel} ${account.accountNumber}');
      }
    } catch (_) {
      // Say "their savings or current account" instead.
    }
  }

  Money? get _parsed => Money.parse(_amount.text);

  String? _check(Money? amount) {
    final a = widget.application;
    if (amount == null || !amount.isPositive) return 'Enter an amount';
    if (amount > a.requestedAmount) {
      return "Can't be more than the ${a.requestedAmount} asked for";
    }
    final product = widget.product;
    if (product != null && amount < product.minAmount) {
      return "Can't be less than the product's minimum of ${product.minAmount}";
    }
    if (product != null && product.feeFor(amount) >= amount) {
      return 'The processing fee would take the whole loan';
    }
    return null;
  }

  void _confirm() {
    final amount = _parsed;
    final error = _check(amount);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop(amount);
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.application;
    final product = widget.product;
    final amount = _parsed;
    final valid = _check(amount) == null;
    final account = _account;
    final into = account == null
        ? "the member's savings or current account"
        : 'their $account';

    return AlertDialog(
      key: const Key('approveLoan.dialog'),
      title: Text("Approve ${a.memberName}'s loan?"),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('approveLoan.amount'),
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              onChanged: (_) => setState(() => _error = null),
              decoration: InputDecoration(
                labelText: 'Amount to approve (GH₵)',
                helperText: 'Up to the ${a.requestedAmount} asked for, over '
                    '${a.termMonths == 1 ? '1 month' : '${a.termMonths} months'}',
                errorText: _error,
              ),
            ),
            const SizedBox(height: 16),
            if (product != null && amount != null && valid)
              LoanQuoteRows(
                quote: LoanQuote.of(product, amount, a.termMonths),
                keyPrefix: 'approveLoan.quote',
              )
            else if (product == null)
              const InfoNote(
                text: "The product's terms couldn't be read, so the fee and "
                    'repayments are worked out by the server.',
              ),
            const SizedBox(height: 12),
            Text(
              'The money goes into $into at once, and the member gets an '
              "SMS. This can't be undone here.",
              key: const Key('approveLoan.account'),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('approveLoan.cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('approveLoan.confirm'),
          onPressed: _confirm,
          child: Text(
            amount != null && valid
                ? 'Approve and pay in '
                    '${product == null ? amount : amount - product.feeFor(amount)}'
                : 'Approve',
          ),
        ),
      ],
    );
  }
}

/// Active loans: the portfolio on the left, the chosen loan with its
/// installments on the right.
class _ActiveLoansTab extends StatefulWidget {
  const _ActiveLoansTab({required this.api});

  final LoanApi api;

  @override
  State<_ActiveLoansTab> createState() => _ActiveLoansTabState();
}

class _ActiveLoansTabState extends State<_ActiveLoansTab> {
  List<PortfolioLoan>? _loans;
  Object? _error;
  String? _selected;
  bool _overdueOnly = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final loans = await widget.api.activeLoans();
      if (mounted) setState(() => _loans = loans);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final loans = _loans;
    final error = _error;
    final selected = _selected;

    Widget list;
    if (loans == null && error == null) {
      list = const Center(child: CircularProgressIndicator());
    } else if (loans == null) {
      list = Column(
        key: const Key('activeLoans.error'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(loanErrorMessage(error!),
              style: textTheme.bodyMedium?.copyWith(color: scheme.error)),
          TextButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ],
      );
    } else {
      final shown = _overdueOnly ? loans.where((l) => l.isOverdue).toList() : loans;
      list = ListView(
        children: [
          FilterChip(
            key: const Key('activeLoans.overdueOnly'),
            label: const Text('Overdue only'),
            selected: _overdueOnly,
            onSelected: (v) => setState(() => _overdueOnly = v),
          ),
          const SizedBox(height: 8),
          if (shown.isEmpty)
            Text(
              _overdueOnly ? 'No loans are overdue.' : 'No active loans.',
              key: const Key('activeLoans.empty'),
              style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          for (final l in shown)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: ListTile(
                key: Key('activeLoans.item.${l.loanId}'),
                selected: l.loanId == selected,
                selectedTileColor: scheme.primaryContainer,
                selectedColor: scheme.onPrimaryContainer,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                title: Text(l.memberName),
                subtitle: Text([
                  '${l.outstanding} owed',
                  l.productName,
                  if (l.branchName != null) l.branchName!,
                ].join(' · ')),
                trailing: l.isOverdue
                    ? const StatusPill(label: 'Overdue', tone: StatusTone.danger)
                    : null,
                onTap: () => setState(() => _selected = l.loanId),
              ),
            ),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 340, child: list),
        const SizedBox(width: 24),
        Expanded(
          child: selected == null
              ? Align(
                  alignment: Alignment.topLeft,
                  child: GlassCard(
                    key: const Key('activeLoans.nothingSelected'),
                    title: 'Loan',
                    icon: Icons.request_quote_outlined,
                    child: Text(
                      'Choose a loan on the left to see its installments.',
                      style: textTheme.bodyMedium,
                    ),
                  ),
                )
              : LoanPane(
                  key: ValueKey(selected),
                  api: widget.api,
                  loanId: selected,
                ),
        ),
      ],
    );
  }
}
