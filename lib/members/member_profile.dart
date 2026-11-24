import 'package:flutter/foundation.dart';

import '../api/paged.dart';

export '../api/paged.dart';

import 'member_models.dart';

// What the Members page reads: search results and member details, as the
// backend sends them (CASH_CLIENT_DESKTOP.md section 20). Fields the backend
// doesn't send (yet, or for an Agent looking at another branch's member)
// are null, and the page leaves them out.

/// A member's membership status (`MembershipStatus`).
enum MembershipStatus {
  pending('PENDING', 'Pending'),
  active('ACTIVE', 'Active'),
  inactive('INACTIVE', 'Inactive'),
  suspended('SUSPENDED', 'Suspended');

  const MembershipStatus(this.backendName, this.label);

  final String backendName;
  final String label;

  static MembershipStatus? parse(Object? value) =>
      _byName(MembershipStatus.values, value, (s) => s.backendName);
}

/// Where a member's ID document stands (`kyc.status`, section 18).
enum KycState {
  notSubmitted('NOT_SUBMITTED', 'ID not added'),
  pending('PENDING', 'ID under review'),
  manualReview('MANUAL_REVIEW', 'ID under manual review'),
  verified('VERIFIED', 'ID verified'),
  rejected('REJECTED', 'ID rejected');

  const KycState(this.backendName, this.label);

  final String backendName;
  final String label;

  static KycState? parse(Object? value) =>
      _byName(KycState.values, value, (s) => s.backendName);
}

/// An account's status (`AccountStatus`).
enum AccountState {
  active('ACTIVE', 'Active'),
  inactive('INACTIVE', 'Inactive'),
  frozen('FROZEN', 'Frozen'),
  closed('CLOSED', 'Closed');

  const AccountState(this.backendName, this.label);

  final String backendName;
  final String label;

  static AccountState? parse(Object? value) =>
      _byName(AccountState.values, value, (s) => s.backendName);
}

T? _byName<T>(List<T> values, Object? value, String Function(T) name) {
  if (value is! String) return null;
  for (final v in values) {
    if (name(v) == value) return v;
  }
  return null;
}

String? _text(Object? value) =>
    value is String && value.trim().isNotEmpty ? value : null;

String _fullName(Object? first, Object? middle, Object? last) => [
      _text(first),
      _text(middle),
      _text(last),
    ].whereType<String>().join(' ');

/// One search or list result (`MemberSummaryResponse`). For another
/// branch's member an Agent gets no phone number.
@immutable
class MemberSummary {
  const MemberSummary({
    required this.memberId,
    required this.fullName,
    this.phoneNumber,
    this.branchId,
    this.branchName,
    this.status,
    this.accounts = const [],
  });

  final String memberId;
  final String fullName;
  final String? phoneNumber;
  final String? branchId;
  final String? branchName;
  final MembershipStatus? status;
  final List<MemberAccountSummary> accounts;

  static MemberSummary? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final id = _text(json['memberId']);
    final name =
        _fullName(json['firstName'], json['middleName'], json['lastName']);
    if (id == null || name.isEmpty) return null;
    final accounts = json['accounts'];
    return MemberSummary(
      memberId: id,
      fullName: name,
      phoneNumber: _text(json['phoneNumber']),
      branchId: _text(json['branchId']),
      branchName: _text(json['branchName']),
      status: MembershipStatus.parse(json['membershipStatus']),
      accounts: accounts is List
          ? accounts
              .map(MemberAccountSummary.fromJson)
              .whereType<MemberAccountSummary>()
              .toList()
          : const [],
    );
  }
}

/// One page of member search results.
typedef MemberSearchPage = PagedResult<MemberSummary>;

/// One of a member's accounts. Balances aren't sent (backend decision).
@immutable
class MemberAccountSummary {
  const MemberAccountSummary({
    required this.accountNumber,
    this.type,
    this.status,
  });

  final String accountNumber;

  /// `SAVINGS`, `CURRENT` or `SHARES`, shown as Savings, Current, Shares.
  final String? type;
  final AccountState? status;

  String get typeLabel {
    final t = type;
    if (t == null || t.isEmpty) return 'Account';
    return t[0] + t.substring(1).toLowerCase();
  }

  static MemberAccountSummary? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final number = _text(json['accountNumber']);
    if (number == null) return null;
    return MemberAccountSummary(
      accountNumber: number,
      type: _text(json['accountType']),
      status: AccountState.parse(json['status']),
    );
  }
}

/// The member's ID document status, as the backend reports it.
@immutable
class MemberKyc {
  const MemberKyc({
    required this.state,
    required this.canUpload,
    this.documentType,
    this.rejectionReason,
  });

  final KycState state;

  /// The backend's rule for the signed-in staff member: no document yet,
  /// or rejected and they registered the member.
  final bool canUpload;
  final KycDocumentType? documentType;
  final String? rejectionReason;

  static MemberKyc? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final state = KycState.parse(json['status']);
    if (state == null) return null;
    final type = json['documentType'];
    return MemberKyc(
      state: state,
      canUpload: json['canUpload'] == true,
      documentType: KycDocumentType.values
          .where((t) => t.backendName == type)
          .firstOrNull,
      rejectionReason: _text(json['rejectionReason']),
    );
  }
}

/// A member's details (`GET /api/member/v1/member-details/{id}`).
@immutable
class MemberProfile {
  const MemberProfile({
    required this.memberId,
    required this.fullName,
    required this.accounts,
    required this.limited,
    this.phoneNumber,
    this.dateOfBirth,
    this.residentialAddress,
    this.occupation,
    this.status,
    this.branchName,
    this.registeredBy,
    this.registeredOn,
    this.kyc,
  });

  final String memberId;
  final String fullName;
  final List<MemberAccountSummary> accounts;

  /// The backend sent the limited view (an Agent looking at another
  /// branch's member): name, phone number and accounts only.
  final bool limited;

  final String? phoneNumber;
  final DateTime? dateOfBirth;
  final String? residentialAddress;
  final String? occupation;
  final MembershipStatus? status;
  final String? branchName;
  final String? registeredBy;
  final DateTime? registeredOn;

  /// Null when the backend doesn't report it (not yet built, or a limited
  /// view). The page then offers no upload.
  final MemberKyc? kyc;

  static MemberProfile? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final id = _text(json['memberId']);
    final name =
        _fullName(json['firstName'], json['middleName'], json['lastName']);
    final accounts = json['accounts'];
    if (id == null || name.isEmpty) return null;
    final limited = json['detailLevel'] == 'LIMITED';
    return MemberProfile(
      memberId: id,
      fullName: name,
      accounts: accounts is List
          ? accounts
              .map(MemberAccountSummary.fromJson)
              .whereType<MemberAccountSummary>()
              .toList()
          : const [],
      limited: limited,
      phoneNumber: _text(json['phoneNumber']),
      dateOfBirth: parseIsoDate(_text(json['dateOfBirth']) ?? ''),
      residentialAddress: _text(json['residentialAddress']),
      occupation: _text(json['occupation']),
      status: MembershipStatus.parse(json['membershipStatus']),
      branchName: _text(json['branchName']),
      registeredBy: _text(json['registeredByStaffId']),
      // createdAt is a LocalDateTime such as 2026-11-16T10:15:30.123.
      registeredOn: DateTime.tryParse(_text(json['createdAt']) ?? ''),
      kyc: limited ? null : MemberKyc.fromJson(json['kyc']),
    );
  }
}
