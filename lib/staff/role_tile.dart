import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'staff_models.dart';

/// A role that can be ticked, with its hint. Shows a check mark as well as
/// the colour, so the choice doesn't rely on colour alone.
class RoleTile extends StatelessWidget {
  const RoleTile({
    super.key,
    required this.keyPrefix,
    required this.role,
    required this.selected,
    required this.onTap,
  });

  /// Test key: `<keyPrefix>.role.<name>`.
  final String keyPrefix;
  final StaffRoleOption role;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final foreground =
        selected ? scheme.onPrimaryContainer : scheme.onSurface;
    final secondary =
        selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant;

    return Semantics(
      checked: selected,
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
          key: Key('$keyPrefix.role.${role.name}'),
          borderRadius: BorderRadius.circular(AppTheme.controlRadius),
          onTap: onTap,
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(minHeight: AppTheme.minTouchTarget),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    selected
                        ? Icons.check_box
                        : Icons.check_box_outline_blank,
                    size: 20,
                    color: selected ? scheme.primary : scheme.outline,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          role.label,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: foreground,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          role.hint,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: secondary),
                        ),
                      ],
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
