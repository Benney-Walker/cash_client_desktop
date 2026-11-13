import 'dart:convert';

import 'package:cash_client_desktop/auth/auth_api.dart';
import 'package:cash_client_desktop/auth/inactivity_lock.dart';
import 'package:cash_client_desktop/auth/session_manager.dart';
import 'package:cash_client_desktop/main.dart';
import 'package:cash_client_desktop/settings/theme_controller.dart';
import 'package:cash_client_desktop/shell/sidebar_controller.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/fakes.dart';

void main() {
  late DateTime now;
  late InactivityLock lock;
  late SessionManager sessions;
  late List<String> loginStaffIds;
  late List<String> loginRoles;

  /// A backend whose password is "right"; anything else gets a 401.
  AuthApi backend() => AuthApi(
        baseUrl: testBaseUrl,
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          loginStaffIds.add(body['staffId'] as String);
          if (body['password'] != 'right') {
            return http.Response(errorBody(401, 'Invalid ID or password'), 401);
          }
          return http.Response(loginBody(roles: loginRoles), 200);
        }),
      );

  Future<void> pumpSignedIn(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    now = DateTime(2026, 11, 13, 9);
    loginStaffIds = [];
    loginRoles = ['ADMINISTRATOR'];
    lock = InactivityLock(now: () => now);
    sessions = SessionManager(api: backend());
    final theme = ThemeController(MemoryThemeModeStore());
    await theme.load();
    final sidebar = SidebarController(MemorySidebarStateStore());
    await sidebar.load();

    await tester.pumpWidget(
      CashClientApp(
        sessions: sessions,
        lock: lock,
        theme: theme,
        sidebar: sidebar,
        appInfo: testAppInfo,
      ),
    );
    await tester.enterText(find.byKey(const Key('login.staffId')), 'STF0012');
    await tester.enterText(find.byKey(const Key('login.password')), 'right');
    await tester.tap(find.byKey(const Key('login.signIn')));
    await tester.pumpAndSettle();
  }

  Future<void> goIdle(WidgetTester tester) async {
    now = now.add(const Duration(minutes: 20));
    lock.check();
    await tester.pumpAndSettle();
  }

  final lockScreen = find.byKey(const Key('lock.screen'));

  Future<void> unlockWith(WidgetTester tester, String password) async {
    await tester.enterText(find.byKey(const Key('lock.password')), password);
    await tester.tap(find.byKey(const Key('lock.unlock')));
    await tester.pumpAndSettle();
  }

  testWidgets('signing in starts the timer', (tester) async {
    await pumpSignedIn(tester);

    expect(lock.running, isTrue);
    expect(lockScreen, findsNothing);
  });

  testWidgets('after 20 idle minutes the lock card covers the app',
      (tester) async {
    await pumpSignedIn(tester);

    await goIdle(tester);

    expect(lockScreen, findsOneWidget);
    expect(find.text('Kofi Mensah'), findsOneWidget);
    expect(find.text('Administrator · STF0012'), findsOneWidget);
    expect(find.text('Locked after 20 minutes of inactivity'), findsOneWidget);
    // The app is still there underneath, dimmed.
    expect(find.byKey(const Key('shell.sidebar')), findsOneWidget);
  });

  testWidgets('the app underneath cannot be clicked while locked',
      (tester) async {
    await pumpSignedIn(tester);
    await goIdle(tester);

    await tester.tap(find.text('Settings'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('settings.account')), findsNothing);
  });

  testWidgets('mouse activity keeps the app unlocked', (tester) async {
    await pumpSignedIn(tester);

    now = now.add(const Duration(minutes: 15));
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: const Offset(600, 400));
    await gesture.moveTo(const Offset(620, 420));
    now = now.add(const Duration(minutes: 15));
    lock.check();
    await tester.pumpAndSettle();
    await gesture.removePointer();

    expect(lockScreen, findsNothing);
  });

  testWidgets('keyboard activity keeps the app unlocked', (tester) async {
    await pumpSignedIn(tester);

    now = now.add(const Duration(minutes: 15));
    await tester.sendKeyEvent(LogicalKeyboardKey.shiftLeft);
    now = now.add(const Duration(minutes: 15));
    lock.check();
    await tester.pumpAndSettle();

    expect(lockScreen, findsNothing);
  });

  testWidgets('a wrong password says so and stays locked', (tester) async {
    await pumpSignedIn(tester);
    await goIdle(tester);

    await unlockWith(tester, 'wrong');

    expect(find.text('Wrong password. Try again.'), findsOneWidget);
    expect(lockScreen, findsOneWidget);
  });

  testWidgets('the right password unlocks with the same staff ID',
      (tester) async {
    await pumpSignedIn(tester);
    await goIdle(tester);

    await unlockWith(tester, 'right');

    expect(lockScreen, findsNothing);
    expect(loginStaffIds.last, 'STF0012');
    expect(sessions.session, isNotNull);
  });

  testWidgets('an empty password is not sent', (tester) async {
    await pumpSignedIn(tester);
    await goIdle(tester);
    final before = loginStaffIds.length;

    await tester.tap(find.byKey(const Key('lock.unlock')));
    await tester.pumpAndSettle();

    expect(find.text('Enter your password'), findsOneWidget);
    expect(loginStaffIds, hasLength(before));
  });

  testWidgets('"Not you? Sign out" returns to the sign-in screen',
      (tester) async {
    await pumpSignedIn(tester);
    await goIdle(tester);

    await tester.tap(find.byKey(const Key('lock.signOut')));
    await tester.pumpAndSettle();

    expect(lockScreen, findsNothing);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(lock.running, isFalse);
  });

  testWidgets('if their office role was removed, unlocking signs them out',
      (tester) async {
    await pumpSignedIn(tester);
    await goIdle(tester);
    loginRoles = ['COLLECTOR'];

    await unlockWith(tester, 'right');

    expect(lockScreen, findsNothing);
    expect(sessions.session, isNull);
    expect(find.text('Welcome back'), findsOneWidget);
  });

  testWidgets('the lock covers open dialogs too', (tester) async {
    await pumpSignedIn(tester);
    var dialogTaps = 0;
    final context = tester.element(find.byKey(const Key('shell.sidebar')));
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        content: TextButton(
          onPressed: () => dialogTaps++,
          child: const Text('Dialog button'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await goIdle(tester);
    await tester.tap(find.text('Dialog button'), warnIfMissed: false);
    await tester.pump();

    // The lock is drawn above the navigator, so the dialog is behind it.
    expect(lockScreen, findsOneWidget);
    expect(dialogTaps, 0);
  });
}
