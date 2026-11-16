import 'package:flutter/material.dart';

import '../theme/app_gradients.dart';

/// The "CC" tile used next to the app name.
///
/// It sits on the button gradient rather than the lighter illustration
/// gradient, because white letters on the light cyan end would be too faint
/// to read.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    final gradients = AppGradients.of(context);

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: gradients.button,
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Text(
        'CC',
        style: TextStyle(
          color: gradients.onButton,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.36,
        ),
      ),
    );
  }
}
