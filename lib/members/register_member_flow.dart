import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_exception.dart';
import '../branches/branch_api.dart';
import '../branches/branch_field.dart';
import '../common/glass_card.dart';
import '../common/gradient_backdrop.dart';
import '../common/gradient_button.dart';
import '../common/step_flow.dart';
import '../common/uuid.dart';
import '../theme/app_gradients.dart';
import '../theme/app_theme.dart';
import 'kyc_image_picker.dart';
import 'member_api.dart';
import 'member_models.dart';

/// Register member in five steps (design option M1): Personal, Contact and
/// work, Account, ID document, then Review.
///
/// Registering is two backend calls: add-member, which returns the new
/// member's id, then the ID document upload. The ID step can be skipped
/// (owner decision 16 November 2026). If the upload fails after the member
/// was created, the flow stays on the ID document alone, so the member is
/// never registered twice.
class RegisterMemberFlow extends StatefulWidget {
  const RegisterMemberFlow({
    super.key,
    required this.api,
    required this.branchApi,
    required this.onClose,
    this.pickImage = pickKycImageFile,
  });

  final MemberApi api;
  final BranchApi branchApi;

  /// Back to the Members page.
  final VoidCallback onClose;

  /// Replaced in tests; the real one opens the system file dialog.
  final PickKycImage pickImage;

  @override
  State<RegisterMemberFlow> createState() => _RegisterMemberFlowState();
}

class _RegisterMemberFlowState extends State<RegisterMemberFlow> {
  static const _k = 'registerMember';
  static const _stepTitles = [
    'Personal',
    'Contact and work',
    'Account',
    'ID document',
    'Review',
  ];

  // Same rule as the backend: PhoneNumberRules (0 and nine more digits).
  static final _phonePattern = RegExp(r'^0\d{9}$');

  final _formKeys = List.generate(4, (_) => GlobalKey<FormState>());
  final _firstName = TextEditingController();
  final _middleName = TextEditingController();
  final _lastName = TextEditingController();
  final _dateOfBirth = TextEditingController();
  final _phone = TextEditingController();
  final _occupation = TextEditingController();
  final _address = TextEditingController();
  final _idNumber = TextEditingController();

  List<TextEditingController> get _controllers => [
        _firstName,
        _middleName,
        _lastName,
        _dateOfBirth,
        _phone,
        _occupation,
        _address,
        _idNumber,
      ];

  int _step = 0;
  MemberAccountType? _accountType;
  Branch? _branch;
  KycDocumentType? _documentType;
  KycImage? _image;
  String? _imageProblem;
  bool _skipId = false;

  List<Branch>? _branches;
  Object? _branchError;
  bool _loadingBranches = false;

  bool _submitting = false;
  String? _submitError;
  RegisterMemberStep? _submitErrorStep;

  /// One key per registration, reused on every retry (section 15). Cleared
  /// when the details are edited after a failure the backend answered.
  String? _idempotencyKey;

  /// An attempt of this registration ended without an answer, so the
  /// member may already exist.
  bool _registerOutcomeUnknown = false;

  /// Set once the backend has created the member.
  String? _memberId;
  NewMember? _registered;

  bool _kycSent = false;
  bool _kycSkipped = false;

  /// The upload after registering failed, so only the ID is shown now.
  bool _uploadFailed = false;
  String? _kycError;
  bool _kycOutcomeUnknown = false;

