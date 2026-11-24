import 'package:flutter/material.dart';

import '../api/api_exception.dart';
import '../branches/branch.dart';
import '../branches/branch_api.dart';
import '../common/branch_chip.dart';
import '../common/glass_card.dart';
import '../common/gradient_backdrop.dart';
import '../common/money.dart';
import '../common/names.dart';
import '../common/step_flow.dart';
import '../members/member_api.dart' show commonFailureMessage;
import '../theme/app_gradients.dart';
import 'dashboard_api.dart';

/// Where a waiting card leads. The shell turns it into a section (and, for
/// Approvals, a tab).
enum DashboardTarget {
  submissions,
  idDocuments,
  memberUpdates,
  loanApplications,
  pendingMembers,
}

/// The dashboard (layout D3, content D-C, owner decisions 24 November 2026):
/// a gradient headline with the period's deposits and withdrawals and how
/// much is waiting; cards with the waiting counts, each opening its page;
/// and two sections, the period's totals by type and the loan portfolio.
///
/// Every figure comes from an existing backend endpoint (there are no
/// dashboard endpoints), already limited to an Agent's branch. Each part
/// loads on its own, so one failure leaves the rest showing.
class DashboardPage extends StatefulWidget {
  const DashboardPage({
    super.key,
    required this.api,
    required this.branchApi,
    required this.staffName,
    required this.isAdministrator,
    required this.onOpen,
    this.scopeBranch,
    this.now = DateTime.now,
  });

  final DashboardApi api;
  final BranchApi branchApi;
  final String staffName;
  final bool isAdministrator;
  final ValueChanged<DashboardTarget> onOpen;

  /// An Agent's branch, for the "… branch only" chip (option B2).
  final String? scopeBranch;
  final DateTime Function() now;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

/// One part of the dashboard as it loads.
class _Slot<T> {
  T? value;
  Object? error;
  bool loading = false;
  int run = 0;
}

class _DashboardPageState extends State<DashboardPage> {
  static const _k = 'dashboard';

  DashboardPeriod _period = DashboardPeriod.today;

  /// Administrators' branch choice; null is every branch.
  String? _branchId;
  List<Branch> _branches = const [];

  final _transactions = _Slot<TransactionSummary>();
  final _collections = _Slot<CollectionsSummary>();
  final _loans = _Slot<LoanPortfolioSummary>();
  final _counts = {
    for (final t in DashboardTarget.values) t: _Slot<int>(),
  };

  bool get _admin => widget.isAdministrator;

  /// The cards this role sees. Loan applications are Administrators' only:
  /// the backend lists every branch's to everyone, and only Administrators
  /// approve them, so on an Agent's branch dashboard the count would mislead.
  List<DashboardTarget> get _cards => [
        DashboardTarget.submissions,
        if (_admin) DashboardTarget.idDocuments,
        if (_admin) DashboardTarget.memberUpdates,
        if (_admin) DashboardTarget.loanApplications,
        DashboardTarget.pendingMembers,
      ];

  @override
  void initState() {
    super.initState();
    _refresh();
    if (_admin) _loadBranches();
  }

  Future<void> _loadBranches() async {
    try {
      final branches = await widget.branchApi.fetchBranches();
      if (mounted) setState(() => _branches = branches);
    } catch (_) {
      // Without the list the picker stays on every branch.
    }
  }

  Future<void> _fill<T>(_Slot<T> slot, Future<T> Function() load) async {
    final run = ++slot.run;
    setState(() {
      slot.loading = true;
      slot.error = null;
    });
    try {
      final value = await load();
      if (!mounted || run != slot.run) return;
      setState(() => slot.value = value);
    } catch (error) {
      if (!mounted || run != slot.run) return;
      setState(() => slot.error = error);
    } finally {
      if (mounted && run == slot.run) setState(() => slot.loading = false);
    }
  }

