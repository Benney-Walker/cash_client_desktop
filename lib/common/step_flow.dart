import 'package:flutter/material.dart';

import '../theme/app_gradients.dart';
import '../theme/app_status_colors.dart';

// Pieces shared by the step-by-step forms (Add staff, Register member).
// Each takes a [keyPrefix] so tests can find its parts, for example
// `addStaff.step2` or `registerMember.edit.Personal`.

/// The row of numbered steps above the card: done steps get a check, the
/// current one the gradient.
class StepIndicator extends StatelessWidget {
  const StepIndicator({
    super.key,
    required this.titles,
    required this.current,
    required this.keyPrefix,
  });

  final List<String> titles;
  final int current;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final gradients = AppGradients.of(context);

    return Semantics(
      label: 'Step ${current + 1} of ${titles.length}: ${titles[current]}',
      child: ExcludeSemantics(
        child: Row(
          children: [
            for (var i = 0; i < titles.length; i++) ...[
              if (i > 0)
                Expanded(
                  child: Divider(
                    indent: 8,
                    endIndent: 8,
                    color: i <= current ? scheme.primary : scheme.outline,
                  ),
                ),
              Row(
                key: Key('$keyPrefix.step$i'),
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: i == current ? gradients.button : null,
                      color: i < current ? scheme.primaryContainer : null,
                      border: i > current
                          ? Border.all(color: scheme.outline, width: 1.5)
                          : null,
                    ),
                    child: i < current
                        ? Icon(Icons.check,
                            size: 16, color: scheme.onPrimaryContainer)
                        : Text(
                            '${i + 1}',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: i == current
                                  ? gradients.onButton
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    titles[i],
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight:
                          i == current ? FontWeight.w600 : FontWeight.w400,
                      color: i == current
                          ? scheme.onSurface
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One titled block of label/value rows on a review step, with an Edit
/// link back to the step it came from.
class ReviewSection extends StatelessWidget {
  const ReviewSection({
    super.key,
    required this.title,
    required this.rows,
    required this.onEdit,
    required this.keyPrefix,
  });

  final String title;
  final List<(String, String)> rows;
  final VoidCallback onEdit;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: textTheme.labelLarge)),
              TextButton(
                key: Key('$keyPrefix.edit.$title'),
                onPressed: onEdit,
                child: const Text('Edit'),
              ),
            ],
          ),
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 130,
                    child: Text(
                      label,
                      style: textTheme.bodyMedium
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                  Expanded(child: Text(value, style: textTheme.bodyMedium)),
                ],
              ),
            ),
          const Divider(height: 12),
        ],
      ),
    );
  }
}

/// A neutral information box with an icon.
class InfoNote extends StatelessWidget {
  const InfoNote({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final status = AppStatusColors.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: status.neutralContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 20, color: status.neutral),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: status.neutral),
            ),
          ),
        ],
      ),
    );
  }
}

/// A failed request, announced to screen readers, with an optional button
/// that takes the user to where the problem can be fixed.
class ErrorBanner extends StatelessWidget {
  const ErrorBanner({
    super.key,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.actionKey,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Key? actionKey;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = actionLabel;

    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, size: 20, color: scheme.onErrorContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: scheme.onErrorContainer),
                  ),
                  if (label != null && onAction != null)
                    TextButton(
                      key: actionKey,
                      style: TextButton.styleFrom(
                        foregroundColor: scheme.onErrorContainer,
                        padding: EdgeInsets.zero,
                      ),
                      onPressed: onAction,
                      child: Text(label),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The tone of a [StatusPill].
enum StatusTone { success, warning, danger, neutral }

/// A status shown as an icon and a label, so it doesn't rely on colour
/// alone.
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.tone,
    this.icon,
  });

  final String label;
  final StatusTone tone;

  /// Replaces the tone's usual icon.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final status = AppStatusColors.of(context);
    final (background, foreground, toneIcon) = switch (tone) {
      StatusTone.success => (
          status.successContainer,
          status.success,
          Icons.check_circle,
        ),
      StatusTone.warning => (
          status.warningContainer,
          status.warning,
          Icons.schedule,
        ),
      StatusTone.danger => (
          status.dangerContainer,
          status.danger,
          Icons.cancel_outlined,
        ),
      StatusTone.neutral => (
          status.neutralContainer,
          status.neutral,
          Icons.remove_circle_outline,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon ?? toneIcon, size: 18, color: foreground),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: foreground),
          ),
        ],
      ),
    );
  }
}
