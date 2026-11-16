import 'package:cash_client_desktop/common/gradient_switch.dart';
import 'package:cash_client_desktop/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<List<bool>> pumpSwitch(WidgetTester tester, bool value) async {
    final changes = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(
            child: GradientSwitch(value: value, onChanged: changes.add),
          ),
        ),
      ),
    );
    return changes;
  }

  double gradientOpacity(WidgetTester tester) =>
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity;

  testWidgets('shows the gradient track when on', (tester) async {
    await pumpSwitch(tester, true);

    expect(gradientOpacity(tester), 1);
  });

  testWidgets('hides the gradient track when off', (tester) async {
    await pumpSwitch(tester, false);

    expect(gradientOpacity(tester), 0);
  });

  testWidgets('reports a tap as the opposite value', (tester) async {
    final changes = await pumpSwitch(tester, true);

    await tester.tap(find.byType(Switch));

    expect(changes, [false]);
  });
}
