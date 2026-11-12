import 'package:cash_client_desktop/theme/app_gradients.dart';
import 'package:cash_client_desktop/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/contrast.dart';

/// Every colour a gradient passes through at its stops and halfway between
/// neighbouring stops. Text sits on all of them somewhere.
List<Color> samples(LinearGradient gradient) {
  final colors = gradient.colors;
  return [
    for (var i = 0; i < colors.length; i++) ...[
      colors[i],
      if (i + 1 < colors.length) Color.lerp(colors[i], colors[i + 1], 0.5)!,
    ],
  ];
}

/// The panel's possible backgrounds: its base colours, with each glow laid
/// over them at full strength (the glow's centre).
List<Color> panelBackgrounds(AppGradients g) => [
      for (final base in samples(g.panel)) ...[
        base,
        for (final glow in g.panelGlows) Color.alphaBlend(glow, base),
      ],
    ];

void main() {
  for (final entry in {
    'light': AppTheme.light,
    'dark': AppTheme.dark,
  }.entries) {
    final g = entry.value.extension<AppGradients>();

    group('${entry.key} gradients', () {
      test('are registered on the theme', () {
        expect(g, isNotNull);
      });

      test('button text is readable across the whole button', () {
        for (final colour in samples(g!.button)) {
          expect(
            contrastRatio(g.onButton, colour),
            greaterThanOrEqualTo(minTextContrast),
            reason: 'on $colour',
          );
        }
      });

      test('panel text is readable anywhere on the panel', () {
        for (final background in panelBackgrounds(g!)) {
          for (final text in [g.panelText, g.panelTextSecondary]) {
            expect(
              contrastRatio(text, background),
              greaterThanOrEqualTo(minTextContrast),
              reason: '$text on $background',
            );
          }
        }
      });

      test('glass label text is readable anywhere on the panel', () {
        for (final background in panelBackgrounds(g!)) {
          final glass = Color.alphaBlend(g.glassFill, background);
          expect(
            contrastRatio(g.panelText, glass),
            greaterThanOrEqualTo(minTextContrast),
            reason: 'on $glass',
          );
        }
      });

      test('form text is readable on the page glows', () {
        final scheme = entry.value.colorScheme;
        for (final glow in g!.pageGlows) {
          final background = Color.alphaBlend(glow, scheme.surface);
          expect(
            contrastRatio(scheme.onSurfaceVariant, background),
            greaterThanOrEqualTo(minTextContrast),
          );
        }
      });
    });
  }

  test('switching theme mode blends without errors', () {
    final mid = AppGradients.light.lerp(AppGradients.dark, 0.5);
    expect(mid.panelGlows, isNotEmpty);
    expect(AppGradients.light.lerp(AppGradients.dark, 1).onButton,
        AppGradients.dark.onButton);
  });
}
