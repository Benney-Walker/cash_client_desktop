import 'package:flutter/material.dart';

import '../common/dates.dart';
import '../common/glass_card.dart';
import '../common/money.dart';
import '../common/step_flow.dart';
import 'loan_api.dart';

/// A label and its value, for the loan panes.
class LoanRow extends StatelessWidget {
  const LoanRow({
    super.key,
    required this.label,
    required this.value,
    this.strong = false,
  });

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
            width: 170,
            child: Text(
              label,
              style:
                  textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: strong ? FontWeight.w600 : null,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// What a loan costs, from [LoanQuote]: interest, to repay, monthly, fee
/// and what's paid in. The same arithmetic as the backend.
class LoanQuoteRows extends StatelessWidget {
  const LoanQuoteRows({super.key, required this.quote, this.keyPrefix = 'quote'});

  final LoanQuote quote;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final monthly = quote.months == 1
        ? '${quote.lastInstallment} in one payment'
        : quote.monthly == quote.lastInstallment
            ? '${quote.monthly} × ${quote.months}'
            : '${quote.monthly} × ${quote.months - 1}, then '
                '${quote.lastInstallment}';
    return Column(
      children: [
        LoanRow(
          key: Key('$keyPrefix.interest'),
          label: 'Interest (flat)',
          value: quote.interest.toString(),
        ),
        LoanRow(
          key: Key('$keyPrefix.toRepay'),
          label: 'To repay',
          value: quote.toRepay.toString(),
          strong: true,
        ),
        LoanRow(key: Key('$keyPrefix.monthly'), label: 'Monthly', value: monthly),
        LoanRow(
          key: Key('$keyPrefix.fee'),
          label: 'Processing fee',
          value: quote.fee.toString(),
        ),
        LoanRow(
          key: Key('$keyPrefix.paidIn'),
          label: 'Paid into the account',
          value: quote.paidIn.toString(),
          strong: true,
        ),
      ],
    );
  }
}

StatusPill installmentPill(InstallmentStatus status) => switch (status) {
      InstallmentStatus.paid =>
        const StatusPill(label: 'Paid', tone: StatusTone.success),
      InstallmentStatus.overdue =>
        const StatusPill(label: 'Overdue', tone: StatusTone.danger),
      InstallmentStatus.pending =>
        const StatusPill(label: 'Due later', tone: StatusTone.neutral),
    };

/// One loan: its terms, what's paid and owed, and the installments.
class LoanDetailsView extends StatelessWidget {
  const LoanDetailsView({super.key, required this.loan});

  final LoanDetails loan;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final next = loan.nextDue;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (loan.closed)
              const StatusPill(label: 'Repaid', tone: StatusTone.success)
            else if (loan.overdue.isPositive)
              StatusPill(
                label: '${loan.overdue} overdue',
                tone: StatusTone.danger,
              )
            else
              const StatusPill(label: 'Being repaid', tone: StatusTone.neutral),
          ],
        ),
        const SizedBox(height: 12),
        GlassCard(
          key: const Key('loan.terms'),
          title: loan.productName,
          icon: Icons.request_quote_outlined,
          child: Column(
            children: [
              LoanRow(label: 'Member', value: loan.memberName),
              if (loan.accountNumber != null)
                LoanRow(label: 'Account', value: loan.accountNumber!),
              LoanRow(label: 'Lent', value: loan.amount.toString()),
              if (loan.ratePercent != null)
                LoanRow(label: 'Interest rate', value: '${loan.ratePercent}% a year'),
              if (loan.totalInterest != null)
                LoanRow(label: 'Interest', value: loan.totalInterest.toString()),
              if (loan.processingFee != null)
                LoanRow(label: 'Processing fee', value: loan.processingFee.toString()),
              LoanRow(
                label: 'Term',
                value: loan.termMonths == 1 ? '1 month' : '${loan.termMonths} months',
              ),
              if (loan.disbursementDate != null)
                LoanRow(label: 'Paid out', value: isoDate(loan.disbursementDate!)),
              if (loan.maturityDate != null)
                LoanRow(label: 'Last payment due', value: isoDate(loan.maturityDate!)),
              const Divider(height: 20),
              LoanRow(
                key: const Key('loan.toRepay'),
                label: 'To repay',
                value: loan.totalToRepay.toString(),
              ),
              LoanRow(key: const Key('loan.paid'), label: 'Paid', value: loan.paid.toString()),
              LoanRow(
                key: const Key('loan.outstanding'),
                label: 'Still owed',
                value: loan.outstanding.toString(),
                strong: true,
              ),
              if (next != null)
                LoanRow(
                  key: const Key('loan.next'),
                  label: 'Next payment',
                  value: '${next.remaining} on ${isoDate(next.dueDate)}',
                ),
            ],
          ),
        ),
        if (loan.installments.isNotEmpty) ...[
          const SizedBox(height: 16),
          GlassCard(
            key: const Key('loan.installments'),
            title: 'Installments',
            icon: Icons.calendar_month_outlined,
            child: Column(
              children: [
                for (final i in loan.installments)
                  Padding(
                    key: Key('loan.installment.${i.number}'),
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 28,
                          child: Text('${i.number}', style: textTheme.bodyMedium),
                        ),
                        SizedBox(
                          width: 110,
                          child: Text(isoDate(i.dueDate), style: textTheme.bodyMedium),
                        ),
                        Expanded(
                          child: Text(
                            i.paid.isPositive && i.remaining.isPositive
                                ? '${i.amount} · ${i.paid} paid'
                                : i.amount.toString(),
                            style: textTheme.bodyMedium?.copyWith(
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                        installmentPill(i.status),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  'Installments are taken from the member\'s account by the daily '
                  'job; an overdue one keeps being collected, with no penalty.',
                  style: textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Loads one loan and shows it.
class LoanPane extends StatefulWidget {
  const LoanPane({super.key, required this.api, required this.loanId});

  final LoanApi api;
  final String loanId;

  @override
  State<LoanPane> createState() => _LoanPaneState();
}

class _LoanPaneState extends State<LoanPane> {
  LoanDetails? _loan;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final loan = await widget.api.loan(widget.loanId);
      if (mounted) setState(() => _loan = loan);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loan = _loan;
    final error = _error;
    if (loan != null) {
      return ListView(
        key: const Key('loan.pane'),
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Text(
            loan.memberName,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          LoanDetailsView(loan: loan),
        ],
      );
    }
    if (error != null) {
      return Align(
        alignment: Alignment.topLeft,
        child: ErrorBanner(
          key: const Key('loan.error'),
          message: loanErrorMessage(error),
          actionLabel: 'Try again',
          onAction: _load,
        ),
      );
    }
    return const Center(child: CircularProgressIndicator());
  }
}

/// "GH₵ 2,000.00 · 6 months".
String amountAndTerm(Money amount, int months) =>
    '$amount · ${months == 1 ? '1 month' : '$months months'}';
