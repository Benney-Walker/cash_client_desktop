import 'package:cash_client_desktop/api/api_exception.dart';
import 'package:cash_client_desktop/branches/branch.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  group('fetchBranches', () {
    test('reads and sorts the branches by name', () async {
      final backend = FakeStaffBackend();

      final branches = await backend.branchApi.fetchBranches();

      expect(branches.map((b) => b.name), ['Accra', 'Tarkwa']);
      expect(backend.requests.single.url.toString(),
          '$testBaseUrl/api/branch/v1/all');
    });

    test('reads id and name, the only fields the backend sends', () async {
      final backend = FakeStaffBackend()
        ..branches = '[{"id": "b1", "name": "Tarkwa"}]';

      final branch = (await backend.branchApi.fetchBranches()).single;

      expect(branch.id, 'b1');
      expect(branch.location, isNull);
      expect(branch.label, 'Tarkwa');
    });

    test('skips malformed entries', () async {
      final backend = FakeStaffBackend()
        ..branches = '[{"id": "b1", "name": "Tarkwa"}, {"name": "No id"}]';

      final branches = await backend.branchApi.fetchBranches();

      expect(branches.map((b) => b.id), ['b1']);
    });

    test('a missing endpoint is notFound', () async {
      final backend = FakeStaffBackend(branchesStatus: 404);

      await expectLater(
        backend.branchApi.fetchBranches(),
        throwsA(isA<ApiException>()
            .having((e) => e.failure, 'failure', ApiFailure.notFound)),
      );
    });
  });

  test('a location, if ever sent, is shown with the name', () {
    final branch = Branch.fromJson(
      {'id': 'b1', 'name': 'Tarkwa', 'location': 'Tarkwa Market'},
    )!;

    expect(branch.label, 'Tarkwa · Tarkwa Market');
  });
}
