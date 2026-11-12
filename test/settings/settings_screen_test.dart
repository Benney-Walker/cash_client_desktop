import 'package:cash_client_desktop/common/gradient_switch.dart';
import 'package:cash_client_desktop/settings/settings_screen.dart';
import 'package:cash_client_desktop/settings/theme_controller.dart';
import 'package:cash_client_desktop/shell/sidebar_controller.dart';
import 'package:cash_client_desktop/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  late MemoryThemeModeStore themeStore;
  late ThemeController theme;
  late MemorySidebarStateStore sidebarStore;
  late SidebarController sidebar;

  Future<void> pumpSettings(
    WidgetTester tester, {
    ThemeMode? saved,
    bool? rememberSidebar,
  }) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    themeStore = MemoryThemeModeStore(saved);
    theme = ThemeController(themeStore);
    await theme.load();
    sidebarStore = MemorySidebarStateStore(remember: rememberSidebar);
    sidebar = SidebarController(sidebarStore);
    await sidebar.load();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SettingsScreen(
            theme: theme,
            sidebar: sidebar,
            appInfo: testAppInfo,
          ),
        ),
      ),
    );
  }

  SegmentedButton<ThemeMode> picker(WidgetTester tester) =>
      tester.widget(find.byKey(const Key('settings.themeMode')));

  GradientSwitch rememberSwitch(WidgetTester tester) => tester.widget(
        find.descendant(
          of: find.byKey(const Key('settings.rememberSidebar')),
          matching: find.byType(GradientSwitch),
        ),
      );

  testWidgets('shows Appearance above About', (tester) async {
    await pumpSettings(tester);

    final appearance = find.byKey(const Key('settings.appearance'));
    final about = find.byKey(const Key('settings.about'));
    expect(
      tester.getTopLeft(appearance).dy,
      lessThan(tester.getTopLeft(about).dy),
    );
  });

  testWidgets('shows the three theme choices with the current one selected',
      (tester) async {
    await pumpSettings(tester);

    expect(find.text('System'), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
    expect(picker(tester).selected, {ThemeMode.system});
    expect(find.textContaining("computer's light or dark"), findsOneWidget);
  });

  testWidgets('shows a saved theme choice as selected', (tester) async {
    await pumpSettings(tester, saved: ThemeMode.light);

    expect(picker(tester).selected, {ThemeMode.light});
    expect(find.text('Always light.'), findsOneWidget);
  });

  testWidgets('choosing dark applies and saves it', (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    expect(theme.mode, ThemeMode.dark);
    expect(themeStore.mode, ThemeMode.dark);
    expect(picker(tester).selected, {ThemeMode.dark});
    expect(find.text('Always dark.'), findsOneWidget);
  });

  testWidgets('each theme choice is at least 48dp tall', (tester) async {
    await pumpSettings(tester);

    for (final label in ['System', 'Light', 'Dark']) {
      final segment = find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      );
      expect(tester.getSize(segment.first).height,
          greaterThanOrEqualTo(AppTheme.minTouchTarget));
    }
  });

  testWidgets('remember sidebar state is on for a new installation',
      (tester) async {
    await pumpSettings(tester);

    expect(rememberSwitch(tester).value, isTrue);
    expect(find.text('Remember sidebar state'), findsOneWidget);
  });

  testWidgets('tapping the row turns remembering off and saves it',
      (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.text('Remember sidebar state'));
    await tester.pumpAndSettle();

    expect(sidebar.remember, isFalse);
    expect(sidebarStore.remember, isFalse);
    expect(rememberSwitch(tester).value, isFalse);
  });

  testWidgets('tapping the switch itself also toggles it', (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(sidebar.remember, isFalse);
  });

  testWidgets('cards have gradient icon tiles', (tester) async {
    await pumpSettings(tester);

    expect(find.byIcon(Icons.palette_outlined), findsOneWidget);
    expect(find.byIcon(Icons.info_outline), findsOneWidget);
  });

  testWidgets('shows a saved off choice', (tester) async {
    await pumpSettings(tester, rememberSidebar: false);

    expect(rememberSwitch(tester).value, isFalse);
  });

  testWidgets('About shows the version and the server', (tester) async {
    await pumpSettings(tester);

    expect(
      find.descendant(
        of: find.byKey(const Key('settings.version')),
        matching: find.text('1.0.0 (build 1)'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('settings.server')),
        matching: find.text('https://api.test.example'),
      ),
      findsOneWidget,
    );
  });
}