  void _refresh() {
    _loadMoney();
    _loadBranchParts();
    final api = widget.api;
    _fill(_counts[DashboardTarget.submissions]!, api.submissionsWaiting);
    if (_admin) {
      _fill(_counts[DashboardTarget.idDocuments]!, api.idDocumentsToReview);
      _fill(_counts[DashboardTarget.memberUpdates]!, api.memberUpdatesWaiting);
      _fill(
        _counts[DashboardTarget.loanApplications]!,
        api.loanApplicationsWaiting,
      );
    }
  }

  void _loadMoney() {
    final (from, to) = _period.range(widget.now());
    final branch = _branchId;
    _fill(
      _transactions,
      () => widget.api.transactions(from, to, branchId: branch),
    );
    _fill(
      _collections,
      () => widget.api.collections(from, to, branchId: branch),
    );
  }

  /// The parts that follow the branch choice but not the period.
  void _loadBranchParts() {
    final branch = _branchId;
    _fill(_loans, () => widget.api.loanPortfolio(branchId: branch));
    _fill(
      _counts[DashboardTarget.pendingMembers]!,
      () => widget.api.pendingMembers(branchId: branch),
    );
  }

  void _setPeriod(DashboardPeriod period) {
    if (period == _period) return;
    setState(() => _period = period);
    _loadMoney();
  }

  void _setBranch(String? branchId) {
    if (branchId == _branchId) return;
    setState(() => _branchId = branchId);
    _loadMoney();
    _loadBranchParts();
  }

  String get _scopeLabel {
    if (!_admin) {
      final branch = widget.scopeBranch;
      return branch == null ? 'Your branch' : '$branch branch';
    }
    final id = _branchId;
    if (id == null) return 'All branches';
    return _branches.where((b) => b.id == id).firstOrNull?.name ?? 'One branch';
  }

