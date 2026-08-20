import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peero/models/chat_message.dart';
import 'package:peero/screens/blocked_users_screen.dart';
import 'package:peero/screens/language_screen.dart';
import 'package:peero/screens/settings_screen.dart';
import 'package:peero/services/chat_repository.dart';
import 'package:peero/services/device_identity_service.dart';
import 'package:peero/services/locale_service.dart';
import 'package:peero/services/notification_service.dart';
import 'package:peero/services/update_service.dart';
import 'package:peero/widgets/avatar.dart';

import '../helpers/test_harness.dart';

class _FakeUpdateService implements UpdateService {
  String version = '1.0.0';
  UpdateInfo? nextUpdate;
  Object? checkError;
  UpdateInstallKind kind = UpdateInstallKind.appImage;
  bool installSucceeds = true;
  final openedUrls = <String>[];
  int installCalls = 0;

  @override
  Future<String> currentVersion() async => version;

  @override
  Future<UpdateInfo?> checkForUpdate() async {
    if (checkError != null) throw checkError!;
    return nextUpdate;
  }

  @override
  UpdateInstallKind installKind() => kind;

  @override
  Future<bool> installAndRestart(UpdateInfo info) async {
    installCalls++;
    return installSucceeds;
  }

  @override
  Future<void> openUrl(String url) async => openedUrls.add(url);
}

