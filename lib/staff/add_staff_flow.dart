import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../branches/branch_api.dart';
import '../branches/branch_field.dart';
import '../common/glass_card.dart';
import '../common/gradient_backdrop.dart';
import '../common/gradient_button.dart';
import '../common/step_flow.dart';
import '../theme/app_gradients.dart';
import 'role_tile.dart';
import 'staff_api.dart';
import 'staff_models.dart';

/// Add staff in four steps (design option F3): Personal, Contact, Role and
/// branch, then Review. Each step is checked before moving on, with the
/// same rules the backend applies, so most mistakes are caught before the
/// request is sent.
///
/// There's no password step: the backend generates a default password and
/// texts the new staff member their staff ID (owner decisions 15 November
/// 2026; CASH_CLIENT_DESKTOP.md section 16).
class AddStaffFlow extends StatefulWidget {
  const AddStaffFlow({
    super.key,
    required this.api,
    required this.branchApi,
    required this.onClose,
  });

  final StaffApi api;
  final BranchApi branchApi;

  /// Back to the Staff page.
  final VoidCallback onClose;

  @override
  State<AddStaffFlow> createState() => _AddStaffFlowState();
}

class _AddStaffFlowState extends State<AddStaffFlow> {
  static const _stepTitles = [
    'Personal',
    'Contact',
    'Role and branch',
    'Review',
  ];

  // Same rules as the backend: PhoneNumberRules (0 and nine more digits).
  static final _phonePattern = RegExp(r'^0\d{9}$');
  // A light check only; the backend has no email format rule of its own.
  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  final _formKeys = List.generate(3, (_) => GlobalKey<FormState>());
  final _firstName = TextEditingController();
  final _middleName = TextEditingController();
  final _lastName = TextEditingController();
  final _dateOfBirth = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _address = TextEditingController();

  int _step = 0;
  Set<StaffRoleOption> _roles = {};
  Branch? _branch;

  List<Branch>? _branches;
  Object? _branchError;
  bool _loadingBranches = false;

  bool _submitting = false;
  String? _submitError;
  AddStaffStep? _submitErrorStep;
  NewStaff? _added;

  @override
  void initState() {
    super.initState();
    _loadBranches();
  }

