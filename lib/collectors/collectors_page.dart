import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../common/branch_chip.dart';
import '../common/dates.dart';
import '../common/glass_card.dart';
import '../common/gradient_backdrop.dart';
import '../common/money.dart';
import '../common/step_flow.dart';
import '../config/app_config.dart';
import '../staff/staff_api.dart';
import '../staff/staff_models.dart';
import '../transactions/transaction_models.dart' show maskedAccount;
import 'collector_api.dart';

/// The Collectors section (option C1, owner decisions 24 November 2026):
/// collectors on the left with their payments for the chosen day; on the
/// right that collector's day on a map (the route, with payments pinned on
/// it) above a timeline.
///
/// Any day in the last 90 days, the backend's retention. Release phone
/// stays on the Staff page (owner decision). Agents see their own branch's
/// collectors, Administrators every branch's (the backend decides).
class CollectorsPage extends StatefulWidget {
  const CollectorsPage({
    super.key,
    required this.api,
    required this.staffApi,
    this.scopeBranch,
    this.showTiles = true,
    this.now = DateTime.now,
  });

  final CollectorApi api;
  final StaffApi staffApi;

  /// An Agent's branch, for the "… branch only" chip (option B2).
  final String? scopeBranch;

  /// Off in tests, so no map tiles are downloaded.
  final bool showTiles;
  final DateTime Function() now;

  @override
  State<CollectorsPage> createState() => _CollectorsPageState();
}

class _CollectorsPageState extends State<CollectorsPage> {
  static const _k = 'collectors';

  late DateTime _date = _today;
  List<StaffMember> _collectors = const [];
  bool _loading = true;
  Object? _error;
  Map<String, CollectorDayTotal>? _totals;
  bool _totalsFailed = false;
  int _totalsRun = 0;
  String? _selectedId;

  DateTime get _today {
    final now = widget.now();
    return DateTime(now.year, now.month, now.day);
  }

  DateTime get _firstDay =>
      _today.subtract(const Duration(days: CollectorApi.keptDays - 1));

  @override
  void initState() {
    super.initState();
    _loadCollectors();
    _loadTotals();
  }

  Future<void> _loadCollectors() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final staff = await widget.staffApi.listStaff();
      if (!mounted) return;
      setState(() => _collectors = staff.where((s) => s.isCollector).toList());
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadTotals() async {
    final run = ++_totalsRun;
    setState(() {
      _totals = null;
      _totalsFailed = false;
    });
    try {
      final totals = await widget.api.dayTotals(_date);
      if (mounted && run == _totalsRun) setState(() => _totals = totals);
    } catch (_) {
      if (mounted && run == _totalsRun) setState(() => _totalsFailed = true);
    }
  }

