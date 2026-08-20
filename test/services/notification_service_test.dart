import 'package:flutter_test/flutter_test.dart';
import 'package:peero/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_harness.dart';

void main() {
  setUp(useInMemoryPreferences);

  test('notifications are on until the user says otherwise', () {
    expect(NotificationService().enabled, isTrue);
  });

  test('setEnabled persists the choice and notifies', () async {
    final service = NotificationService();
    var notifications = 0;
    service.addListener(() => notifications++);

    await service.setEnabled(false);

    expect(service.enabled, isFalse);
    expect(notifications, 1);
    expect(
      await SharedPreferencesAsync().getBool('notifications_enabled'),
      isFalse,
    );
  });

  test(
    'the saved preference is read back before the platform is set up',
    () async {
      useInMemoryPreferences({'notifications_enabled': false});
      final service = NotificationService();

      await expectLater(service.init(), throwsA(anything));

      expect(service.enabled, isFalse);
    },
  );

  test(
    'a disabled service shows nothing, never reaching the platform',
    () async {
      final service = NotificationService();
      await service.setEnabled(false);

      await service.showMessage(title: 'Bob', body: 'Salut');
    },
  );
}
