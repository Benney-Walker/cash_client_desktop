import 'package:cash_client_desktop/main.dart';
import 'package:cash_client_desktop/settings/theme_controller.dart';
import 'package:cash_client_desktop/shell/sidebar_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  Future<ThemeController> pumpApp(
    WidgetTester tester, {
    ThemeMode? saved,
  }) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final theme = ThemeController(MemoryThemeModeStore(saved));
    await theme.load();
    final sidebar = SidebarController(MemorySidebarStateStore());
    await sidebar.load();
    await tester.pumpWidget(
      CashClientApp(theme: theme, sidebar: sidebar, appInfo: testAppInfo),
    );
    return theme;
  }

  MaterialApp app(WidgetTester tester) =>
      tester.widget(find.byType(MaterialApp));

  testWidgets('opens on the shell with the saved theme mode', (tester) async {
    await pumpApp(tester, saved: ThemeMode.dark);

    expect(app(tester).title, 'Cash Client');
    expect(app(tester).themeMode, ThemeMode.dark);
    expect(find.byKey(const Key('page.dashboard')), findsOneWidget);
  });

  testWidgets('changing the theme in settings applies to the whole app',
      (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    expect(app(tester).themeMode, ThemeMode.dark);
  });
}