  String _greeting() {
    final hour = widget.now().hour;
    final part = hour < 12
        ? 'Good morning'
        : hour < 17
            ? 'Good afternoon'
            : 'Good evening';
    final first = displayName(widget.staffName).split(' ').first;
    return first.isEmpty ? part : '$part, $first';
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      key: const Key('page.dashboard'),
      children: [
        const Positioned.fill(child: PageGlows()),
        ListView(
          padding: const EdgeInsets.fromLTRB(32, 28, 32, 32),
          children: [
            PageTitle(_greeting(), scopeBranch: widget.scopeBranch),
            const SizedBox(height: 16),
            _controls(),
            const SizedBox(height: 20),
            _headline(context),
            const SizedBox(height: 20),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [for (final t in _cards) _card(context, t)],
            ),
            if (_admin && _branchId != null) ...[
              const SizedBox(height: 12),
              const InfoNote(
                key: Key('$_k.branchNote'),
                text: 'The branch choice applies to pending members, money '
                    'and loans. The other waiting counts cover every branch: '
                    'those lists have no branch filter on the server.',
              ),
            ],
            const SizedBox(height: 20),
            LayoutBuilder(
              builder: (context, constraints) {
                final byType = _byTypeSection(context);
                final loans = _loansSection(context);
                if (constraints.maxWidth < 760) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [byType, const SizedBox(height: 16), loans],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: byType),
                    const SizedBox(width: 16),
                    Expanded(child: loans),
                  ],
                );
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _controls() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SegmentedButton<DashboardPeriod>(
          key: const Key('$_k.period'),
          segments: [
            for (final p in DashboardPeriod.values)
              ButtonSegment(
                value: p,
                label: Text(p.label, key: Key('$_k.period.${p.name}')),
              ),
          ],
          selected: {_period},
          showSelectedIcon: false,
          onSelectionChanged: (s) => _setPeriod(s.single),
        ),
        if (_admin)
          SizedBox(
            width: 260,
            child: DropdownButtonFormField<String?>(
              key: const Key('$_k.branch'),
              initialValue: _branchId,
              isExpanded: true,
              decoration:
                  const InputDecoration(labelText: 'Branch', isDense: true),
              items: [
                const DropdownMenuItem(value: null, child: Text('All branches')),
                for (final b in _branches)
                  DropdownMenuItem(value: b.id, child: Text(b.name)),
              ],
              onChanged: _setBranch,
            ),
          ),
        IconButton(
          key: const Key('$_k.refresh'),
          tooltip: 'Refresh',
          onPressed: _refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    );
  }

  int? get _waitingTotal {
    var total = 0;
    for (final t in _cards) {
      if (t == DashboardTarget.pendingMembers) continue;
      final value = _counts[t]!.value;
      if (value == null) return null;
      total += value;
    }
    return total;
  }

  Widget _headline(BuildContext context) {
    final gradients = AppGradients.of(context);
    final textTheme = Theme.of(context).textTheme;
    final summary = _transactions.value;
    final error = _transactions.error;
    final waiting = _waitingTotal;

    final String main;
    if (summary != null) {
      main = '${summary.deposits} deposited · ${summary.withdrawals} '
          'withdrawn ${_period.inSentence}';
    } else if (error != null) {
      main = "${_period.label}'s totals couldn't be loaded";
    } else {
      main = 'Loading ${_period.inSentence}…';
    }

    return Container(
      key: const Key('$_k.headline'),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 22),
      decoration: BoxDecoration(
        gradient: gradients.panel,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_period.label} · $_scopeLabel',
            key: const Key('$_k.scope'),
            style: textTheme.labelLarge
                ?.copyWith(color: gradients.panelTextSecondary),
          ),
          const SizedBox(height: 6),
          Text(
            main,
            key: const Key('$_k.money'),
            style: textTheme.headlineSmall?.copyWith(
              color: gradients.panelText,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            waiting == null
                ? ' '
                : waiting == 0
                    ? 'Nothing waiting for you'
                    : waiting == 1
                        ? '1 thing waiting for you'
                        : '$waiting things waiting for you',
            key: const Key('$_k.waiting'),
            style: textTheme.titleSmall
                ?.copyWith(color: gradients.panelTextSecondary),
          ),
        ],
      ),
    );
  }

  static (String, IconData) _cardInfo(DashboardTarget t) => switch (t) {
        DashboardTarget.submissions =>
          ('Collector days waiting', Icons.fact_check_outlined),
        DashboardTarget.idDocuments =>
          ('ID documents to review', Icons.badge_outlined),
        DashboardTarget.memberUpdates =>
          ('Member updates waiting', Icons.edit_note_outlined),
        DashboardTarget.loanApplications =>
          ('Loan applications waiting', Icons.request_quote_outlined),
        DashboardTarget.pendingMembers =>
          ('Members not yet active', Icons.person_add_alt_outlined),
      };

  Widget _card(BuildContext context, DashboardTarget target) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final gradients = AppGradients.of(context);
    final slot = _counts[target]!;
    final (label, icon) = _cardInfo(target);
    final value = slot.value;

    final Widget figure;
    if (value != null) {
      figure = Text(
        '$value',
        key: Key('$_k.count.${target.name}'),
        style: textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );
    } else if (slot.error != null) {
      figure = Row(
        key: Key('$_k.countError.${target.name}'),
        children: [
          Icon(Icons.error_outline, size: 18, color: scheme.error),
          const SizedBox(width: 6),
          Text("Couldn't load",
              style: textTheme.bodyMedium?.copyWith(color: scheme.error)),
        ],
      );
    } else {
      figure = Text('—', style: textTheme.headlineMedium);
    }

    return SizedBox(
      width: 200,
      child: Material(
        color: gradients.glassCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: gradients.glassCardBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: Key('$_k.card.${target.name}'),
          onTap: () => widget.onOpen(target),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 20, color: scheme.primary),
                    const Spacer(),
                    Icon(Icons.chevron_right,
                        size: 18, color: scheme.onSurfaceVariant),
                  ],
                ),
                const SizedBox(height: 10),
                figure,
                const SizedBox(height: 2),
                Text(
                  label,
                  style: textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _failed(String what, Object error, VoidCallback retry) {
    final scheme = Theme.of(context).colorScheme;
    final message = error is ApiException
        ? commonFailureMessage(error, action: 'see $what')
        : 'Something went wrong.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(message, style: TextStyle(color: scheme.error)),
        TextButton.icon(
          onPressed: retry,
          icon: const Icon(Icons.refresh),
          label: const Text('Try again'),
        ),
      ],
    );
  }

  Widget _byTypeSection(BuildContext context) {
    final summary = _transactions.value;
    final collections = _collections.value;
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    final Widget body;
    if (summary == null && _transactions.error != null) {
      body = _failed('reports', _transactions.error!, _loadMoney);
    } else if (summary == null) {
      body = const Padding(
        padding: EdgeInsets.all(12),
        child: Center(child: CircularProgressIndicator()),
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (summary.byType.isEmpty)
            Text(
              'No transactions ${_period.inSentence}.',
              key: const Key('$_k.noTransactions'),
              style: textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          for (final t in summary.byType)
            _FigureRow(
              key: Key('$_k.type.${t.type}'),
              label: t.label,
              note: t.count == 1 ? '1 transaction' : '${t.count} transactions',
              value: t.amount,
            ),
          if (summary.byType.isNotEmpty) ...[
            const Divider(height: 20),
            _FigureRow(
              key: const Key('$_k.fees'),
              label: 'Fees charged',
              value: summary.fees,
            ),
          ],
          if (collections != null) ...[
            _FigureRow(
              key: const Key('$_k.collected'),
              label: 'Collected in the field',
              value: collections.collected,
            ),
            if (collections.counted.isPositive)
              _FigureRow(
                key: const Key('$_k.counted'),
                label: 'Counted at the office',
                value: collections.counted,
              ),
          ],
        ],
      );
    }

    return GlassCard(
      key: const Key('$_k.byType'),
      title: '${_period.label} by type',
      icon: Icons.payments_outlined,
      child: body,
    );
  }

  Widget _loansSection(BuildContext context) {
    final loans = _loans.value;

    final Widget body;
    if (loans == null && _loans.error != null) {
      body = _failed('loans', _loans.error!, _loadBranchParts);
    } else if (loans == null) {
      body = const Padding(
        padding: EdgeInsets.all(12),
        child: Center(child: CircularProgressIndicator()),
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FigureRow(
            key: const Key('$_k.loans.active'),
            label: 'Active loans',
            count: loans.activeLoans,
          ),
          _FigureRow(
            key: const Key('$_k.loans.overdueCount'),
            label: 'Overdue loans',
            count: loans.overdueLoans,
          ),
          const Divider(height: 20),
          _FigureRow(label: 'Amount lent', value: loans.amountLent),
          _FigureRow(
            key: const Key('$_k.loans.outstanding'),
            label: 'Still owed',
            value: loans.outstanding,
          ),
          _FigureRow(
            key: const Key('$_k.loans.overdue'),
            label: 'Overdue',
            value: loans.overdue,
          ),
        ],
      );
    }

    return GlassCard(
      key: const Key('$_k.loans'),
      title: 'Loans now',
      icon: Icons.request_quote_outlined,
      child: body,
    );
  }
}

/// A label with an amount or a count on the right.
class _FigureRow extends StatelessWidget {
  const _FigureRow({
    super.key,
    required this.label,
    this.note,
    this.value,
    this.count,
  });

  final String label;
  final String? note;
  final Money? value;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final figure = value?.toString() ?? '${count ?? ''}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: textTheme.bodyMedium),
                if (note != null)
                  Text(
                    note!,
                    style: textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          Text(
            figure,
            style: textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
