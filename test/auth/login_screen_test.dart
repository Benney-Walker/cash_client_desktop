import 'dart:async';

import 'package:cash_client_desktop/auth/login_screen.dart';
import 'package:cash_client_desktop/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  late List<(String, String)> attempts;
  late Completer<String?> result;

  Future<void> pumpLogin(
    WidgetTester tester, {
    ThemeData? theme,
    String? notice,
  }) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    attempts = [];
    result = Completer<String?>();
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? AppTheme.light,
        home: LoginScreen(
          appInfo: testAppInfo,
          notice: notice,
          onSignIn: (staffId, password) {
            attempts.add((staffId, password));
            return result.future;
          },
        ),
      ),
    );
  }

  final staffId = find.byKey(const Key('login.staffId'));
  final password = find.byKey(const Key('login.password'));
  final signIn = find.byKey(const Key('login.signIn'));

  Future<void> fillIn(WidgetTester tester, String id, String pass) async {
    await tester.enterText(staffId, id);
    await tester.enterText(password, pass);
  }

  testWidgets('shows the form, the brand panel and the footer',
      (tester) async {
    await pumpLogin(tester);

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Cash Client'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    // Password reset is kept out of the app for now.
    expect(find.text('Forgot password?'), findsNothing);
    expect(
      find.text('Version 1.0.0 (build 1) · Powered by Bynex Labs'),
      findsOneWidget,
    );
  });

  testWidgets('puts the footer in the bottom-right corner', (tester) async {
    await pumpLogin(tester);

    final footer = tester.getBottomRight(find.byKey(const Key('login.footer')));
    expect(footer.dx, greaterThan(1280 - 40));
    expect(footer.dy, greaterThan(720 - 40));
  });

  testWidgets('asks for both fields and sends nothing when empty',
      (tester) async {
    await pumpLogin(tester);

    await tester.tap(signIn);
    await tester.pump();

    expect(find.text('Enter your staff ID'), findsOneWidget);
    expect(find.text('Enter your password'), findsOneWidget);
    expect(attempts, isEmpty);
  });

  testWidgets('a staff ID of only spaces counts as empty', (tester) async {
    await pumpLogin(tester);
    await fillIn(tester, '   ', 'secret123');

    await tester.tap(signIn);
    await tester.pump();

    expect(find.text('Enter your staff ID'), findsOneWidget);
    expect(attempts, isEmpty);
  });

  testWidgets('sends the trimmed staff ID and the password as typed',
      (tester) async {
    await pumpLogin(tester);
    await fillIn(tester, '  STF0012 ', ' secret123 ');

    await tester.tap(signIn);
    await tester.pump();

    expect(attempts, [('STF0012', ' secret123 ')]);
  });

  testWidgets('shows progress and locks the form while signing in',
      (tester) async {
    await pumpLogin(tester);
    await fillIn(tester, 'STF0012', 'secret123');

    await tester.tap(signIn);
    await tester.pump();

    expect(find.text('Signing in…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField).first).enabled,
        isFalse);

    // A second press while busy doesn't send again.
    await tester.tap(signIn, warnIfMissed: false);
    await tester.pump();
    expect(attempts, hasLength(1));

    result.complete(null);
    await tester.pumpAndSettle();
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('shows the message from a failed sign-in', (tester) async {
    await pumpLogin(tester);
    await fillIn(tester, 'STF0012', 'wrong');

    await tester.tap(signIn);
    await tester.pump();
    result.complete('Staff ID or password is incorrect.');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('login.error')), findsOneWidget);
    expect(find.text('Staff ID or password is incorrect.'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });

  testWidgets('a sign-in that throws shows a connection message',
      (tester) async {
    await pumpLogin(tester);
    await fillIn(tester, 'STF0012', 'secret123');

    await tester.tap(signIn);
    await tester.pump();
    result.completeError(StateError('offline'));
    await tester.pumpAndSettle();

    expect(find.textContaining("Couldn't sign in"), findsOneWidget);
  });

  testWidgets('pressing Enter in the password field signs in',
      (tester) async {
    await pumpLogin(tester);
    await fillIn(tester, 'STF0012', 'secret123');

    await tester.showKeyboard(password);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(attempts, hasLength(1));
  });

  testWidgets('the eye button shows and hides the password', (tester) async {
    await pumpLogin(tester);
    TextField passwordField() => tester.widget<TextField>(
          find.descendant(of: password, matching: find.byType(TextField)),
        );

    expect(passwordField().obscureText, isTrue);
    expect(find.byTooltip('Show password'), findsOneWidget);

    await tester.tap(find.byKey(const Key('login.togglePassword')));
    await tester.pump();

    expect(passwordField().obscureText, isFalse);
    expect(find.byTooltip('Hide password'), findsOneWidget);
  });

  testWidgets('shows a notice until the next attempt', (tester) async {
    await pumpLogin(tester, notice: 'Your session has ended.');

    expect(find.byKey(const Key('login.notice')), findsOneWidget);
    expect(find.text('Your session has ended.'), findsOneWidget);
    expect(find.byIcon(Icons.info_outline), findsOneWidget);

    await fillIn(tester, 'STF0012', 'secret123');
    await tester.tap(signIn);
    await tester.pump();

    expect(find.byKey(const Key('login.notice')), findsNothing);
  });

  testWidgets('shows no notice by default', (tester) async {
    await pumpLogin(tester);

    expect(find.byKey(const Key('login.notice')), findsNothing);
  });

  testWidgets('renders in dark mode too', (tester) async {
    await pumpLogin(tester, theme: AppTheme.dark);

    expect(find.text('Welcome back'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
