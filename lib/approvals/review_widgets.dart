import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../common/glass_card.dart';
import 'approval_api.dart';

/// Asks for a rejection reason: one of [presets] to pick (it fills the box)
/// or the staff member's own words (owner decision 24 November 2026).
/// Returns the reason, or null when cancelled.
Future<String?> askRejectionReason(
  BuildContext context, {
  required String title,
  required String explanation,
  required List<String> presets,
}) =>
    showDialog<String>(
      context: context,
      builder: (context) => _RejectDialog(
        title: title,
        explanation: explanation,
        presets: presets,
      ),
    );

class _RejectDialog extends StatefulWidget {
  const _RejectDialog({
    required this.title,
    required this.explanation,
    required this.presets,
  });

  final String title;
  final String explanation;
  final List<String> presets;

  @override
  State<_RejectDialog> createState() => _RejectDialogState();
}

class _RejectDialogState extends State<_RejectDialog> {
  final _reason = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _pick(String preset) => setState(() {
        _reason.text = preset;
        _error = null;
      });

  void _confirm() {
    final reason = _reason.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = 'Choose a reason or type one');
      return;
    }
    Navigator.of(context).pop(reason);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return AlertDialog(
      key: const Key('reject.dialog'),
      title: Text(widget.title),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.explanation, style: textTheme.bodyMedium),
            const SizedBox(height: 16),
            Text('Common reasons', style: textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (i, preset) in widget.presets.indexed)
                  ChoiceChip(
                    key: Key('reject.preset.$i'),
                    label: Text(preset),
                    selected: _reason.text == preset,
                    onSelected: (_) => _pick(preset),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('reject.reason'),
              controller: _reason,
              maxLines: 3,
              maxLength: RejectionReasons.maxLength,
              onChanged: (_) => setState(() => _error = null),
              decoration: InputDecoration(
                labelText: 'Reason',
                hintText: 'Or type your own',
                errorText: _error,
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('reject.cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('reject.confirm'),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: _confirm,
          child: const Text('Reject'),
        ),
      ],
    );
  }
}

/// The member's ID picture, large enough to read the card, with zoom
/// (buttons, scroll or pinch) and rotation.
///
/// It's fetched once when shown: the backend records each view in the
/// audit log, and the bytes stay in memory only.
class KycPictureViewer extends StatefulWidget {
  const KycPictureViewer({
    super.key,
    required this.api,
    required this.memberId,
    this.height = 340,
  });

  final ApprovalApi api;
  final String memberId;
  final double height;

  @override
  State<KycPictureViewer> createState() => _KycPictureViewerState();
}

class _KycPictureViewerState extends State<KycPictureViewer> {
  static const _k = 'kycPicture';
  static const _maxScale = 5.0;

  Uint8List? _bytes;
  Object? _error;
  bool _loading = true;
  int _quarterTurns = 0;
  final _transform = TransformationController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bytes = await widget.api.fetchKycPicture(widget.memberId);
      if (mounted) setState(() => _bytes = bytes);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  double get _scale => _transform.value.getMaxScaleOnAxis();

  void _zoom(double factor) {
    final next = (_scale * factor).clamp(1.0, _maxScale);
    setState(() => _transform.value = Matrix4.diagonal3Values(next, next, 1));
  }

  void _reset() => setState(() {
        _transform.value = Matrix4.identity();
        _quarterTurns = 0;
      });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bytes = _bytes;

    Widget body;
    if (bytes == null && _loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (bytes == null) {
      body = Center(
        child: Column(
          key: const Key('$_k.error'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              approvalErrorMessage(_error ?? 'unknown'),
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.error),
            ),
            TextButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        ),
      );
    } else {
      body = ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: InteractiveViewer(
          transformationController: _transform,
          minScale: 1,
          maxScale: _maxScale,
          child: Center(
            child: RotatedBox(
              quarterTurns: _quarterTurns,
              child: Image.memory(
                bytes,
                key: const Key('$_k.image'),
                fit: BoxFit.contain,
                gaplessPlayback: true,
                semanticLabel: 'ID document picture',
                errorBuilder: (context, _, __) => Text(
                  "The picture couldn't be shown.",
                  key: const Key('$_k.bad'),
                  style: TextStyle(color: scheme.error),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return GlassCard(
      key: const Key(_k),
      title: 'ID picture',
      icon: Icons.image_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: widget.height,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: body,
          ),
          if (bytes != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton(
                  key: const Key('$_k.zoomOut'),
                  tooltip: 'Zoom out',
                  onPressed: () => _zoom(1 / 1.5),
                  icon: const Icon(Icons.zoom_out),
                ),
                IconButton(
                  key: const Key('$_k.zoomIn'),
                  tooltip: 'Zoom in',
                  onPressed: () => _zoom(1.5),
                  icon: const Icon(Icons.zoom_in),
                ),
                IconButton(
                  key: const Key('$_k.rotate'),
                  tooltip: 'Rotate',
                  onPressed: () =>
                      setState(() => _quarterTurns = (_quarterTurns + 1) % 4),
                  icon: const Icon(Icons.rotate_right),
                ),
                TextButton(
                  key: const Key('$_k.reset'),
                  onPressed: _reset,
                  child: const Text('Reset'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// A label and its value, for the review panes.
class ReviewRow extends StatelessWidget {
  const ReviewRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style:
                  textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(child: Text(value, style: textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
