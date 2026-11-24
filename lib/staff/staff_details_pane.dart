import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../auth/auth_session.dart';
import '../common/glass_card.dart';
import '../common/gradient_button.dart';
import '../common/step_flow.dart';
import 'role_tile.dart';
import 'staff_api.dart';
import 'staff_models.dart';

/// The status a staff member's tile and header show: locked first, then
/// inactive, then active.
StatusPill staffStatusPill(StaffMember member) {
  if (member.isLocked) {
    return const StatusPill(
      label: 'Locked',
      tone: StatusTone.danger,
      icon: Icons.lock_outline,
    );
  }
  if (!member.isActive) {
    return const StatusPill(label: 'Inactive', tone: StatusTone.neutral);
  }
  return const StatusPill(label: 'Active', tone: StatusTone.success);
}

/// What the details pane is showing.
enum _Mode { view, edit, roles }

/// The right side of the Staff page: one staff member's details and the
/// actions the signed-in role may take (owner decisions 24 November 2026).
///
/// Administrators: Unlock (when locked), Edit, Change roles, Release phone
/// (collectors with a registered phone), Deactivate (active, and not
/// themselves) or Reactivate. Agents: Release phone only. Deactivate and
/// Release phone ask first; the rest take effect when saved or tapped.
class StaffDetailsPane extends StatefulWidget {
  const StaffDetailsPane({
    super.key,
    required this.api,
    required this.member,
    required this.session,
    required this.onChanged,
  });

  final StaffApi api;
  final StaffMember member;
  final AuthSession session;

  /// Called with the backend's updated record after an action.
  final ValueChanged<StaffMember> onChanged;

  @override
  State<StaffDetailsPane> createState() => _StaffDetailsPaneState();
}

class _StaffDetailsPaneState extends State<StaffDetailsPane> {
  static final _phonePattern = RegExp(r'^0\d{9}$');
  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  _Mode _mode = _Mode.view;
  bool _busy = false;
  String? _error;
  String? _done;

  final _form = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _middleName = TextEditingController();
  final _lastName = TextEditingController();
  final _dateOfBirth = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _address = TextEditingController();

  Set<StaffRoleOption> _roles = {};

  StaffMember get _member => widget.member;

  bool get _isAdministrator =>
      widget.session.role == StaffRole.administrator;

  bool get _isSelf => _member.staffId == widget.session.staffId;

  bool get _canRelease => _member.isCollector && _member.hasRegisteredPhone;

