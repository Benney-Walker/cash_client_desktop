import 'package:flutter/material.dart';

import '../theme/app_gradients.dart';
import 'names.dart';

/// The staff member's initials on a round gradient badge, as in the chosen
/// Settings design (S3).
///
/// It uses the button gradient with the button's text colour (white in
/// light mode, dark indigo in dark mode), a pairing the contrast tests
/// already cover.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({super.key, required this.name, this.size = 44});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final gradients = AppGradients.of(context);

    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: gradients.button,
          shape: BoxShape.circle,
        ),
        child: Text(
          initials(name),
          style: TextStyle(
            color: gradients.onButton,
            fontWeight: FontWeight.w700,
            fontSize: size * 0.36,
          ),
        ),
      ),
    );
  }
}