void main() {
  late TestStores stores;
  late DeviceIdentityService identity;
  late NotificationService notifications;
  late _FakeUpdateService updateService;

  setUp(() {
    useInMemoryPreferences();

    TestPathProvider.install();
    stores = TestStores.inMemory();
    identity = loadedIdentity(
      id: '7f3a9c12-0000-0000-0000-000000000000',
      alias: 'Mon poste',
    );
    notifications = NotificationService();
    updateService = _FakeUpdateService();
    debugUpdateServiceFactory = () => updateService;
  });
  tearDown(() async {
    debugUpdateServiceFactory = null;
    await stores.dispose();
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await setLargeSurface(tester);

    await pumpWidgetWithRealIO(
      tester,
      wrapWithApp(
        const SettingsScreen(),
        stores: stores,
        identity: identity,
        notifications: notifications,
      ),
    );
  }

  Future<void> addMessage(String peerId, String alias, {int count = 1}) async {
    for (var i = 0; i < count; i++) {
      await stores.chatStore.add(
        peerId,
        alias,
        ChatMessage(
          fromId: peerId,
          fromAlias: alias,
          text: 'Salut $i',
          timestamp: DateTime(2026, 1, 1, 10),
          isMine: false,
        ),
      );
    }
  }

  testWidgets('shows the device identity card', (tester) async {
    await pumpScreen(tester);

    expect(find.text('Mon poste'), findsWidgets);
    expect(find.text(l10nFr.settingsDeviceIdLabel('7F:3A:9C')), findsOneWidget);
    expect(find.byType(Avatar), findsOneWidget);
  });

  testWidgets('shows every settings row', (tester) async {
    await pumpScreen(tester);

    expect(find.text(l10nFr.settingsDeviceName), findsOneWidget);
    expect(find.text(l10nFr.settingsLanguage), findsOneWidget);
    expect(find.text(l10nFr.settingsNetwork), findsOneWidget);
    expect(find.text(l10nFr.settingsNotifications), findsOneWidget);
    expect(find.text(l10nFr.settingsStorage), findsOneWidget);
    expect(find.text(l10nFr.settingsBlockedUsers), findsOneWidget);
    expect(find.text(l10nFr.settingsVersion), findsOneWidget);
    expect(find.text(l10nFr.settingsCheckForUpdates), findsOneWidget);
  });

  testWidgets('the network row falls back to "unavailable"', (tester) async {
    await pumpScreen(tester);
    await settleRealWork(tester);

    expect(find.text(l10nFr.settingsUnavailable), findsOneWidget);
  });

  testWidgets('the storage row reports the space in use', (tester) async {
    await addMessage('peer-1', 'Bob');
    await pumpScreen(tester);

    expect(find.textContaining(l10nFr.storageUnitKB), findsOneWidget);
  });

  testWidgets('the blocked-users row shows how many there are', (tester) async {
    await stores.chatStore.setStatus(
      'peer-1',
      'Zoe',
      ConversationStatus.blocked,
    );
    await pumpScreen(tester);

    expect(find.text('1'), findsOneWidget);
  });

  group('device name', () {
    testWidgets('renaming updates the identity', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.text(l10nFr.settingsDeviceName));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Nouveau nom');
      await tester.tap(find.text(l10nFr.save));
      await tester.pumpAndSettle();

      expect(identity.alias, 'Nouveau nom');
      expect(find.text('Nouveau nom'), findsWidgets);
    });

    testWidgets('cancelling leaves the name alone', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.text(l10nFr.settingsDeviceName));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Ignoré');
      await tester.tap(find.text(l10nFr.cancel));
      await tester.pumpAndSettle();

      expect(identity.alias, 'Mon poste');
    });

    testWidgets('an all-whitespace name is refused', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.text(l10nFr.settingsDeviceName));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.text(l10nFr.save));
      await tester.pumpAndSettle();

      expect(identity.alias, 'Mon poste');
    });
  });

  group('notifications toggle', () {
    testWidgets('starts on and can be switched off', (tester) async {
      await pumpScreen(tester);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

      await tester.tap(find.byType(Switch));
      await tester.pump();

      expect(notifications.enabled, isFalse);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    });
  });

  group('navigation', () {
    testWidgets('opens the language screen', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.text(l10nFr.settingsLanguage));
      await tester.pumpAndSettle();

      expect(find.byType(LanguageScreen), findsOneWidget);
    });

    testWidgets('opens the blocked-users screen', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.text(l10nFr.settingsBlockedUsers));
      await tester.pumpAndSettle();

      expect(find.byType(BlockedUsersScreen), findsOneWidget);
    });
  });

  group('delete all conversations', () {
    testWidgets('confirming wipes every conversation', (tester) async {
      await addMessage('peer-1', 'Bob');
      await addMessage('peer-2', 'Carol');
      await pumpScreen(tester);

      await tester.tap(find.text(l10nFr.deleteAllSettingsLabel));
      await tester.pumpAndSettle();
      expect(find.text(l10nFr.deleteAllTitle), findsOneWidget);
      await tester.tap(find.text(l10nFr.delete));
      await settleRealWork(tester);

      expect(stores.chatStore.conversations, isEmpty);
    });

    testWidgets('cancelling keeps them', (tester) async {
      await addMessage('peer-1', 'Bob');
      await pumpScreen(tester);

      await tester.tap(find.text(l10nFr.deleteAllSettingsLabel));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10nFr.cancel));
      await tester.pumpAndSettle();

      expect(stores.chatStore.conversations, hasLength(1));
    });
  });

  group('clear media', () {
    testWidgets('confirming drops cached peer photos but keeps our own', (
      tester,
    ) async {
      await stores.avatarRepository.setPhoto('peer-1', pngBytes(), 'v1');
      await stores.avatarRepository.setPhoto(identity.id, pngBytes(), 'v1');
      stores.avatarStore.load();
      await pumpScreen(tester);

      await tester.tap(find.text(l10nFr.settingsClearMedia));
      await tester.pumpAndSettle();
      expect(find.text(l10nFr.clearMediaConfirmTitle), findsOneWidget);
      await tester.tap(find.text(l10nFr.delete));
      await settleRealWork(tester);

      expect(stores.avatarStore.photoBytes('peer-1'), isNull);
      expect(stores.avatarStore.photoBytes(identity.id), isNotNull);
    });

    testWidgets('cancelling keeps everything', (tester) async {
      await stores.avatarRepository.setPhoto('peer-1', pngBytes(), 'v1');
      stores.avatarStore.load();
      await pumpScreen(tester);

      await tester.tap(find.text(l10nFr.settingsClearMedia));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10nFr.cancel));
      await tester.pumpAndSettle();

      expect(stores.avatarStore.photoBytes('peer-1'), isNotNull);
    });
  });

  group('profile photo', () {
    testWidgets('the sheet offers only "choose" when there is no photo', (
      tester,
    ) async {
      await pumpScreen(tester);

      await tester.tap(find.byType(Avatar));
      await tester.pumpAndSettle();

      expect(find.text(l10nFr.profilePhotoChoose), findsOneWidget);
      expect(find.text(l10nFr.profilePhotoRemove), findsNothing);
    });

    testWidgets('the sheet offers "remove" once a photo is set', (
      tester,
    ) async {
      await stores.avatarRepository.setPhoto(identity.id, pngBytes(), 'v1');
      stores.avatarStore.load();
      await pumpScreen(tester);

      await tester.tap(find.byType(Avatar));
      await tester.pumpAndSettle();

      expect(find.text(l10nFr.profilePhotoRemove), findsOneWidget);
    });

    testWidgets('removing clears the photo', (tester) async {
      await stores.avatarRepository.setPhoto(identity.id, pngBytes(), 'v1');
      stores.avatarStore.load();
      await pumpScreen(tester);

      await tester.tap(find.byType(Avatar));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10nFr.profilePhotoRemove));
      await tester.pumpAndSettle();

      expect(stores.avatarStore.photoBytes(identity.id), isNull);
    });

    testWidgets('dismissing the sheet changes nothing', (tester) async {
      await stores.avatarRepository.setPhoto(identity.id, pngBytes(), 'v1');
      stores.avatarStore.load();
      await pumpScreen(tester);

      await tester.tap(find.byType(Avatar));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(stores.avatarStore.photoBytes(identity.id), isNotNull);
      expect(find.text(l10nFr.profilePhotoChoose), findsNothing);
    });
  });

  group('version and updates', () {
    testWidgets('shows the current app version', (tester) async {
      updateService.version = '1.2.3';
      await pumpScreen(tester);
      await settleRealWork(tester);

      expect(find.text('1.2.3'), findsOneWidget);
    });

    testWidgets('reports being up to date', (tester) async {
      updateService.nextUpdate = null;
      await pumpScreen(tester);

      await tapAndSettle(tester, find.text(l10nFr.settingsCheckForUpdates));

      expect(find.text(l10nFr.updateUpToDate), findsOneWidget);
    });

    testWidgets('reports a failed check', (tester) async {
      updateService.checkError = Exception('network down');
      await pumpScreen(tester);

      await tapAndSettle(tester, find.text(l10nFr.settingsCheckForUpdates));

      expect(find.text(l10nFr.updateCheckFailed), findsOneWidget);
    });

    testWidgets(
      'offers to update and restart on an auto-installable platform',
      (tester) async {
        updateService.kind = UpdateInstallKind.appImage;
        updateService.nextUpdate = const UpdateInfo(
          version: '2.0.0',
          releaseUrl: 'https://github.com/peero-app/peero/releases/latest',
        );
        await pumpScreen(tester);

        await tapAndSettle(tester, find.text(l10nFr.settingsCheckForUpdates));
        expect(find.text(l10nFr.updateInstallNow), findsOneWidget);

        await tapAndSettle(tester, find.text(l10nFr.updateInstallNow));

        expect(updateService.installCalls, 1);
      },
    );

    testWidgets('reports a failed install', (tester) async {
      updateService.kind = UpdateInstallKind.appImage;
      updateService.installSucceeds = false;
      updateService.nextUpdate = const UpdateInfo(
        version: '2.0.0',
        releaseUrl: 'https://github.com/peero-app/peero/releases/latest',
      );
      await pumpScreen(tester);

      await tapAndSettle(tester, find.text(l10nFr.settingsCheckForUpdates));
      await tapAndSettle(tester, find.text(l10nFr.updateInstallNow));

      expect(find.text(l10nFr.updateInstallFailed), findsOneWidget);
    });

    testWidgets('opens the download page when the install is manual', (
      tester,
    ) async {
      updateService.kind = UpdateInstallKind.manual;
      updateService.nextUpdate = const UpdateInfo(
        version: '2.0.0',
        releaseUrl: 'https://github.com/peero-app/peero/releases/latest',
      );
      await pumpScreen(tester);

      await tapAndSettle(tester, find.text(l10nFr.settingsCheckForUpdates));
      expect(find.text(l10nFr.updateOpenDownloadPage), findsOneWidget);

      await tapAndSettle(tester, find.text(l10nFr.updateOpenDownloadPage));

      expect(updateService.openedUrls, [
        'https://github.com/peero-app/peero/releases/latest',
      ]);
      expect(updateService.installCalls, 0);
    });
  });

  testWidgets('the language row shows the current language natively', (
    tester,
  ) async {
    final localeService = LocaleService();
    await localeService.setLocale(const Locale('de'));
    await setLargeSurface(tester);
    await tester.pumpWidget(
      wrapWithApp(
        const SettingsScreen(),
        stores: stores,
        identity: identity,
        notifications: notifications,
        localeService: localeService,
      ),
    );
    await tester.pump();

    expect(find.text('Deutsch'), findsOneWidget);
  });
}
