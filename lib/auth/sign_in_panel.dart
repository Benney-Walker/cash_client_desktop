import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../common/brand_mark.dart';
import '../common/gradient_backdrop.dart';
import '../theme/app_gradients.dart';
import 'shield_illustration.dart';

/// The left side of the sign-in screen: a light gradient panel whose right
/// edge curves outward, with the app name and the shield illustration.
class SignInPanel extends StatelessWidget {
  const SignInPanel({super.key});

  /// How far the curve's ends sit inside the panel's width. The middle of
  /// the curve bulges back out to within a quarter of this from the edge.
  static const double curveDepth = 56;

  @override
  Widget build(BuildContext context) {
    final gradients = AppGradients.of(context);
    final textTheme = Theme.of(context).textTheme;

    return ClipPath(
      clipper: const _CurvedEdgeClipper(curveDepth),
      child: GradientBackdrop(
        child: Padding(
          // Extra room on the right keeps content clear of the curve.
          padding: const EdgeInsets.fromLTRB(40, 32, 40 + curveDepth, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const BrandMark(),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Cash Client',
                        style: textTheme.titleLarge?.copyWith(
                          color: gradients.panelText,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'For administrators and agents',
                        style: textTheme.bodyMedium?.copyWith(
                          color: gradients.panelTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => Center(
                    child: ShieldIllustration(
                      size: math.min(
                        300,
                        math.min(
                          constraints.maxWidth * 0.7,
                          constraints.maxHeight * 0.8,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Balances the brand row so the shield sits in the middle.
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

class _CurvedEdgeClipper extends CustomClipper<Path> {
  const _CurvedEdgeClipper(this.depth);

  final double depth;

  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    final end = w - depth;
    return Path()
      ..moveTo(0, 0)
      ..lineTo(end, 0)
      ..cubicTo(w, h * 0.26, w, h * 0.74, end, h)
      ..lineTo(0, h)
      ..close();
  }

  @override
  bool shouldReclip(_CurvedEdgeClipper old) => old.depth != depth;
}
