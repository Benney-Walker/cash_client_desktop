import 'package:flutter/foundation.dart';

import '../members/member_models.dart' show KycDocumentType;

export '../members/member_models.dart' show KycDocumentType;
export '../members/member_update.dart';

/// The ID document review statuses the queue can show (`KycStatus`).
///
/// `MANUAL_REVIEW` is the queue proper: the automatic check couldn't decide.
/// `PENDING` documents are still waiting for that check, but an
/// Administrator can review them too.
enum KycReviewStatus {
  manualReview('MANUAL_REVIEW', 'Needs review'),
  pending('PENDING', 'Automatic check'),
  verified('VERIFIED', 'Verified'),
  rejected('REJECTED', 'Rejected');

  const KycReviewStatus(this.backendName, this.label);

  final String backendName;
  final String label;

  /// Approve and Reject only work on these (`KycService.reviewableRecord`).
  bool get reviewable => this == manualReview || this == pending;

  static KycReviewStatus? parse(Object? value) {
    for (final s in values) {
      if (s.backendName == value) return s;
    }
    return null;
  }
}

/// One member's ID document record (`KycRecordResponse`).
@immutable
class KycRecord {
  const KycRecord({
    required this.memberId,
    required this.memberName,
    required this.status,
    this.documentType,
    this.idNumber,
    this.reason,
    this.automatic = false,
    this.reviewedBy,
    this.registeredBy,
    this.submittedAt,
    this.verifiedAt,
  });

  final String memberId;
  final String memberName;
  final KycReviewStatus status;
  final KycDocumentType? documentType;
  final String? idNumber;

  /// Why the automatic check sent it to manual review, or why an
  /// Administrator rejected it.
  final String? reason;

  /// True when the automatic check decided (`verificationMethod`
  /// AUTOMATED).
  final bool automatic;
  final String? reviewedBy;
  final String? registeredBy;
  final DateTime? submittedAt;
  final DateTime? verifiedAt;

  static KycRecord? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final id = _text(json['memberId']);
    final status = KycReviewStatus.parse(json['status']);
    if (id == null || status == null) return null;
    final name = [_text(json['firstName']), _text(json['lastName'])]
        .whereType<String>()
        .join(' ');
    final type = json['documentType'];
    return KycRecord(
      memberId: id,
      memberName: name.isEmpty ? 'Member' : name,
      status: status,
      documentType:
          KycDocumentType.values.where((t) => t.backendName == type).firstOrNull,
      idNumber: _text(json['idNumber']),
      reason: _text(json['reason']),
      automatic: json['verificationMethod'] == 'AUTOMATED',
      reviewedBy: _text(json['reviewedByStaffId']),
      registeredBy: _text(json['registeredByStaffId']),
      submittedAt: DateTime.tryParse(_text(json['submittedAt']) ?? ''),
      verifiedAt: DateTime.tryParse(_text(json['verifiedAt']) ?? ''),
    );
  }
}

/// Common reasons offered when rejecting (owner decision 24 November 2026:
/// pick one or type your own). Each is written for the staff member who
/// sees it.
abstract final class RejectionReasons {
  static const idDocument = [
    'The picture is blurry or hard to read.',
    "The ID number doesn't match the card.",
    "The name on the card doesn't match the member.",
    'The card has expired.',
    'Part of the card is cut off.',
  ];

  static const memberUpdate = [
    "The member didn't ask for this change.",
    "The new phone number couldn't be confirmed with the member.",
    'The new details have a mistake.',
  ];

  /// The longest reason the app sends. The backend only needs it not to be
  /// blank.
  static const maxLength = 500;
}

String? _text(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;
