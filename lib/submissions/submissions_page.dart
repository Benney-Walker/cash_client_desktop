import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../common/dates.dart';
import '../common/glass_card.dart';
import '../common/gradient_backdrop.dart';
import '../common/gradient_button.dart';
import '../common/step_flow.dart';
import '../theme/app_gradients.dart';
import '../theme/app_status_colors.dart';
import 'submission_api.dart';
import 'submission_models.dart';

/// The Daily submissions section (option S3, owner decisions 24 November
/// 2026): collectors' handed-in days on the left; the chosen one on the
/// right with its totals, payments and, while it's waiting, the cash-count
/// helper and Approve.
///
/// There's no rejection (backend decision): a count below the expected
/// cash can't be approved, so Approve stays off until the count reaches
/// it. A surplus is approved directly and recorded by the backend.
class SubmissionsPage extends StatefulWidget {
  const SubmissionsPage({super.key, required this.api});

  final SubmissionApi api;

  @override
  State<SubmissionsPage> createState() => _SubmissionsPageState();
}

class _SubmissionsPageState extends State<SubmissionsPage> {
  SubmissionStatus _status = SubmissionStatus.submitted;
  List<CollectorSubmission> _items = const [];
  int _page = 0;
  bool _hasMore = false;
  int _total = 0;
  bool _loading = false;
  bool _loadingMore = false;
  Object? _error;
  int _loadNumber = 0;
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final number = ++_loadNumber;
    final status = _status;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.api.list(status);
      if (!mounted || number != _loadNumber) return;
      setState(() {
        _items = page.items;
        _page = page.number;
        _hasMore = page.hasMore;
        _total = page.totalElements;
      });
    } catch (error) {
      if (!mounted || number != _loadNumber) return;
      setState(() => _error = error);
    } finally {
      if (mounted && number == _loadNumber) setState(() => _loading = false);
    }
  }

  Future<void> _more() async {
    final number = _loadNumber;
    setState(() => _loadingMore = true);
    try {
      final page = await widget.api.list(_status, page: _page + 1);
      if (!mounted || number != _loadNumber) return;
      setState(() {
        _items = [..._items, ...page.items];
        _page = page.number;
        _hasMore = page.hasMore;
        _total = page.totalElements;
      });
    } catch (error) {
      if (mounted && number == _loadNumber) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _switch(SubmissionStatus status) {
    if (status == _status) return;
    setState(() {
      _status = status;
      _items = const [];
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final selected = _selectedId;

    return Stack(
      key: const Key('page.submissions'),
      children: [
        const Positioned.fill(child: PageGlows()),
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 28, 32, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Daily submissions',
                style: textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 340, child: _list(context)),
                    const SizedBox(width: 24),
                    Expanded(
                      child: selected == null
                          ? const _NothingSelected()
                          : SubmissionDetailsPane(
                              key: ValueKey(selected),
                              api: widget.api,
                              submissionId: selected,
                              onApproved: _load,
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

  Widget _list(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final error = _error;

    Widget body;
    if (_items.isEmpty && _loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (error != null && _items.isEmpty) {
      body = Column(
        key: const Key('sub.listError'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            submissionLoadErrorMessage(error),
            style: textTheme.bodyMedium?.copyWith(color: scheme.error),
          ),
          TextButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ],
      );
    } else if (_items.isEmpty) {
      body = Text(
        _status == SubmissionStatus.submitted
            ? 'No submissions are waiting.'
            : 'No approved submissions yet.',
        key: const Key('sub.empty'),
        style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      );
    } else {
      body = ListView(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Text(
              _total == 1 ? '1 submission' : '$_total submissions',
              style: textTheme.labelMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          for (final item in _items)
            _ListTile(
              item: item,
              selected: item.submissionId == _selectedId,
              onTap: () => setState(() => _selectedId = item.submissionId),
            ),
          if (_hasMore)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const Key('sub.more'),
                onPressed: _loadingMore ? null : _more,
                child: Text(_loadingMore ? 'Loading…' : 'Show more'),
              ),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: SegmentedButton<SubmissionStatus>(
                segments: const [
                  ButtonSegment(
                    value: SubmissionStatus.submitted,
                    label: Text('Waiting', key: Key('sub.tab.submitted')),
                  ),
                  ButtonSegment(
                    value: SubmissionStatus.approved,
                    label: Text('Approved', key: Key('sub.tab.approved')),
                  ),
                ],
                selected: {_status},
                showSelectedIcon: false,
                onSelectionChanged: (s) => _switch(s.single),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              key: const Key('sub.refresh'),
              tooltip: 'Refresh',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(child: body),
      ],
    );
  }
}

class _ListTile extends StatelessWidget {
  const _ListTile({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final CollectorSubmission item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final when = item.submittedAt;
    final details = [
      item.branchName,
      if (when != null) dateAndTime(when),
    ].whereType<String>().join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        key: Key('sub.item.${item.submissionId}'),
        selected: selected,
        selectedTileColor: scheme.primaryContainer,
        selectedColor: scheme.onPrimaryContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(item.collectorName),
        subtitle: details.isEmpty ? null : Text(details),
        trailing: Text(
          item.expectedAmount.plain,
          style: const TextStyle(
            fontFeatures: [FontFeature.tabularFigures()],
            fontWeight: FontWeight.w600,
          ),
        ),
        onTap: onTap,
      ),
    );
  }
}

class _NothingSelected extends StatelessWidget {
  const _NothingSelected();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: GlassCard(
        key: const Key('sub.nothingSelected'),
        title: 'Submission',
        icon: Icons.fact_check_outlined,
        child: Text(
          'Choose a collector on the left to see their day and count the '
          'cash they handed in.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}

/// One submission: totals, the cash count and Approve while it's waiting,
/// and its payments. Give it a key per submission so it starts fresh.
class SubmissionDetailsPane extends StatefulWidget {
  const SubmissionDetailsPane({
    super.key,
    required this.api,
    required this.submissionId,
    required this.onApproved,
  });

  final SubmissionApi api;
  final String submissionId;

  /// After an approval, so the list can drop it from Waiting.
  final VoidCallback onApproved;

  @override
  State<SubmissionDetailsPane> createState() => _SubmissionDetailsPaneState();
}

class _SubmissionDetailsPaneState extends State<SubmissionDetailsPane> {
  CollectorSubmission? _submission;
  Object? _loadError;
  bool _loading = true;

  CashCount _count = const CashCount();
  bool _approving = false;
  String? _approveError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final submission = await widget.api.fetch(widget.submissionId);
      if (mounted) setState(() => _submission = submission);
    } catch (error) {
      if (mounted) setState(() => _loadError = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _approve() async {
    final submission = _submission;
    if (submission == null || _approving) return;
    final counted = _count.total;
    if (counted < submission.expectedAmount) return;
    setState(() {
      _approving = true;
      _approveError = null;
    });
    try {
      final approved = await widget.api.approve(submission.submissionId, counted);
      if (!mounted) return;
      setState(() => _submission = approved);
      widget.onApproved();
    } catch (error) {
      if (mounted) setState(() => _approveError = approveErrorMessage(error));
    } finally {
      if (mounted) setState(() => _approving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final submission = _submission;
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    if (submission == null && _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (submission == null) {
      return Column(
        key: const Key('sub.loadError'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            submissionLoadErrorMessage(_loadError ?? 'error'),
            style: textTheme.bodyMedium?.copyWith(color: scheme.error),
          ),
          TextButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ],
      );
    }

    final when = submission.submittedAt;
    return ListView(
      key: const Key('sub.details'),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    submission.collectorName,
                    style: textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    [
                      submission.collectorStaffId,
                      submission.branchName,
                      if (when != null) 'submitted ${dateAndTime(when)}',
                    ].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
                    style: textTheme.bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            StatusPill(
              label: submission.status.label,
              tone: submission.waiting ? StatusTone.warning : StatusTone.success,
            ),
          ],
        ),
        const SizedBox(height: 16),
        GlassCard(
          key: const Key('sub.summary'),
          title: 'The day',
          icon: Icons.summarize_outlined,
          child: Column(
            children: [
              _Line(
                label: 'Payments',
                value: '${submission.paymentCount}',
              ),
              _Line(
                label: 'Expected cash',
                value: submission.expectedAmount.toString(),
                strong: true,
              ),
              if (submission.failedCount > 0)
                _Line(
                  label: 'Failed payments',
                  value: '${submission.failedCount} · '
                      '${submission.failedAmount} (not in the expected cash)',
                ),
              if (submission.countedAmount != null)
                _Line(
                  label: 'Cash counted',
                  value: submission.countedAmount.toString(),
                ),
              if (submission.overageAmount != null &&
                  submission.overageAmount!.isPositive)
                _Line(
                  label: 'Surplus recorded',
                  value: submission.overageAmount.toString(),
                ),
              if (submission.approvedAt != null)
                _Line(
                  label: 'Approved',
                  value: [
                    dateAndTime(submission.approvedAt!),
                    if (submission.approvedByStaffId != null)
                      'by ${submission.approvedByStaffId}',
                  ].join(' '),
                ),
            ],
          ),
        ),
        if (submission.waiting) ...[
          const SizedBox(height: 16),
          _countCard(context, submission),
        ],
        const SizedBox(height: 16),
        _paymentsCard(context, submission),
      ],
    );
  }

  Widget _countCard(BuildContext context, CollectorSubmission submission) {
    final textTheme = Theme.of(context).textTheme;
    final status = AppStatusColors.of(context);
    final total = _count.total;
    final expected = submission.expectedAmount;
    final error = _approveError;

    final (Color colour, Color background, IconData icon, String text) =
        total == expected
            ? (
                status.success,
                status.successContainer,
                Icons.check_circle,
                'Counted $total · matches the expected cash',
              )
            : total < expected
                ? (
                    status.warning,
                    status.warningContainer,
                    Icons.pending_outlined,
                    'Counted $total · ${expected - total} still to count',
                  )
                : (
                    status.neutral,
                    status.neutralContainer,
                    Icons.add_circle_outline,
                    'Counted $total · ${total - expected} over, recorded as a '
                        'surplus',
                  );

    return GlassCard(
      key: const Key('sub.countCard'),
      title: 'Count the cash',
      icon: Icons.payments_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Enter how many of each note and coin you counted.',
            style: textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final d in Denomination.values)
                SizedBox(
                  width: 150,
                  child: _DenominationField(
                    denomination: d,
                    subtotal: _count.subtotal(d),
                    enabled: !_approving,
                    onChanged: (count) =>
                        setState(() => _count = _count.withCount(d, count)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Semantics(
            liveRegion: true,
            child: Container(
              key: const Key('sub.total'),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(icon, color: colour),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      text,
                      style: textTheme.titleSmall?.copyWith(
                        color: colour,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            ErrorBanner(key: const Key('sub.error'), message: error),
          ],
          const SizedBox(height: 12),
          Text(
            'Approving is final and signs ${submission.collectorName} out '
            'until tomorrow.',
            style: textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: GradientButton(
              key: const Key('sub.approve'),
              onPressed: total >= expected && !_approving ? _approve : null,
              child: _approving
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppGradients.of(context).onButton,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text('Approving…'),
                      ],
                    )
                  : Text(error == null ? 'Approve' : 'Approve again'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _paymentsCard(BuildContext context, CollectorSubmission submission) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return GlassCard(
      key: const Key('sub.payments'),
      title: 'Payments',
      icon: Icons.receipt_long_outlined,
      child: submission.payments.isEmpty
          ? Text('No payments in this submission.', style: textTheme.bodyMedium)
          : Column(
              children: [
                for (final p in submission.payments)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 56,
                          child: Text(
                            p.createdAt == null ? '' : clockTime(p.createdAt!),
                            style: textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(p.memberName, style: textTheme.bodyMedium),
                              Text(
                                '${p.typeLabel} ${p.accountNumber}',
                                style: textTheme.bodySmall
                                    ?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                              if (!p.completed)
                                Text(
                                  'Failed${p.failureReason == null ? '' : ': ${p.failureReason}'}',
                                  style: textTheme.bodySmall
                                      ?.copyWith(color: scheme.error),
                                ),
                            ],
                          ),
                        ),
                        Text(
                          p.amount.plain,
                          style: textTheme.bodyMedium?.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                            decoration:
                                p.completed ? null : TextDecoration.lineThrough,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

/// A count box for one note or coin, with its subtotal underneath.
class _DenominationField extends StatelessWidget {
  const _DenominationField({
    required this.denomination,
    required this.subtotal,
    required this.enabled,
    required this.onChanged,
  });

  final Denomination denomination;
  final Money subtotal;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: Key('sub.count.${denomination.name}'),
          enabled: enabled,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(5),
          ],
          style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
          decoration: InputDecoration(
            labelText: denomination.label,
            suffixText: '×',
            isDense: true,
          ),
          onChanged: (text) => onChanged(int.tryParse(text) ?? 0),
        ),
        const SizedBox(height: 2),
        Text(
          '= ${subtotal.plain}',
          style: textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value, this.strong = false});

  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(
              label,
              style:
                  textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: (strong ? textTheme.titleMedium : textTheme.bodyMedium)
                  ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ),
        ],
      ),
    );
  }
}
