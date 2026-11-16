import 'package:flutter/material.dart';

import '../api/api_exception.dart';
import '../common/glass_card.dart';
import '../common/gradient_button.dart';
import '../common/step_flow.dart';
import '../theme/app_gradients.dart';
import 'kyc_document_fields.dart';
import 'kyc_image_picker.dart';
import 'member_api.dart';
import 'member_models.dart';
import 'member_status_style.dart';

/// The right side of the Members page (design P2): one member's details,
/// accounts and ID document, with "Upload ID document" when the backend
/// says the signed-in staff member may upload.
///
/// Give it a key per member (`ValueKey(memberId)`) so it starts fresh when
/// another member is chosen.
class MemberDetailsPane extends StatefulWidget {
  const MemberDetailsPane({
    super.key,
    required this.api,
    required this.memberId,
    this.pickImage = pickKycImageFile,
    this.acceptDrops = true,
  });

  final MemberApi api;
  final String memberId;
  final PickKycImage pickImage;
  final bool acceptDrops;

  @override
  State<MemberDetailsPane> createState() => _MemberDetailsPaneState();
}

class _MemberDetailsPaneState extends State<MemberDetailsPane> {
  static const _k = 'memberDetails';

  MemberProfile? _member;
  Object? _loadError;
  bool _loading = true;

