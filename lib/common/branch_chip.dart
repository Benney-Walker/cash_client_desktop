import 'package:flutter/material.dart';

/// "Tarkwa branch only" beside a page title (option B2, owner decision 24
/// November 2026): shown to Agents on pages the backend limits to their
/// branch, so they know the list isn't the whole credit union.
class BranchScopeChip extends StatelessWidget {
  const BranchScopeChip({super.key, required this.branchName});

  final String branchName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Showing $branchName branch only',
      excludeSemantics: true,
      child: Container(
        key: const Key('branchScope'),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.account_balance_outlined,
                size: 16, color: scheme.onPrimaryContainer),
            const SizedBox(width: 6),
            Text(
              '$branchName branch only',
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(color: scheme.onPrimaryContainer),
            ),
          ],
        ),
      ),
    );
  }
}

/// A page title with the branch chip after it when [scopeBranch] is set.
class PageTitle extends StatelessWidget {
  const PageTitle(this.title, {super.key, this.scopeBranch});

  final String title;
  final String? scopeBranch;

  @override
  Widget build(BuildContext context) {
    final branch = scopeBranch;
    return Row(
      children: [
        Flexible(
          child: Text(
            title,
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        if (branch != null) ...[
          const SizedBox(width: 12),
          BranchScopeChip(branchName: branch),
        ],
      ],
    );
  }
}
