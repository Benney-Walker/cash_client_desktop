import 'package:flutter/material.dart';

import '../common/glass_card.dart';
import 'approval_api.dart';

/// What a review pane calls once its item is approved or rejected, with
/// the line to show above the list.
typedef OnReviewed = void Function(String message);

/// One review queue (option K2): a status picker and the paged list on the
/// left, the chosen item's review pane on the right. Shared by the ID
/// documents and Member updates tabs.
///
/// After a review the item leaves the list (its status changed) and the next
/// one opens, so a queue can be worked through in order.
class ReviewQueue<S, T> extends StatefulWidget {
  const ReviewQueue({
    super.key,
    required this.keyPrefix,
    required this.statuses,
    required this.statusLabel,
    required this.statusKey,
    required this.load,
    required this.idOf,
    required this.titleOf,
    required this.subtitleOf,
    required this.pane,
    required this.emptyText,
    required this.nothingSelected,
    required this.nothingSelectedIcon,
    this.onWaitingCount,
  });

  /// Test keys: `<keyPrefix>.item.<id>`, `.status`, `.more`, `.done`, …
  final String keyPrefix;

  /// The first is the waiting status, shown first and counted.
  final List<S> statuses;
  final String Function(S status) statusLabel;

  /// A short name for test keys: `<keyPrefix>.tab.<statusKey>`.
  final String Function(S status) statusKey;
  final Future<PagedResult<T>> Function(S status, int page) load;
  final String Function(T item) idOf;
  final String Function(T item) titleOf;
  final String Function(T item) subtitleOf;
  final Widget Function(T item, OnReviewed onReviewed) pane;
  final String Function(S status) emptyText;
  final String nothingSelected;
  final IconData nothingSelectedIcon;

  /// The number waiting, each time the waiting list loads or shrinks.
  final ValueChanged<int>? onWaitingCount;

  @override
  State<ReviewQueue<S, T>> createState() => _ReviewQueueState<S, T>();
}

class _ReviewQueueState<S, T> extends State<ReviewQueue<S, T>> {
  late S _status = widget.statuses.first;
  List<T> _items = const [];
  int _page = 0;
  bool _hasMore = false;
  int _total = 0;
  bool _loading = false;
  bool _loadingMore = false;
  Object? _error;
  int _loadNumber = 0;
  String? _selectedId;
  String? _done;

  String get _k => widget.keyPrefix;
  bool get _onWaiting => _status == widget.statuses.first;

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
      final page = await widget.load(status, 0);
      if (!mounted || number != _loadNumber) return;
      setState(() {
        _items = page.items;
        _page = page.number;
        _hasMore = page.hasMore;
        _total = page.totalElements;
        if (!_items.any((i) => widget.idOf(i) == _selectedId)) {
          _selectedId = null;
        }
      });
      if (_onWaiting) widget.onWaitingCount?.call(_total);
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
      final page = await widget.load(_status, _page + 1);
      if (!mounted || number != _loadNumber) return;
      final known = {for (final i in _items) widget.idOf(i)};
      setState(() {
        // An item reviewed since the last page shifts the pages by one, so
        // skip any already listed.
        _items = [
          ..._items,
          ...page.items.where((i) => !known.contains(widget.idOf(i))),
        ];
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

  void _switch(S status) {
    if (status == _status) return;
    setState(() {
      _status = status;
      _items = const [];
      _selectedId = null;
      _done = null;
    });
    _load();
  }

  void _reviewed(String id, String message) {
    final index = _items.indexWhere((i) => widget.idOf(i) == id);
    if (index < 0) return;
    final rest = [..._items]..removeAt(index);
    setState(() {
      _items = rest;
      _total = _total > 0 ? _total - 1 : 0;
      _done = message;
      _selectedId = rest.isEmpty
          ? null
          : widget.idOf(rest[index < rest.length ? index : rest.length - 1]);
    });
    if (_onWaiting) widget.onWaitingCount?.call(_total);
  }

  @override
  Widget build(BuildContext context) {
    T? selected;
    for (final item in _items) {
      if (widget.idOf(item) == _selectedId) selected = item;
    }
    final item = selected;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 340, child: _list(context)),
        const SizedBox(width: 24),
        Expanded(
          child: item == null
              ? Align(
                  alignment: Alignment.topLeft,
                  child: GlassCard(
                    key: Key('$_k.nothingSelected'),
                    title: 'Review',
                    icon: widget.nothingSelectedIcon,
                    child: Text(
                      widget.nothingSelected,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                )
              : KeyedSubtree(
                  key: ValueKey('${widget.idOf(item)}-$_status'),
                  child: widget.pane(
                    item,
                    (message) => _reviewed(widget.idOf(item), message),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _statusPicker() {
    if (widget.statuses.length <= 3) {
      return SegmentedButton<S>(
        key: Key('$_k.status'),
        segments: [
          for (final s in widget.statuses)
            ButtonSegment(
              value: s,
              label: Text(widget.statusLabel(s), key: Key('$_k.tab.${widget.statusKey(s)}')),
            ),
        ],
        selected: {_status},
        showSelectedIcon: false,
        onSelectionChanged: (s) => _switch(s.single),
      );
    }
    return DropdownButtonFormField<S>(
      key: Key('$_k.status'),
      initialValue: _status,
      decoration: const InputDecoration(labelText: 'Show', isDense: true),
      items: [
        for (final s in widget.statuses)
          DropdownMenuItem(value: s, child: Text(widget.statusLabel(s))),
      ],
      onChanged: (s) {
        if (s != null) _switch(s);
      },
    );
  }

  Widget _list(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final error = _error;
    final done = _done;

    Widget body;
    if (_items.isEmpty && _loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (error != null && _items.isEmpty) {
      body = Column(
        key: Key('$_k.listError'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            approvalErrorMessage(error),
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
        widget.emptyText(_status),
        key: Key('$_k.empty'),
        style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      );
    } else {
      body = ListView(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Text(
              _total == 1 ? '1 item' : '$_total items',
              key: Key('$_k.count'),
              style: textTheme.labelMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          for (final item in _items)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: ListTile(
                key: Key('$_k.item.${widget.idOf(item)}'),
                selected: widget.idOf(item) == _selectedId,
                selectedTileColor: scheme.primaryContainer,
                selectedColor: scheme.onPrimaryContainer,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                title: Text(widget.titleOf(item)),
                subtitle: Text(widget.subtitleOf(item)),
                onTap: () => setState(() {
                  _selectedId = widget.idOf(item);
                  _done = null;
                }),
              ),
            ),
          if (_hasMore)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: Key('$_k.more'),
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
            Expanded(child: _statusPicker()),
            const SizedBox(width: 8),
            IconButton(
              key: Key('$_k.refresh'),
              tooltip: 'Refresh',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        if (done != null) ...[
          const SizedBox(height: 12),
          Row(
            key: Key('$_k.done'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.check_circle_outline, color: scheme.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(done, style: textTheme.bodyMedium)),
            ],
          ),
        ],
        const SizedBox(height: 12),
        Expanded(child: body),
      ],
    );
  }
}
