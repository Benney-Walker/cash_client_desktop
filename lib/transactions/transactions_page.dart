import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_exception.dart';
import '../common/dates.dart';
import '../common/glass_card.dart';
import '../common/gradient_backdrop.dart';
import '../common/gradient_button.dart';
import '../common/step_flow.dart';
import '../common/uuid.dart';
import '../members/member_api.dart';
import '../members/member_status_style.dart';
import '../theme/app_gradients.dart';
import 'account_finder.dart';
import 'receipt.dart';
import 'transaction_api.dart';
import 'transaction_models.dart';

/// The Transactions section (design option T3, owner decisions
/// 24 November 2026): the account, its balances and recent history on the
/// left, and the transaction form, review and result on the right.
/// Withdrawal, deposit, share purchase and transfer, for Administrators
/// and Agents, for a member of any branch.
///
/// Idempotency follows CASH_CLIENT_DESKTOP.md section 15: one key per
/// review step, the same key on every retry, and a lost answer shown as
/// "outcome unknown" with only a same-key retry offered.
class TransactionsPage extends StatefulWidget {
  const TransactionsPage({
    super.key,
    required this.api,
    required this.memberApi,
    required this.staffId,
    required this.creditUnionName,
    this.printReceipt = printReceiptPdf,
  });

  final TransactionApi api;
  final MemberApi memberApi;

  /// The signed-in staff member, for the receipt's "Served by".
  final String staffId;
  final String creditUnionName;
  final PrintReceipt printReceipt;

  @override
  State<TransactionsPage> createState() => _TransactionsPageState();
}

enum _Stage { form, review, done }

class _TransactionsPageState extends State<TransactionsPage> {
  static const _k = 'tx';

  CounterSettings? _settings;

  // The chosen account (left side).
  MemberSummary? _member;
  String? _accountNumber;
  AccountDetails? _account;
  Object? _accountError;
  bool _loadingAccount = false;
  List<TransactionRecord> _history = const [];
  Object? _historyError;
  bool _loadingHistory = false;

  // The form (right side).
  TransactionKind _kind = TransactionKind.withdrawal;
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  final _toNumber = TextEditingController();
  AccountDetails? _toAccount;
  String? _toError;
  bool _findingTo = false;