  bool _uploading = false;
  bool _sending = false;
  String? _uploadError;
  bool _uploadOutcomeUnknown = false;
  bool _justUploaded = false;
  final _formKey = GlobalKey<FormState>();
  final _document = KycDocumentDraft();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _document.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final member = await widget.api.fetchMember(widget.memberId);
      if (mounted) setState(() => _member = member);
    } catch (error) {
      if (mounted) setState(() => _loadError = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _startUpload() => setState(() {
        _uploading = true;
        _uploadError = null;
        _justUploaded = false;
      });

  void _cancelUpload() => setState(() {
        _uploading = false;
        _uploadError = null;
        _document.clear();
      });

  Future<void> _upload() async {
    if (_sending || !_formKey.currentState!.validate()) return;
    final document = _document.build();
    setState(() {
      _sending = true;
      _uploadError = null;
    });
    try {
      await widget.api.uploadKycDocument(
        memberId: widget.memberId,
        document: document,
      );
      _uploaded();
    } catch (error) {
      if (!mounted) return;
      if (_uploadOutcomeUnknown && _alreadySubmitted(error)) {
        // The attempt that lost its answer did reach the backend.
        _uploaded();
        return;
      }
      setState(() {
        if (error is ApiException && error.failure == ApiFailure.network) {
          _uploadOutcomeUnknown = true;
        }
        _uploadError = kycErrorMessage(error);
      });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _uploaded() {
    if (!mounted) return;
    setState(() {
      _uploading = false;
      _justUploaded = true;
      _uploadOutcomeUnknown = false;
      _document.clear();
    });
    _load();
  }

  static bool _alreadySubmitted(Object error) =>
      error is ApiException &&
      error.failure == ApiFailure.conflict &&
      (error.message ?? '').toLowerCase().contains('already been submitted');

  @override
  Widget build(BuildContext context) {
    final member = _member;
    final error = _loadError;

    if (member == null && _loading) {
      return const Center(
        key: Key('$_k.loading'),
        child: CircularProgressIndicator(),
      );
    }
    if (member == null) {
      return _LoadFailed(
        message: _loadErrorMessage(error),
        onRetry: _load,
      );
    }

    final textTheme = Theme.of(context).textTheme;
    final status = member.status;
    final kyc = member.kyc;

    return ListView(
      key: const Key('$_k.view'),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Text(
          member.fullName,
          key: const Key('$_k.name'),
          style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (status != null) membershipPill(status),
            if (kyc != null) kycPill(kyc.state, key: const Key('$_k.kycPill')),
          ],
        ),
        if (member.limited) ...[
          const SizedBox(height: 12),
          const InfoNote(
            key: Key('$_k.limited'),
            text: 'This member belongs to another branch, so only their '
                'name, phone number and accounts are shown.',
          ),
        ],
        const SizedBox(height: 16),
        GlassCard(
          key: const Key('$_k.details'),
          title: 'Details',
          icon: Icons.person_outline,
          child: _detailRows(context, member),
        ),
        const SizedBox(height: 16),
        GlassCard(
          key: const Key('$_k.accounts'),
          title: 'Accounts',
          icon: Icons.account_balance_wallet_outlined,
          child: _accounts(context, member),
        ),
        if (!member.limited) ...[
          const SizedBox(height: 16),
          _uploading ? _uploadCard() : _kycCard(context, kyc),
        ],
      ],
    );
  }

  String _loadErrorMessage(Object? error) {
    if (error is ApiException && error.failure == ApiFailure.notFound) {
      return "This member couldn't be found.";
    }
    if (error is ApiException) {
      return commonFailureMessage(error, action: 'view members');
    }
    return 'Something went wrong. Try again.';
  }

  Widget _detailRows(BuildContext context, MemberProfile member) {
    final registered = [
      if (member.registeredOn != null) isoDate(member.registeredOn!),
      if (member.registeredBy != null) 'by ${member.registeredBy}',
    ].join(' ');
    final rows = <(String, String?)>[
      ('Phone number', member.phoneNumber),
      ('Branch', member.branchName),
      (
        'Date of birth',
        member.dateOfBirth == null ? null : isoDate(member.dateOfBirth!),
      ),
      ('Occupation', member.occupation),
      ('Address', member.residentialAddress),
      ('Registered', registered.isEmpty ? null : registered),
    ];
    return Column(
      children: [
        for (final (label, value) in rows)
          if (value != null) _LabelValue(label: label, value: value),
      ],
    );
  }

  Widget _accounts(BuildContext context, MemberProfile member) {
    final textTheme = Theme.of(context).textTheme;
    if (member.accounts.isEmpty) {
      return Text('No accounts.', style: textTheme.bodyMedium);
    }
    return Column(
      children: [
        for (final account in member.accounts)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 90,
                  child: Text(account.typeLabel, style: textTheme.titleSmall),
                ),
                Expanded(
                  child: Text(
                    account.accountNumber,
                    style: textTheme.bodyMedium?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                if (account.status != null) accountPill(account.status!),
              ],
            ),
          ),
      ],
    );
  }

  Widget _kycCard(BuildContext context, MemberKyc? kyc) {
    final textTheme = Theme.of(context).textTheme;

    final String text;
    if (kyc == null) {
      text = "The server doesn't report this member's ID status yet, so an "
          "ID document can't be uploaded from here.";
    } else {
      text = switch (kyc.state) {
        KycState.notSubmitted => 'No ID document yet. The member\'s '
            'accounts stay inactive until one is uploaded and verified.',
        KycState.pending || KycState.manualReview =>
          'The ID document is being reviewed.',
        KycState.verified => 'The ID document has been verified.',
        KycState.rejected => 'The ID document was rejected.',
      };
    }

    return GlassCard(
      key: const Key('$_k.kyc'),
      title: 'ID document',
      icon: Icons.badge_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_justUploaded) ...[
            const StatusPill(
              key: Key('$_k.uploaded'),
              label: 'ID document sent for verification',
              tone: StatusTone.success,
            ),
            const SizedBox(height: 12),
          ],
          Text(text, style: textTheme.bodyMedium),
          if (kyc?.documentType != null)
            _LabelValue(label: 'Document', value: kyc!.documentType!.label),
          if (kyc?.rejectionReason != null)
            _LabelValue(label: 'Reason', value: kyc!.rejectionReason!),
          if (kyc != null &&
              kyc.state == KycState.rejected &&
              !kyc.canUpload) ...[
            const SizedBox(height: 8),
            Text(
              'Only the staff member who registered this member can upload '
              'a new one.',
              style: textTheme.bodySmall,
            ),
          ],
          if (kyc != null && kyc.canUpload) ...[
            const SizedBox(height: 16),
            GradientButton(
              key: const Key('$_k.upload'),
              onPressed: _startUpload,
              child: Text(kyc.state == KycState.rejected
                  ? 'Upload a new ID document'
                  : 'Upload ID document'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _uploadCard() {
    final error = _uploadError;
    return Form(
      key: _formKey,
      child: GlassCard(
        key: const Key('$_k.uploadForm'),
        title: 'Upload ID document',
        icon: Icons.badge_outlined,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            KycDocumentFields(
              draft: _document,
              keyPrefix: _k,
              pickImage: widget.pickImage,
              acceptDrops: widget.acceptDrops,
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              ErrorBanner(key: const Key('$_k.uploadError'), message: error),
            ],
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  key: const Key('$_k.cancelUpload'),
                  onPressed: _sending ? null : _cancelUpload,
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                GradientButton(
                  key: const Key('$_k.sendUpload'),
                  onPressed: _sending ? null : _upload,
                  child: _sending
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppGradients.of(context).onButton,
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Text('Uploading…'),
                          ],
                        )
                      : const Text('Upload ID document'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LabelValue extends StatelessWidget {
  const _LabelValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
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

class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      key: const Key('memberDetails.loadError'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(message, style: TextStyle(color: scheme.error)),
        TextButton.icon(
          key: const Key('memberDetails.retry'),
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('Try again'),
        ),
      ],
    );
  }
}
