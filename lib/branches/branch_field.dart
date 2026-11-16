import 'package:flutter/material.dart';

import '../api/api_exception.dart';
import 'branch.dart';

/// A branch dropdown inside a [Form], with its loading and error states.
///
/// While [branches] is null it shows a spinner ([loading]) or, after a
/// failure, the problem and a "Try again" button. A list that can't be
/// loaded still blocks the form, so the step can't be left without a branch.
class BranchField extends StatelessWidget {
  const BranchField({
    super.key,
    required this.keyPrefix,
    required this.branches,
    required this.loading,
    required this.error,
    required this.onRetry,
    required this.value,
    required this.onChanged,
    required this.neededTo,
  });

  /// For test keys: `<keyPrefix>.branch`, `<keyPrefix>.branchesLoading`,
  /// `<keyPrefix>.branchesError` and `<keyPrefix>.retryBranches`.
  final String keyPrefix;
  final List<Branch>? branches;
  final bool loading;
  final Object? error;
  final VoidCallback onRetry;
  final Branch? value;
  final ValueChanged<Branch?> onChanged;

  /// Completes "Branches are needed to …", such as "add staff".
  final String neededTo;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final list = branches;

    if (loading && list == null) {
      return Row(
        key: Key('$keyPrefix.branchesLoading'),
        children: const [
          SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 10),
          Text('Loading branches…'),
        ],
      );
    }
    if (list == null) {
      final failure = error;
      final notOffered =
          failure is ApiException && failure.failure == ApiFailure.notFound;
      return Column(
        key: Key('$keyPrefix.branchesError'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FormField<Branch>(
            validator: (_) => 'Branches are needed to $neededTo',
            builder: (field) => Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline, size: 20, color: scheme.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    notOffered
                        ? "Branches can't be loaded: the server doesn't "
                            'offer the branch list yet.'
                        : "Branches couldn't be loaded. Check your "
                            'connection and try again.',
                    style: textTheme.bodyMedium?.copyWith(color: scheme.error),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          TextButton.icon(
            key: Key('$keyPrefix.retryBranches'),
            onPressed: loading ? null : onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ],
      );
    }
    return DropdownButtonFormField<Branch>(
      key: Key('$keyPrefix.branch'),
      initialValue: value,
      decoration: const InputDecoration(labelText: 'Branch'),
      disabledHint: const Text('No branches have been set up yet'),
      items: [
        for (final branch in list)
          DropdownMenuItem(value: branch, child: Text(branch.label)),
      ],
      onChanged: onChanged,
      validator: (value) => value == null ? 'Choose a branch' : null,
    );
  }
}
