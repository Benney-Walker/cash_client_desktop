import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../common/glass_card.dart';
import '../common/gradient_button.dart';
import '../common/money.dart';
import '../common/step_flow.dart';
import 'loan_api.dart';
import 'loan_widgets.dart';

/// Loan products: the list on the left, the chosen product on the right.
/// Administrators add and edit products (including switching one off);
/// Agents see the active ones, read only.
class ProductsTab extends StatefulWidget {
  const ProductsTab({
    super.key,
    required this.api,
    required this.isAdministrator,
    required this.onChanged,
  });

  final LoanApi api;
  final bool isAdministrator;

  /// After a save, so the page's product terms follow.
  final VoidCallback onChanged;

  @override
  State<ProductsTab> createState() => _ProductsTabState();
}

class _ProductsTabState extends State<ProductsTab> {
  static const _k = 'products';

  List<LoanProduct>? _products;
  Object? _error;
  int? _selected;

  /// null: viewing; 0: adding; a product id: editing that one.
  int? _editing;
  String? _done;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final products = await widget.api.products();
      if (mounted) setState(() => _products = products);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  void _saved(LoanProduct product, {required bool added}) {
    setState(() {
      final list = [...?_products]..removeWhere((p) => p.id == product.id);
      _products = [...list, product]
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      _selected = product.id;
      _editing = null;
      _done = added ? '${product.name} added.' : '${product.name} saved.';
    });
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final products = _products;
    final error = _error;

    LoanProduct? selected;
    for (final p in products ?? const <LoanProduct>[]) {
      if (p.id == _selected) selected = p;
    }

    Widget list;
    if (products == null && error == null) {
      list = const Center(child: CircularProgressIndicator());
    } else if (products == null) {
      list = Column(
        key: const Key('$_k.error'),
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
      list = ListView(
        children: [
          if (widget.isAdministrator)
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: const Key('$_k.add'),
                onPressed: () => setState(() {
                  _editing = 0;
                  _done = null;
                }),
                icon: const Icon(Icons.add),
                label: const Text('New product'),
              ),
            ),
          const SizedBox(height: 8),
          if (products.isEmpty)
            Text(
              'No loan products yet.',
              key: const Key('$_k.empty'),
              style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          for (final p in products)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: ListTile(
                key: Key('$_k.item.${p.id}'),
                selected: p.id == _selected,
                selectedTileColor: scheme.primaryContainer,
                selectedColor: scheme.onPrimaryContainer,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                title: Text(p.name),
                subtitle: Text('${p.rateLabel} · up to ${p.maxAmount}'),
                trailing: p.active
                    ? null
                    : const StatusPill(label: 'Off', tone: StatusTone.neutral),
                onTap: () => setState(() {
                  _selected = p.id;
                  _editing = null;
                  _done = null;
                }),
              ),
            ),
        ],
      );
    }

    final Widget right;
    final editing = _editing;
    if (editing != null) {
      right = ProductForm(
        key: ValueKey('form-$editing'),
        api: widget.api,
        product: editing == 0 ? null : selected,
        onSaved: _saved,
        onCancel: () => setState(() => _editing = null),
      );
    } else if (selected == null) {
      right = Align(
        alignment: Alignment.topLeft,
        child: GlassCard(
          key: const Key('$_k.nothingSelected'),
          title: 'Product',
          icon: Icons.inventory_2_outlined,
          child: Text(
            'Choose a product on the left to see its terms.',
            style: textTheme.bodyMedium,
          ),
        ),
      );
    } else {
      final p = selected;
      right = ListView(
        key: const Key('$_k.view'),
        children: [
          if (_done != null) ...[
            Row(
              key: const Key('$_k.done'),
              children: [
                Icon(Icons.check_circle_outline, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(_done!)),
              ],
            ),
            const SizedBox(height: 12),
          ],
          GlassCard(
            title: p.name,
            icon: Icons.inventory_2_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LoanRow(label: 'Interest', value: '${p.rateLabel} (flat)'),
                LoanRow(label: 'Amount', value: '${p.minAmount} to ${p.maxAmount}'),
                LoanRow(
                  label: 'Longest term',
                  value: p.maxTermMonths == 1 ? '1 month' : '${p.maxTermMonths} months',
                ),
                LoanRow(label: 'Processing fee', value: p.feeLabel),
                LoanRow(
                  label: 'Guarantors',
                  value: p.guarantorsRequired == 0
                      ? 'None needed'
                      : '${p.guarantorsRequired} needed',
                ),
                LoanRow(label: 'Offered', value: p.active ? 'Yes' : 'No, switched off'),
                if (widget.isAdministrator) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const Key('$_k.edit'),
                    onPressed: () => setState(() {
                      _editing = p.id;
                      _done = null;
                    }),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit product'),
                  ),
                ],
              ],
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
        Expanded(child: right),
      ],
    );
  }
}

/// Adds or edits a product (Administrators). The checks match the
/// backend's `LoanProductRequest`.
class ProductForm extends StatefulWidget {
  const ProductForm({
    super.key,
    required this.api,
    required this.product,
    required this.onSaved,
    required this.onCancel,
  });

  final LoanApi api;

  /// Null to add one.
  final LoanProduct? product;
  final void Function(LoanProduct product, {required bool added}) onSaved;
  final VoidCallback onCancel;

