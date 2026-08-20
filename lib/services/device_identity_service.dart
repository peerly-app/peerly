import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class DeviceIdentityService extends ChangeNotifier {
  static const _idKey = 'device_id';
  static const _aliasKey = 'device_alias';

  late String id;
  late String alias;
  final String platform = _detectPlatform();

  bool _ready = false;
  bool get ready => _ready;

  Future<void> load() async {
    final prefs = SharedPreferencesAsync();

    var storedId = await prefs.getString(_idKey);
    storedId ??= const Uuid().v4();
    await prefs.setString(_idKey, storedId);

    var storedAlias = await prefs.getString(_aliasKey);
    storedAlias ??= _defaultAlias();
    await prefs.setString(_aliasKey, storedAlias);

    id = storedId;
    alias = storedAlias;
    _ready = true;
    notifyListeners();
  }

  Future<void> updateAlias(String newAlias) async {
    if (newAlias.trim().isEmpty || newAlias == alias) return;
    alias = newAlias.trim();
    final prefs = SharedPreferencesAsync();
    await prefs.setString(_aliasKey, alias);
    notifyListeners();
  }

  static String _detectPlatform() {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }

  static String _defaultAlias() {
    try {
      final host = Platform.localHostname;
      if (host.isNotEmpty) return host;
    } catch (_) {}
    return 'Appareil ${_detectPlatform()}';
  }
}
