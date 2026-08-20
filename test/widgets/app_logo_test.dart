import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peero/design/colors.dart';
import 'package:peero/widgets/app_logo.dart';

void main() {
  Future<void> pumpLogo(WidgetTester tester, Widget logo) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Center(child: logo)),
      ),
    );
  }

  BoxDecoration tileDecoration(WidgetTester tester) {
    return tester
            .widget<Container>(
              find
                  .descendant(
                    of: find.byType(AppLogo),
                    matching: find.byType(Container),
                  )
                  .first,
            )
            .decoration!
        as BoxDecoration;
  }

  group('AppLogo', () {
    testWidgets('renders at the requested size', (tester) async {
      await pumpLogo(tester, const AppLogo(size: 80));

      expect(tester.getSize(find.byType(AppLogo)), const Size(80, 80));
    });

    testWidgets('defaults to an accent tile with no border', (tester) async {
      await pumpLogo(tester, const AppLogo(size: 80));

      final decoration = tileDecoration(tester);
      expect(decoration.color, AppColors.accent);
      expect(decoration.border, isNull);
    });

    testWidgets('the on-dark variant uses a bordered panel tile', (
      tester,
    ) async {
      await pumpLogo(tester, const AppLogo(size: 80, onDark: true));

      final decoration = tileDecoration(tester);
      expect(decoration.color, AppColors.panel);
      expect(decoration.border, isNotNull);
    });

    testWidgets('draws two rings and a dot', (tester) async {
      await pumpLogo(tester, const AppLogo(size: 80));

      expect(find.byType(Positioned), findsNWidgets(3));
      expect(find.byType(Opacity), findsNWidgets(2));
    });

    testWidgets('clips its contents to the tile', (tester) async {
      await pumpLogo(tester, const AppLogo(size: 80));

      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(AppLogo),
              matching: find.byType(Container),
            )
            .first,
      );

      expect(container.clipBehavior, Clip.antiAlias);
    });
  });

  group('AppLogoLockup', () {
    testWidgets('pairs the mark with the wordmark', (tester) async {
      await pumpLogo(tester, const AppLogoLockup());

      expect(find.byType(AppLogo), findsOneWidget);
      expect(find.byType(Text), findsOneWidget);
    });

    testWidgets('honours a custom icon size', (tester) async {
      await pumpLogo(tester, const AppLogoLockup(iconSize: 60));

      expect(tester.getSize(find.byType(AppLogo)), const Size(60, 60));
    });
  });
}
