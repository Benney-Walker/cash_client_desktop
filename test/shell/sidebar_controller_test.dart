import 'package:cash_client_desktop/shell/sidebar_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  test('a new installation remembers, and opens expanded', () async {
    final sidebar = SidebarController(MemorySidebarStateStore());

    await sidebar.load();

    expect(sidebar.remember, isTrue);
    expect(sidebar.expanded, isTrue);
  });

  test('reopens collapsed when that was saved', () async {
    final sidebar = SidebarController(
      MemorySidebarStateStore(remember: true, expanded: false),
    );

    await sidebar.load();

    expect(sidebar.expanded, isFalse);
  });

  test('with remembering off, opens expanded whatever was saved', () async {
    final sidebar = SidebarController(
      MemorySidebarStateStore(remember: false, expanded: false),
    );

    await sidebar.load();

    expect(sidebar.remember, isFalse);
    expect(sidebar.expanded, isTrue);
  });

  test('unreadable preferences fall back to the defaults', () async {
    final sidebar = SidebarController(
      MemorySidebarStateStore()..failReads = true,
    );

    await sidebar.load();

    expect(sidebar.remember, isTrue);
    expect(sidebar.expanded, isTrue);
  });

  test('collapsing saves the state when remembering', () async {
    final store = MemorySidebarStateStore();
    final sidebar = SidebarController(store);
    await sidebar.load();
    var notified = 0;
    sidebar.addListener(() => notified++);

    await sidebar.toggle();

    expect(sidebar.expanded, isFalse);
    expect(store.expanded, isFalse);
    expect(notified, 1);
  });

  test('collapsing saves nothing when not remembering', () async {
    final store = MemorySidebarStateStore(remember: false);
    final sidebar = SidebarController(store);
    await sidebar.load();

    await sidebar.setExpanded(false);

    expect(sidebar.expanded, isFalse);
    expect(store.expanded, isNull);
  });

  test('turning remembering off forgets the saved state', () async {
    final store = MemorySidebarStateStore(remember: true, expanded: false);
    final sidebar = SidebarController(store);
    await sidebar.load();

    await sidebar.setRemember(false);

    expect(sidebar.remember, isFalse);
    expect(store.remember, isFalse);
    expect(store.expanded, isNull);
    // The sidebar stays as it is now; only the next launch changes.
    expect(sidebar.expanded, isFalse);
  });

  test('turning remembering on saves the current state', () async {
    final store = MemorySidebarStateStore(remember: false);
    final sidebar = SidebarController(store);
    await sidebar.load();
    await sidebar.setExpanded(false);

    await sidebar.setRemember(true);

    expect(store.remember, isTrue);
    expect(store.expanded, isFalse);
  });

  test('a failed save still applies the change for now', () async {
    final store = MemorySidebarStateStore()..failSaves = true;
    final sidebar = SidebarController(store);
    await sidebar.load();

    await sidebar.setExpanded(false);
    await sidebar.setRemember(false);

    expect(sidebar.expanded, isFalse);
    expect(sidebar.remember, isFalse);
  });

  test('setting the current value again does nothing', () async {
    final sidebar = SidebarController(MemorySidebarStateStore());
    await sidebar.load();
    var notified = 0;
    sidebar.addListener(() => notified++);

    await sidebar.setExpanded(true);
    await sidebar.setRemember(true);

    expect(notified, 0);
  });
}
