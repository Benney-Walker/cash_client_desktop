import 'package:flutter/material.dart';

import '../auth/auth_session.dart';
import '../branches/branch_api.dart';
import '../common/glass_card.dart';
import '../common/gradient_backdrop.dart';
import '../common/gradient_button.dart';
import 'add_staff_flow.dart';
import 'staff_api.dart';
import 'staff_details_pane.dart';
import 'staff_models.dart';

/// The Staff section (option St2, owner decisions 24 November 2026): the
/// staff list with search and filters on the left, the chosen staff member
/// with their details and actions on the right, and "Add staff" at the top
/// for Administrators.
///
/// Administrators can edit, change roles, deactivate, reactivate, unlock
/// and release a collector's phone. Agents see their own branch's staff
/// (the backend's list) and can only release their collectors' phones.
/// This is presentation: the backend should refuse the rest for Agents too
/// (asked in CASH_CLIENT_DESKTOP.md section 14).
class StaffPage extends StatefulWidget {
  const StaffPage({
    super.key,
    required this.session,
    required this.api,
    required this.branchApi,
  });

  final AuthSession session;
  final StaffApi api;
  final BranchApi branchApi;

  @override
  State<StaffPage> createState() => _StaffPageState();
}

/// The status filter's choices.
enum _StatusFilter { all, active, inactive, locked }

class _StaffPageState extends State<StaffPage> {
  bool _adding = false;

  List<StaffMember> _staff = const [];
  bool _loading = false;
  Object? _error;
  String? _selectedId;

  final _search = TextEditingController();
  StaffRoleOption? _roleFilter;
  _StatusFilter _statusFilter = _StatusFilter.all;

  bool get _isAdministrator =>
      widget.session.role == StaffRole.administrator;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final staff = await widget.api.listStaff();
      if (mounted) setState(() => _staff = staff);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _replace(StaffMember updated) {
    setState(() {
      _staff = [
        for (final s in _staff) s.staffId == updated.staffId ? updated : s,
      ];
    });
  }

  List<StaffMember> get _visible {
    final query = _search.text.trim().toLowerCase();
    return _staff.where((s) {
      if (query.isNotEmpty &&
          !s.fullName.toLowerCase().contains(query) &&
          !s.staffId.toLowerCase().contains(query)) {
        return false;
      }
      if (_roleFilter != null && !s.roles.contains(_roleFilter)) return false;
      return switch (_statusFilter) {
        _StatusFilter.all => true,
        _StatusFilter.active => s.isActive,
        _StatusFilter.inactive => !s.isActive,
        _StatusFilter.locked => s.isLocked,
      };
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_adding) {
      return AddStaffFlow(
        api: widget.api,
        branchApi: widget.branchApi,
        onClose: () {
          setState(() => _adding = false);
          _load();
        },
      );
    }

    final textTheme = Theme.of(context).textTheme;
    StaffMember? selected;
    for (final s in _staff) {
      if (s.staffId == _selectedId) selected = s;
    }

    return Stack(
      key: const Key('page.staff'),
      children: [
        const Positioned.fill(child: PageGlows()),
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 28, 32, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Staff',
                      style: textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (_isAdministrator)
                    GradientButton(
                      key: const Key('staff.add'),
                      onPressed: () => setState(() => _adding = true),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.person_add_alt_1_outlined),
                          SizedBox(width: 8),
                          Text('Add staff'),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 360, child: _list(context)),
                    const SizedBox(width: 24),
                    Expanded(
                      child: selected == null
                          ? const _NothingSelected()
                          : StaffDetailsPane(
                              key: ValueKey(selected.staffId),
                              api: widget.api,
                              member: selected,
                              session: widget.session,
                              onChanged: _replace,
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _list(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final error = _error;
    final visible = _visible;

    Widget body;
    if (_staff.isEmpty && _loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (error != null && _staff.isEmpty) {
      body = Column(
        key: const Key('staff.listError'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            staffActionErrorMessage(error),
            style: textTheme.bodyMedium?.copyWith(color: scheme.error),
          ),
          TextButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ],
      );
    } else if (visible.isEmpty) {
      body = Text(
        _staff.isEmpty ? 'No staff yet.' : 'No staff match these filters.',
        key: const Key('staff.empty'),
        style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      );
    } else {
      body = ListView(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Text(
              visible.length == 1 ? '1 staff member' : '${visible.length} staff',
              style: textTheme.labelMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          for (final member in visible)
            _StaffTile(
              member: member,
              selected: member.staffId == _selectedId,
              onTap: () => setState(() => _selectedId = member.staffId),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('staff.search'),
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Find staff',
            hintText: 'Name or staff ID',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<StaffRoleOption?>(
                key: const Key('staff.roleFilter'),
                initialValue: _roleFilter,
                decoration:
                    const InputDecoration(labelText: 'Role', isDense: true),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All roles')),
                  for (final role in StaffRoleOption.values)
                    DropdownMenuItem(value: role, child: Text(role.label)),
                ],
                onChanged: (role) => setState(() => _roleFilter = role),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<_StatusFilter>(
                key: const Key('staff.statusFilter'),
                initialValue: _statusFilter,
                decoration:
                    const InputDecoration(labelText: 'Status', isDense: true),
                items: const [
                  DropdownMenuItem(value: _StatusFilter.all, child: Text('All')),
                  DropdownMenuItem(
                      value: _StatusFilter.active, child: Text('Active')),
                  DropdownMenuItem(
                      value: _StatusFilter.inactive, child: Text('Inactive')),
                  DropdownMenuItem(
                      value: _StatusFilter.locked, child: Text('Locked')),
                ],
                onChanged: (status) => setState(
                    () => _statusFilter = status ?? _StatusFilter.all),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(child: body),
      ],
    );
  }
}

class _StaffTile extends StatelessWidget {
  const _StaffTile({
    required this.member,
    required this.selected,
    required this.onTap,
  });

  final StaffMember member;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final details = [
      member.rolesLabel,
      member.branchName,
    ].whereType<String>().where((s) => s.isNotEmpty).join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        key: Key('staff.item.${member.staffId}'),
        selected: selected,
        selectedTileColor: scheme.primaryContainer,
        selectedColor: scheme.onPrimaryContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(member.fullName),
        subtitle: Text(
          details.isEmpty ? member.staffId : '${member.staffId} · $details',
        ),
        trailing: staffStatusPill(member),
        onTap: onTap,
      ),
    );
  }
}

class _NothingSelected extends StatelessWidget {
  const _NothingSelected();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: GlassCard(
        key: const Key('staff.nothingSelected'),
        title: 'Staff member',
        icon: Icons.badge_outlined,
        child: Text(
          'Choose someone on the left to see their details.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}
