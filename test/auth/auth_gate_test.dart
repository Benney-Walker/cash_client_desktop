import 'package:cash_client_desktop/auth/auth_gate.dart';
import 'package:cash_client_desktop/auth/session_manager.dart';
import 'package:cash_client_desktop/settings/theme_controller.dart';
import 'package:cash_client_desktop/shell/sidebar_controller.dart';
import 'package:cash_client_desktop/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  late List<Uri> opened;

  Future<void> pumpGate(
    WidgetTester tester, {
    String baseUrl = testBaseUrl,
    bool browserOpens = true,
  }) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    opened = [];
    final theme = ThemeController(MemoryThemeModeStore());
    await theme.load();
    final sidebar = SidebarController(MemorySidebarStateStore());
    await sidebar.load();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: AuthGate(
        sessions: SessionManager(api: fakeAuthApi(200, loginBody())),
        apis: fakeApis(),
        theme: theme,
        sidebar: sidebar,
        appInfo: testAppInfo,
        baseUrl: baseUrl,
        openInBrowser: (uri) async {
          opened.add(uri);
          return browserOpens;
        },
      ),
    ));
    await tester.pumpAndSettle();
  }

  final link = find.byKey(const Key('login.forgotPassword'));

  testWidgets('Forgot password? opens the reset page with the staff ID',
      (tester) async {
    await pumpGate(tester);
    await tester.enterText(find.byKey(const Key('login.staffId')), 'STF0012');

    await tester.tap(link);
    await tester.pumpAndSettle();

    expect(opened.single.toString(),
        '$testBaseUrl/password-reset?staffId=STF0012');
    expect(find.byKey(const Key('login.error')), findsNothing);
  });

  testWidgets('when no browser opens, the address is shown to type in',
      (tester) async {
    await pumpGate(tester, browserOpens: false);

    await tester.tap(link);
    await tester.pumpAndSettle();

    expect(find.textContaining('$testBaseUrl/password-reset'), findsOneWidget);
  });

  testWidgets('a build without a server address says so', (tester) async {
    await pumpGate(tester, baseUrl: '');

    await tester.tap(link);
    await tester.pumpAndSettle();

    expect(opened, isEmpty);
    expect(find.textContaining('no server address'), findsOneWidget);
  });
}
