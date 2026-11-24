import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_exception.dart';
import '../members/member_api.dart';
import '../members/member_status_style.dart';

/// The left side's search (owner decision 24 November 2026): one box for an
/// account number, a name or a phone number, through the backend's member
/// search, which matches part of a name, part of a phone number or an
/// exact account number. Each result lists the member's accounts to pick.
class AccountFinder extends StatefulWidget {
  const AccountFinder({
    super.key,
    required this.api,
    required this.onPick,
    this.debounce = const Duration(milliseconds: 400),
  });

  final MemberApi api;

  /// Called with the member and the account number chosen.
  final void Function(MemberSummary member, String accountNumber) onPick;
  final Duration debounce;

  @override
  State<AccountFinder> createState() => _AccountFinderState();
}

class _AccountFinderState extends State<AccountFinder> {
  final _query = TextEditingController();
  Timer? _timer;
  int _searchNumber = 0;

  String _searched = '';
  List<MemberSummary> _results = const [];
  bool _loading = false;
  Object? _error;

  @override
  void dispose() {
    _timer?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _changed(String text) {
    _timer?.cancel();
    final query = text.trim();
    if (query.length < MemberApi.minQueryLength) {
      _searchNumber++;
      setState(() {
        _searched = '';
        _results = const [];
        _loading = false;
        _error = null;
      });
      return;
    }
    _timer = Timer(widget.debounce, () => _search(query));
  }

  Future<void> _search(String query) async {
    final number = ++_searchNumber;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.api.searchMembers(query);
      if (!mounted || number != _searchNumber) return;
      setState(() {
        _searched = query;
        _results = page.items;
      });
    } catch (error) {
      if (!mounted || number != _searchNumber) return;
      setState(() {
        _searched = query;
        _results = const [];
        _error = error;
      });
    } finally {
      if (mounted && number == _searchNumber) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final error = _error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('tx.search'),
          controller: _query,
          autofocus: true,
          onChanged: _changed,
          onSubmitted: (text) {
            final query = text.trim();
            if (query.length < MemberApi.minQueryLength) return;
            _timer?.cancel();
            _search(query);
          },
          decoration: InputDecoration(
            labelText: 'Find an account',
            hintText: 'Account number, name or phone',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _loading
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Semantics(
            liveRegion: true,
            child: Builder(builder: (context) {
              if (error != null) {
                return Column(
                  key: const Key('tx.searchError'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      error is ApiException
                          ? commonFailureMessage(error, action: 'search members')
                          : 'Something went wrong. Try again.',
                      style: textTheme.bodyMedium?.copyWith(color: scheme.error),
                    ),
                    TextButton.icon(
                      onPressed: () => _search(_searched),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try again'),
                    ),
                  ],
                );
              }
              if (_searched.isEmpty) {
                return Text(
                  'Type an account number, or at least '
                  '${MemberApi.minQueryLength} characters of a name or '
                  'phone number.',
                  style: textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                );
              }
              if (_results.isEmpty) {
                return Text(
                  'No members match "$_searched".',
                  key: const Key('tx.noResults'),
                  style: textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                );
              }
              return ListView(
                children: [
                  for (final member in _results)
                    _MemberAccounts(
                      member: member,
                      onPick: (number) => widget.onPick(member, number),
                    ),
                ],
              );
            }),
          ),
        ),
      ],
    );
  }
}

class _MemberAccounts extends StatelessWidget {
  const _MemberAccounts({required this.member, required this.onPick});

  final MemberSummary member;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final status = member.status;
    final details = [member.phoneNumber, member.branchName]
        .whereType<String>()
        .join(' · ');

    return Card(
      key: Key('tx.result.${member.memberId}'),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(member.fullName, style: textTheme.titleSmall),
                      if (details.isNotEmpty)
                        Text(
                          details,
                          style: textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
                if (status != null) membershipPill(status),
              ],
            ),
            const SizedBox(height: 4),
            if (member.accounts.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text('No accounts yet.', style: textTheme.bodySmall),
              ),
            for (final account in member.accounts)
              ListTile(
                key: Key('tx.account.${account.accountNumber}'),
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: const Icon(Icons.account_balance_wallet_outlined),
                title: Text(
                  '${account.typeLabel} ${account.accountNumber}',
                  style: const TextStyle(
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                trailing: account.status == null
                    ? null
                    : accountPill(account.status!),
                onTap: () => onPick(account.accountNumber),
              ),
          ],
        ),
      ),
    );
  }
}
