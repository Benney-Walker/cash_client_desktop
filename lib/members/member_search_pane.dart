import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_exception.dart';
import 'member_api.dart';
import 'member_status_style.dart';

/// The left side of the Members page (design P2): one search box for name,
/// phone number or account number, and the matching members.
class MemberSearchPane extends StatefulWidget {
  const MemberSearchPane({
    super.key,
    required this.api,
    required this.selectedId,
    required this.onSelect,
    this.debounce = const Duration(milliseconds: 400),
  });

  final MemberApi api;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  /// How long typing must pause before a search is sent.
  final Duration debounce;

  @override
  State<MemberSearchPane> createState() => _MemberSearchPaneState();
}

class _MemberSearchPaneState extends State<MemberSearchPane> {
  final _query = TextEditingController();
  Timer? _timer;

  /// Each search gets a number; an answer to an older one is ignored, so
  /// slow answers can't overwrite newer results.
  int _searchNumber = 0;

  String _searched = '';
  List<MemberSummary> _results = const [];
  int _total = 0;
  int _page = 0;
  bool _hasMore = false;
  bool _loading = false;
  bool _loadingMore = false;
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
        _total = 0;
        _hasMore = false;
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
        _total = page.totalElements;
        _page = page.number;
        _hasMore = page.hasMore;
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

  Future<void> _more() async {
    final number = _searchNumber;
    setState(() => _loadingMore = true);
    try {
      final page = await widget.api.searchMembers(_searched, page: _page + 1);
      if (!mounted || number != _searchNumber) return;
      setState(() {
        _results = [..._results, ...page.items];
        _total = page.totalElements;
        _page = page.number;
        _hasMore = page.hasMore;
      });
    } catch (error) {
      if (!mounted || number != _searchNumber) return;
      setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  String _errorMessage(Object error) {
    if (error is ApiException && error.failure == ApiFailure.notFound) {
      return "The server doesn't offer member search yet.";
    }
    if (error is ApiException) {
      return commonFailureMessage(error, action: 'search members');
    }
    return 'Something went wrong. Try again.';
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
          key: const Key('members.search'),
          controller: _query,
          autofocus: true,
          onChanged: _changed,
          textInputAction: TextInputAction.search,
          onSubmitted: (text) {
            final query = text.trim();
            if (query.length < MemberApi.minQueryLength) return;
            _timer?.cancel();
            _search(query);
          },
          decoration: InputDecoration(
            labelText: 'Find a member',
            hintText: 'Name, phone or account number',
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
            child: Builder(
              builder: (context) {
                if (error != null) {
                  return Column(
                    key: const Key('members.searchError'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _errorMessage(error),
                        style: textTheme.bodyMedium
                            ?.copyWith(color: scheme.error),
                      ),
                      TextButton.icon(
                        key: const Key('members.retrySearch'),
                        onPressed: () => _search(_searched),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Try again'),
                      ),
                    ],
                  );
                }
                if (_searched.isEmpty) {
                  return Text(
                    'Type at least ${MemberApi.minQueryLength} characters '
                    'of a name, phone number or account number.',
                    key: const Key('members.searchHint'),
                    style: textTheme.bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  );
                }
                if (_results.isEmpty) {
                  return Text(
                    'No members match "$_searched".',
                    key: const Key('members.noResults'),
                    style: textTheme.bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  );
                }
                return ListView(
                  key: const Key('members.results'),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4, left: 4),
                      child: Text(
                        _total == 1 ? '1 member' : '$_total members',
                        style: textTheme.labelMedium
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                    for (final member in _results)
                      _ResultTile(
                        member: member,
                        selected: member.memberId == widget.selectedId,
                        onTap: () => widget.onSelect(member.memberId),
                      ),
                    if (_hasMore)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          key: const Key('members.more'),
                          onPressed: _loadingMore ? null : _more,
                          child: Text(
                              _loadingMore ? 'Loading…' : 'Show more'),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({
    required this.member,
    required this.selected,
    required this.onTap,
  });

  final MemberSummary member;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = member.status;
    final details = [member.phoneNumber, member.branchName]
        .whereType<String>()
        .join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        key: Key('members.result.${member.memberId}'),
        selected: selected,
        selectedTileColor: scheme.primaryContainer,
        selectedColor: scheme.onPrimaryContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(member.fullName),
        subtitle: details.isEmpty ? null : Text(details),
        trailing: status == null ? null : membershipPill(status),
        onTap: onTap,
      ),
    );
  }
}
