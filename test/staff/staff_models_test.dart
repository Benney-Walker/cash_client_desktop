import 'package:cash_client_desktop/staff/staff_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const admin = StaffRoleOption.administrator;
  const agent = StaffRoleOption.agent;
  const collector = StaffRoleOption.collector;

  group('role choice', () {
    test('Administrator and Agent can be combined', () {
      var roles = StaffRoleOption.toggle({}, admin);
      roles = StaffRoleOption.toggle(roles, agent);

      expect(roles, {admin, agent});
    });

    test('choosing Collector clears the other roles', () {
      expect(StaffRoleOption.toggle({admin, agent}, collector), {collector});
    });

    test('choosing another role clears Collector', () {
      expect(StaffRoleOption.toggle({collector}, agent), {agent});
    });

    test('tapping a chosen role removes it', () {
      expect(StaffRoleOption.toggle({admin, agent}, admin), {agent});
    });

    test('uses the backend role names', () {
      expect(
        StaffRoleOption.values.map((r) => r.backendName),
        ['ADMINISTRATOR', 'AGENT', 'COLLECTOR'],
      );
    });
  });

  group('dates', () {
    test('formats as yyyy-MM-dd', () {
      expect(isoDate(DateTime(1994, 3, 7)), '1994-03-07');
    });

    test('parses valid dates and rejects impossible ones', () {
      expect(parseIsoDate('1994-03-21'), DateTime(1994, 3, 21));
      expect(parseIsoDate('2026-02-30'), isNull);
      expect(parseIsoDate('21/03/1994'), isNull);
      expect(parseIsoDate('1994-3-21'), isNull);
    });
  });

  group('NewStaff', () {
    NewStaff staff({String? middleName, Set<StaffRoleOption>? roles}) =>
        NewStaff(
          firstName: 'Ama',
          middleName: middleName,
          lastName: 'Owusu',
          dateOfBirth: DateTime(1994, 3, 21),
          phoneNumber: '0241234567',
          email: 'ama@example.com',
          residentialAddress: 'Hse 12, Tarkwa',
          roles: roles ?? {agent},
          branch: const Branch(id: 'b-tarkwa', name: 'Tarkwa'),
        );

    test('builds the add-staff body without a password', () {
      expect(staff().toJson(), {
        'firstName': 'Ama',
        'lastName': 'Owusu',
        'dateOfBirth': '1994-03-21',
        'phoneNumber': '0241234567',
        'email': 'ama@example.com',
        'residentialAddress': 'Hse 12, Tarkwa',
        'roles': ['AGENT'],
        'branchId': 'b-tarkwa',
      });
    });

    test('sends the middle name only when there is one', () {
      expect(staff(middleName: 'Esi').toJson()['middleName'], 'Esi');
      expect(staff(middleName: '').toJson().containsKey('middleName'), false);
    });

    test('lists roles in a fixed order', () {
      expect(staff(roles: {agent, admin}).toJson()['roles'],
          ['ADMINISTRATOR', 'AGENT']);
    });

    test('joins the full name', () {
      expect(staff(middleName: 'Esi').fullName, 'Ama Esi Owusu');
      expect(staff().fullName, 'Ama Owusu');
    });
  });
}
