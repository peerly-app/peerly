import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationService extends ChangeNotifier {
  static const _appUserModelId = 'com.sikander.peero';
  static const _windowsGuid = '6c1d9c10-6e9b-4c21-8b7b-6d3b6d2f6c11';
  static const _enabledPrefKey = 'notifications_enabled';

  final _plugin = FlutterLocalNotificationsPlugin();

  bool enabled = true;

  Future<void> setEnabled(bool value) async {
    enabled = value;
    await SharedPreferencesAsync().setBool(_enabledPrefKey, value);
    notifyListeners();
  }

  Future<void> init() async {
    enabled = await SharedPreferencesAsync().getBool(_enabledPrefKey) ?? true;

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const darwinSettings = DarwinInitializationSettings();
    const linuxSettings = LinuxInitializationSettings(
      defaultActionName: 'Ouvrir Peero',
    );
    const windowsSettings = WindowsInitializationSettings(
      appName: 'Peero',
      appUserModelId: _appUserModelId,
      guid: _windowsGuid,
    );

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
        macOS: darwinSettings,
        linux: linuxSettings,
        windows: windowsSettings,
      ),
    );

    if (!kIsWeb && Platform.isAndroid) {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    }
  }

  Future<void> showMessage({
    required String title,
    required String body,
  }) async {
    if (!enabled) return;
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'messages',
        'Messages',
        channelDescription: 'Nouveaux messages Peero',
        importance: Importance.high,
        priority: Priority.high,
      ),
      linux: LinuxNotificationDetails(),
      windows: WindowsNotificationDetails(),
    );
    await _plugin.show(
      id: DateTime.now().millisecondsSinceEpoch.remainder(1 << 31),
      title: title,
      body: body,
      notificationDetails: details,
    );
  }
}
