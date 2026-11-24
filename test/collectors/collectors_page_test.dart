import 'package:cash_client_desktop/collectors/collector_api.dart';
import 'package:cash_client_desktop/collectors/collectors_page.dart';
import 'package:cash_client_desktop/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  late FakeCollectorBackend backend;
  final now = DateTime(2026, 11, 25, 18);

  Future<void> pumpPage(
    WidgetTester tester, {
    FakeCollectorBackend? collectors,
    String? scopeBranch,
  }) async {
    tester.view.physicalSize = const Size(1400, 1300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    backend = collectors ?? FakeCollectorBackend();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: CollectorsPage(
          api: backend.api,
          staffApi: FakeStaffBackend().api,
          scopeBranch: scopeBranch,
          showTiles: false,
          now: () => now,
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Finder key(String name) => find.byKey(Key(name));

  Future<void> open(WidgetTester tester, String staffId) async {
    await tester.tap(key('collectors.item.$staffId'));
    await tester.pumpAndSettle();
  }

  testWidgets('lists only collectors, with their payments for the day',
      (tester) async {
    await pumpPage(tester);

    expect(key('collectors.item.STF0031'), findsOneWidget);
    expect(key('collectors.item.STF0044'), findsOneWidget);
    expect(key('collectors.item.STF0020'), findsNothing); // an agent
    expect(find.text('2 collectors'), findsOneWidget);
    expect(find.text('12 payments · GH₵ 1,250.00'), findsOneWidget);
    expect(find.text('No payments'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    final report = backend.requests
        .firstWhere((r) => r.url.path.endsWith(CollectorApi.collectionsReportPath));
    expect(report.url.queryParameters, {'from': '2026-11-25', 'to': '2026-11-25'});
  });

  testWidgets("a collector's day shows the summary, map and payments",
      (tester) async {
    await pumpPage(tester);
    await open(tester, 'STF0031');

    expect(backend.trailDates, ['STF0031 2026-11-25']);
    // Two payments reached the server; one failed, so one counts.
    expect(find.text('1 payment · GH₵ 100.00'), findsOneWidget);
    expect(find.text('08:05 to 17:30'), findsOneWidget);
    expect(find.text('Battery 41% at the last point'), findsOneWidget);
    expect(key('collectorDay.map'), findsOneWidget);
    expect(find.text('© OpenStreetMap contributors'), findsOneWidget);

    // Payments, plus the first and last positions.
    expect(key('collectorDay.row.0'), findsOneWidget);
    expect(key('collectorDay.row.1'), findsNothing);
    expect(find.text('1. Deposit GH₵ 100.00'), findsOneWidget);
    expect(find.textContaining('Ama Owusu · •••• 7891'), findsOneWidget);
    expect(find.text('2. Deposit GH₵ 50.00'), findsOneWidget);
    expect(find.textContaining('Failed'), findsOneWidget);
    expect(find.text('3. Payment'), findsOneWidget);
    expect(find.textContaining("hasn't reached the server"), findsOneWidget);
    expect(find.textContaining('sent later (offline)'), findsOneWidget);
    expect(find.text('Last position'), findsOneWidget);

    // Pins: start, three payments, end.
    for (final i in [0, 2, 4, 5, 6]) {
      expect(key('collectorDay.marker.$i'), findsOneWidget, reason: '$i');
    }
    expect(key('collectorDay.marker.1'), findsNothing);
  });

  testWidgets('every position can be shown', (tester) async {
    await pumpPage(tester);
    await open(tester, 'STF0031');

    await tester.ensureVisible(key('collectorDay.showAll'));
    await tester.tap(key('collectorDay.showAll'));
    await tester.pumpAndSettle();

    for (var i = 0; i < 7; i++) {
      expect(key('collectorDay.row.$i'), findsOneWidget, reason: '$i');
    }
  });

  testWidgets('choosing a timeline row highlights its pin', (tester) async {
    await pumpPage(tester);
    await open(tester, 'STF0031');

    await tester.ensureVisible(key('collectorDay.row.2'));
    await tester.tap(key('collectorDay.row.2'));
    await tester.pumpAndSettle();

    expect(tester.widget<ListTile>(key('collectorDay.row.2')).selected, isTrue);
  });

  testWidgets('a day without points says so', (tester) async {
    await pumpPage(tester);
    await open(tester, 'STF0044');

    expect(key('collectorDay.noPoints'), findsOneWidget);
    expect(key('collectorDay.map'), findsNothing);
  });

  testWidgets('earlier days, back to 90 days, but not the future',
      (tester) async {
    await pumpPage(tester);
    await open(tester, 'STF0031');

    expect(tester.widget<IconButton>(key('collectors.nextDay')).onPressed,
        isNull);

    await tester.tap(key('collectors.previousDay'));
    await tester.pumpAndSettle();

    expect(find.text('Yesterday'), findsOneWidget);
    expect(backend.trailDates.last, 'STF0031 2026-11-24');
    final report = backend.requests
        .lastWhere((r) => r.url.path.endsWith(CollectorApi.collectionsReportPath));
    expect(report.url.queryParameters['from'], '2026-11-24');
    expect(tester.widget<IconButton>(key('collectors.nextDay')).onPressed,
        isNotNull);
  });

  testWidgets('a refused day is explained and can be retried',
      (tester) async {
    final refusing = FakeCollectorBackend()..trailStatus = 403;
    await pumpPage(tester, collectors: refusing);
    await open(tester, 'STF0031');

    expect(key('collectorDay.error'), findsOneWidget);
    expect(find.textContaining('another branch'), findsOneWidget);

    refusing.trailStatus = 200;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(key('collectorDay.view'), findsOneWidget);
  });

  testWidgets("totals that fail don't block the list", (tester) async {
    final failing = FakeCollectorBackend()..reportStatus = 500;
    await pumpPage(tester, collectors: failing);

    expect(find.text("Day's payments couldn't be loaded"), findsNWidgets(2));
    await open(tester, 'STF0031');
    expect(key('collectorDay.view'), findsOneWidget);
  });

  testWidgets('Agents see their branch chip', (tester) async {
    await pumpPage(tester, scopeBranch: 'Tarkwa');

    expect(find.text('Tarkwa branch only'), findsOneWidget);
  });

  test('points read the backend shape', () {
    final p = LocationPoint.fromJson(
      pointJson('09:12', payment: true, paid: paidJson(100), receivedTime: '09:40'),
    )!;
    expect(p.atPayment, isTrue);
    expect(p.payment!.amount.pesewas, 10000);
    expect(p.payment!.typeLabel, 'Deposit');
    expect(p.recordedAt, DateTime(2026, 11, 25, 9, 12));
    expect(p.accuracyMeters, 12.4);
    expect(p.sentLater, isTrue);
    expect(LocationPoint.fromJson({'latitude': 1}), isNull);
  });
}
