import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peero/screens/image_viewer_screen.dart';

import '../helpers/test_harness.dart';

void main() {
  late Directory tempDir;
  late String imagePath;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('peero_viewer_');
    imagePath = '${tempDir.path}/photo.png';
    File(imagePath).writeAsBytesSync(pngBytes());
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  testWidgets('shows the image on a black canvas', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: ImageViewerScreen(path: imagePath)),
    );

    expect(find.byType(Image), findsOneWidget);
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      Colors.black,
    );
  });

  testWidgets('allows pinch-zoom and pan within bounds', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: ImageViewerScreen(path: imagePath)),
    );

    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );

    expect(viewer.minScale, 1);
    expect(viewer.maxScale, 5);
  });

  testWidgets('can be dismissed with the back button', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ImageViewerScreen(path: imagePath),
                ),
              ),
              child: const Text('ouvrir'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();
    expect(find.byType(ImageViewerScreen), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.byType(ImageViewerScreen), findsNothing);
  });
}
