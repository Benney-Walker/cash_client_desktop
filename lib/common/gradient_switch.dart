import 'package:flutter/material.dart';

import '../theme/app_gradients.dart';

/// A [Switch] whose track shows the button gradient when it's on (owner
/// decision: switches follow the gradient rule).
///
/// Flutter's Switch can't paint a gradient track, so this one is drawn with
/// a transparent track over a gradient pill of the same size. The Switch
/// itself still handles focus, keyboard, dragging and screen readers.
class GradientSwitch extends StatelessWidget {
  const GradientSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  // Material 3's track size.
  static const _trackSize = Size(52, 32);

  @override
  Widget build(BuildContext context) {
    final gradients = AppGradients.of(context);

    return Stack(
      alignment: Alignment.center,
      children: [
        AnimatedOpacity(
          opacity: value ? 1 : 0,
          duration: const Duration(milliseconds: 150),
          child: Container(
            width: _trackSize.width,
            height: _trackSize.height,
            decoration: BoxDecoration(
              gradient: gradients.button,
              borderRadius: BorderRadius.circular(_trackSize.height / 2),
            ),
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          trackColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? Colors.transparent
                : null,
          ),
          trackOutlineColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? Colors.transparent
                : null,
          ),
          thumbColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? gradients.onButton
                : null,
          ),
        ),
      ],
    );
  }
}
