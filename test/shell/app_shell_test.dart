import 'package:cash_client_desktop/settings/theme_controller.dart';
import 'package:cash_client_desktop/shell/app_section.dart';
import 'package:cash_client_desktop/shell/app_shell.dart';
import 'package:cash_client_desktop/shell/sidebar_controller.dart';
import 'package:cash_client_desktop/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  late MemorySidebarStateStore sidebarStore;

  Future<void> pumpShell(WidgetTester tester, {bool? savedExpanded}) async {
    // Roughly a small laptop screen, so the expanded sidebar and a page fit.
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    sidebarStore = MemorySidebarStateStore(expanded: savedExpanded);
    final sidebar = SidebarController(sidebarStore);
    await sidebar.load();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: AppShell(
          theme: ThemeController(MemoryThemeModeStore()),
          sidebar: sidebar,
          appInfo: testAppInfo,
        ),
      ),
    );
  }

  NavigationRail rail(WidgetTester tester) =>
      tester.widget(find.byKey(const Key('shell.sidebar')));

  testWidgets('opens on the dashboard with the sidebar expanded',
      (tester) async {
    await pumpShell(tester);

    expect(rail(tester).extended, isTrue);
    expect(rail(tester).selectedIndex, AppSection.dashboard.index);
    expect(find.byKey(const Key('page.dashboard')), findsOneWidget);
    expect(find.text('Cash Client'), findsOneWidget);
  });

  testWidgets('lists every section in order', (tester) async {
    await pumpShell(tester);

    final destinations = rail(tester).destinations;
    expect(destinations, hasLength(AppSection.values.length));
    for (final section in AppSection.values) {
      final label = destinations[section.index].label as Text;
      expect(label.data, section.label);
    }
  });

  testWidgets('selecting a section shows its page', (tester) async {
    await pumpShell(tester);

    await tester.tap(find.text('Members'));
    await tester.pumpAndSettle();

    expect(rail(tester).selectedIndex, AppSection.members.index);
    expect(find.byKey(const Key('page.members')), findsOneWidget);
    expect(find.byKey(const Key('page.dashboard')), findsNothing);
  });

  testWidgets('sections without screens say so', (tester) async {
    await pumpShell(tester);

    expect(find.text('Not built yet'), findsOneWidget);
  });

  testWidgets('settings opens the theme choice', (tester) async {
    await pumpShell(tester);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('settings.themeMode')), findsOneWidget);
  });

  testWidgets('the sidebar collapses to icons with tooltips and expands again',
      (tester) async {
    await pumpShell(tester);

    await tester.tap(find.byKey(const Key('shell.toggleSidebar')));
    await tester.pumpAndSettle();

    expect(rail(tester).extended, isFalse);
    expect(find.byTooltip('Members'), findsOneWidget);
    expect(find.byTooltip('Expand sidebar'), findsOneWidget);

    await tester.tap(find.byKey(const Key('shell.toggleSidebar')));
    await tester.pumpAndSettle();

    expect(rail(tester).extended, isTrue);
    expect(find.text('Cash Client'), findsOneWidget);
  });

  testWidgets('collapsing is saved for next time', (tester) async {
    await pumpShell(tester);

    await tester.tap(find.byKey(const Key('shell.toggleSidebar')));
    await tester.pumpAndSettle();

    expect(sidebarStore.expanded, isFalse);
  });

  testWidgets('opens collapsed when it was left collapsed', (tester) async {
    await pumpShell(tester, savedExpanded: false);

    expect(rail(tester).extended, isFalse);
  });

  testWidgets('settings shows the remember switch and About', (tester) async {
    await pumpShell(tester);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('settings.rememberSidebar')), findsOneWidget);
    expect(find.byKey(const Key('settings.about')), findsOneWidget);
  });
}
