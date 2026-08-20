import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peero/widgets/radar_pulse.dart';

void main() {
  Future<void> pumpRadar(WidgetTester tester, {double? coreDiameter}) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: coreDiameter == null
                ? const RadarPulse()
                : RadarPulse(coreDiameter: coreDiameter),
          ),
        ),
      ),
    );
  }

  testWidgets('sizes itself to 1.6x the core so rings have room', (
    tester,
  ) async {
    await pumpRadar(tester, coreDiameter: 50);

    expect(tester.getSize(find.byType(RadarPulse)), const Size(80, 80));
  });

  testWidgets('defaults to a 70px core', (tester) async {
    await pumpRadar(tester);

    expect(tester.getSize(find.byType(RadarPulse)), const Size(112, 112));
  });

  testWidgets('draws three staggered rings plus the core', (tester) async {
    await pumpRadar(tester);

    expect(find.byType(Opacity), findsNWidgets(3));
    expect(
      find.descendant(
        of: find.byType(Opacity),
        matching: find.byType(Transform),
      ),
      findsNWidgets(3),
    );
  });

  testWidgets('keeps animating frame after frame', (tester) async {
    await pumpRadar(tester);

    final first = tester
        .widgetList<Opacity>(find.byType(Opacity))
        .map((o) => o.opacity)
        .toList();

    await tester.pump(const Duration(milliseconds: 600));

    final later = tester
        .widgetList<Opacity>(find.byType(Opacity))
        .map((o) => o.opacity)
        .toList();

    expect(later, isNot(first));
  });

  testWidgets('ring opacity stays within bounds across a full cycle', (
    tester,
  ) async {
    await pumpRadar(tester);

    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      for (final opacity
          in tester
              .widgetList<Opacity>(find.byType(Opacity))
              .map((o) => o.opacity)) {
        expect(opacity, inInclusiveRange(0.0, 1.0));
      }
    }
  });

  testWidgets('disposes its controller with the widget', (tester) async {
    await pumpRadar(tester);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(RadarPulse), findsNothing);
  });
}