  @override
  void initState() {
    super.initState();
    _loadBranches();
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadBranches() async {
    setState(() {
      _loadingBranches = true;
      _branchError = null;
    });
    try {
      final branches = await widget.branchApi.fetchBranches();
      if (!mounted) return;
      setState(() {
        _branches = branches;
        if (_branch != null && !branches.contains(_branch)) _branch = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _branchError = error);
    } finally {
      if (mounted) setState(() => _loadingBranches = false);
    }
  }

  bool get _finished => _memberId != null && (_kycSent || _kycSkipped);

  bool get _dirty =>
      _memberId == null &&
      (_controllers.any((c) => c.text.trim().isNotEmpty) ||
          _accountType != null ||
          _branch != null ||
          _documentType != null ||
          _image != null);

  NewMember _buildMember() => NewMember(
        firstName: _firstName.text.trim(),
        middleName: _middleName.text.trim(),
        lastName: _lastName.text.trim(),
        dateOfBirth: parseIsoDate(_dateOfBirth.text)!,
        phoneNumber: _phone.text.trim(),
        residentialAddress: _address.text.trim(),
        occupation: _occupation.text.trim(),
        accountType: _accountType!,
        branch: _branch!,
      );

  KycDocument _buildDocument() => KycDocument(
        type: _documentType!,
        idNumber: KycDocumentType.normalize(_idNumber.text),
        image: _image!,
      );

  /// Details are about to change: a new registration needs a new key,
  /// unless an earlier attempt may have registered the member.
  void _detailsMayChange() {
    if (!_registerOutcomeUnknown) _idempotencyKey = null;
  }

  void _next() {
    if (!_formKeys[_step].currentState!.validate()) return;
    setState(() {
      if (_step == RegisterMemberStep.idDocument.index) _skipId = false;
      _step++;
    });
  }

  void _skipIdStep() {
    setState(() {
      _skipId = true;
      _step = RegisterMemberStep.review.index;
    });
  }

  void _back() {
    if (_step == 0) {
      _leave();
    } else {
      setState(() {
        _detailsMayChange();
        _step--;
      });
    }
  }

  void _goTo(RegisterMemberStep step) => setState(() {
        _detailsMayChange();
        _step = step.index;
        _submitError = null;
        _submitErrorStep = null;
      });

  Future<void> _leave() async {
    if (_dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Discard this registration?'),
          content: const Text("What you've entered so far won't be saved."),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep editing'),
            ),
            TextButton(
              key: const Key('$_k.discard'),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Discard'),
            ),
          ],
        ),
      );
      if (discard != true) return;
    }
    widget.onClose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final member = _buildMember();
    final document = _skipId ? null : _buildDocument();
    final key = _idempotencyKey ??= newUuid();
    setState(() {
      _submitting = true;
      _submitError = null;
      _submitErrorStep = null;
    });
    try {
      final memberId = await widget.api.registerMember(
        member,
        idempotencyKey: key,
      );
      if (!mounted) return;
      setState(() {
        _memberId = memberId;
        _registered = member;
        _kycSkipped = document == null;
      });
    } catch (error) {
      if (!mounted) return;
      final (message, step) = registerErrorMessage(
        error,
        afterUnknownOutcome: _registerOutcomeUnknown,
      );
      setState(() {
        if (error is ApiException && error.failure == ApiFailure.network) {
          _registerOutcomeUnknown = true;
        }
        _submitError = message;
        _submitErrorStep = step;
        _submitting = false;
      });
      return;
    }
    if (document != null) await _upload(document);
    if (mounted) setState(() => _submitting = false);
  }

  /// Sends the ID document for the member just registered.
  Future<void> _upload(KycDocument document) async {
    final memberId = _memberId!;
    setState(() {
      _submitting = true;
      _kycError = null;
    });
    try {
      await widget.api.uploadKycDocument(
        memberId: memberId,
        document: document,
      );
      if (mounted) setState(() => _kycSent = true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        if (_kycOutcomeUnknown && _alreadySubmitted(error)) {
          // The attempt that lost its answer did reach the backend.
          _kycSent = true;
          return;
        }
        if (error is ApiException && error.failure == ApiFailure.network) {
          _kycOutcomeUnknown = true;
        }
        _uploadFailed = true;
        _kycError = kycErrorMessage(error);
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  static bool _alreadySubmitted(Object error) =>
      error is ApiException &&
      error.failure == ApiFailure.conflict &&
      (error.message ?? '').toLowerCase().contains('already been submitted');

  Future<void> _retryUpload() async {
    if (_submitting) return;
    if (!_formKeys[RegisterMemberStep.idDocument.index]
        .currentState!
        .validate()) {
      return;
    }
    await _upload(_buildDocument());
  }

  void _registerAnother() {
    for (final controller in _controllers) {
      controller.clear();
    }
    setState(() {
      _step = 0;
      _accountType = null;
      _branch = null;
      _documentType = null;
      _image = null;
      _imageProblem = null;
      _skipId = false;
      _submitError = null;
      _submitErrorStep = null;
      _idempotencyKey = null;
      _registerOutcomeUnknown = false;
      _memberId = null;
      _registered = null;
      _kycSent = false;
      _kycSkipped = false;
      _kycError = null;
      _kycOutcomeUnknown = false;
      _uploadFailed = false;
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final current = parseIsoDate(_dateOfBirth.text);
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(1900),
      lastDate: today,
      initialDate: current != null && !current.isAfter(today)
          ? current
          : DateTime(today.year - 30, today.month, today.day),
      initialEntryMode: DatePickerEntryMode.calendar,
      helpText: 'Date of birth',
    );
    if (picked != null) {
      setState(() => _dateOfBirth.text = isoDate(picked));
    }
  }

  Future<void> _chooseImage() async {
    final result = await widget.pickImage();
    if (result == null || !mounted) return;
    final (image, problem) = result;
    setState(() {
      if (image != null) _image = image;
      _imageProblem = problem;
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final registered = _registered;

    final Widget body;
    if (registered != null && _finished) {
      body = _RegisteredCard(
        member: registered,
        kycSent: _kycSent,
        onRegisterAnother: _registerAnother,
        onDone: widget.onClose,
      );
    } else if (registered != null && _uploadFailed) {
      body = _finishIdView(context, registered);
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StepIndicator(titles: _stepTitles, current: _step, keyPrefix: _k),
          const SizedBox(height: 20),
          _buildStep(context),
          const SizedBox(height: 20),
          _buildButtons(),
        ],
      );
    }

    return Stack(
      children: [
        const Positioned.fill(child: PageGlows()),
        ListView(
          padding: const EdgeInsets.fromLTRB(32, 20, 32, 32),
          children: [
            Row(
              children: [
                TextButton(
                  key: const Key('$_k.breadcrumb'),
                  onPressed: _memberId == null ? _leave : widget.onClose,
                  child: const Text('Members'),
                ),
                Icon(Icons.chevron_right,
                    size: 18, color: scheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(
                  'Register member',
                  style: textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
            Text(
              'Register member',
              style: textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                // Wider than Add staff: five step titles have to fit.
                constraints: const BoxConstraints(maxWidth: 760),
                child: body,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _busyLabel(String text) {
    return Row(
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
        Text(text),
      ],
    );
  }

  Widget _buildButtons() {
    final last = _step == _stepTitles.length - 1;
    final onIdStep = _step == RegisterMemberStep.idDocument.index;

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        OutlinedButton(
          key: const Key('$_k.back'),
          onPressed: _submitting ? null : _back,
          child: Text(_step == 0 ? 'Cancel' : 'Back'),
        ),
        if (onIdStep) ...[
          const SizedBox(width: 12),
          TextButton(
            key: const Key('$_k.skipId'),
            onPressed: _skipIdStep,
            child: const Text('Skip for now'),
          ),
        ],
        const SizedBox(width: 12),
        GradientButton(
          key: const Key('$_k.next'),
          onPressed: _submitting ? null : (last ? _submit : _next),
          child: !last
              ? const Text('Next')
              : _submitting
                  ? _busyLabel('Registering…')
                  : const Text('Register member'),
        ),
      ],
    );
  }

  Widget _buildStep(BuildContext context) {
    return switch (RegisterMemberStep.values[_step]) {
      RegisterMemberStep.personal => _personalStep(),
      RegisterMemberStep.contactAndWork => _contactStep(),
      RegisterMemberStep.account => _accountStep(context),
      RegisterMemberStep.idDocument => _idStep(context),
      RegisterMemberStep.review => _reviewStep(),
    };
  }

  static String? _required(String? value, String message) =>
      (value == null || value.trim().isEmpty) ? message : null;

  Widget _personalStep() {
    return Form(
      key: _formKeys[0],
      child: GlassCard(
        key: const Key('$_k.personal'),
        title: 'Personal details',
        icon: Icons.person_outline,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    key: const Key('$_k.firstName'),
                    controller: _firstName,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'First name'),
                    validator: (v) => _required(v, 'Enter the first name'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    key: const Key('$_k.middleName'),
                    controller: _middleName,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Middle name (optional)',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    key: const Key('$_k.lastName'),
                    controller: _lastName,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Last name'),
                    validator: (v) => _required(v, 'Enter the last name'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: 260,
              child: TextFormField(
                key: const Key('$_k.dateOfBirth'),
                controller: _dateOfBirth,
                keyboardType: TextInputType.datetime,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9-]')),
                  LengthLimitingTextInputFormatter(10),
                ],
                decoration: InputDecoration(
                  labelText: 'Date of birth',
                  hintText: 'yyyy-mm-dd',
                  suffixIcon: IconButton(
                    key: const Key('$_k.pickDate'),
                    tooltip: 'Choose a date',
                    icon: const Icon(Icons.calendar_today_outlined),
                    onPressed: _pickDate,
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Enter the date of birth';
                  }
                  final date = parseIsoDate(value);
                  if (date == null) return 'Use the format yyyy-mm-dd';
                  if (date.isAfter(DateTime.now())) {
                    return "The date of birth can't be in the future";
                  }
                  return null;
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _contactStep() {
    return Form(
      key: _formKeys[1],
      child: GlassCard(
        key: const Key('$_k.contact'),
        title: 'Contact and work',
        icon: Icons.phone_outlined,
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    key: const Key('$_k.phone'),
                    controller: _phone,
                    autofocus: true,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Phone number',
                      hintText: '0241234567',
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Enter the phone number';
                      }
                      return _phonePattern.hasMatch(value)
                          ? null
                          : 'Use 10 digits starting with 0';
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    key: const Key('$_k.occupation'),
                    controller: _occupation,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Occupation',
                      hintText: 'Trader',
                    ),
                    validator: (v) => _required(v, 'Enter the occupation'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('$_k.address'),
              controller: _address,
              textCapitalization: TextCapitalization.words,
              decoration:
                  const InputDecoration(labelText: 'Residential address'),
              validator: (v) => _required(v, 'Enter the residential address'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _accountStep(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Form(
      key: _formKeys[2],
      child: GlassCard(
        key: const Key('$_k.account'),
        title: 'Account',
        icon: Icons.account_balance_wallet_outlined,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Account to open with the shares account',
                style: textTheme.labelLarge),
            const SizedBox(height: 8),
            FormField<MemberAccountType>(
              initialValue: _accountType,
              validator: (_) =>
                  _accountType == null ? 'Choose Savings or Current' : null,
              builder: (field) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      for (final type in MemberAccountType.values) ...[
                        if (type != MemberAccountType.values.first)
                          const SizedBox(width: 12),
                        Expanded(
                          child: _ChoiceTile(
                            key: Key('$_k.accountType.${type.name}'),
                            label: type.label,
                            selected: _accountType == type,
                            onTap: () {
                              setState(() => _accountType = type);
                              field.didChange(type);
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (field.hasError) ...[
                    const SizedBox(height: 6),
                    Text(
                      field.errorText!,
                      style:
                          textTheme.bodySmall?.copyWith(color: scheme.error),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            BranchField(
              keyPrefix: _k,
              branches: _branches,
              loading: _loadingBranches,
              error: _branchError,
              onRetry: _loadBranches,
              value: _branch,
              onChanged: (branch) => setState(() => _branch = branch),
              neededTo: 'register members',
            ),
            const SizedBox(height: 16),
            const InfoNote(
              key: Key('$_k.accountNote'),
              text: 'Every member also gets a shares account. The member '
                  'starts as pending, and their accounts stay inactive '
                  'until their ID document is verified.',
            ),
          ],
        ),
      ),
    );
  }

  /// The ID document fields. Used as step 4, and on its own when the
  /// member is registered but the upload failed.
  Widget _idFields(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final type = _documentType;
    final image = _image;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: DropdownButtonFormField<KycDocumentType>(
                key: const Key('$_k.documentType'),
                initialValue: type,
                decoration: const InputDecoration(labelText: 'Document'),
                items: [
                  for (final option in KycDocumentType.values)
                    DropdownMenuItem(value: option, child: Text(option.label)),
                ],
                onChanged: (value) => setState(() => _documentType = value),
                validator: (value) =>
                    value == null ? 'Choose the document' : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                key: const Key('$_k.idNumber'),
                controller: _idNumber,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(50),
                  _UpperCaseFormatter(),
                ],
                decoration: InputDecoration(
                  labelText: 'ID number',
                  hintText: type?.example,
                ),
                validator: (value) => type == null
                    ? null
                    : type.problemWith(value ?? ''),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        FormField<KycImage>(
          validator: (_) =>
              _image == null ? 'Choose a picture of the ID document' : null,
          builder: (field) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (image == null)
                _ChooseImageBox(onTap: _chooseImage)
              else
                _ChosenImage(
                  image: image,
                  onReplace: _chooseImage,
                  onRemove: () => setState(() => _image = null),
                ),
              // The "choose a picture" error only matters while none is
              // chosen; it would otherwise linger until the next check.
              for (final problem in [
                _imageProblem,
                if (image == null) field.errorText,
              ])
                if (problem != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    problem,
                    key: problem == _imageProblem
                        ? const Key('$_k.imageProblem')
                        : null,
                    style: textTheme.bodySmall?.copyWith(color: scheme.error),
                  ),
                ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _idStep(BuildContext context) {
    return Form(
      key: _formKeys[3],
      child: GlassCard(
        key: const Key('$_k.idDocument'),
        title: 'ID document',
        icon: Icons.badge_outlined,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _idFields(context),
            const SizedBox(height: 16),
            const InfoNote(
              key: Key('$_k.idNote'),
              text: "If the member hasn't brought their ID, choose Skip for "
                  'now. Their accounts stay inactive until an ID document '
                  'is uploaded and verified.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _reviewStep() {
    final member = _buildMember();
    final document = _skipId ? null : _buildDocument();
    final error = _submitError;
    final errorStep = _submitErrorStep;

    return GlassCard(
      key: const Key('$_k.review'),
      title: 'Review',
      icon: Icons.fact_check_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ReviewSection(
            keyPrefix: _k,
            title: 'Personal',
            onEdit: () => _goTo(RegisterMemberStep.personal),
            rows: [
              ('Name', member.fullName),
              ('Date of birth', isoDate(member.dateOfBirth)),
            ],
          ),
          ReviewSection(
            keyPrefix: _k,
            title: 'Contact and work',
            onEdit: () => _goTo(RegisterMemberStep.contactAndWork),
            rows: [
              ('Phone number', member.phoneNumber),
              ('Occupation', member.occupation),
              ('Address', member.residentialAddress),
            ],
          ),
          ReviewSection(
            keyPrefix: _k,
            title: 'Account',
            onEdit: () => _goTo(RegisterMemberStep.account),
            rows: [
              ('Accounts', 'Shares and ${member.accountType.label}'),
              ('Branch', member.branch.name),
            ],
          ),
          ReviewSection(
            keyPrefix: _k,
            title: 'ID document',
            onEdit: () => _goTo(RegisterMemberStep.idDocument),
            rows: document == null
                ? const [('Document', 'Not added. Upload it later.')]
                : [
                    ('Document', document.type.label),
                    ('ID number', document.idNumber),
                    (
                      'Picture',
                      '${document.image.fileName} '
                          '(${document.image.type.label}, '
                          '${document.image.sizeLabel})',
                    ),
                  ],
          ),
          if (error != null) ...[
            const SizedBox(height: 4),
            ErrorBanner(
              key: const Key('$_k.error'),
              message: error,
              actionKey: const Key('$_k.fixStep'),
              actionLabel: errorStep != null &&
                      errorStep != RegisterMemberStep.review
                  ? 'Go to ${_stepTitles[errorStep.index]}'
                  : null,
              onAction: errorStep == null ? null : () => _goTo(errorStep),
            ),
          ],
        ],
      ),
    );
  }

  /// The member exists but their ID document didn't upload. Only the ID
  /// can be changed here, so retrying can't register them again.
  Widget _finishIdView(BuildContext context, NewMember member) {
    final textTheme = Theme.of(context).textTheme;
    final error = _kycError;

    return Form(
      key: _formKeys[RegisterMemberStep.idDocument.index],
      child: GlassCard(
        key: const Key('$_k.finishId'),
        title: 'Finish the ID document',
        icon: Icons.badge_outlined,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: StatusPill(label: 'Registered', tone: StatusTone.success),
            ),
            const SizedBox(height: 12),
            Text(
              '${member.fullName} is registered, but the ID document '
              "didn't upload. Fix it below and try again, or upload it "
              'later.',
              style: textTheme.bodyMedium,
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              ErrorBanner(key: const Key('$_k.kycError'), message: error),
            ],
            const SizedBox(height: 16),
            _idFields(context),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  key: const Key('$_k.uploadLater'),
                  onPressed: _submitting
                      ? null
                      : () => setState(() => _kycSkipped = true),
                  child: const Text('Upload it later'),
                ),
                const SizedBox(width: 12),
                GradientButton(
                  key: const Key('$_k.retryUpload'),
                  onPressed: _submitting ? null : _retryUpload,
                  child: _submitting
                      ? _busyLabel('Uploading…')
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

/// Capitals as the user types, the way the backend stores ID numbers.
class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) =>
      newValue.copyWith(text: newValue.text.toUpperCase());
}

/// One of a set of mutually exclusive options. Shows a radio mark as well
/// as the colour, so the choice doesn't rely on colour alone.
class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      button: true,
      child: Material(
        color: selected ? scheme.primaryContainer : scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.controlRadius),
          side: BorderSide(
            color: selected ? scheme.primary : scheme.outline,
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.controlRadius),
          onTap: onTap,
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(minHeight: AppTheme.minTouchTarget),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 20,
                    color: selected ? scheme.primary : scheme.outline,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: selected
                          ? scheme.onPrimaryContainer
                          : scheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The empty picture area: a large target that opens the file dialog.
class _ChooseImageBox extends StatelessWidget {
  const _ChooseImageBox({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: scheme.primaryContainer.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.primary, width: 1.5),
      ),
      child: InkWell(
        key: const Key('registerMember.chooseImage'),
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
          child: Column(
            children: [
              Icon(Icons.upload_file_outlined, size: 32, color: scheme.primary),
              const SizedBox(height: 8),
              Text(
                'Choose a picture of the ID',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'JPEG or PNG, 5 MB at most',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The chosen picture, with its name and size, so staff can check it's
/// the right card and readable before sending it.
class _ChosenImage extends StatelessWidget {
  const _ChosenImage({
    required this.image,
    required this.onReplace,
    required this.onRemove,
  });

  final KycImage image;
  final VoidCallback onReplace;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      key: const Key('registerMember.chosenImage'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(
              image.bytes,
              width: 180,
              height: 112,
              fit: BoxFit.cover,
              semanticLabel: 'Picture of the ID document',
              errorBuilder: (context, error, stackTrace) => Container(
                width: 180,
                height: 112,
                color: scheme.surfaceContainerHighest,
                alignment: Alignment.center,
                child: Icon(Icons.broken_image_outlined,
                    color: scheme.onSurfaceVariant),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  image.fileName,
                  style: theme.textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${image.type.label} · ${image.sizeLabel}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton(
                      key: const Key('registerMember.replaceImage'),
                      onPressed: onReplace,
                      child: const Text('Replace'),
                    ),
                    TextButton(
                      key: const Key('registerMember.removeImage'),
                      onPressed: onRemove,
                      child: const Text('Remove'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown once the member is registered and the ID step is settled.
class _RegisteredCard extends StatelessWidget {
  const _RegisteredCard({
    required this.member,
    required this.kycSent,
    required this.onRegisterAnother,
    required this.onDone,
  });

  final NewMember member;
  final bool kycSent;
  final VoidCallback onRegisterAnother;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return GlassCard(
      key: const Key('registerMember.registered'),
      title: 'Member registered',
      icon: Icons.how_to_reg_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              const StatusPill(label: 'Registered', tone: StatusTone.success),
              StatusPill(
                key: const Key('registerMember.kycStatus'),
                label: kycSent ? 'ID sent for verification' : 'ID not added',
                tone: StatusTone.warning,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${member.fullName} is registered at ${member.branch.name} with '
            'a shares account and a ${member.accountType.label.toLowerCase()} '
            'account.',
            style: textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            kycSent
                ? 'Their ID document has been sent for verification. Their '
                    'accounts become active once it is verified.'
                : 'No ID document was added. Their accounts stay inactive '
                    'until one is uploaded and verified.',
            style: textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton(
                key: const Key('registerMember.registerAnother'),
                onPressed: onRegisterAnother,
                child: const Text('Register another'),
              ),
              const SizedBox(width: 12),
              GradientButton(
                key: const Key('registerMember.done'),
                onPressed: onDone,
                child: const Text('Back to members'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
