import 'package:flutter/material.dart';

import '../theme/app_gradients.dart';
import '../theme/app_theme.dart';
import 'gradient_icon_tile.dart';

/// A frosted card: semi-transparent so the page glows show through, with a
/// gradient icon tile beside the title. Used by Settings and Add staff
/// (design option S3).
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final gradients = AppGradients.of(context);

    return Card(
      color: gradients.glassCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        side: BorderSide(color: gradients.glassCardBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                GradientIconTile(icon: icon),
                const SizedBox(width: 10),
                Text(title, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}
