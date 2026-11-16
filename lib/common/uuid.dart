import 'dart:math';

final _random = Random.secure();

/// A random UUID (version 4), such as `3b241101-e2bb-4255-8caf-4136c566a962`.
/// Used as an idempotency key: one per action, reused on every retry of
/// that action (CASH_CLIENT_DESKTOP.md section 15).
String newUuid() {
  final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0F) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3F) | 0x80; // RFC 4122 variant
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