  void _setDate(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    if (day == _date || day.isBefore(_firstDay) || day.isAfter(_today)) return;
    setState(() => _date = day);
    _loadTotals();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: _firstDay,
      lastDate: _today,
      initialDate: _date,
      helpText: "Collector's day",
    );
    if (picked != null) _setDate(picked);
  }

  String get _dateLabel {
    if (_date == _today) return 'Today';
    if (_date == _today.subtract(const Duration(days: 1))) return 'Yesterday';
    return isoDate(_date);
  }

  @override
  Widget build(BuildContext context) {
    StaffMember? selected;
    for (final c in _collectors) {
      if (c.staffId == _selectedId) selected = c;
    }
    final collector = selected;

    return Stack(
      key: const Key('page.collectors'),
      children: [
        const Positioned.fill(child: PageGlows()),
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 28, 32, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: PageTitle(
                      'Collectors',
                      scopeBranch: widget.scopeBranch,
                    ),
                  ),
                  _dateControls(),
                ],
              ),
              const SizedBox(height: 20),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 320, child: _list(context)),
                    const SizedBox(width: 24),
                    Expanded(
                      child: collector == null
                          ? Align(
                              alignment: Alignment.topLeft,
                              child: GlassCard(
                                key: const Key('$_k.nothingSelected'),
                                title: "Collector's day",
                                icon: Icons.route_outlined,
                                child: Text(
                                  'Choose a collector on the left to see '
                                  'their route and payments for the day.',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ),
                            )
                          : CollectorDayPane(
                              key: ValueKey(
                                  '${collector.staffId}-${isoDate(_date)}'),
                              api: widget.api,
                              collector: collector,
                              date: _date,
                              showTiles: widget.showTiles,
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

  Widget _dateControls() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: const Key('$_k.previousDay'),
          tooltip: 'Day before',
          onPressed: _date.isAfter(_firstDay)
              ? () => _setDate(_date.subtract(const Duration(days: 1)))
              : null,
          icon: const Icon(Icons.chevron_left),
        ),
        OutlinedButton.icon(
          key: const Key('$_k.date'),
          onPressed: _pickDate,
          icon: const Icon(Icons.calendar_today_outlined, size: 18),
          label: Text(_dateLabel),
        ),
        IconButton(
          key: const Key('$_k.nextDay'),
          tooltip: 'Day after',
          onPressed: _date.isBefore(_today)
              ? () => _setDate(_date.add(const Duration(days: 1)))
              : null,
          icon: const Icon(Icons.chevron_right),
        ),
        const SizedBox(width: 4),
        IconButton(
          key: const Key('$_k.refresh'),
          tooltip: 'Refresh',
          onPressed: () {
            _loadCollectors();
            _loadTotals();
          },
          icon: const Icon(Icons.refresh),
        ),
      ],
    );
  }

  String _subtitle(StaffMember c) {
    if (_totalsFailed) return "Day's payments couldn't be loaded";
    final totals = _totals;
    if (totals == null) return '…';
    final t = totals[c.staffId];
    if (t == null || t.payments == 0) return 'No payments';
    return '${t.payments == 1 ? '1 payment' : '${t.payments} payments'} · '
        '${t.amount}';
  }

  Widget _list(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final error = _error;

    if (_collectors.isEmpty && _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null && _collectors.isEmpty) {
      return Column(
        key: const Key('$_k.listError'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            staffActionErrorMessage(error),
            style: textTheme.bodyMedium?.copyWith(color: scheme.error),
          ),
          TextButton.icon(
            onPressed: _loadCollectors,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ],
      );
    }
    if (_collectors.isEmpty) {
      return Text(
        'No collectors yet.',
        key: const Key('$_k.empty'),
        style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      );
    }
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 4),
          child: Text(
            _collectors.length == 1
                ? '1 collector'
                : '${_collectors.length} collectors',
            style:
                textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
        for (final c in _collectors)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: ListTile(
              key: Key('$_k.item.${c.staffId}'),
              selected: c.staffId == _selectedId,
              selectedTileColor: scheme.primaryContainer,
              selectedColor: scheme.onPrimaryContainer,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              title: Text(c.fullName),
              subtitle: Text(
                _subtitle(c),
                key: Key('$_k.total.${c.staffId}'),
              ),
              trailing: c.isActive
                  ? null
                  : const StatusPill(label: 'Inactive', tone: StatusTone.neutral),
              onTap: () => setState(() => _selectedId = c.staffId),
            ),
          ),
      ],
    );
  }
}

/// One collector's day: a summary, the map and the timeline. Give it a key
/// per collector and date so it starts fresh.
class CollectorDayPane extends StatefulWidget {
  const CollectorDayPane({
    super.key,
    required this.api,
    required this.collector,
    required this.date,
    this.showTiles = true,
  });

  final CollectorApi api;
  final StaffMember collector;
  final DateTime date;
  final bool showTiles;

  @override
  State<CollectorDayPane> createState() => _CollectorDayPaneState();
}

class _CollectorDayPaneState extends State<CollectorDayPane> {
  static const _k = 'collectorDay';

  List<LocationPoint>? _points;
  Object? _error;
  bool _showAll = false;

  /// The highlighted point, by its index in [_points].
  int? _selected;
  final _map = MapController();
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final points = await widget.api.trail(widget.collector.staffId, widget.date);
      if (mounted) setState(() => _points = points);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  void _select(int index) {
    setState(() => _selected = index);
    final p = _points![index];
    if (_mapReady) {
      _map.move(LatLng(p.latitude, p.longitude), _map.camera.zoom);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final points = _points;
    final error = _error;

    final header = Text(
      widget.collector.fullName,
      key: const Key('$_k.name'),
      style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
    );

    if (points == null && error == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          const SizedBox(height: 40),
          const Center(child: CircularProgressIndicator()),
        ],
      );
    }
    if (points == null) {
      return Column(
        key: const Key('$_k.error'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          const SizedBox(height: 12),
          ErrorBanner(
            message: collectorErrorMessage(error!),
            actionLabel: 'Try again',
            onAction: _load,
          ),
        ],
      );
    }

