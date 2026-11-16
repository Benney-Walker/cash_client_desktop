import 'package:flutter/material.dart';

import 'app_section.dart';

/// The common layout for a page in the content area: a heading, then the
/// page's content, scrolling together.
class SectionPage extends StatelessWidget {
  const SectionPage({
    super.key,
    required this.title,
    required this.child,
    this.maxContentWidth,
  });

  final String title;
  final Widget child;

  /// Caps the width of forms and settings, which are hard to read when they
  /// stretch across a maximised window. Leave null for tables and dashboards.
  final double? maxContentWidth;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    Widget content = child;
    final maxWidth = maxContentWidth;
    if (maxWidth != null) {
      content = Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: content,
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 32),
      children: [
        Text(
          title,
          style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 24),
        content,
      ],
    );
  }
}

/// Stands in for a section whose screens haven't been built, so the sidebar
/// can be reviewed without pretending the feature exists.
class SectionPlaceholder extends StatelessWidget {
  const SectionPlaceholder({super.key, required this.section});

  final AppSection section;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return SectionPage(
      title: section.label,
      maxContentWidth: 640,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.construction_outlined, color: scheme.onSurfaceVariant),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Not built yet', style: textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      'This section will be added in a later step, once its '
                      'requirements and backend endpoints are confirmed.',
                      style: textTheme.bodyMedium
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
