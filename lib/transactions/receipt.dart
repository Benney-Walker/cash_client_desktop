import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../common/dates.dart';
import 'transaction_models.dart';

/// What a printed receipt shows (owner decisions 24 November 2026: A4 or
/// Letter page, no balance). Account numbers are masked to their last 4
/// digits, as in the member's SMS.
@immutable
class ReceiptData {
  const ReceiptData({
    required this.creditUnionName,
    required this.kind,
    required this.record,
    required this.memberName,
    required this.staffId,
    this.toMemberName,
  });

  /// The heading; the build's `CREDIT_UNION_NAME`, or "Cash Client".
  final String creditUnionName;
  final TransactionKind kind;
  final TransactionRecord record;
  final String memberName;

  /// For a transfer: who received it.
  final String? toMemberName;

  /// Who served the member, when the backend didn't say.
  final String staffId;

  /// The receipt's lines, in order. Shared by the PDF and the tests.
  List<(String, String)> get rows {
    final fee = record.fee;
    final share = record.shareAmount;
    final when = record.createdAt;
    return [
      ('Reference', record.transactionId),
      if (when != null) ('Date and time', _dateTime(when)),
      ('Transaction', kind.label),
      ('Member', memberName),
      (
        kind == TransactionKind.transfer ? 'From account' : 'Account',
        maskedAccount(record.accountNumber),
      ),
      if (kind == TransactionKind.transfer &&
          record.counterpartyAccountNumber != null)
        (
          'To account',
          [
            maskedAccount(record.counterpartyAccountNumber!),
            if (toMemberName != null) toMemberName!,
          ].join(' · '),
        ),
      ('Amount', record.amount.toString()),
      if (share != null && share.isPositive) ('Of which shares', '$share'),
      if (fee != null && fee.isPositive) ...[
        ('Fee', fee.toString()),
        ('Total taken from the account', (record.amount + fee).toString()),
      ],
      if (record.description != null) ('Note', record.description!),
      ('Served by', record.staffId ?? staffId),
    ];
  }

  static String _dateTime(DateTime t) =>
      '${isoDate(t)} ${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';
}

/// Builds the receipt as a PDF on an A4 page: the receipt fills the top
/// half, so a cut gives a half-page slip. Uses the app's bundled Inter,
/// which has the cedi sign.
Future<Uint8List> buildReceiptPdf(
  ReceiptData data, {
  PdfPageFormat format = PdfPageFormat.a4,
}) async {
  final regular = pw.Font.ttf(
    await rootBundle.load('assets/fonts/inter/Inter-Regular.ttf'),
  );
  final bold = pw.Font.ttf(
    await rootBundle.load('assets/fonts/inter/Inter-SemiBold.ttf'),
  );
  final doc = pw.Document(
    title: '${data.kind.label} receipt ${data.record.transactionId}',
    theme: pw.ThemeData.withFont(base: regular, bold: bold),
  );
  doc.addPage(
    pw.Page(
      pageFormat: format,
      margin: const pw.EdgeInsets.all(48),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            data.creditUnionName,
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            '${data.kind.label} receipt',
            style: const pw.TextStyle(fontSize: 13),
          ),
          pw.SizedBox(height: 16),
          pw.Divider(thickness: 0.5),
          pw.SizedBox(height: 8),
          for (final (label, value) in data.rows)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 4),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.SizedBox(
                    width: 170,
                    child: pw.Text(
                      label,
                      style: const pw.TextStyle(
                        fontSize: 11,
                        color: PdfColors.grey700,
                      ),
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Text(value, style: const pw.TextStyle(fontSize: 11)),
                  ),
                ],
              ),
            ),
          pw.SizedBox(height: 8),
          pw.Divider(thickness: 0.5),
          pw.SizedBox(height: 8),
          pw.Text(
            'Keep this receipt. The member also receives an SMS for every '
            'transaction.',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
        ],
      ),
    ),
  );
  return doc.save();
}

/// Prints a receipt. Replaced in tests; the real one opens the system's
/// print dialog with the PDF.
typedef PrintReceipt = Future<void> Function(ReceiptData data);

Future<void> printReceiptPdf(ReceiptData data) => Printing.layoutPdf(
      name: 'Receipt ${data.record.transactionId}',
      format: PdfPageFormat.a4,
      onLayout: (format) => buildReceiptPdf(data, format: format),
    );
