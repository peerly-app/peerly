import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:peero/services/device_identity_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_harness.dart';

void main() {
  setUp(useInMemoryPreferences);

  test('is not ready before load()', () {
    expect(DeviceIdentityService().ready, isFalse);
  });

  test('load() generates and persists an id on first run', () async {
    final service = DeviceIdentityService();

    await service.load();

    expect(service.ready, isTrue);
    expect(service.id, isNotEmpty);
    expect(await SharedPreferencesAsync().getString('device_id'), service.id);
  });

  test('the id is stable across restarts', () async {
    final first = DeviceIdentityService();
    await first.load();

    final second = DeviceIdentityService();
    await second.load();

    expect(second.id, first.id);
  });

  test('a stored alias is preferred over the default', () async {
    useInMemoryPreferences({'device_id': 'abc', 'device_alias': 'Mon poste'});
    final service = DeviceIdentityService();

    await service.load();

    expect(service.id, 'abc');
    expect(service.alias, 'Mon poste');
  });

  test('the default alias falls back to the hostname', () async {
    final service = DeviceIdentityService();

    await service.load();

    expect(service.alias, isNotEmpty);
    expect(service.alias, Platform.localHostname);
  });

  test('load() notifies listeners', () async {
    final service = DeviceIdentityService();
    var notifications = 0;
    service.addListener(() => notifications++);

    await service.load();

    expect(notifications, 1);
  });

  test('the detected platform is one of the known values', () async {
    final service = DeviceIdentityService();
    await service.load();

    expect(
      service.platform,
      isIn(['web', 'android', 'ios', 'macos', 'windows', 'linux', 'unknown']),
    );
  });

  group('updateAlias', () {
    late DeviceIdentityService service;

    setUp(() async {
      service = DeviceIdentityService();
      await service.load();
    });

    test('persists the new alias and notifies', () async {
      var notifications = 0;
      service.addListener(() => notifications++);

      await service.updateAlias('Nouveau nom');

      expect(service.alias, 'Nouveau nom');
      expect(notifications, 1);
      expect(
        await SharedPreferencesAsync().getString('device_alias'),
        'Nouveau nom',
      );
    });

    test('trims surrounding whitespace', () async {
      await service.updateAlias('  Espaces  ');

      expect(service.alias, 'Espaces');
    });

    test('ignores an empty or whitespace-only alias', () async {
      final before = service.alias;

      await service.updateAlias('');
      await service.updateAlias('   ');

      expect(service.alias, before);
    });

    test('ignores an alias identical to the current one', () async {
      await service.updateAlias('Stable');
      var notifications = 0;
      service.addListener(() => notifications++);

      await service.updateAlias('Stable');

      expect(notifications, 0);
    });
  });
}
