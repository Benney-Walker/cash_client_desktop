import 'package:cash_client_desktop/api/api_exception.dart';
import 'package:cash_client_desktop/staff/staff_api.dart';
import 'package:cash_client_desktop/staff/staff_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  final newStaff = NewStaff(
    firstName: 'Ama',
    lastName: 'Owusu',
    dateOfBirth: DateTime(1994, 3, 21),
    phoneNumber: '0241234567',
    email: 'ama@example.com',
    residentialAddress: 'Hse 12, Tarkwa',
    roles: const {StaffRoleOption.agent},
    branch: const Branch(id: 'b-tarkwa', name: 'Tarkwa'),
  );

  group('fetchBranches', () {
    test('reads and sorts the branches by name', () async {
      final backend = FakeStaffBackend();

      final branches = await backend.api.fetchBranches();

      expect(branches.map((b) => b.name), ['Accra', 'Tarkwa']);
      expect(branches.last.location, 'Tarkwa Market');
      expect(backend.requests.single.url.toString(),
          '$testBaseUrl/api/branch/v1/all');
    });

    test('skips malformed entries', () async {
      final backend = FakeStaffBackend()
        ..branches = '[{"id": "b1", "name": "Tarkwa"}, {"name": "No id"}]';

      final branches = await backend.api.fetchBranches();

      expect(branches.map((b) => b.id), ['b1']);
    });

    test('a missing endpoint is notFound', () async {
      final backend = FakeStaffBackend(branchesStatus: 404);

      await expectLater(
        backend.api.fetchBranches(),
        throwsA(isA<ApiException>()
            .having((e) => e.failure, 'failure', ApiFailure.notFound)),
      );
    });
  });

  group('addStaff', () {
    test('posts the details as JSON', () async {
      final backend = FakeStaffBackend();

      await backend.api.addStaff(newStaff);

      final request = backend.requests.single;
      expect(request.method, 'POST');
      expect(request.url.toString(), '$testBaseUrl/api/staff/v1/add-staff');
      expect(request.headers['Content-Type'], startsWith('application/json'));
      expect(backend.lastAdd['branchId'], 'b-tarkwa');
      expect(backend.lastAdd['roles'], ['AGENT']);
      expect(backend.lastAdd.containsKey('password'), isFalse);
    });

    test('a 409 is a conflict carrying the backend message', () async {
      final backend = FakeStaffBackend(
        addStatus: 409,
        addBody: errorBody(409, 'Phone number already exist'),
      );

      await expectLater(
        backend.api.addStaff(newStaff),
        throwsA(isA<ApiException>()
            .having((e) => e.failure, 'failure', ApiFailure.conflict)
            .having((e) => e.message, 'message',
                'Phone number already exist')),
      );
    });
  });

  group('addStaffErrorMessage', () {
    (String, AddStaffStep?) forConflict(String message) =>
        addStaffErrorMessage(
          ApiException(ApiFailure.conflict, message: message, statusCode: 409),
        );

    test('points duplicate contact details to the Contact step', () {
      expect(forConflict('Phone number already exist').$2,
          AddStaffStep.contact);
      expect(forConflict('Email already exist').$2, AddStaffStep.contact);
    });

    test('points the one-agent rule to Role and branch', () {
      final (message, step) =
          forConflict('Branch Tarkwa already has an active agent');
      expect(message, contains('only one active agent'));
      expect(step, AddStaffStep.roleAndBranch);
    });

    test('explains an existing staff member', () {
      final (message, step) = forConflict('Staff already exist');
      expect(message, contains('already exists'));
      expect(step, AddStaffStep.personal);
    });

    test('shows an unknown conflict as the backend wrote it', () {
      expect(forConflict('Something new').$1, 'Something new');
    });

    test('every failure has a message', () {
      for (final failure in ApiFailure.values) {
        expect(addStaffErrorMessage(ApiException(failure)).$1, isNotEmpty);
      }
    });
  });
}
