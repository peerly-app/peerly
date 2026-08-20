import 'dart:io';

import 'package:flutter/foundation.dart';

@visibleForTesting
bool? debugIsDesktopPlatformOverride;

bool get isDesktopPlatform =>
    debugIsDesktopPlatformOverride ??
    (!kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux));
