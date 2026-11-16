import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../branches/branch.dart';
import '../common/dates.dart';

export '../branches/branch.dart';
export '../common/dates.dart';

/// The account a new member opens alongside their shares account. The
/// backend opens the shares account itself and rejects SHARES here
/// (`MemberService.parseSelectedAccountType`).
enum MemberAccountType {
  savings('SAVINGS', 'Savings'),
  current('CURRENT', 'Current');

  const MemberAccountType(this.backendName, this.label);

  final String backendName;
  final String label;
}

/// The ID documents the backend accepts (`KycDocumentType`).
enum KycDocumentType {
  ghanaCard('ECOWAS_CARD', 'Ghana Card', 'GHA-123456789-0'),
  voterCard('VOTER_CARD', "Voter's ID card", null);

  const KycDocumentType(this.backendName, this.label, this.example);

  final String backendName;
  final String label;

  /// An example ID number, or null when the format isn't fixed yet (the
  /// voter card format is still to be decided on the backend).
  final String? example;

  // Same rule as the backend's IdNumberRules.
  static final _ghanaCardPin = RegExp(r'^GHA-\d{9}-\d$');

  /// The ID number as the backend stores it: trimmed and in capitals
  /// (`KycService.normalizeIdNumber`).
  static String normalize(String idNumber) => idNumber.trim().toUpperCase();

  /// Why [idNumber] would be refused for this document, or null if it's
  /// fine. Mirrors `normalizeIdNumber` and `IdNumberRules`.
  String? problemWith(String idNumber) {
    final normalized = normalize(idNumber);
    if (normalized.isEmpty) return 'Enter the ID number';
    if (normalized.length > 50) return 'Use at most 50 characters';
    if (this == ghanaCard && !_ghanaCardPin.hasMatch(normalized)) {
      return 'A Ghana Card number looks like GHA-123456789-0';
    }
    return null;
  }
}

/// The image types the backend accepts for an ID document, told apart by
/// their first bytes as the backend does (`KycUploadRules`).
enum KycImageType {
  jpeg('image/jpeg', 'JPEG'),
  png('image/png', 'PNG');

  const KycImageType(this.mimeType, this.label);

  final String mimeType;
  final String label;

  static const _pngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  static const _jpegSignature = [0xFF, 0xD8, 0xFF];

  /// The type of [bytes], or null when they're neither JPEG nor PNG.
  static KycImageType? detect(Uint8List bytes) {
    bool startsWith(List<int> signature) {
      if (bytes.length < signature.length) return false;
      for (var i = 0; i < signature.length; i++) {
        if (bytes[i] != signature[i]) return false;
      }
      return true;
    }

    if (startsWith(_pngSignature)) return png;
    if (startsWith(_jpegSignature)) return jpeg;
    return null;
  }
}

/// A picture of an ID document that passed the backend's rules: a JPEG or
/// PNG of at most 5 MB.
@immutable
class KycImage {
  const KycImage._(this.fileName, this.bytes, this.type);

  /// The backend's limit (`KycUploadRules.MAX_SIZE_BYTES`).
  static const maxBytes = 5 * 1024 * 1024;

  final String fileName;
  final Uint8List bytes;
  final KycImageType type;

  /// Checks a chosen file. Returns the image, or a message saying why it
  /// can't be used.
  static (KycImage?, String?) check(String fileName, Uint8List bytes) {
    if (bytes.isEmpty) return (null, 'That file is empty. Choose another.');
    if (bytes.length > maxBytes) {
      return (null, 'That file is larger than 5 MB. Choose a smaller one.');
    }
    final type = KycImageType.detect(bytes);
    if (type == null) {
      return (null, 'That file isn\'t a JPEG or PNG image. Choose another.');
    }
    return (KycImage._(fileName, bytes, type), null);
  }

  /// The size for display, such as "820 KB" or "1.4 MB".
  String get sizeLabel {
    final kb = bytes.length / 1024;
    if (kb < 1024) return '${kb.ceil()} KB';
    return '${(kb / 1024).toStringAsFixed(1)} MB';
  }
}

/// The ID document to send for KYC review.
@immutable
class KycDocument {
  const KycDocument({
    required this.type,
    required this.idNumber,
    required this.image,
  });

  final KycDocumentType type;

  /// Already normalised (see [KycDocumentType.normalize]).
  final String idNumber;
  final KycImage image;
}

/// What the Register member steps collect, sent to
/// `POST /api/member/v1/add-member` (`MemberDetails`).
@immutable
class NewMember {
  const NewMember({
    required this.firstName,
    this.middleName,
    required this.lastName,
    required this.dateOfBirth,
    required this.phoneNumber,
    required this.residentialAddress,
    required this.occupation,
    required this.accountType,
    required this.branch,
  });

  final String firstName;
  final String? middleName;
  final String lastName;
  final DateTime dateOfBirth;
  final String phoneNumber;
  final String residentialAddress;
  final String occupation;
  final MemberAccountType accountType;
  final Branch branch;

  String get fullName => [firstName, middleName, lastName]
      .whereType<String>()
      .where((part) => part.isNotEmpty)
      .join(' ');

  /// The request body. [idempotencyKey] is the same on every retry of one
  /// registration, so a retry after a dropped connection can't register the
  /// member twice (backend support requested in CASH_CLIENT_DESKTOP.md
  /// section 17; until then the backend ignores the field).
  Map<String, Object?> toJson({required String idempotencyKey}) => {
        'firstName': firstName,
        if (middleName != null && middleName!.isNotEmpty)
          'middleName': middleName,
        'lastName': lastName,
        // MemberDetails calls it `dob`, parsed as yyyy-MM-dd.
        'dob': isoDate(dateOfBirth),
        'phoneNumber': phoneNumber,
        'residentialAddress': residentialAddress,
        'occupation': occupation,
        'accountType': accountType.backendName,
        'branchId': branch.id,
        'idempotencyKey': idempotencyKey,
      };
}
