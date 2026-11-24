import 'package:flutter/foundation.dart';

/// One page of a list from the backend, which sends Spring's `PagedModel`:
/// `{"content": [...], "page": {"size", "number", "totalElements",
/// "totalPages"}}`. Used for member search, account history, collector
/// submissions, the KYC queue and the audit log.
@immutable
class PagedResult<T> {
  const PagedResult({
    required this.items,
    required this.number,
    required this.size,
    required this.totalElements,
    required this.totalPages,
  });

  final List<T> items;

  /// This page's number, from 0.
  final int number;
  final int size;

  /// How many items there are in all, across pages.
  final int totalElements;
  final int totalPages;

  /// Another page follows this one.
  bool get hasMore => number + 1 < totalPages;

  /// Reads a `PagedModel`; [item] turns one entry into a [T], or null to
  /// skip a malformed one. Returns null when [json] isn't a page.
  static PagedResult<T>? fromJson<T>(
    Object? json,
    T? Function(Object? entry) item,
  ) {
    if (json is! Map<String, dynamic>) return null;
    final content = json['content'];
    final page = json['page'];
    if (content is! List || page is! Map<String, dynamic>) return null;
    final number = page['number'];
    final size = page['size'];
    final total = page['totalElements'];
    final pages = page['totalPages'];
    if (number is! int || size is! int || total is! int || pages is! int) {
      return null;
    }
    return PagedResult(
      items: content.map(item).whereType<T>().toList(),
      number: number,
      size: size,
      totalElements: total,
      totalPages: pages,
    );
  }
}
