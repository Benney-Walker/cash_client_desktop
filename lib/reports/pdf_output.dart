import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../common/dates.dart';
import 'report_api.dart';

/// Saves [bytes] as a PDF where the staff member chooses. Returns false
/// when they cancel.
typedef SavePdf = Future<bool> Function(Uint8List bytes, String fileName);

/// Opens the system print dialog for [bytes].
typedef PrintPdf = Future<void> Function(Uint8List bytes, String name);

/// The system "Save" dialog, then writes the file. macOS needs the
/// `files.user-selected.read-write` entitlement for this.
Future<bool> savePdfToFile(Uint8List bytes, String fileName) async {
  final location = await getSaveLocation(
    suggestedName: fileName,
    acceptedTypeGroups: const [
      XTypeGroup(
        label: 'PDF',
        extensions: ['pdf'],
        uniformTypeIdentifiers: ['com.adobe.pdf'],
      ),
    ],
  );
  if (location == null) return false;
  var path = location.path;
  if (!path.toLowerCase().endsWith('.pdf')) path = '$path.pdf';
  await File(path).writeAsBytes(bytes, flush: true);
  return true;
}

Future<void> printPdfBytes(Uint8List bytes, String name) =>
    Printing.layoutPdf(name: name, onLayout: (_) async => bytes);

/// "Save PDF" and "Print" for a PDF the backend makes, with the outcome
/// beside them (owner decision 24 November 2026: save and print).
class PdfActions extends StatefulWidget {
  const PdfActions({
    super.key,
    required this.keyPrefix,
    required this.load,
    required this.fileName,
    required this.savePdf,
    required this.printPdf,
    this.enabled = true,
  });

  final String keyPrefix;
  final Future<Uint8List> Function() load;

  /// Without ".pdf".
  final String fileName;
  final SavePdf savePdf;
  final PrintPdf printPdf;
  final bool enabled;

  @override
  State<PdfActions> createState() => _PdfActionsState();
}

class _PdfActionsState extends State<PdfActions> {
  bool _busy = false;
  String? _message;
  bool _failed = false;

  Future<void> _run(bool save) async {
    setState(() {
      _busy = true;
      _message = null;
      _failed = false;
    });
    try {
      final bytes = await widget.load();
      if (save) {
        final saved = await widget.savePdf(bytes, '${widget.fileName}.pdf');
        if (mounted && saved) setState(() => _message = 'PDF saved.');
      } else {
        await widget.printPdf(bytes, widget.fileName);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _failed = true;
          _message = e is FileSystemException
              ? "The PDF couldn't be saved there. Choose another place."
              : reportErrorMessage(e);
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final k = widget.keyPrefix;
    final message = _message;
    final on = widget.enabled && !_busy;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OutlinedButton.icon(
          key: Key('$k.savePdf'),
          onPressed: on ? () => _run(true) : null,
          icon: const Icon(Icons.download_outlined),
          label: const Text('Save PDF'),
        ),
        OutlinedButton.icon(
          key: Key('$k.printPdf'),
          onPressed: on ? () => _run(false) : null,
          icon: const Icon(Icons.print_outlined),
          label: const Text('Print'),
        ),
        if (_busy)
          const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        if (message != null)
          Text(
            message,
            key: Key('$k.pdfMessage'),
            style: TextStyle(color: _failed ? scheme.error : scheme.primary),
          ),
      ],
    );
  }
}

/// From and To date buttons; the range never runs backwards or past
/// today.
class DateRangeBar extends StatelessWidget {
  const DateRangeBar({
    super.key,
    required this.keyPrefix,
    required this.from,
    required this.to,
    required this.today,
    required this.onChanged,
  });

  final String keyPrefix;
  final DateTime from;
  final DateTime to;
  final DateTime today;
  final void Function(DateTime from, DateTime to) onChanged;

  Future<void> _pick(BuildContext context, bool isFrom) async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: today,
      initialDate: isFrom ? from : to,
      helpText: isFrom ? 'From' : 'To',
    );
    if (picked == null) return;
    if (isFrom) {
      onChanged(picked, picked.isAfter(to) ? picked : to);
    } else {
      onChanged(picked.isBefore(from) ? picked : from, picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OutlinedButton.icon(
          key: Key('$keyPrefix.from'),
          onPressed: () => _pick(context, true),
          icon: const Icon(Icons.calendar_today_outlined, size: 16),
          label: Text('From ${isoDate(from)}'),
        ),
        OutlinedButton.icon(
          key: Key('$keyPrefix.to'),
          onPressed: () => _pick(context, false),
          icon: const Icon(Icons.calendar_today_outlined, size: 16),
          label: Text('To ${isoDate(to)}'),
        ),
      ],
    );
  }
}
