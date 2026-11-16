import 'package:cash_client_desktop/auth/inactivity_lock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DateTime now;
  late InactivityLock lock;

  setUp(() {
    now = DateTime(2026, 11, 13, 9);
    lock = InactivityLock(now: () => now);
  });

  tearDown(() => lock.dispose());

  void wait(Duration d) => now = now.add(d);

  test('locks after 20 minutes by default', () {
    expect(InactivityLock.defaultTimeout, const Duration(minutes: 20));
  });

  test('does not lock before the timeout', () {
    lock.start();

    wait(const Duration(minutes: 19, seconds: 59));
    lock.check();

    expect(lock.locked, isFalse);
  });

  test('locks once the timeout has passed without activity', () {
    lock.start();
    var notified = 0;
    lock.addListener(() => notified++);

    wait(const Duration(minutes: 20));
    lock.check();

    expect(lock.locked, isTrue);
    expect(notified, 1);
  });

  test('activity restarts the count', () {
    lock.start();

    wait(const Duration(minutes: 15));
    lock.recordActivity();
    wait(const Duration(minutes: 15));
    lock.check();

    expect(lock.locked, isFalse);
  });

  test('activity while locked does not unlock or count', () {
    lock.start();
    wait(const Duration(minutes: 20));
    lock.check();

    lock.recordActivity();

    expect(lock.locked, isTrue);
  });

  test('nothing locks when it is not running', () {
    wait(const Duration(hours: 1));
    lock.check();

    expect(lock.locked, isFalse);
  });

  test('unlocking counts from the moment of unlocking', () {
    lock.start();
    wait(const Duration(minutes: 20));
    lock.check();

    lock.unlock();
    wait(const Duration(minutes: 19));
    lock.check();

    expect(lock.locked, isFalse);
    wait(const Duration(minutes: 1));
    lock.check();
    expect(lock.locked, isTrue);
  });

  test('stopping clears the lock', () {
    lock.start();
    wait(const Duration(minutes: 20));
    lock.check();

    lock.stop();

    expect(lock.locked, isFalse);
    expect(lock.running, isFalse);
  });
}
