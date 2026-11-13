import 'package:flutter/material.dart';

import '../theme/app_gradients.dart';

/// A small rounded square with an icon on the button gradient, used beside
/// card titles.
///
/// It uses the button gradient rather than the lighter illustration one so
/// the icon keeps enough contrast in both modes.
class GradientIconTile extends StatelessWidget {
  const GradientIconTile({super.key, required this.icon, this.size = 28});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final gradients = AppGradients.of(context);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: gradients.button,
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(icon, size: size * 0.58, color: gradients.onButton),
    );
  }
}