  // Review and result.
  _Stage _stage = _Stage.form;
  TransactionDraft? _draft;
  String? _formError;
  bool _preparing = false;
  String? _idempotencyKey;
  bool _sending = false;
  String? _sendError;
  bool _outcomeUnknown = false;
  TransactionRecord? _result;
  bool _printing = false;
  String? _printError;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    _toNumber.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final settings = await widget.api.fetchSettings();
    if (mounted) setState(() => _settings = settings);
  }

  // ---------------------------------------------------------------------
  // Account (left side)

  void _pick(MemberSummary member, String accountNumber) {
    setState(() {
      _member = member;
      _accountNumber = accountNumber;
      _account = null;
      _history = const [];
      _resetForm(keepKind: false);
    });
    _loadAccount();
  }

  void _changeAccount() {
    if (_outcomeUnknown) return;
    setState(() {
      _member = null;
      _accountNumber = null;
      _account = null;
      _history = const [];
      _resetForm(keepKind: false);
    });
  }

  Future<void> _loadAccount() async {
    final number = _accountNumber;
    if (number == null) return;
    setState(() {
      _loadingAccount = true;
      _accountError = null;
    });
    try {
      final account = await widget.api.fetchAccount(number);
      if (!mounted || number != _accountNumber) return;
      setState(() {
        _account = account;
        if (account.isShares) _kind = TransactionKind.sharePurchase;
      });
    } catch (error) {
      if (!mounted || number != _accountNumber) return;
      setState(() => _accountError = error);
    } finally {
      if (mounted && number == _accountNumber) {
        setState(() => _loadingAccount = false);
      }
    }
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final number = _accountNumber;
    if (number == null) return;
    setState(() {
      _loadingHistory = true;
      _historyError = null;
    });
    try {
      final page = await widget.api.fetchHistory(number);
      if (!mounted || number != _accountNumber) return;
      setState(() => _history = page.items);
    } catch (error) {
      if (!mounted || number != _accountNumber) return;
      setState(() => _historyError = error);
    } finally {
      if (mounted && number == _accountNumber) {
        setState(() => _loadingHistory = false);
      }
    }
  }

  /// The member's shares account, for a share purchase started from a
  /// savings or current account.
  String? get _sharesAccountNumber {
    final account = _account;
    if (account != null && account.isShares) return account.accountNumber;
    for (final a in _member?.accounts ?? const <MemberAccountSummary>[]) {
      if (a.type == 'SHARES') return a.accountNumber;
    }
    return null;
  }

  bool _kindAvailable(TransactionKind kind) {
    final account = _account;
    if (account == null) return false;
    if (account.isShares) return kind == TransactionKind.sharePurchase;
    if (kind == TransactionKind.sharePurchase) {
      return _sharesAccountNumber != null;
    }
    return true;
  }

  // ---------------------------------------------------------------------
  // Form, review, result (right side)

  void _resetForm({required bool keepKind}) {
    if (!keepKind) _kind = TransactionKind.withdrawal;
    _amount.clear();
    _note.clear();
    _toNumber.clear();
    _toAccount = null;
    _toError = null;
    _stage = _Stage.form;
    _draft = null;
    _formError = null;
    _idempotencyKey = null;
    _sendError = null;
    _outcomeUnknown = false;
    _result = null;
    _printError = null;
  }

  void _selectKind(TransactionKind kind) {
    if (_stage != _Stage.form) return;
    setState(() {
      _kind = kind;
      _formError = null;
    });
  }

  Future<void> _findTo() async {
    final number = _toNumber.text.trim();
    if (number.isEmpty) {
      setState(() => _toError = 'Enter the receiving account number');
      return;
    }
    setState(() {
      _findingTo = true;
      _toError = null;
      _toAccount = null;
    });
    try {
      final account = await widget.api.fetchAccount(number);
      if (!mounted) return;
      setState(() {
        if (account.accountNumber == _account?.accountNumber) {
          _toError = "That's the same account. Choose another.";
        } else if (account.isShares) {
          _toError = "Transfers can't go to a shares account.";
        } else {
          _toAccount = account;
        }
      });
    } catch (error) {
      if (mounted) setState(() => _toError = accountErrorMessage(error));
    } finally {
      if (mounted) setState(() => _findingTo = false);
    }
  }

  Future<void> _review() async {
    final account = _account;
    if (account == null || _preparing) return;
    if (!_formKey.currentState!.validate()) return;
    if (_kind == TransactionKind.transfer && _toAccount == null) {
      setState(() => _toError = 'Find the receiving account first');
      return;
    }
    final amount = Money.parse(_amount.text)!;
    var target = account;
    if (_kind == TransactionKind.sharePurchase && !account.isShares) {
      // Shares are bought into the member's shares account.
      setState(() {
        _preparing = true;
        _formError = null;
      });
      try {
        target = await widget.api.fetchAccount(_sharesAccountNumber!);
      } catch (error) {
        if (!mounted) return;
        setState(() {
          _formError = accountErrorMessage(error);
          _preparing = false;
        });
        return;
      }
      if (!mounted) return;
    }
    setState(() {
      _preparing = false;
      _formError = null;
      _draft = TransactionDraft(
        kind: _kind,
        account: target,
        toAccount: _kind == TransactionKind.transfer ? _toAccount : null,
        amount: amount,
        description: _note.text,
      );
      // One key for this review; kept for every retry of it.
      _idempotencyKey = newUuid();
      _sendError = null;
      _outcomeUnknown = false;
      _stage = _Stage.review;
    });
  }

  void _backToForm() {
    if (_sending || _outcomeUnknown) return;
    setState(() {
      _stage = _Stage.form;
      // Changing anything makes it a new transaction with a new key.
      _idempotencyKey = null;
      _sendError = null;
    });
  }

  Future<void> _confirm() async {
    final draft = _draft;
    final key = _idempotencyKey;
    if (draft == null || key == null || _sending) return;
    setState(() {
      _sending = true;
      _sendError = null;
    });
    try {
      final record = await widget.api.send(draft, idempotencyKey: key);
      if (!mounted) return;
      setState(() {
        _result = record;
        _stage = _Stage.done;
        _outcomeUnknown = false;
      });
      _loadAccount();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        if (error is ApiException && error.failure == ApiFailure.network) {
          _outcomeUnknown = true;
        }
        _sendError = transactionErrorMessage(error);
      });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _newTransaction() => setState(() => _resetForm(keepKind: true));

  ReceiptData _receipt(TransactionRecord record, TransactionDraft draft) =>
      ReceiptData(
        creditUnionName: widget.creditUnionName,
        kind: draft.kind,
        record: record,
        memberName: draft.account.memberName,
        toMemberName: draft.toAccount?.memberName,
        staffId: widget.staffId,
      );

  Future<void> _print() async {
    final record = _result;
    final draft = _draft;
    if (record == null || draft == null || _printing) return;
    setState(() {
      _printing = true;
      _printError = null;
    });
    try {
      await widget.printReceipt(_receipt(record, draft));
    } catch (_) {
      if (mounted) {
        setState(() => _printError =
            "The receipt couldn't be printed. Check the printer and try "
            'again.');
      }
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  // ---------------------------------------------------------------------
  // Layout

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Stack(
      key: const Key('page.transactions'),
      children: [
        const Positioned.fill(child: PageGlows()),
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 28, 32, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Transactions',
                style: textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 380, child: _leftSide(context)),
                    const SizedBox(width: 24),
                    Expanded(child: _rightSide(context)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _leftSide(BuildContext context) {
    if (_accountNumber == null) {
      return AccountFinder(api: widget.memberApi, onPick: _pick);
    }
    return ListView(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const Key('$_k.changeAccount'),
            onPressed: _outcomeUnknown || _sending ? null : _changeAccount,
            icon: const Icon(Icons.arrow_back),
            label: const Text('Find another account'),
          ),
        ),
        const SizedBox(height: 8),
        _accountCard(context),
        const SizedBox(height: 16),
        _historyCard(context),
      ],
    );
  }

  Widget _accountCard(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final account = _account;
    final error = _accountError;

    Widget body;
    if (account == null && _loadingAccount) {
      body = const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (account == null) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ErrorBanner(
            message: error == null
                ? 'Something went wrong. Try again.'
                : accountErrorMessage(error),
          ),
          TextButton.icon(
            onPressed: _loadAccount,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ],
      );
    } else {
      final status = account.status;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(account.memberName, style: textTheme.titleMedium),
          const SizedBox(height: 2),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${account.typeLabel} ${account.accountNumber}',
                  style: textTheme.bodyMedium?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              if (status != null) accountPill(status),
            ],
          ),
          const SizedBox(height: 12),
          _AmountLine(label: 'Available', money: account.availableBalance),
          _AmountLine(
            label: 'Current',
            money: account.currentBalance,
            quiet: true,
          ),
          if (!account.canTransact) ...[
            const SizedBox(height: 12),
            InfoNote(
              key: const Key('$_k.inactive'),
              text: "Money can't move on this account while it is "
                  '${status?.label.toLowerCase() ?? 'not active'}. Accounts '
                  "become active once the member's ID is verified.",
            ),
          ],
        ],
      );
    }

    return GlassCard(
      key: const Key('$_k.accountCard'),
      title: 'Account',
      icon: Icons.account_balance_wallet_outlined,
      child: body,
    );
  }

  Widget _historyCard(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final number = _accountNumber!;
    final error = _historyError;

    Widget body;
    if (_history.isEmpty && _loadingHistory) {
      body = const Center(child: CircularProgressIndicator());
    } else if (error != null && _history.isEmpty) {
      body = Text(
        accountErrorMessage(error),
        style: textTheme.bodyMedium?.copyWith(color: scheme.error),
      );
    } else if (_history.isEmpty) {
      body = Text('No transactions yet.', style: textTheme.bodyMedium);
    } else {
      body = Column(
        children: [
          for (final record in _history)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(record.typeLabel, style: textTheme.bodyMedium),
                        if (record.createdAt != null)
                          Text(
                            isoDate(record.createdAt!),
                            style: textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    _signed(record.signedFor(number)),
                    style: textTheme.bodyMedium?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    }

    return GlassCard(
      key: const Key('$_k.history'),
      title: 'Recent transactions',
      icon: Icons.history,
      child: body,
    );
  }

  static String _signed(Money money) =>
      money.pesewas >= 0 ? '+${money.plain}' : money.plain;

  Widget _rightSide(BuildContext context) {
    final account = _account;
    if (account == null) {
      return Align(
        alignment: Alignment.topLeft,
        child: GlassCard(
          key: const Key('$_k.nothingChosen'),
          title: 'New transaction',
          icon: Icons.payments_outlined,
          child: Text(
            'Find the account on the left: type its number, or the '
            "member's name or phone number, then choose the account.",
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }
    return ListView(
      children: [
        switch (_stage) {
          _Stage.form => _form(context, account),
          _Stage.review => _reviewCard(context),
          _Stage.done => _doneCard(context),
        },
      ],
    );
  }

  Widget _form(BuildContext context, AccountDetails account) {
    final textTheme = Theme.of(context).textTheme;
    final settings = _settings;
    final error = _formError;

    final String? note = switch (_kind) {
      TransactionKind.withdrawal => settings == null
          ? 'A withdrawal fee is added on top of the amount. The account '
              'keeps a minimum balance, and there is a daily limit.'
          : _withdrawalNote(settings),
      TransactionKind.deposit => settings == null
          ? "A member's first deposit has a minimum, and part of it goes to "
              'their shares account.'
          : "A member's first deposit must be at least "
              '${settings.minFirstDeposit}; ${settings.initialShareAmount} '
              'of it goes to their shares account.',
      TransactionKind.sharePurchase => account.isShares
          ? null
          : "Shares are bought into the member's shares account "
              '(${_sharesAccountNumber ?? ''}).',
      TransactionKind.transfer =>
        'No fee. The source account keeps its minimum balance.',
    };

    return Form(
      key: _formKey,
      child: GlassCard(
        key: const Key('$_k.form'),
        title: 'New transaction',
        icon: Icons.payments_outlined,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final kind in TransactionKind.values)
                  ChoiceChip(
                    key: Key('$_k.kind.${kind.name}'),
                    label: Text(kind.tab),
                    selected: _kind == kind,
                    onSelected: _kindAvailable(kind)
                        ? (_) => _selectKind(kind)
                        : null,
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (_kind == TransactionKind.transfer) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      key: const Key('$_k.toAccount'),
                      controller: _toNumber,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      onChanged: (_) {
                        if (_toAccount != null || _toError != null) {
                          setState(() {
                            _toAccount = null;
                            _toError = null;
                          });
                        }
                      },
                      onFieldSubmitted: (_) => _findTo(),
                      decoration: InputDecoration(
                        labelText: 'To account number',
                        errorText: _toError,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: OutlinedButton(
                      key: const Key('$_k.findTo'),
                      onPressed: _findingTo ? null : _findTo,
                      child: Text(_findingTo ? 'Finding…' : 'Find'),
                    ),
                  ),
                ],
              ),
              if (_toAccount != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'To ${_toAccount!.memberName} · '
                    '${_toAccount!.typeLabel} ${_toAccount!.accountNumber}',
                    key: const Key('$_k.toFound'),
                    style: textTheme.bodyMedium,
                  ),
                ),
              const SizedBox(height: 16),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    key: const Key('$_k.amount'),
                    controller: _amount,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    style: const TextStyle(
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Amount',
                      prefixText: 'GH₵ ',
                    ),
                    validator: (value) {
                      final money = Money.parse(value ?? '');
                      if (money == null) {
                        return 'Enter an amount, such as 250 or 250.50';
                      }
                      if (!money.isPositive) {
                        return 'The amount must be more than zero';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    key: const Key('$_k.note'),
                    controller: _note,
                    inputFormatters: [LengthLimitingTextInputFormatter(500)],
                    decoration:
                        const InputDecoration(labelText: 'Note (optional)'),
                  ),
                ),
              ],
            ),
            if (note != null) ...[
              const SizedBox(height: 16),
              InfoNote(key: const Key('$_k.kindNote'), text: note),
            ],
            if (error != null) ...[
              const SizedBox(height: 12),
              ErrorBanner(message: error),
            ],
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerRight,
              child: GradientButton(
                key: const Key('$_k.review'),
                onPressed: !account.canTransact ||
                        !_kindAvailable(_kind) ||
                        _preparing
                    ? null
                    : _review,
                child: Text(_preparing ? 'Getting ready…' : 'Review'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _withdrawalNote(CounterSettings settings) {
    final fee = !settings.withdrawalFeeEnabled
        ? 'No withdrawal fee.'
        : settings.withdrawalFeePercentage
            ? 'A fee of ${_percent(settings.withdrawalFeeValue)}% is added '
                'on top.'
            : 'A fee of ${settings.withdrawalFee(Money.zero)} is added on top.';
    return '$fee The account keeps at least ${settings.withdrawalMinBalance}, '
        'and at most ${settings.withdrawalDailyLimit} can be withdrawn from '
        'it a day.';
  }

  /// 2 for 2.0, 1.5 for 1.5.
  static String _percent(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toString();

  Widget _reviewCard(BuildContext context) {
    final draft = _draft!;
    final settings = _settings;
    final error = _sendError;
    final fee = draft.kind == TransactionKind.withdrawal && settings != null
        ? settings.withdrawalFee(draft.amount)
        : null;

    final rows = <(String, String)>[
      ('Transaction', draft.kind.label),
      ('Member', draft.account.memberName),
      (
        draft.kind == TransactionKind.transfer ? 'From' : 'Account',
        '${draft.account.typeLabel} ${draft.account.accountNumber}',
      ),
      if (draft.toAccount != null)
        (
          'To',
          '${draft.toAccount!.memberName} · ${draft.toAccount!.typeLabel} '
              '${draft.toAccount!.accountNumber}',
        ),
      ('Amount', draft.amount.toString()),
      if (fee != null && fee.isPositive) ...[
        ('Fee', fee.toString()),
        ('Taken from the account', (draft.amount + fee).toString()),
      ],
      if (draft.kind == TransactionKind.withdrawal && settings == null)
        ('Fee', 'Added on top by the system'),
      if (draft.description != null && draft.description!.trim().isNotEmpty)
        ('Note', draft.description!.trim()),
    ];

    return GlassCard(
      key: const Key('$_k.reviewCard'),
      title: 'Check before you confirm',
      icon: Icons.fact_check_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (label, value) in rows) _Row(label: label, value: value),
          if (error != null) ...[
            const SizedBox(height: 12),
            ErrorBanner(key: const Key('$_k.error'), message: error),
          ],
          if (_outcomeUnknown) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('$_k.checkHistory'),
                onPressed: _loadHistory,
                icon: const Icon(Icons.history),
                label: const Text('Refresh the history'),
              ),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton(
                key: const Key('$_k.back'),
                onPressed: _sending || _outcomeUnknown ? null : _backToForm,
                child: const Text('Back'),
              ),
              const SizedBox(width: 12),
              GradientButton(
                key: const Key('$_k.confirm'),
                onPressed: _sending ? null : _confirm,
                child: _sending
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
                          const Text('Sending…'),
                        ],
                      )
                    : Text(error == null
                        ? 'Confirm ${draft.kind.label.toLowerCase()}'
                        : 'Try again'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _doneCard(BuildContext context) {
    final record = _result!;
    final draft = _draft!;
    final error = _printError;

    return GlassCard(
      key: const Key('$_k.done'),
      title: '${draft.kind.label} recorded',
      icon: Icons.check_circle_outline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: StatusPill(label: 'Recorded', tone: StatusTone.success),
          ),
          const SizedBox(height: 12),
          for (final (label, value) in _receipt(record, draft).rows)
            _Row(label: label, value: value),
          const SizedBox(height: 4),
          Text(
            'The member gets an SMS with the details.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            ErrorBanner(key: const Key('$_k.printError'), message: error),
          ],
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton.icon(
                key: const Key('$_k.print'),
                onPressed: _printing ? null : _print,
                icon: const Icon(Icons.print_outlined),
                label: Text(_printing ? 'Preparing…' : 'Print receipt'),
              ),
              const SizedBox(width: 12),
              GradientButton(
                key: const Key('$_k.new'),
                onPressed: _newTransaction,
                child: const Text('New transaction'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AmountLine extends StatelessWidget {
  const _AmountLine({
    required this.label,
    required this.money,
    this.quiet = false,
  });

  final String label;
  final Money money;
  final bool quiet;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final style = (quiet ? textTheme.bodyMedium : textTheme.titleMedium)
        ?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
      color: quiet ? scheme.onSurfaceVariant : scheme.onSurface,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          Text(money.toString(), style: style),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

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
            width: 180,
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
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