  @override
  void dispose() {
    for (final controller in [
      _firstName,
      _middleName,
      _lastName,
      _dateOfBirth,
      _phone,
      _email,
      _address,
    ]) {
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
        // Keep the choice if it's still offered.
        if (_branch != null && !branches.contains(_branch)) _branch = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _branchError = error);
    } finally {
      if (mounted) setState(() => _loadingBranches = false);
    }
  }

  bool get _dirty =>
      _added == null &&
      ([
            _firstName,
            _middleName,
            _lastName,
            _dateOfBirth,
            _phone,
            _email,
            _address,
          ].any((c) => c.text.trim().isNotEmpty) ||
          _roles.isNotEmpty ||
          _branch != null);

  NewStaff _buildStaff() => NewStaff(
        firstName: _firstName.text.trim(),
        middleName: _middleName.text.trim(),
        lastName: _lastName.text.trim(),
        dateOfBirth: parseIsoDate(_dateOfBirth.text)!,
        phoneNumber: _phone.text.trim(),
        email: _email.text.trim(),
        residentialAddress: _address.text.trim(),
        roles: _roles,
        branch: _branch!,
      );

  void _next() {
    if (!_formKeys[_step].currentState!.validate()) return;
    setState(() => _step++);
  }

  void _back() {
    if (_step == 0) {
      _leave();
    } else {
      setState(() => _step--);
    }
  }

  void _goTo(AddStaffStep step) => setState(() {
        _step = step.index;
        _submitError = null;
        _submitErrorStep = null;
      });

  Future<void> _leave() async {
    if (_dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Discard this new staff member?'),
          content: const Text("What you've entered so far won't be saved."),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep editing'),
            ),
            TextButton(
              key: const Key('addStaff.discard'),
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
    final staff = _buildStaff();
    setState(() {
      _submitting = true;
      _submitError = null;
      _submitErrorStep = null;
    });
    try {
      await widget.api.addStaff(staff);
      if (!mounted) return;
      setState(() => _added = staff);
    } catch (error) {
      if (!mounted) return;
      final (message, step) = addStaffErrorMessage(error);
      setState(() {
        _submitError = message;
        _submitErrorStep = step;
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _addAnother() {
    for (final controller in [
      _firstName,
      _middleName,
      _lastName,
      _dateOfBirth,
      _phone,
      _email,
      _address,
    ]) {
      controller.clear();
    }
    setState(() {
      _step = 0;
      _roles = {};
      _branch = null;
      _added = null;
      _submitError = null;
      _submitErrorStep = null;
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

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final added = _added;

    return Stack(
      children: [
        const Positioned.fill(child: PageGlows()),
        ListView(
          padding: const EdgeInsets.fromLTRB(32, 20, 32, 32),
          children: [
            Row(
              children: [
                TextButton(
                  key: const Key('addStaff.breadcrumb'),
                  onPressed: added == null ? _leave : widget.onClose,
                  child: const Text('Staff'),
                ),
                Icon(Icons.chevron_right,
                    size: 18, color: scheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(
                  'Add staff',
                  style: textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
            Text(
              'Add staff',
              style: textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: added != null
                    ? _AddedCard(
                        staff: added,
                        onAddAnother: _addAnother,
                        onDone: widget.onClose,
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          StepIndicator(
                            titles: _stepTitles,
                            current: _step,
                            keyPrefix: 'addStaff',
                          ),
                          const SizedBox(height: 20),
                          _buildStep(context),
                          const SizedBox(height: 20),
                          _buildButtons(),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildButtons() {
    final onButton = AppGradients.of(context).onButton;
    final last = _step == _stepTitles.length - 1;

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        OutlinedButton(
          key: const Key('addStaff.back'),
          onPressed: _submitting ? null : _back,
          child: Text(_step == 0 ? 'Cancel' : 'Back'),
        ),
        const SizedBox(width: 12),
        GradientButton(
          key: const Key('addStaff.next'),
          onPressed: _submitting ? null : (last ? _submit : _next),
          child: !last
              ? const Text('Next')
              : _submitting
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: onButton,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text('Adding…'),
                      ],
                    )
                  : const Text('Add staff'),
        ),
      ],
    );
  }

  Widget _buildStep(BuildContext context) {
    return switch (_step) {
      0 => _personalStep(),
      1 => _contactStep(),
      2 => _roleAndBranchStep(context),
      _ => _reviewStep(context),
    };
  }

  static String? _required(String? value, String message) =>
      (value == null || value.trim().isEmpty) ? message : null;

  Widget _personalStep() {
    return Form(
      key: _formKeys[0],
      child: GlassCard(
        key: const Key('addStaff.personal'),
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
                    key: const Key('addStaff.firstName'),
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
                    key: const Key('addStaff.middleName'),
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
                    key: const Key('addStaff.lastName'),
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
                key: const Key('addStaff.dateOfBirth'),
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
                    key: const Key('addStaff.pickDate'),
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
        key: const Key('addStaff.contact'),
        title: 'Contact',
        icon: Icons.phone_outlined,
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    key: const Key('addStaff.phone'),
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
                    key: const Key('addStaff.email'),
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      hintText: 'name@example.com',
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Enter the email address';
                      }
                      return _emailPattern.hasMatch(value.trim())
                          ? null
                          : 'Enter a valid email address';
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('addStaff.address'),
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

  Widget _roleAndBranchStep(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Form(
      key: _formKeys[2],
      child: GlassCard(
        key: const Key('addStaff.roleAndBranch'),
        title: 'Role and branch',
        icon: Icons.badge_outlined,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Roles', style: textTheme.labelLarge),
            const SizedBox(height: 8),
            FormField<Set<StaffRoleOption>>(
              initialValue: _roles,
              validator: (_) =>
                  _roles.isEmpty ? 'Choose at least one role' : null,
              builder: (field) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      for (final role in StaffRoleOption.values) ...[
                        if (role != StaffRoleOption.values.first)
                          const SizedBox(width: 12),
                        Expanded(
                          child: RoleTile(
                            keyPrefix: 'addStaff',
                            role: role,
                            selected: _roles.contains(role),
                            onTap: () {
                              setState(() {
                                _roles =
                                    StaffRoleOption.toggle(_roles, role);
                              });
                              field.didChange(_roles);
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
            _branchField(context),
            const SizedBox(height: 16),
            const InfoNote(
              key: Key('addStaff.rules'),
              text: "A collector can't have any other role. Administrator "
                  'and Agent can be combined. Each branch can have only one '
                  'active agent.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _branchField(BuildContext context) {
    return BranchField(
      keyPrefix: 'addStaff',
      branches: _branches,
      loading: _loadingBranches,
      error: _branchError,
      onRetry: _loadBranches,
      value: _branch,
      onChanged: (branch) => setState(() => _branch = branch),
      neededTo: 'add staff',
    );
  }

  Widget _reviewStep(BuildContext context) {
    final staff = _buildStaff();
    final error = _submitError;
    final errorStep = _submitErrorStep;

    return GlassCard(
      key: const Key('addStaff.review'),
      title: 'Review',
      icon: Icons.fact_check_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ReviewSection(
            keyPrefix: 'addStaff',
            title: 'Personal',
            onEdit: () => _goTo(AddStaffStep.personal),
            rows: [
              ('Name', staff.fullName),
              ('Date of birth', isoDate(staff.dateOfBirth)),
            ],
          ),
          ReviewSection(
            keyPrefix: 'addStaff',
            title: 'Contact',
            onEdit: () => _goTo(AddStaffStep.contact),
            rows: [
              ('Phone number', staff.phoneNumber),
              ('Email', staff.email),
              ('Address', staff.residentialAddress),
            ],
          ),
          ReviewSection(
            keyPrefix: 'addStaff',
            title: 'Role and branch',
            onEdit: () => _goTo(AddStaffStep.roleAndBranch),
            rows: [
              (
                'Roles',
                staff.orderedRoles.map((role) => role.label).join(', '),
              ),
              ('Branch', staff.branch.name),
            ],
          ),
          const SizedBox(height: 8),
          InfoNote(
            key: const Key('addStaff.passwordNote'),
            text: 'When you add them, the system creates a default password '
                'and texts the staff ID to ${staff.phoneNumber}. They then '
                'set their own password with the password reset.',
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            ErrorBanner(
              key: const Key('addStaff.error'),
              message: error,
              actionKey: const Key('addStaff.fixStep'),
              actionLabel: errorStep != null && errorStep != AddStaffStep.review
                  ? 'Go to ${_stepTitles[errorStep.index]}'
                  : null,
              onAction: errorStep == null ? null : () => _goTo(errorStep),
            ),
          ],
        ],
      ),
    );
  }
}

/// A role that can be ticked. Shows a checkbox as well as the colour, so the
/// choice doesn't rely on colour alone.
/// Shown after the backend accepted the new staff member.
class _AddedCard extends StatelessWidget {
  const _AddedCard({
    required this.staff,
    required this.onAddAnother,
    required this.onDone,
  });

  final NewStaff staff;
  final VoidCallback onAddAnother;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final roles = staff.orderedRoles.map((role) => role.label).join(' and ');

    return GlassCard(
      key: const Key('addStaff.added'),
      title: 'Staff added',
      icon: Icons.how_to_reg_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const StatusPill(label: 'Added', tone: StatusTone.success),
          const SizedBox(height: 12),
          Text(
            '${staff.fullName} has been added as $roles at '
            '${staff.branch.name}.',
            style: textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'Their staff ID has been sent by SMS to ${staff.phoneNumber}. '
            "They'll set their own password with the password reset.",
            style: textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton(
                key: const Key('addStaff.addAnother'),
                onPressed: onAddAnother,
                child: const Text('Add another'),
              ),
              const SizedBox(width: 12),
              GradientButton(
                key: const Key('addStaff.done'),
                onPressed: onDone,
                child: const Text('Back to staff'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
