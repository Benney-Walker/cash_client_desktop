import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../branches/branch.dart';
import '../branches/branch_api.dart';
import '../common/branch_chip.dart';
import '../common/dates.dart';
import '../common/glass_card.dart';
import '../common/gradient_backdrop.dart';
import '../common/step_flow.dart';
import 'pdf_output.dart';
import 'report_api.dart';

/// The Reports section (option R1, owner decisions 24 November 2026): a tab
/// per report, each with its filters, the figures on screen, and the
/// backend's PDF to save or print. Administrators also get the audit log
/// and the trial balance as two more tabs.
class ReportsPage extends StatefulWidget {
  const ReportsPage({
    super.key,
    required this.api,
    required this.branchApi,
    required this.isAdministrator,
    this.scopeBranch,
    this.savePdf = savePdfToFile,
    this.printPdf = printPdfBytes,
    this.now = DateTime.now,
  });

  final ReportApi api;
  final BranchApi branchApi;
  final bool isAdministrator;

  /// An Agent's branch: every report is limited to it (option B2).
  final String? scopeBranch;
  final SavePdf savePdf;
  final PrintPdf printPdf;
  final DateTime Function() now;

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage>
    with SingleTickerProviderStateMixin {
  late final _tabs = TabController(
    length: widget.isAdministrator ? 6 : 4,
    vsync: this,
  )..addListener(() {
      if (mounted) setState(() {});
    });
  List<Branch> _branches = const [];

  @override
  void initState() {
    super.initState();
    if (widget.isAdministrator) _loadBranches();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadBranches() async {
    try {
      final branches = await widget.branchApi.fetchBranches();
      if (mounted) setState(() => _branches = branches);
    } catch (_) {
      // The reports still work for every branch.
    }
  }

  DateTime get _today {
    final n = widget.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  Widget build(BuildContext context) {
    final admin = widget.isAdministrator;
    final api = widget.api;
    final branches = admin ? _branches : null;

    return Stack(
      key: const Key('page.reports'),
      children: [
        const Positioned.fill(child: PageGlows()),
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 28, 32, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageTitle('Reports', scopeBranch: widget.scopeBranch),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: TabBar(
                  controller: _tabs,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: [
                    const Tab(key: Key('reports.tab.transactions'), text: 'Transactions'),
                    const Tab(key: Key('reports.tab.collections'), text: 'Collector collections'),
                    const Tab(key: Key('reports.tab.portfolio'), text: 'Loan portfolio'),
                    const Tab(key: Key('reports.tab.statement'), text: 'Statement'),
                    if (admin) const Tab(key: Key('reports.tab.audit'), text: 'Audit log'),
                    if (admin)
                      const Tab(key: Key('reports.tab.trialBalance'), text: 'Trial balance'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: IndexedStack(
                  index: _tabs.index,
                  children: [
                    ReportTab<TransactionReportData>(
                      keyPrefix: 'txReport',
                      today: _today,
                      branches: branches,
                      load: (f, t, b) => api.transactions(f!, t!, branchId: b),
                      pdf: (f, t, b) => api.transactionsPdf(f!, t!, branchId: b),
                      fileName: (f, t) => 'transactions-${isoDate(f!)}-${isoDate(t!)}',
                      savePdf: widget.savePdf,
                      printPdf: widget.printPdf,
                      body: _transactions,
                    ),
                    ReportTab<CollectionsReportData>(
                      keyPrefix: 'colReport',
                      today: _today,
                      branches: branches,
                      load: (f, t, b) => api.collections(f!, t!, branchId: b),
                      pdf: (f, t, b) => api.collectionsPdf(f!, t!, branchId: b),
                      fileName: (f, t) =>
                          'collector-collections-${isoDate(f!)}-${isoDate(t!)}',
                      savePdf: widget.savePdf,
                      printPdf: widget.printPdf,
                      body: _collections,
                    ),
                    ReportTab<PortfolioReportData>(
                      keyPrefix: 'loanReport',
                      today: _today,
                      dated: false,
                      branches: branches,
                      load: (_, __, b) => api.portfolio(branchId: b),
                      pdf: (_, __, b) => api.portfolioPdf(branchId: b),
                      fileName: (_, __) => 'loan-portfolio-${isoDate(_today)}',
                      savePdf: widget.savePdf,
                      printPdf: widget.printPdf,
                      body: _portfolio,
                    ),
                    _StatementTab(
                      api: api,
                      today: _today,
                      savePdf: widget.savePdf,
                      printPdf: widget.printPdf,
                    ),
                    if (admin) _AuditTab(api: api, today: _today),
                    if (admin) _TrialBalanceTab(api: api),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _transactions(BuildContext context, TransactionReportData r) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Figures(keyPrefix: 'txReport', figures: [
          ('Transactions', '${r.count}'),
          ('Amount', r.amount.toString()),
          ('Fees', r.fees.toString()),
        ]),
        const SizedBox(height: 16),
        if (r.totals.isNotEmpty)
          GlassCard(
            title: 'By type',
            icon: Icons.category_outlined,
            child: ReportTable(
              keyPrefix: 'txReport.totals',
              columns: const ['Type', 'Count', 'Amount', 'Fees'],
              numeric: const {1, 2, 3},
              rows: [
                for (final t in r.totals)
                  [t.label, '${t.count}', t.amount.plain, t.fees.plain],
              ],
            ),
          ),
        const SizedBox(height: 16),
        GlassCard(
          title: 'By day',
          icon: Icons.calendar_view_day_outlined,
          child: r.rows.isEmpty
              ? const Text('No transactions in these dates.', key: Key('txReport.none'))
              : ReportTable(
                  keyPrefix: 'txReport.rows',
                  columns: const ['Date', 'Branch', 'Type', 'Count', 'Amount', 'Fees'],
                  numeric: const {3, 4, 5},
                  rows: [
                    for (final row in r.rows)
                      [
                        isoDate(row.date),
                        row.branchName ?? '—',
                        row.typeLabel,
                        '${row.count}',
                        row.amount.plain,
                        row.fees.plain,
                      ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _collections(BuildContext context, CollectionsReportData r) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Figures(keyPrefix: 'colReport', figures: [
          ('Collected', r.collected.toString()),
          ('Expected', r.expected.toString()),
          ('Counted', r.counted.toString()),
          ('Surplus', r.surplus.toString()),
        ]),
        const SizedBox(height: 16),
        GlassCard(
          title: "Collectors' days",
          icon: Icons.route_outlined,
          child: r.days.isEmpty
              ? const Text('No collections in these dates.', key: Key('colReport.none'))
              : ReportTable(
                  keyPrefix: 'colReport.days',
                  columns: const ['Date', 'Collector', 'Branch', 'Payments', 'Amount', 'Failed'],
                  numeric: const {3, 4, 5},
                  rows: [
                    for (final d in r.days)
                      [
                        isoDate(d.date),
                        d.collectorName,
                        d.branchName ?? '—',
                        '${d.payments}',
                        d.amount.plain,
                        '${d.failedPayments}',
                      ],
                  ],
                ),
        ),
        const SizedBox(height: 16),
        GlassCard(
          title: 'Handed in',
          icon: Icons.fact_check_outlined,
          child: r.handovers.isEmpty
              ? const Text('No days handed in.')
              : ReportTable(
                  keyPrefix: 'colReport.handovers',
                  columns: const ['Handed in', 'Collector', 'Expected', 'Counted', 'Surplus', 'Status'],
                  numeric: const {2, 3, 4},
                  rows: [
                    for (final h in r.handovers)
                      [
                        h.submittedAt == null ? '—' : dateAndTime(h.submittedAt!),
                        h.collectorName,
                        h.expected.plain,
                        h.counted?.plain ?? '—',
                        h.surplus?.plain ?? '—',
                        h.approved
                            ? 'Approved${h.approvedBy == null ? '' : ' by ${h.approvedBy}'}'
                            : 'Waiting',
                      ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _portfolio(BuildContext context, PortfolioReportData r) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Figures(keyPrefix: 'loanReport', figures: [
          ('Active loans', '${r.activeLoans}'),
          ('Overdue loans', '${r.overdueLoans}'),
          ('Lent', r.amountLent.toString()),
          ('Still owed', r.outstanding.toString()),
          ('Overdue', r.overdue.toString()),
        ]),
        const SizedBox(height: 16),
        GlassCard(
          title: r.asOf == null ? 'Loans' : 'Loans as of ${dateAndTime(r.asOf!)}',
          icon: Icons.request_quote_outlined,
          child: r.loans.isEmpty
              ? const Text('No active loans.', key: Key('loanReport.none'))
              : ReportTable(
                  keyPrefix: 'loanReport.loans',
                  columns: const [
                    'Member', 'Branch', 'Product', 'Paid out', 'Lent', 'To repay',
                    'Paid', 'Still owed', 'Overdue', 'Next due',
                  ],
                  numeric: const {4, 5, 6, 7, 8},
                  rows: [
                    for (final l in r.loans)
                      [
                        l.memberName,
                        l.branchName ?? '—',
                        l.productName,
                        l.disbursementDate == null ? '—' : isoDate(l.disbursementDate!),
                        l.amount.plain,
                        l.totalToRepay.plain,
                        l.paid.plain,
                        l.outstanding.plain,
                        l.overdue.plain,
                        l.nextDueDate == null ? '—' : isoDate(l.nextDueDate!),
                      ],
                  ],
                ),
        ),
      ],
    );
  }
}

/// A row of headline figures for a report.
class _Figures extends StatelessWidget {
  const _Figures({required this.keyPrefix, required this.figures});

  final String keyPrefix;
  final List<(String, String)> figures;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final (label, value) in figures)
          Container(
            key: Key('$keyPrefix.figure.$label'),
            width: 190,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// A plain table; [numeric] columns are right-aligned with tabular figures.
class ReportTable extends StatelessWidget {
  const ReportTable({
    super.key,
    required this.keyPrefix,
    required this.columns,
    required this.rows,
    this.numeric = const {},
  });

  final String keyPrefix;
  final List<String> columns;
  final List<List<String>> rows;
  final Set<int> numeric;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
        );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        key: Key('$keyPrefix.table'),
        headingRowHeight: 40,
        dataRowMinHeight: 36,
        dataRowMaxHeight: 48,
        columnSpacing: 24,
        columns: [
          for (final (i, c) in columns.indexed)
            DataColumn(label: Text(c), numeric: numeric.contains(i)),
        ],
        rows: [
          for (final (r, row) in rows.indexed)
            DataRow(
              key: ValueKey('$keyPrefix.row.$r'),
              cells: [for (final cell in row) DataCell(Text(cell, style: style))],
            ),
        ],
      ),
    );
  }
}

/// One report: its filters (dates when [dated], a branch for
/// Administrators), the figures, and Save PDF / Print with the same
/// filters. Opens on this month so far.
class ReportTab<T> extends StatefulWidget {
  const ReportTab({
    super.key,
    required this.keyPrefix,
    required this.today,
    required this.load,
    required this.pdf,
    required this.fileName,
    required this.savePdf,
    required this.printPdf,
    required this.body,
    this.branches,
    this.dated = true,
  });

  final String keyPrefix;
  final DateTime today;

  /// Administrators' branch choice; null for Agents (their branch only).
  final List<Branch>? branches;
  final bool dated;
  final Future<T> Function(DateTime? from, DateTime? to, String? branchId) load;
  final Future<Uint8List> Function(DateTime? from, DateTime? to, String? branchId) pdf;
  final String Function(DateTime? from, DateTime? to) fileName;
  final SavePdf savePdf;
  final PrintPdf printPdf;
  final Widget Function(BuildContext context, T report) body;

  @override
  State<ReportTab<T>> createState() => _ReportTabState<T>();
}

class _ReportTabState<T> extends State<ReportTab<T>> {
  late DateTime _from = DateTime(widget.today.year, widget.today.month);
  late DateTime _to = widget.today;
  String? _branchId;
  T? _report;
  Object? _error;
  bool _loading = false;
  int _run = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  DateTime? get _f => widget.dated ? _from : null;
  DateTime? get _t => widget.dated ? _to : null;

  Future<void> _load() async {
    final run = ++_run;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final report = await widget.load(_f, _t, _branchId);
      if (mounted && run == _run) setState(() => _report = report);
    } catch (e) {
      if (mounted && run == _run) setState(() => _error = e);
    } finally {
      if (mounted && run == _run) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final k = widget.keyPrefix;
    final branches = widget.branches;
    final report = _report;
    final error = _error;
    final branchName = _branchId == null
        ? null
        : branches?.where((b) => b.id == _branchId).firstOrNull?.name;

    return ListView(
      key: Key('$k.view'),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (widget.dated)
              DateRangeBar(
                keyPrefix: k,
                from: _from,
                to: _to,
                today: widget.today,
                onChanged: (f, t) {
                  setState(() {
                    _from = f;
                    _to = t;
                  });
                  _load();
                },
              ),
            if (branches != null)
              SizedBox(
                width: 240,
                child: DropdownButtonFormField<String?>(
                  key: Key('$k.branch'),
                  initialValue: _branchId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Branch', isDense: true),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('All branches')),
                    for (final b in branches)
                      DropdownMenuItem(value: b.id, child: Text(b.name)),
                  ],
                  onChanged: (id) {
                    setState(() => _branchId = id);
                    _load();
                  },
                ),
              ),
            IconButton(
              key: Key('$k.refresh'),
              tooltip: 'Refresh',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
            PdfActions(
              keyPrefix: k,
              load: () => widget.pdf(_f, _t, _branchId),
              fileName: [
                widget.fileName(_f, _t),
                if (branchName != null)
                  branchName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-'),
              ].join('-'),
              savePdf: widget.savePdf,
              printPdf: widget.printPdf,
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (report == null && error == null)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (error != null && report == null)
          ErrorBanner(
            key: Key('$k.error'),
            message: reportErrorMessage(error),
            actionLabel: 'Try again',
            onAction: _load,
          )
        else ...[
          if (error != null) ...[
            ErrorBanner(message: reportErrorMessage(error)),
            const SizedBox(height: 12),
          ],
          widget.body(context, report as T),
        ],
      ],
    );
  }
}

/// A statement for an account between two dates, as a PDF to save or
/// print. Also opened from a member's accounts with the number filled in.
class StatementForm extends StatefulWidget {
  const StatementForm({
    super.key,
    required this.api,
    required this.today,
    required this.savePdf,
    required this.printPdf,
    this.accountNumber,
  });

  final ReportApi api;
  final DateTime today;
  final SavePdf savePdf;
  final PrintPdf printPdf;

  /// Filled in (and fixed) when opened from a member's account.
  final String? accountNumber;

  @override
  State<StatementForm> createState() => _StatementFormState();
}

class _StatementFormState extends State<StatementForm> {
  late final _account = TextEditingController(text: widget.accountNumber ?? '');
  late DateTime _from = DateTime(widget.today.year, widget.today.month);
  late DateTime _to = widget.today;

  @override
  void dispose() {
    _account.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final number = _account.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          key: const Key('statement.account'),
          controller: _account,
          readOnly: widget.accountNumber != null,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(labelText: 'Account number'),
        ),
        const SizedBox(height: 12),
        DateRangeBar(
          keyPrefix: 'statement',
          from: _from,
          to: _to,
          today: widget.today,
          onChanged: (f, t) => setState(() {
            _from = f;
            _to = t;
          }),
        ),
        const SizedBox(height: 12),
        PdfActions(
          keyPrefix: 'statement',
          enabled: number.isNotEmpty,
          load: () => widget.api.statementPdf(number, _from, _to),
          fileName: 'statement-${number.replaceAll(RegExp(r'[^0-9A-Za-z-]'), '')}-'
              '${isoDate(_from)}-${isoDate(_to)}',
          savePdf: widget.savePdf,
          printPdf: widget.printPdf,
        ),
        const SizedBox(height: 8),
        Text(
          'Each statement is recorded in the audit log. Agents can make '
          "statements for their own branch's members.",
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _StatementTab extends StatelessWidget {
  const _StatementTab({
    required this.api,
    required this.today,
    required this.savePdf,
    required this.printPdf,
  });

  final ReportApi api;
  final DateTime today;
  final SavePdf savePdf;
  final PrintPdf printPdf;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: GlassCard(
          key: const Key('statement.card'),
          title: 'Account statement',
          icon: Icons.receipt_long_outlined,
          child: StatementForm(
            api: api,
            today: today,
            savePdf: savePdf,
            printPdf: printPdf,
          ),
        ),
      ),
    );
  }
}

/// Opens a statement for [accountNumber] from a member's details.
Future<void> showStatementDialog(
  BuildContext context, {
  required ReportApi api,
  required String accountNumber,
  required DateTime today,
  SavePdf savePdf = savePdfToFile,
  PrintPdf printPdf = printPdfBytes,
}) =>
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('statement.dialog'),
        title: Text('Statement for $accountNumber'),
        content: SizedBox(
          width: 520,
          child: StatementForm(
            api: api,
            today: today,
            accountNumber: accountNumber,
            savePdf: savePdf,
            printPdf: printPdf,
          ),
        ),
        actions: [
          TextButton(
            key: const Key('statement.close'),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );

/// The audit log: filters, then entries newest first, 50 at a time.
class _AuditTab extends StatefulWidget {
  const _AuditTab({required this.api, required this.today});

  final ReportApi api;
  final DateTime today;

  @override
  State<_AuditTab> createState() => _AuditTabState();
}

class _AuditTabState extends State<_AuditTab> {
  static const _k = 'audit';

  late DateTime _from = widget.today.subtract(const Duration(days: 6));
  late DateTime _to = widget.today;
  String? _action;
  String? _targetType;
  final _actor = TextEditingController();
  final _target = TextEditingController();

  List<AuditEntry> _entries = const [];
  int _page = 0;
  bool _hasMore = false;
  int _total = 0;
  bool _loading = false;
  Object? _error;
  int _run = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _actor.dispose();
    _target.dispose();
    super.dispose();
  }

  AuditFilter get _filter => AuditFilter(
        from: _from,
        to: _to,
        action: _action,
        targetType: _targetType,
        actorStaffId: _actor.text.trim(),
        targetId: _target.text.trim(),
      );

  Future<void> _load({bool more = false}) async {
    final run = more ? _run : ++_run;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.api.auditLog(_filter, page: more ? _page + 1 : 0);
      if (!mounted || run != _run) return;
      setState(() {
        _entries = more ? [..._entries, ...page.items] : page.items;
        _page = page.number;
        _hasMore = page.hasMore;
        _total = page.totalElements;
      });
    } catch (e) {
      if (mounted && run == _run) setState(() => _error = e);
    } finally {
      if (mounted && run == _run) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final error = _error;
    final actions = auditActionLabels.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    return ListView(
      key: const Key('$_k.view'),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            DateRangeBar(
              keyPrefix: _k,
              from: _from,
              to: _to,
              today: widget.today,
              onChanged: (f, t) {
                setState(() {
                  _from = f;
                  _to = t;
                });
                _load();
              },
            ),
            SizedBox(
              width: 260,
              child: DropdownButtonFormField<String?>(
                key: const Key('$_k.action'),
                initialValue: _action,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Action', isDense: true),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Every action')),
                  for (final a in actions)
                    DropdownMenuItem(value: a.key, child: Text(a.value)),
                ],
                onChanged: (v) {
                  setState(() => _action = v);
                  _load();
                },
              ),
            ),
            SizedBox(
              width: 200,
              child: DropdownButtonFormField<String?>(
                key: const Key('$_k.targetType'),
                initialValue: _targetType,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'About', isDense: true),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Anything')),
                  for (final t in auditTargetLabels.entries)
                    DropdownMenuItem(value: t.key, child: Text(t.value)),
                ],
                onChanged: (v) {
                  setState(() => _targetType = v);
                  _load();
                },
              ),
            ),
            SizedBox(
              width: 160,
              child: TextField(
                key: const Key('$_k.actor'),
                controller: _actor,
                decoration: const InputDecoration(labelText: 'By staff ID', isDense: true),
                onSubmitted: (_) => _load(),
              ),
            ),
            SizedBox(
              width: 200,
              child: TextField(
                key: const Key('$_k.target'),
                controller: _target,
                decoration: const InputDecoration(labelText: 'Record ID', isDense: true),
                onSubmitted: (_) => _load(),
              ),
            ),
            FilledButton.tonal(
              key: const Key('$_k.apply'),
              onPressed: _loading ? null : _load,
              child: const Text('Show'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (error != null)
          ErrorBanner(
            key: const Key('$_k.error'),
            message: reportErrorMessage(error),
            actionLabel: 'Try again',
            onAction: _load,
          ),
        if (_entries.isEmpty && _loading)
          const Center(child: CircularProgressIndicator())
        else if (_entries.isEmpty && error == null)
          Text(
            'Nothing recorded for these filters.',
            key: const Key('$_k.empty'),
            style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          )
        else ...[
          Text(
            _total == 1 ? '1 entry' : '$_total entries',
            key: const Key('$_k.count'),
            style: textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          for (final e in _entries)
            Card(
              key: Key('$_k.entry.${e.id}'),
              margin: const EdgeInsets.only(bottom: 6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 150,
                      child: Text(
                        dateAndTime(e.occurredAt.toLocal()),
                        style: textTheme.bodySmall?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.actionLabel,
                            style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            [
                              e.actorStaffId == null ? 'By the system' : 'By ${e.actorStaffId}',
                              if (e.targetLabel != null) e.targetLabel!,
                            ].join(' · '),
                            style: textTheme.bodySmall,
                          ),
                          if (e.details != null)
                            Text(
                              e.details!,
                              style: textTheme.bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (_hasMore)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const Key('$_k.more'),
                onPressed: _loading ? null : () => _load(more: true),
                child: Text(_loading ? 'Loading…' : 'Show more'),
              ),
            ),
        ],
      ],
    );
  }
}

/// The trial balance: every general ledger account's totals and balance,
/// and whether debits equal credits.
class _TrialBalanceTab extends StatefulWidget {
  const _TrialBalanceTab({required this.api});

  final ReportApi api;

  @override
  State<_TrialBalanceTab> createState() => _TrialBalanceTabState();
}

class _TrialBalanceTabState extends State<_TrialBalanceTab> {
  TrialBalance? _tb;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final tb = await widget.api.trialBalance();
      if (mounted) setState(() => _tb = tb);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tb = _tb;
    final error = _error;
    if (tb == null) {
      return Align(
        alignment: Alignment.topLeft,
        child: error == null
            ? const CircularProgressIndicator()
            : ErrorBanner(
                key: const Key('trialBalance.error'),
                message: reportErrorMessage(error),
                actionLabel: 'Try again',
                onAction: _load,
              ),
      );
    }
    return ListView(
      key: const Key('trialBalance.view'),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Row(
          children: [
            tb.balanced
                ? const StatusPill(
                    key: Key('trialBalance.balanced'),
                    label: 'Debits equal credits',
                    tone: StatusTone.success,
                  )
                : const StatusPill(
                    key: Key('trialBalance.unbalanced'),
                    label: "Debits and credits don't match: tell the backend team",
                    tone: StatusTone.danger,
                  ),
            const Spacer(),
            IconButton(
              key: const Key('trialBalance.refresh'),
              tooltip: 'Refresh',
              onPressed: _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 16),
        GlassCard(
          title: 'General ledger accounts',
          icon: Icons.account_balance_outlined,
          child: ReportTable(
            keyPrefix: 'trialBalance',
            columns: const ['Code', 'Account', 'Category', 'Debits', 'Credits', 'Balance'],
            numeric: const {3, 4, 5},
            rows: [
              for (final l in tb.lines)
                [
                  l.accountCode,
                  l.name,
                  l.category ?? '—',
                  l.totalDebits.plain,
                  l.totalCredits.plain,
                  l.balance.plain,
                ],
              ['', 'Total', '', tb.totalDebits.plain, tb.totalCredits.plain, ''],
            ],
          ),
        ),
      ],
    );
  }
}
