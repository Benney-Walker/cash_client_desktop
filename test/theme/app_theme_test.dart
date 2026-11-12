import 'package:cash_client_desktop/theme/app_gradients.dart';
import 'package:cash_client_desktop/theme/app_status_colors.dart';
import 'package:cash_client_desktop/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/contrast.dart';

// Every text pairing is held to the AA text standard (4.5:1), not the 3:1
// allowed for large text, the same as in the collector app.

void main() {
  for (final entry in {
    'light': AppTheme.light,
    'dark': AppTheme.dark,
  }.entries) {
    final mode = entry.key;
    final theme = entry.value;
    final s = theme.colorScheme;
    final status = theme.extension<AppStatusColors>();

    group('$mode theme', () {
      test('has the expected brightness and status colours', () {
        expect(
          s.brightness,
          mode == 'light' ? Brightness.light : Brightness.dark,
        );
        expect(status, isNotNull);
      });

      final textPairs = <String, (Color, Color)>{
        'text on page': (s.onSurface, s.surface),
        'text on card': (s.onSurface, s.surfaceContainerLow),
        'secondary text on page': (s.onSurfaceVariant, s.surface),
        'secondary text on card': (s.onSurfaceVariant, s.surfaceContainerLow),
        'secondary text on raised': (s.onSurfaceVariant, s.surfaceContainerHigh),
        'secondary text on highest': (
          s.onSurfaceVariant,
          s.surfaceContainerHighest,
        ),
        'on primary': (s.onPrimary, s.primary),
        'on primary container': (s.onPrimaryContainer, s.primaryContainer),
        'primary on card': (s.primary, s.surfaceContainerLow),
        'on secondary': (s.onSecondary, s.secondary),
        'on secondary container': (
          s.onSecondaryContainer,
          s.secondaryContainer,
        ),
        'on error': (s.onError, s.error),
        'on error container': (s.onErrorContainer, s.errorContainer),
        'success chip': (status!.success, status.successContainer),
        'warning chip': (status.warning, status.warningContainer),
        'danger chip': (status.danger, status.dangerContainer),
        'neutral chip': (status.neutral, status.neutralContainer),
      };

      for (final pair in textPairs.entries) {
        test('${pair.key} meets $minTextContrast:1', () {
          final (fg, bg) = pair.value;
          expect(contrastRatio(fg, bg), greaterThanOrEqualTo(minTextContrast));
        });
      }

      // Text sits on every part of the hero gradient, so check each stop.
      test('hero text is readable across the whole gradient', () {
        for (final stop in status!.heroGradient.colors) {
          expect(
            contrastRatio(status.onHero, stop),
            greaterThanOrEqualTo(minTextContrast),
          );
          expect(
            contrastRatio(status.onHeroSecondary, stop),
            greaterThanOrEqualTo(minTextContrast),
          );
        }
      });

      test('input outline is visible on a card', () {
        expect(
          contrastRatio(s.outline, s.surfaceContainerLow),
          greaterThanOrEqualTo(minUiContrast),
        );
      });

      test('uses the bundled Inter font', () {
        expect(theme.textTheme.bodyMedium!.fontFamily, AppTheme.fontFamily);
        expect(theme.textTheme.titleLarge!.fontFamily, AppTheme.fontFamily);
        final buttonText = theme.filledButtonTheme.style!.textStyle!
            .resolve(<WidgetState>{});
        expect(buttonText!.fontFamily, AppTheme.fontFamily);
      });

      test('sidebar uses the gradient panel colours', () {
        // The pairings themselves are checked in app_gradients_test.dart.
        final rail = theme.navigationRailTheme;
        final g = theme.extension<AppGradients>()!;
        expect(rail.backgroundColor, Colors.transparent);
        expect(rail.indicatorColor, g.glassFill);
        expect(rail.selectedIconTheme!.color, g.panelText);
        expect(rail.selectedLabelTextStyle!.color, g.panelText);
        expect(rail.unselectedIconTheme!.color, g.panelTextSecondary);
        expect(rail.unselectedLabelTextStyle!.color, g.panelTextSecondary);
      });

      test('buttons meet the 48dp minimum height', () {
        for (final style in [
          theme.filledButtonTheme.style,
          theme.outlinedButtonTheme.style,
          theme.textButtonTheme.style,
          theme.segmentedButtonTheme.style,
        ]) {
          final size = style!.minimumSize!.resolve(<WidgetState>{});
          expect(size!.height, greaterThanOrEqualTo(AppTheme.minTouchTarget));
        }
      });
    });
  }
}
