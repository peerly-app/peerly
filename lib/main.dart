import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';

import 'l10n/app_localizations.dart';
import 'screens/root_shell.dart';
import 'services/audio_repository.dart';
import 'services/audio_store.dart';
import 'services/avatar_repository.dart';
import 'services/avatar_store.dart';
import 'services/chat_repository.dart';
import 'services/chat_server.dart';
import 'services/chat_store.dart';
import 'services/device_identity_service.dart';
import 'services/discovery_service.dart';
import 'services/file_repository.dart';
import 'services/file_store.dart';
import 'services/locale_service.dart';
import 'services/notification_service.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  final identity = DeviceIdentityService();
  await identity.load();

  final localeService = LocaleService();
  await localeService.load();

  final chatRepository = ChatRepository();
  await chatRepository.init();

  final avatarRepository = AvatarRepository();
  await avatarRepository.init();
  final avatarStore = AvatarStore(repository: avatarRepository);
  avatarStore.load();

  final audioRepository = AudioRepository();
  await audioRepository.init();
  final audioStore = AudioStore(repository: audioRepository);

  final fileRepository = FileRepository();
  await fileRepository.init();
  final fileStore = FileStore(repository: fileRepository);

  final chatStore = ChatStore(
    chatRepository,
    avatarStore,
    audioStore,
    fileStore,
  );
  chatStore.loadSummaries();

  final notificationService = NotificationService();
  await notificationService.init();

  final chatServer = ChatServer(
    chatStore: chatStore,
    notificationService: notificationService,
    avatarStore: avatarStore,
    audioStore: audioStore,
    fileStore: fileStore,
    ownId: identity.id,
  );
  await chatServer.start();

  final discovery = DiscoveryService(
    identity: identity,
    servicePort: () => chatServer.port,
    avatarVersion: () => avatarStore.versionFor(identity.id),

    onPeerAnnounced: (peers) => avatarStore.syncFromPeers(
      peers.where((peer) => chatStore.isKnownContact(peer.id)).toList(),
    ),
  );
  await discovery.start();

  runApp(
    PeeroApp(
      identity: identity,
      discovery: discovery,
      chatStore: chatStore,
      avatarStore: avatarStore,
      audioStore: audioStore,
      fileStore: fileStore,
      notificationService: notificationService,
      localeService: localeService,
    ),
  );
}

class PeeroApp extends StatelessWidget {
  final DeviceIdentityService identity;
  final DiscoveryService discovery;
  final ChatStore chatStore;
  final AvatarStore avatarStore;
  final AudioStore audioStore;
  final FileStore fileStore;
  final NotificationService notificationService;
  final LocaleService localeService;

  const PeeroApp({
    super.key,
    required this.identity,
    required this.discovery,
    required this.chatStore,
    required this.avatarStore,
    required this.audioStore,
    required this.fileStore,
    required this.notificationService,
    required this.localeService,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: identity),
        ChangeNotifierProvider.value(value: discovery),
        ChangeNotifierProvider.value(value: chatStore),
        ChangeNotifierProvider.value(value: avatarStore),
        ChangeNotifierProvider.value(value: audioStore),
        ChangeNotifierProvider.value(value: fileStore),
        ChangeNotifierProvider.value(value: notificationService),
        ChangeNotifierProvider.value(value: localeService),
      ],
      child: Consumer<LocaleService>(
        builder: (context, locale, _) {
          return MaterialApp(
            title: 'Peero',
            theme: buildAppTheme(),
            darkTheme: buildAppTheme(),
            themeMode: ThemeMode.dark,
            locale: locale.locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const RootShell(),
          );
        },
      ),
    );
  }
}
