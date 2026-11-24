import 'package:cash_client_desktop/auth/auth_session.dart';
import 'package:cash_client_desktop/auth/profile_controller.dart';
import 'package:cash_client_desktop/auth/session_manager.dart';
import 'package:cash_client_desktop/auth/staff_profile.dart';
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

  Future<void> pumpShell(
    WidgetTester tester, {
    bool? savedExpanded,
    AuthSession session = adminSession,
    ProfileController? profile,
  }) async {
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
          session: session,
          profile: profile,
          onSignOut: () {},
          apis: fakeApis(),
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

    await tester.tap(find.text('Loans'));
    await tester.pumpAndSettle();

    expect(find.text('Not built yet'), findsOneWidget);
  });

  testWidgets('a dashboard card opens its page and tab', (tester) async {
    await pumpShell(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('dashboard.card.memberUpdates')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('page.approvals')), findsOneWidget);
    expect(rail(tester).selectedIndex, AppSection.approvals.index);
    final tabs = tester.widget<TabBar>(find.byType(TabBar));
    expect(tabs.controller!.index, 1);

    // From the sidebar, Approvals opens on its first tab again.
    await tester.tap(find.text('Members'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approvals'));
    await tester.pumpAndSettle();
    expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 0);
  });

  testWidgets('Staff opens the staff page with Add staff', (tester) async {
    await pumpShell(tester);

    await tester.tap(find.text('Staff'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('page.staff')), findsOneWidget);
    expect(find.byKey(const Key('staff.add')), findsOneWidget);
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

  group('roles (Phase 6)', () {
    List<String?> labels(WidgetTester tester) => [
          for (final d in rail(tester).destinations) (d.label as Text).data,
        ];

    testWidgets('agents don\'t see Approvals', (tester) async {
      await pumpShell(tester, session: agentSession);

      expect(labels(tester), isNot(contains('Approvals')));
      expect(
        labels(tester),
        [for (final s in AppSection.visibleTo(StaffRole.agent)) s.label],
      );
      expect(labels(tester), hasLength(AppSection.values.length - 1));

      // Indexes follow the shorter list.
      await tester.tap(find.text('Staff'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('page.staff')), findsOneWidget);
    });

    testWidgets('administrators see Approvals', (tester) async {
      await pumpShell(tester);

      expect(labels(tester), contains('Approvals'));
      await tester.tap(find.text('Approvals'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('page.approvals')), findsOneWidget);
    });

    Future<ProfileController> signedIn(List<String> roles) async {
      final auth = FakeRefreshApi(FakeRefreshApi.refuses(), loginRoles: roles);
      final sessions = SessionManager(api: auth.api);
      final profile = ProfileController(
        sessions: sessions,
        fetch: () async => StaffProfile(
          staffId: 'STF0020',
          roles: roles.toSet(),
          branchName: 'Tarkwa',
        ),
      );
      await sessions.signIn(staffId: 'STF0020', password: 'x');
      return profile;
    }

    testWidgets('agents see their branch on branch pages and in Settings',
        (tester) async {
      final profile = await signedIn(['AGENT']);
      await pumpShell(tester, session: agentSession, profile: profile);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Staff'));
      await tester.pumpAndSettle();
      expect(find.text('Tarkwa branch only'), findsOneWidget);

      await tester.tap(find.text('Daily submissions'));
      await tester.pumpAndSettle();
      expect(find.text('Tarkwa branch only'), findsOneWidget);

      await tester.tap(find.text('Members'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('branchScope')), findsNothing);

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('settings.branch')), findsOneWidget);
      expect(find.text('Tarkwa branch'), findsOneWidget);
    });

    testWidgets('administrators get no branch chip but see their branch',
        (tester) async {
      final profile = await signedIn(['ADMINISTRATOR']);
      await pumpShell(tester, profile: profile);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Staff'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('branchScope')), findsNothing);

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Tarkwa branch'), findsOneWidget);
    });
  });
}
