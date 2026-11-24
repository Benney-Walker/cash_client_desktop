import 'package:flutter/foundation.dart';

/// A member's contact details that staff can change: phone number,
/// residential address and occupation (`MemberUpdateRequest`). Administrators
/// save them directly; Agents send them as a request an Administrator
/// approves (owner decision 24 November 2026).
@immutable
class MemberContactUpdate {
  const MemberContactUpdate({
    required this.phoneNumber,
    required this.residentialAddress,
    required this.occupation,
  });

  final String phoneNumber;
  final String residentialAddress;
  final String occupation;

  Map<String, Object?> toJson() => {
        'phoneNumber': phoneNumber,
        'residentialAddress': residentialAddress,
        'occupation': occupation,
      };

  /// Same rule as Register member: 10 digits starting with 0.
  static final phonePattern = RegExp(r'^0\d{9}$');
}

/// Where a member update request stands (`MemberUpdateStatus`).
enum MemberUpdateStatus {
  pending('PENDING', 'Waiting'),
  approved('APPROVED', 'Approved'),
  rejected('REJECTED', 'Rejected');

  const MemberUpdateStatus(this.backendName, this.label);

  final String backendName;
  final String label;

  static MemberUpdateStatus? parse(Object? value) {
    for (final s in values) {
      if (s.backendName == value) return s;
    }
    return null;
  }
}

/// Phone, address and occupation at one moment: the member's current values
/// or the proposed ones.
@immutable
class MemberUpdateValues {
  const MemberUpdateValues({
    this.phoneNumber,
    this.residentialAddress,
    this.occupation,
  });

  final String? phoneNumber;
  final String? residentialAddress;
  final String? occupation;

  static MemberUpdateValues fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return const MemberUpdateValues();
    return MemberUpdateValues(
      phoneNumber: _text(json['phoneNumber']),
      residentialAddress: _text(json['residentialAddress']),
      occupation: _text(json['occupation']),
    );
  }
}

/// One proposed member update (`MemberUpdateProposalResponse`), with the
/// member's current values beside the proposed ones.
@immutable
class MemberUpdateRequestRecord {
  const MemberUpdateRequestRecord({
    required this.requestId,
    required this.memberId,
    required this.memberName,
    required this.status,
    required this.current,
    required this.proposed,
    this.branchName,
    this.requestedBy,
    this.requestedAt,
    this.reviewedBy,
    this.reviewedAt,
    this.rejectionReason,
  });

  final String requestId;
  final String memberId;
  final String memberName;
  final String? branchName;
  final MemberUpdateStatus status;
  final MemberUpdateValues current;
  final MemberUpdateValues proposed;
  final String? requestedBy;
  final DateTime? requestedAt;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final String? rejectionReason;

  /// The fields whose proposed value differs from the current one, as
  /// (label, current, proposed).
  List<(String, String?, String?)> get changes => [
        for (final (label, now, next) in [
          ('Phone number', current.phoneNumber, proposed.phoneNumber),
          ('Address', current.residentialAddress, proposed.residentialAddress),
          ('Occupation', current.occupation, proposed.occupation),
        ])
          if (now != next) (label, now, next),
      ];

  static MemberUpdateRequestRecord? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final id = _text(json['requestId']);
    final memberId = _text(json['memberId']);
    final status = MemberUpdateStatus.parse(json['status']);
    if (id == null || memberId == null || status == null) return null;
    return MemberUpdateRequestRecord(
      requestId: id,
      memberId: memberId,
      memberName: _text(json['memberName']) ?? 'Member',
      branchName: _text(json['branchName']),
      status: status,
      current: MemberUpdateValues.fromJson(json['current']),
      proposed: MemberUpdateValues.fromJson(json['proposed']),
      requestedBy: _text(json['requestedByStaffId']),
      requestedAt: DateTime.tryParse(_text(json['requestedAt']) ?? ''),
      reviewedBy: _text(json['reviewedByStaffId']),
      reviewedAt: DateTime.tryParse(_text(json['reviewedAt']) ?? ''),
      rejectionReason: _text(json['rejectionReason']),
    );
  }
}

String? _text(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;
