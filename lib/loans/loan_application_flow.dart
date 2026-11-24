import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_exception.dart';
import '../common/glass_card.dart';
import '../common/gradient_backdrop.dart';
import '../common/gradient_button.dart';
import '../common/money.dart';
import '../common/step_flow.dart';
import '../members/member_api.dart';
import '../theme/app_gradients.dart';
import 'loan_api.dart';
import 'loan_widgets.dart';

/// A member the application is for, or a guarantor.
class PickedMember {
  const PickedMember({required this.id, required this.name, this.status, this.detail});

  final String id;
  final String name;
  final MembershipStatus? status;

  /// Phone or branch, to tell people with the same name apart.
  final String? detail;

  bool get active => status == MembershipStatus.active;

  static PickedMember fromSummary(MemberSummary m) => PickedMember(
        id: m.memberId,
        name: m.fullName,
        status: m.status,
        detail: [m.phoneNumber, m.branchName].whereType<String>().join(' · '),
      );
}

/// Apply for a loan (steps, owner decision 24 November 2026): Member,
/// Product and amount, Guarantors and purpose, Review. Started from Loans
/// or from a member's details, which fills in the member.
///
/// Only active members can borrow and be guarantors (backend rules), so
/// the steps check that first; the backend still checks everything else
/// (membership length, one loan at a time) and its reason is shown.
class LoanApplicationFlow extends StatefulWidget {
  const LoanApplicationFlow({
    super.key,
    required this.api,
    required this.memberApi,
    required this.onClose,
    this.member,
    this.closeLabel = 'Loans',
  });

  final LoanApi api;
  final MemberApi memberApi;
  final VoidCallback onClose;

  /// Filled in when started from a member's details.
  final PickedMember? member;

  /// Where the breadcrumb leads back to.
  final String closeLabel;

  @override
  State<LoanApplicationFlow> createState() => _LoanApplicationFlowState();
}

class _LoanApplicationFlowState extends State<LoanApplicationFlow> {
  static const _k = 'applyLoan';
  static const _titles = ['Member', 'Product and amount', 'Guarantors and purpose', 'Review'];

  int _step = 0;
  late PickedMember? _member = widget.member;
  String? _memberError;

  List<LoanProduct>? _products;
  Object? _productsError;
  LoanProduct? _product;
  final _amountForm = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _term = TextEditingController();

  final List<PickedMember> _guarantors = [];
  String? _guarantorError;
  final _purpose = TextEditingController();

  bool _submitting = false;
  bool _outcomeUnknown = false;
  String? _submitError;
  LoanApplicationRecord? _sent;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void dispose() {
    _amount.dispose();
    _term.dispose();
    _purpose.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    setState(() => _productsError = null);
    try {
      final products = await widget.api.products();
      if (mounted) {
        setState(() => _products = products.where((p) => p.active).toList());
      }
    } catch (e) {
      if (mounted) setState(() => _productsError = e);
    }
  }

  Money? get _parsedAmount => Money.parse(_amount.text);
  int? get _parsedTerm => int.tryParse(_term.text);

  LoanQuote? get _quote {
    final product = _product, amount = _parsedAmount, term = _parsedTerm;
    if (product == null || amount == null || term == null || term < 1) return null;
    if (!amount.isPositive) return null;
    return LoanQuote.of(product, amount, term);
  }

  bool get _dirty => _member != widget.member || _product != null;

  void _next() {
    switch (_step) {
      case 0:
        final member = _member;
        if (member == null) {
          setState(() => _memberError = 'Choose the member the loan is for');
          return;
        }
        if (!member.active) {
          setState(() => _memberError = 'Only active members (ID verified) can '
              'get a loan; ${member.name} is ${member.status?.label.toLowerCase() ?? 'not active'}');
          return;
        }
      case 1:
        if (_product == null || !_amountForm.currentState!.validate()) {
          setState(() {});
          return;
        }
      case 2:
        final needed = _product!.guarantorsRequired;
        if (_guarantors.length != needed) {
          setState(() => _guarantorError = needed == 1
              ? '${_product!.name} needs 1 guarantor'
              : '${_product!.name} needs $needed guarantors');
          return;
        }
    }
    setState(() => _step++);
  }

  void _back() {
    if (_step == 0) {
      _leave();
    } else {
      setState(() => _step--);
    }
  }

