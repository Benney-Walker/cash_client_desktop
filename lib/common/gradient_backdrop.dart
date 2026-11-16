import 'package:flutter/material.dart';

import '../theme/app_gradients.dart';

/// The light gradient panel background: a pale wash with soft coloured
/// glows. Used behind the sidebar and the sign-in panel.
///
/// [child] is laid out with the backdrop's own constraints and drawn on top.
class GradientBackdrop extends StatelessWidget {
  const GradientBackdrop({super.key, required this.child});

  final Widget child;

  // Where the glows sit; matched to the theme's glow colours by index.
  static const _glowCentres = [
    Alignment(-0.6, -0.7),
    Alignment(0.7, 0.5),
    Alignment(-0.7, 0.8),
  ];

  @override
  Widget build(BuildContext context) {
    final gradients = AppGradients.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(gradient: gradients.panel),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          for (var i = 0; i < gradients.panelGlows.length; i++)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: _glowCentres[i % _glowCentres.length],
                    radius: 0.9,
                    colors: [
                      gradients.panelGlows[i],
                      gradients.panelGlows[i].withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          child,
        ],
      ),
    );
  }
}

/// Faint coloured spots over the page colour, behind ordinary content such
/// as the sign-in form and Settings.
class PageGlows extends StatelessWidget {
  const PageGlows({super.key});

  static const _centres = [Alignment(0.7, -0.8), Alignment(0.2, 0.9)];

  @override
  Widget build(BuildContext context) {
    final glows = AppGradients.of(context).pageGlows;

    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: Stack(
        children: [
          for (var i = 0; i < glows.length; i++)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: _centres[i % _centres.length],
                    radius: 0.8,
                    colors: [glows[i], glows[i].withValues(alpha: 0)],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