  @override
  State<ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends State<ProductForm> {
  static const _k = 'productForm';

  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.product?.name ?? '');
  late final _rate = TextEditingController(
    text: widget.product == null ? '' : _hundredthsText(widget.product!.ratePercentHundredths),
  );
  late final _min = TextEditingController(text: _moneyText(widget.product?.minAmount));
  late final _max = TextEditingController(text: _moneyText(widget.product?.maxAmount));
  late final _term =
      TextEditingController(text: widget.product?.maxTermMonths.toString() ?? '');
  late LoanFeeType _feeType = widget.product?.feeType ?? LoanFeeType.flat;
  late final _fee = TextEditingController(
    text: widget.product == null ? '0' : _hundredthsText(widget.product!.feeValue),
  );
  late final _guarantors =
      TextEditingController(text: widget.product?.guarantorsRequired.toString() ?? '0');
  late bool _active = widget.product?.active ?? true;
  bool _saving = false;
  String? _error;

  static String _moneyText(Money? m) => m == null ? '' : m.plain.replaceAll(',', '');
  static String _hundredthsText(int h) =>
      (h % 100 == 0) ? '${h ~/ 100}' : (h / 100).toStringAsFixed(2);

  @override
  void dispose() {
    for (final c in [_name, _rate, _min, _max, _term, _fee, _guarantors]) {
      c.dispose();
    }
    super.dispose();
  }

  static int? _toHundredths(String text) {
    final m = Money.parse(text);
    return m?.pesewas;
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    final draft = LoanProductDraft(
      name: _name.text.trim(),
      ratePercentHundredths: _toHundredths(_rate.text)!,
      minAmount: Money.parse(_min.text)!,
      maxAmount: Money.parse(_max.text)!,
      maxTermMonths: int.parse(_term.text),
      feeType: _feeType,
      feeValue: _toHundredths(_fee.text)!,
      guarantorsRequired: int.parse(_guarantors.text),
      active: _active,
    );
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final product = widget.product;
      final saved = product == null
          ? await widget.api.createProduct(draft)
          : await widget.api.updateProduct(product.id, draft);
      if (mounted) widget.onSaved(saved, added: product == null);
    } catch (e) {
      if (mounted) setState(() => _error = loanErrorMessage(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _amount(String? v, {bool allowZero = false}) {
    final m = Money.parse(v ?? '');
    if (m == null) return 'Enter an amount, like 500 or 500.50';
    if (!allowZero && !m.isPositive) return 'Must be more than 0';
    return null;
  }

  String? _whole(String? v, int min, int max, String what) {
    final n = int.tryParse(v ?? '');
    if (n == null || n < min || n > max) return '$what: $min to $max';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    final decimals = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))];
    final digits = [FilteringTextInputFormatter.digitsOnly];

    return Form(
      key: _form,
      child: ListView(
        key: const Key(_k),
        children: [
          GlassCard(
            title: widget.product == null ? 'New product' : 'Edit ${widget.product!.name}',
            icon: Icons.inventory_2_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  key: const Key('$_k.name'),
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Name'),
                  maxLength: 100,
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Enter a name' : null,
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        key: const Key('$_k.rate'),
                        controller: _rate,
                        inputFormatters: decimals,
                        decoration: const InputDecoration(
                          labelText: 'Interest, % a year (flat)',
                        ),
                        validator: (v) {
                          final h = _toHundredths(v ?? '');
                          if (h == null) return 'Enter a rate, like 24 or 24.5';
                          if (h >= 100000) return 'Must be below 1000%';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        key: const Key('$_k.term'),
                        controller: _term,
                        inputFormatters: digits,
                        decoration:
                            const InputDecoration(labelText: 'Longest term (months)'),
                        validator: (v) => _whole(v, 1, 360, 'Months'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        key: const Key('$_k.min'),
                        controller: _min,
                        inputFormatters: decimals,
                        decoration: const InputDecoration(labelText: 'Smallest loan (GH₵)'),
                        validator: _amount,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        key: const Key('$_k.max'),
                        controller: _max,
                        inputFormatters: decimals,
                        decoration: const InputDecoration(labelText: 'Largest loan (GH₵)'),
                        validator: (v) {
                          final problem = _amount(v);
                          if (problem != null) return problem;
                          final min = Money.parse(_min.text);
                          if (min != null && Money.parse(v!)! < min) {
                            return "Can't be less than the smallest loan";
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<LoanFeeType>(
                        key: const Key('$_k.feeType'),
                        initialValue: _feeType,
                        decoration: const InputDecoration(labelText: 'Processing fee'),
                        items: [
                          for (final t in LoanFeeType.values)
                            DropdownMenuItem(value: t, child: Text(t.label)),
                        ],
                        onChanged: (t) => setState(() => _feeType = t ?? _feeType),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        key: const Key('$_k.fee'),
                        controller: _fee,
                        inputFormatters: decimals,
                        decoration: InputDecoration(
                          labelText: _feeType == LoanFeeType.flat
                              ? 'Fee (GH₵, 0 for none)'
                              : 'Fee (% of the loan)',
                        ),
                        validator: (v) => _amount(v, allowZero: true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('$_k.guarantors'),
                  controller: _guarantors,
                  inputFormatters: digits,
                  decoration: const InputDecoration(
                    labelText: 'Guarantors needed (0 for none)',
                  ),
                  validator: (v) => _whole(v, 0, 10, 'Guarantors'),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  key: const Key('$_k.active'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Offered to members'),
                  subtitle: const Text(
                    "Switched off, it can't be applied for or approved.",
                  ),
                  value: _active,
                  onChanged: (v) => setState(() => _active = v),
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  ErrorBanner(key: const Key('$_k.error'), message: error),
                ],
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      key: const Key('$_k.cancel'),
                      onPressed: _saving ? null : widget.onCancel,
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    GradientButton(
                      key: const Key('$_k.save'),
                      onPressed: _saving ? null : _save,
                      child: Text(_saving ? 'Saving…' : 'Save'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