  Future<void> _leave() async {
    if (_dirty && _sent == null) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Discard this application?'),
          content: const Text("What you've entered so far won't be saved."),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep editing'),
            ),
            TextButton(
              key: const Key('$_k.discard'),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Discard'),
            ),
          ],
        ),
      );
      if (discard != true) return;
    }
    widget.onClose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final purpose = _purpose.text.trim();
    final application = NewLoanApplication(
      memberId: _member!.id,
      productId: _product!.id,
      amount: _parsedAmount!,
      termMonths: _parsedTerm!,
      guarantorMemberIds: [for (final g in _guarantors) g.id],
      purpose: purpose.isEmpty ? null : purpose,
    );
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      final sent = await widget.api.apply(application);
      if (mounted) setState(() => _sent = sent);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitError = loanErrorMessage(e, afterUnknownOutcome: _outcomeUnknown);
        if (e is ApiException && e.failure == ApiFailure.network) {
          _outcomeUnknown = true;
        }
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final sent = _sent;

    return Stack(
      key: const Key('$_k.page'),
      children: [
        const Positioned.fill(child: PageGlows()),
        ListView(
          padding: const EdgeInsets.fromLTRB(32, 20, 32, 32),
          children: [
            Row(
              children: [
                TextButton(
                  key: const Key('$_k.breadcrumb'),
                  onPressed: sent == null ? _leave : widget.onClose,
                  child: Text(widget.closeLabel),
                ),
                Icon(Icons.chevron_right, size: 18, color: scheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(
                  'Apply for a loan',
                  style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
            Text(
              'Apply for a loan',
              style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: sent != null
                    ? _sentCard(sent)
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          StepIndicator(titles: _titles, current: _step, keyPrefix: _k),
                          const SizedBox(height: 20),
                          switch (_step) {
                            0 => _memberStep(),
                            1 => _productStep(),
                            2 => _guarantorStep(),
                            _ => _reviewStep(),
                          },
                          const SizedBox(height: 20),
                          _buttons(),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buttons() {
    final last = _step == _titles.length - 1;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        OutlinedButton(
          key: const Key('$_k.back'),
          onPressed: _submitting ? null : _back,
          child: Text(_step == 0 ? 'Cancel' : 'Back'),
        ),
        const SizedBox(width: 12),
        GradientButton(
          key: const Key('$_k.next'),
          onPressed: _submitting ? null : (last ? _submit : _next),
          child: !last
              ? const Text('Next')
              : _submitting
                  ? SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppGradients.of(context).onButton,
                      ),
                    )
                  : const Text('Send application'),
        ),
      ],
    );
  }

  Widget _memberStep() {
    final member = _member;
    return GlassCard(
      key: const Key('$_k.member'),
      title: 'Who is the loan for?',
      icon: Icons.person_search_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (member != null)
            ListTile(
              key: const Key('$_k.chosenMember'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.person_outline),
              title: Text(member.name),
              subtitle: Text([
                if (member.status != null) member.status!.label,
                if (member.detail != null && member.detail!.isNotEmpty) member.detail!,
              ].join(' · ')),
              trailing: TextButton(
                key: const Key('$_k.changeMember'),
                onPressed: () => setState(() {
                  _member = null;
                  _memberError = null;
                }),
                child: const Text('Change'),
              ),
            )
          else
            MemberPicker(
              api: widget.memberApi,
              keyPrefix: '$_k.memberSearch',
              onPicked: (m) => setState(() {
                _member = m;
                _memberError = null;
              }),
            ),
          if (_memberError != null) ...[
            const SizedBox(height: 8),
            ErrorBanner(key: const Key('$_k.memberError'), message: _memberError!),
          ],
        ],
      ),
    );
  }

  Widget _productStep() {
    final products = _products;
    final product = _product;
    final quote = _quote;

    if (products == null) {
      return GlassCard(
        title: 'Product and amount',
        icon: Icons.request_quote_outlined,
        child: _productsError == null
            ? const Center(child: CircularProgressIndicator())
            : ErrorBanner(
                message: loanErrorMessage(_productsError!),
                actionLabel: 'Try again',
                onAction: _loadProducts,
              ),
      );
    }

    return Form(
      key: _amountForm,
      child: GlassCard(
        key: const Key('$_k.product'),
        title: 'Product and amount',
        icon: Icons.request_quote_outlined,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (products.isEmpty)
              const InfoNote(text: 'No loan products are offered at the moment.')
            else
              DropdownButtonFormField<int>(
                key: const Key('$_k.productChoice'),
                initialValue: product?.id,
                decoration: const InputDecoration(labelText: 'Loan product'),
                items: [
                  for (final p in products)
                    DropdownMenuItem(value: p.id, child: Text(p.name)),
                ],
                validator: (_) => _product == null ? 'Choose a product' : null,
                onChanged: (id) => setState(() {
                  _product = products.where((p) => p.id == id).firstOrNull;
                  _guarantors.clear();
                  _guarantorError = null;
                }),
              ),
            if (product != null) ...[
              const SizedBox(height: 8),
              Text(
                '${product.rateLabel}, flat · ${product.minAmount} to '
                '${product.maxAmount} · up to ${product.maxTermMonths} months · '
                '${product.feeLabel} · '
                '${product.guarantorsRequired == 0 ? 'no guarantors' : '${product.guarantorsRequired} guarantor(s)'}',
                key: const Key('$_k.productTerms'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      key: const Key('$_k.amount'),
                      controller: _amount,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                      decoration: const InputDecoration(labelText: 'Amount (GH₵)'),
                      onChanged: (_) => setState(() {}),
                      validator: (v) {
                        final m = Money.parse(v ?? '');
                        if (m == null || !m.isPositive) return 'Enter an amount';
                        if (m < product.minAmount || m > product.maxAmount) {
                          return 'Between ${product.minAmount} and ${product.maxAmount}';
                        }
                        if (product.feeFor(m) >= m) {
                          return 'The processing fee would take the whole loan';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      key: const Key('$_k.term'),
                      controller: _term,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(labelText: 'Term (months)'),
                      onChanged: (_) => setState(() {}),
                      validator: (v) {
                        final n = int.tryParse(v ?? '');
                        if (n == null || n < 1 || n > product.maxTermMonths) {
                          return '1 to ${product.maxTermMonths} months';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              if (quote != null) ...[
                const SizedBox(height: 16),
                LoanQuoteRows(quote: quote, keyPrefix: '$_k.quote'),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _guarantorStep() {
    final product = _product!;
    final needed = product.guarantorsRequired;
    return GlassCard(
      key: const Key('$_k.guarantors'),
      title: 'Guarantors and purpose',
      icon: Icons.group_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            needed == 0
                ? '${product.name} needs no guarantors.'
                : '${product.name} needs $needed guarantor${needed == 1 ? '' : 's'}: '
                    'other active members. They are recorded with the loan.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          for (final g in _guarantors)
            ListTile(
              key: Key('$_k.guarantor.${g.id}'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.person_outline),
              title: Text(g.name),
              subtitle: g.detail == null || g.detail!.isEmpty ? null : Text(g.detail!),
              trailing: IconButton(
                tooltip: 'Remove',
                onPressed: () => setState(() => _guarantors.remove(g)),
                icon: const Icon(Icons.close),
              ),
            ),
          if (_guarantors.length < needed) ...[
            const SizedBox(height: 8),
            MemberPicker(
              api: widget.memberApi,
              keyPrefix: '$_k.guarantorSearch',
              label: 'Find a guarantor',
              onPicked: (m) {
                String? problem;
                if (m.id == _member!.id) {
                  problem = "A member can't guarantee their own loan";
                } else if (_guarantors.any((g) => g.id == m.id)) {
                  problem = '${m.name} is already a guarantor';
                } else if (!m.active) {
                  problem = '${m.name} is not an active member';
                }
                setState(() {
                  _guarantorError = problem;
                  if (problem == null) _guarantors.add(m);
                });
              },
            ),
          ],
          if (_guarantorError != null) ...[
            const SizedBox(height: 8),
            ErrorBanner(key: const Key('$_k.guarantorError'), message: _guarantorError!),
          ],
          const SizedBox(height: 16),
          TextField(
            key: const Key('$_k.purpose'),
            controller: _purpose,
            maxLength: 500,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Purpose (optional)'),
          ),
        ],
      ),
    );
  }

  Widget _reviewStep() {
    final quote = _quote!;
    final error = _submitError;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassCard(
          key: const Key('$_k.review'),
          title: 'Review',
          icon: Icons.fact_check_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ReviewSection(
                title: 'Member',
                keyPrefix: '$_k.review.member',
                onEdit: () => setState(() => _step = 0),
                rows: [('Member', _member!.name)],
              ),
              ReviewSection(
                title: 'Loan',
                keyPrefix: '$_k.review.loan',
                onEdit: () => setState(() => _step = 1),
                rows: [
                  ('Product', _product!.name),
                  ('Amount', quote.amount.toString()),
                  ('Term', quote.months == 1 ? '1 month' : '${quote.months} months'),
                ],
              ),
              ReviewSection(
                title: 'Guarantors and purpose',
                keyPrefix: '$_k.review.guarantors',
                onEdit: () => setState(() => _step = 2),
                rows: [
                  (
                    'Guarantors',
                    _guarantors.isEmpty ? 'None' : _guarantors.map((g) => g.name).join(', '),
                  ),
                  ('Purpose', _purpose.text.trim().isEmpty ? '—' : _purpose.text.trim()),
                ],
              ),
              const Divider(height: 24),
              LoanQuoteRows(quote: quote, keyPrefix: '$_k.reviewQuote'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const InfoNote(
          text: 'An administrator approves or rejects the application. '
              'Approval pays the loan into the member\'s savings or current '
              'account, less the processing fee, and repayments are taken '
              'from it each month.',
        ),
        if (error != null) ...[
          const SizedBox(height: 12),
          ErrorBanner(key: const Key('$_k.error'), message: error),
        ],
      ],
    );
  }

  Widget _sentCard(LoanApplicationRecord sent) {
    return GlassCard(
      key: const Key('$_k.sent'),
      title: 'Application sent',
      icon: Icons.check_circle_outline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "${sent.memberName}'s application for "
            '${amountAndTerm(sent.requestedAmount, sent.termMonths)} '
            '(${sent.productName}) is waiting for an administrator.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          GradientButton(
            key: const Key('$_k.done'),
            onPressed: widget.onClose,
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}

/// A small member search: a box and up to the first page of results.
/// Searches once typing pauses, from two characters.
class MemberPicker extends StatefulWidget {
  const MemberPicker({
    super.key,
    required this.api,
    required this.keyPrefix,
    required this.onPicked,
    this.label = 'Find the member',
  });

  final MemberApi api;
  final String keyPrefix;
  final ValueChanged<PickedMember> onPicked;
  final String label;

  @override
  State<MemberPicker> createState() => _MemberPickerState();
}

class _MemberPickerState extends State<MemberPicker> {
  final _query = TextEditingController();
  Timer? _pause;
  List<MemberSummary>? _results;
  Object? _error;
  int _run = 0;

  @override
  void dispose() {
    _pause?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _changed(String text) {
    _pause?.cancel();
    if (text.trim().length < MemberApi.minQueryLength) {
      setState(() {
        _results = null;
        _error = null;
      });
      return;
    }
    _pause = Timer(const Duration(milliseconds: 400), () => _search(text));
  }

  Future<void> _search(String text) async {
    final run = ++_run;
    try {
      final page = await widget.api.searchMembers(text);
      if (mounted && run == _run) {
        setState(() {
          _results = page.items;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && run == _run) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    final error = _error;
    final scheme = Theme.of(context).colorScheme;
    final k = widget.keyPrefix;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: Key('$k.field'),
          controller: _query,
          onChanged: _changed,
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: 'Name, phone number or account number',
            prefixIcon: const Icon(Icons.search),
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              error is ApiException
                  ? commonFailureMessage(error, action: 'find members')
                  : 'Something went wrong.',
              style: TextStyle(color: scheme.error),
            ),
          ),
        if (results != null && results.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('No members match.'),
          ),
        if (results != null)
          for (final m in results)
            ListTile(
              key: Key('$k.result.${m.memberId}'),
              contentPadding: EdgeInsets.zero,
              title: Text(m.fullName),
              subtitle: Text([
                if (m.status != null) m.status!.label,
                if (m.phoneNumber != null) m.phoneNumber!,
                if (m.branchName != null) m.branchName!,
              ].join(' · ')),
              onTap: () {
                widget.onPicked(PickedMember.fromSummary(m));
                _query.clear();
                setState(() => _results = null);
              },
            ),
      ],
    );
  }
}
