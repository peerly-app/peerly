import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:peero/utils/platform_info.dart';

void main() {
  tearDown(() => debugIsDesktopPlatformOverride = null);

  test('reports the real platform when no override is set', () {
    final expected = Platform.isMacOS || Platform.isWindows || Platform.isLinux;
    expect(isDesktopPlatform, expected);
  });

  test('the override wins in both directions', () {
    debugIsDesktopPlatformOverride = true;
    expect(isDesktopPlatform, isTrue);

    debugIsDesktopPlatformOverride = false;
    expect(isDesktopPlatform, isFalse);
  });
}
