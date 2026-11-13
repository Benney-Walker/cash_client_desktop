import 'package:cash_client_desktop/auth/session_manager.dart';
import 'package:cash_client_desktop/main.dart';
import 'package:cash_client_desktop/settings/theme_controller.dart';
import 'package:cash_client_desktop/shell/sidebar_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  late SessionManager sessions;
  late ThemeController theme;

  Future<void> pumpApp(
    WidgetTester tester, {
    ThemeMode? saved,
    List<String> roles = const ['ADMINISTRATOR'],
    int loginStatus = 200,
  }) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    theme = ThemeController(MemoryThemeModeStore(saved));
    await theme.load();
    final sidebar = SidebarController(MemorySidebarStateStore());
    await sidebar.load();
    sessions = SessionManager(
      api: fakeAuthApi(
        loginStatus,
        loginStatus == 200
            ? loginBody(roles: roles)
            : errorBody(loginStatus, 'Invalid ID or password'),
      ),
    );
    await tester.pumpWidget(
      CashClientApp(
        sessions: sessions,
        theme: theme,
        sidebar: sidebar,
        appInfo: testAppInfo,
      ),
    );
  }

  Future<void> signIn(WidgetTester tester) async {
    await tester.enterText(find.byKey(const Key('login.staffId')), 'STF0012');
    await tester.enterText(find.byKey(const Key('login.password')), 'secret');
    await tester.tap(find.byKey(const Key('login.signIn')));
    await tester.pumpAndSettle();
  }

  MaterialApp app(WidgetTester tester) =>
      tester.widget(find.byType(MaterialApp));

  testWidgets('opens on the sign-in screen with the saved theme mode',
      (tester) async {
    await pumpApp(tester, saved: ThemeMode.dark);

    expect(app(tester).title, 'Cash Client');
    expect(app(tester).themeMode, ThemeMode.dark);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.byKey(const Key('shell.sidebar')), findsNothing);
  });

  testWidgets('signing in opens the app', (tester) async {
    await pumpApp(tester);

    await signIn(tester);

    expect(find.byKey(const Key('shell.sidebar')), findsOneWidget);
    expect(find.byKey(const Key('page.dashboard')), findsOneWidget);
  });

  testWidgets('a wrong password stays on the sign-in screen', (tester) async {
    await pumpApp(tester, loginStatus: 401);

    await signIn(tester);

    expect(find.text('Wrong staff ID or password.'), findsOneWidget);
    expect(find.byKey(const Key('shell.sidebar')), findsNothing);
  });

  testWidgets('a collector is told the app is for office staff',
      (tester) async {
    await pumpApp(tester, roles: ['COLLECTOR']);

    await signIn(tester);

    expect(
      find.textContaining('This app is for administrators and agents'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('shell.sidebar')), findsNothing);
  });

  testWidgets('signing out from Settings returns to sign-in', (tester) async {
    await pumpApp(tester);
    await signIn(tester);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings.signOut')));
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
    expect(sessions.session, isNull);
    // Signing out yourself isn't "your session has ended".
    expect(find.byKey(const Key('login.notice')), findsNothing);
  });

  testWidgets('when the backend ends the session, sign-in explains why',
      (tester) async {
    await pumpApp(tester);
    await signIn(tester);

    sessions.endSession();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('login.notice')), findsOneWidget);
    expect(find.textContaining('session has ended'), findsOneWidget);
  });

  testWidgets('changing the theme in settings applies to the whole app',
      (tester) async {
    await pumpApp(tester);
    await signIn(tester);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    expect(app(tester).themeMode, ThemeMode.dark);
  });
}