    if (points.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          const SizedBox(height: 12),
          InfoNote(
            key: const Key('$_k.noPoints'),
            text: 'No locations were recorded on this day. The collector '
                "didn't work, or their phone didn't send its position.",
          ),
        ],
      );
    }

    final payments = [
      for (final p in points)
        if (p.payment != null && !p.payment!.failed) p.payment!,
    ];
    final total = payments.fold<Money>(Money.zero, (sum, p) => sum + p.amount);
    final battery = points.last.batteryPercent;

    return ListView(
      key: const Key('$_k.view'),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        header,
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _chip(
              Icons.payments_outlined,
              payments.length == 1
                  ? '1 payment · $total'
                  : '${payments.length} payments · $total',
              const Key('$_k.summary'),
            ),
            _chip(
              Icons.schedule,
              '${clockTime(points.first.recordedAt)} to '
                  '${clockTime(points.last.recordedAt)}',
              const Key('$_k.hours'),
            ),
            if (battery != null)
              _chip(
                Icons.battery_std_outlined,
                'Battery $battery% at the last point',
                const Key('$_k.battery'),
              ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(height: 380, child: _mapCard(points)),
        const SizedBox(height: 16),
        _timeline(context, points),
      ],
    );
  }

  Widget _chip(IconData icon, String text, Key key) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(text, style: Theme.of(context).textTheme.labelLarge),
        ],
      ),
    );
  }

  Widget _mapCard(List<LocationPoint> points) {
    final scheme = Theme.of(context).colorScheme;
    final route = [for (final p in points) LatLng(p.latitude, p.longitude)];
    final single = route.toSet().length == 1;

    final markers = <Marker>[];
    var number = 0;
    for (final (i, p) in points.indexed) {
      final isPayment = p.atPayment;
      if (isPayment) number++;
      final first = i == 0, last = i == points.length - 1;
      if (!isPayment && !first && !last && i != _selected) continue;
      final selected = i == _selected;
      final size = selected ? 34.0 : 26.0;
      final Color color;
      final String label;
      if (isPayment) {
        color = p.payment?.failed == true ? scheme.error : const Color(0xFF0F766E);
        label = '$number';
      } else {
        color = scheme.primary;
        label = first ? 'S' : last ? 'E' : '•';
      }
      markers.add(Marker(
        point: route[i],
        width: size,
        height: size,
        child: GestureDetector(
          key: Key('$_k.marker.$i'),
          onTap: () => _select(i),
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white,
                width: selected ? 3 : 2,
              ),
            ),
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ));
    }

    return ClipRRect(
      key: const Key('$_k.map'),
      borderRadius: BorderRadius.circular(16),
      child: FlutterMap(
        mapController: _map,
        options: MapOptions(
          initialCenter: route.first,
          initialZoom: 16,
          initialCameraFit: single
              ? null
              : CameraFit.bounds(
                  bounds: LatLngBounds.fromPoints(route),
                  padding: const EdgeInsets.all(40),
                  maxZoom: 17,
                ),
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
          ),
          onMapReady: () => _mapReady = true,
        ),
        children: [
          if (widget.showTiles)
            TileLayer(
              urlTemplate: AppConfig.mapTileUrl,
              userAgentPackageName: AppConfig.mapUserAgentPackage,
            ),
          PolylineLayer(
            polylines: [
              Polyline(points: route, strokeWidth: 4, color: scheme.primary),
            ],
          ),
          MarkerLayer(markers: markers),
          const SimpleAttributionWidget(
            source: Text(AppConfig.mapAttribution),
          ),
        ],
      ),
    );
  }

  Widget _timeline(BuildContext context, List<LocationPoint> points) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    var number = 0;
    final rows = <Widget>[];
    for (final (i, p) in points.indexed) {
      if (p.atPayment) number++;
      final first = i == 0, last = i == points.length - 1;
      if (!_showAll && !p.atPayment && !first && !last) continue;

      final payment = p.payment;
      final String title;
      final List<String> details = [];
      if (p.atPayment && payment != null) {
        title = '$number. ${payment.typeLabel} ${payment.amount}';
        details.addAll([
          if (payment.memberName != null) payment.memberName!,
          if (payment.accountNumber != null) maskedAccount(payment.accountNumber!),
          if (payment.failed) 'Failed',
        ]);
      } else if (p.atPayment) {
        title = '$number. Payment';
        details.add("The payment hasn't reached the server yet");
      } else {
        title = first
            ? 'First position'
            : last
                ? 'Last position'
                : 'Position';
      }
      details.addAll([
        if (p.accuracyMeters != null) '±${p.accuracyMeters!.round()} m',
        if (p.batteryPercent != null) 'battery ${p.batteryPercent}%',
        if (p.sentLater) 'sent later (offline)',
      ]);

      rows.add(ListTile(
        key: Key('$_k.row.$i'),
        dense: true,
        selected: i == _selected,
        selectedTileColor: scheme.primaryContainer,
        selectedColor: scheme.onPrimaryContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        leading: SizedBox(
          width: 48,
          child: Text(
            clockTime(p.recordedAt),
            style: textTheme.titleSmall?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        title: Text(
          title,
          style: payment?.failed == true
              ? const TextStyle(decoration: TextDecoration.lineThrough)
              : null,
        ),
        subtitle: details.isEmpty ? null : Text(details.join(' · ')),
        onTap: () => _select(i),
      ));
    }

    return GlassCard(
      key: const Key('$_k.timeline'),
      title: 'Timeline',
      icon: Icons.timeline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            key: const Key('$_k.showAll'),
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Show every position (every 5 minutes)',
              style: textTheme.bodyMedium,
            ),
            value: _showAll,
            onChanged: (v) => setState(() => _showAll = v),
          ),
          ...rows,
        ],
      ),
    );
  }
}
