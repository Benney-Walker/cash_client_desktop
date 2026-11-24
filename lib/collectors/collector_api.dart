import 'package:http/http.dart' as http;

import '../api/api_call.dart';
import '../api/api_exception.dart';
import '../api/endpoint.dart';
import '../common/dates.dart';
import '../members/member_api.dart' show commonFailureMessage;
import 'collector_models.dart';

export 'collector_models.dart';

/// A collector's day for the office: their location points with the
/// payments placed on them, and each collector's totals for a day.
/// Administrators see every collector, Agents their own branch's (the
/// backend checks).
class CollectorApi {
  CollectorApi({
    required String baseUrl,
    required http.Client client,
    this.timeout = const Duration(seconds: 20),
  })  : _baseUrl = baseUrl,
        _client = client;

  static const locationsPath = '/api/transaction/v1/collector-locations';
  static const collectionsReportPath = '/api/report/v1/collector-collections';

  /// How long the backend keeps location points.
  static const keptDays = 90;

  final String _baseUrl;
  final http.Client _client;
  final Duration timeout;

  /// `GET /api/transaction/v1/collector-locations/{staffId}?date=`: the
  /// collector's points for [date], in time order.
  Future<List<LocationPoint>> trail(String collectorStaffId, DateTime date) async {
    final response = await sendChecked(
      () => _client.get(
        apiUri(
          _baseUrl,
          '$locationsPath/${Uri.encodeComponent(collectorStaffId)}',
          {'date': isoDate(date)},
        ),
        headers: const {'Accept': 'application/json'},
      ),
      timeout: timeout,
    );
    final json = decodeJson(response.body);
    if (json is! List) throw unexpectedOk();
    return json.map(LocationPoint.fromJson).whereType<LocationPoint>().toList();
  }

  /// Each collector's payments for [date], by staff ID, from
  /// `GET /api/report/v1/collector-collections?from=&to=`.
  Future<Map<String, CollectorDayTotal>> dayTotals(DateTime date) async {
    final day = isoDate(date);
    final response = await sendChecked(
      () => _client.get(
        apiUri(_baseUrl, collectionsReportPath, {'from': day, 'to': day}),
        headers: const {'Accept': 'application/json'},
      ),
      timeout: timeout,
    );
    final json = decodeJson(response.body);
    final days = json is Map<String, dynamic> ? json['days'] : null;
    if (days is! List) throw unexpectedOk();
    final totals = <String, CollectorDayTotal>{};
    for (final entry in days) {
      final total = CollectorDayTotal.fromJson(entry);
      if (total == null) continue;
      if (entry is Map && entry['date'] != null && entry['date'] != day) {
        continue;
      }
      totals[total.collectorStaffId] = total;
    }
    return totals;
  }
}

/// A message for a failed collector call.
String collectorErrorMessage(Object error) {
  if (error is! ApiException) return 'Something went wrong. Try again.';
  if (error.failure == ApiFailure.notFound) {
    return 'This collector no longer exists.';
  }
  if (error.failure == ApiFailure.forbidden) {
    return "This collector is from another branch, so their day can't be "
        'shown.';
  }
  return commonFailureMessage(error, action: "see collectors' days");
}