  @override
  void dispose() {
    for (final c in [
      _firstName,
      _middleName,
      _lastName,
      _dateOfBirth,
      _phone,
      _email,
      _address,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _startEdit() {
    _firstName.text = _member.firstName;
    _middleName.text = _member.middleName ?? '';
    _lastName.text = _member.lastName;
    final dob = _member.dateOfBirth;
    _dateOfBirth.text = dob == null ? '' : isoDate(dob);
    _phone.text = _member.localPhoneNumber;
    _email.text = _member.email ?? '';
    _address.text = _member.residentialAddress ?? '';
    setState(() {
      _mode = _Mode.edit;
      _error = null;
      _done = null;
    });
  }

  void _startRoles() {
    setState(() {
      _roles = {..._member.roles};
      _mode = _Mode.roles;
      _error = null;
      _done = null;
    });
  }

  void _cancel() => setState(() {
        _mode = _Mode.view;
        _error = null;
      });

  /// Runs [action]; on success hands the updated record to the page,
  /// returns to the view and shows [doneMessage].
  Future<void> _run(
    Future<StaffMember> Function() action,
    String doneMessage,
  ) async {
    setState(() {
      _busy = true;
      _error = null;
      _done = null;
    });
    try {
      final updated = await action();
      if (!mounted) return;
      widget.onChanged(updated);
      setState(() {
        _mode = _Mode.view;
        _done = doneMessage;
      });
    } catch (error) {
      if (mounted) setState(() => _error = staffActionErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final middle = _middleName.text.trim();
    final update = StaffProfileUpdate(
      firstName: _firstName.text.trim(),
      middleName: middle.isEmpty ? null : middle,
      lastName: _lastName.text.trim(),
      dateOfBirth: parseIsoDate(_dateOfBirth.text)!,
      phoneNumber: _phone.text,
      email: _email.text.trim(),
      residentialAddress: _address.text.trim(),
    );
    await _run(
      () => widget.api.updateProfile(_member.staffId, update),
      'Details saved.',
    );
  }

  Future<void> _saveRoles() async {
    if (_roles.isEmpty) {
      setState(() => _error = 'Choose at least one role.');
      return;
    }
    await _run(
      () => widget.api.updateRoles(_member.staffId, _roles),
      'Roles changed.',
    );
  }

  Future<void> _deactivate() async {
    final ok = await _confirm(
      title: 'Deactivate ${_member.fullName}?',
      body: "They will be signed out everywhere and can't sign in until an "
          'administrator reactivates them.',
      action: 'Deactivate',
    );
    if (!ok) return;
    await _run(
      () => widget.api.deactivate(_member.staffId),
      '${_member.fullName} is deactivated.',
    );
  }

  Future<void> _releasePhone() async {
    final ok = await _confirm(
      title: "Release ${_member.fullName}'s phone?",
      body: 'They will be signed out everywhere. The next phone they sign in '
          'on becomes their registered phone.',
      action: 'Release phone',
    );
    if (!ok) return;
    await _run(() async {
      await widget.api.releaseDevice(_member.staffId);
      // The release answers with no body; read the record back so the page
      // shows no registered phone. If that read fails, the release still
      // happened, so show the record without the phone.
      try {
        return await widget.api.fetchStaff(_member.staffId);
      } catch (_) {
        return _member.withoutRegisteredPhone();
      }
    }, 'Phone released. Their next sign-in registers a phone.');
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String action,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('staff.confirmDialog'),
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            key: const Key('staff.confirmCancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('staff.confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return result ?? false;
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

    return SingleChildScrollView(
      key: const Key('staff.details'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _member.fullName,
                      key: const Key('staff.name'),
                      style: textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      _member.staffId,
                      style: textTheme.bodyMedium
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              staffStatusPill(_member),
            ],
          ),
          const SizedBox(height: 12),
          if (_mode == _Mode.view) _actions(),
          if (_done != null) ...[
            const SizedBox(height: 12),
            Row(
              key: const Key('staff.done'),
              children: [
                Icon(Icons.check_circle_outline, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(_done!)),
              ],
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            ErrorBanner(key: const Key('staff.error'), message: _error!),
          ],
          const SizedBox(height: 16),
          switch (_mode) {
            _Mode.view => _details(),
            _Mode.edit => _editForm(),
            _Mode.roles => _rolesForm(),
          },
        ],
      ),
    );
  }

  Widget _actions() {
    final buttons = <Widget>[
      if (_isAdministrator && _member.isLocked)
        FilledButton.tonalIcon(
          key: const Key('staff.unlock'),
          onPressed: _busy
              ? null
              : () => _run(
                    () => widget.api.unlock(_member.staffId),
                    '${_member.fullName} can sign in again.',
                  ),
          icon: const Icon(Icons.lock_open_outlined),
          label: const Text('Unlock'),
        ),
      if (_isAdministrator)
        OutlinedButton.icon(
          key: const Key('staff.edit'),
          onPressed: _busy ? null : _startEdit,
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Edit details'),
        ),
      if (_isAdministrator)
        OutlinedButton.icon(
          key: const Key('staff.roles'),
          onPressed: _busy ? null : _startRoles,
          icon: const Icon(Icons.badge_outlined),
          label: const Text('Change roles'),
        ),
      if (_canRelease)
        OutlinedButton.icon(
          key: const Key('staff.release'),
          onPressed: _busy ? null : _releasePhone,
          icon: const Icon(Icons.phonelink_erase_outlined),
          label: const Text('Release phone'),
        ),
      if (_isAdministrator && _member.isActive && !_isSelf)
        OutlinedButton.icon(
          key: const Key('staff.deactivate'),
          onPressed: _busy ? null : _deactivate,
          icon: const Icon(Icons.person_off_outlined),
          label: const Text('Deactivate'),
        ),
      if (_isAdministrator && !_member.isActive)
        OutlinedButton.icon(
          key: const Key('staff.reactivate'),
          onPressed: _busy
              ? null
              : () => _run(
                    () => widget.api.reactivate(_member.staffId),
                    '${_member.fullName} is active again.',
                  ),
          icon: const Icon(Icons.person_outline),
          label: const Text('Reactivate'),
        ),
    ];
    if (buttons.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 8, runSpacing: 8, children: buttons);
  }

  Widget _details() {
    final dob = _member.dateOfBirth;
    final rows = <(String, String)>[
      ('Roles', _member.rolesLabel.isEmpty ? '—' : _member.rolesLabel),
      ('Branch', _member.branchName ?? '—'),
      ('Phone', _member.phoneNumber ?? '—'),
      ('Email', _member.email ?? '—'),
      ('Date of birth', dob == null ? '—' : isoDate(dob)),
      ('Address', _member.residentialAddress ?? '—'),
      if (_member.isCollector)
        (
          'Registered phone',
          _member.deviceRegisteredAt == null
              ? 'None yet. Their next sign-in registers one.'
              : 'Since ${dateAndTime(_member.deviceRegisteredAt!.toLocal())}',
        ),
      if (_member.isLocked)
        (
          'Locked',
          'Since ${dateAndTime(_member.lockedAt!.toLocal())} '
              'after 5 wrong passwords',
        ),
    ];
    return GlassCard(
      key: const Key('staff.detailsCard'),
      title: 'Details',
      icon: Icons.badge_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 150,
                    child: Text(
                      label,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ),
                  Expanded(
                    child: Text(value, key: Key('staff.field.$label')),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String? _required(String? value, String message) =>
      value == null || value.trim().isEmpty ? message : null;

  Widget _editForm() {
    return Form(
      key: _form,
      child: GlassCard(
        key: const Key('staff.editForm'),
        title: 'Edit details',
        icon: Icons.edit_outlined,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    key: const Key('staff.firstName'),
                    controller: _firstName,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'First name'),
                    validator: (v) => _required(v, 'Enter the first name'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    key: const Key('staff.middleName'),
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
                    key: const Key('staff.lastName'),
                    controller: _lastName,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Last name'),
                    validator: (v) => _required(v, 'Enter the last name'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    key: const Key('staff.dateOfBirth'),
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
                        key: const Key('staff.pickDate'),
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
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    key: const Key('staff.phone'),
                    controller: _phone,
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
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('staff.email'),
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Enter the email address';
                }
                return _emailPattern.hasMatch(value.trim())
                    ? null
                    : 'Enter a valid email address';
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('staff.address'),
              controller: _address,
              textCapitalization: TextCapitalization.words,
              decoration:
                  const InputDecoration(labelText: 'Residential address'),
              validator: (v) => _required(v, 'Enter the residential address'),
            ),
            const SizedBox(height: 12),
            const InfoNote(
              text: "The branch and roles aren't changed here. Use Change "
                  'roles for roles.',
            ),
            const SizedBox(height: 16),
            _saveRow(_save),
          ],
        ),
      ),
    );
  }

  Widget _rolesForm() {
    return GlassCard(
      key: const Key('staff.rolesForm'),
      title: 'Change roles',
      icon: Icons.badge_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (final role in StaffRoleOption.values) ...[
                if (role != StaffRoleOption.values.first)
                  const SizedBox(width: 12),
                Expanded(
                  child: RoleTile(
                    keyPrefix: 'staffRoles',
                    role: role,
                    selected: _roles.contains(role),
                    onTap: () => setState(() {
                      _roles = StaffRoleOption.toggle(_roles, role);
                      _error = null;
                    }),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          const InfoNote(
            text: "A collector can't have another role, and each branch has "
                'one active agent. The new roles apply from their next action '
                'in the app.',
          ),
          const SizedBox(height: 16),
          _saveRow(_saveRoles),
        ],
      ),
    );
  }

  Widget _saveRow(Future<void> Function() onSave) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          key: const Key('staff.cancel'),
          onPressed: _busy ? null : _cancel,
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 8),
        GradientButton(
          key: const Key('staff.save'),
          onPressed: _busy ? null : onSave,
          child: _busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
