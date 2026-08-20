import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:peero/l10n/app_localizations.dart';
import 'package:peero/models/peer.dart';
import 'package:peero/services/audio_client.dart';
import 'package:peero/services/audio_recorder_service.dart';
import 'package:peero/services/audio_repository.dart';
import 'package:peero/services/audio_store.dart';
import 'package:peero/services/avatar_client.dart';
import 'package:peero/services/avatar_repository.dart';
import 'package:peero/services/avatar_store.dart';
import 'package:peero/services/chat_repository.dart';
import 'package:peero/services/chat_store.dart';
import 'package:peero/services/device_identity_service.dart';
import 'package:peero/services/discovery_service.dart';
import 'package:peero/services/file_client.dart';
import 'package:peero/services/file_repository.dart';
import 'package:peero/services/file_store.dart';
import 'package:peero/services/locale_service.dart';
import 'package:peero/services/notification_service.dart';
import 'package:peero/services/voice_player.dart';
import 'package:peero/theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'in_memory_repositories.dart';

void useInMemoryPreferences([Map<String, Object> initialValues = const {}]) {
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.withData(
        Map<String, Object>.from(initialValues),
      );
}

class TestPathProvider extends PathProviderPlatform {
  final Directory root;

  bool downloadsSupported;

  bool downloadsThrows;

  TestPathProvider(
    this.root, {
    this.downloadsSupported = true,
    this.downloadsThrows = false,
  });

  static TestPathProvider install() {
    final root = Directory.systemTemp.createTempSync('peero_paths_');
    final provider = TestPathProvider(root);
    PathProviderPlatform.instance = provider;
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    return provider;
  }

  String _subPath(String name) => '${root.path}/$name';

  @override
  Future<String?> getTemporaryPath() async => _subPath('tmp');

  @override
  Future<String?> getApplicationSupportPath() async => _subPath('support');

  @override
  Future<String?> getApplicationDocumentsPath() async => _subPath('documents');

  @override
  Future<String?> getApplicationCachePath() async => _subPath('cache');

  @override
  Future<String?> getDownloadsPath() async {
    if (downloadsThrows) throw UnsupportedError('no downloads directory');
    return downloadsSupported ? _subPath('downloads') : null;
  }
}

class TestStores {
  final Directory? directory;
  final ChatRepository chatRepository;
  final AvatarRepository avatarRepository;
  final AudioRepository audioRepository;
  final FileRepository fileRepository;
  final AvatarStore avatarStore;
  final AudioStore audioStore;
  final FileStore fileStore;
  final ChatStore chatStore;
  final FakeAvatarClient avatarClient;
  final FakeAudioClient audioClient;
  final FakeFileClient fileClient;

  TestStores._({
    required this.directory,
    required this.chatRepository,
    required this.avatarRepository,
    required this.audioRepository,
    required this.fileRepository,
    required this.avatarStore,
    required this.audioStore,
    required this.fileStore,
    required this.chatStore,
    required this.avatarClient,
    required this.audioClient,
    required this.fileClient,
  });

  static Future<TestStores> create() async {
    final directory = Directory.systemTemp.createTempSync('peero_stores_');
    final chatRepository = ChatRepository();
    await chatRepository.init(testStoragePath: directory.path);

    final avatarRepository = AvatarRepository();
    await avatarRepository.init();
    final audioRepository = AudioRepository();
    await audioRepository.init();
    final fileRepository = FileRepository();
    await fileRepository.init();

    return _wire(
      directory: directory,
      chatRepository: chatRepository,
      avatarRepository: avatarRepository,
      audioRepository: audioRepository,
      fileRepository: fileRepository,
    );
  }

  static TestStores inMemory() {
    return _wire(
      directory: null,
      chatRepository: InMemoryChatRepository(),
      avatarRepository: InMemoryAvatarRepository(),
      audioRepository: InMemoryAudioRepository(),
      fileRepository: InMemoryFileRepository(),
    );
  }

  static TestStores _wire({
    required Directory? directory,
    required ChatRepository chatRepository,
    required AvatarRepository avatarRepository,
    required AudioRepository audioRepository,
    required FileRepository fileRepository,
  }) {
    final avatarClient = FakeAvatarClient();
    final audioClient = FakeAudioClient();
    final fileClient = FakeFileClient();

    final avatarStore = AvatarStore(
      repository: avatarRepository,
      client: avatarClient,
    );
    final audioStore = AudioStore(
      repository: audioRepository,
      client: audioClient,
    );
    final fileStore = FileStore(repository: fileRepository, client: fileClient);
    final chatStore = ChatStore(
      chatRepository,
      avatarStore,
      audioStore,
      fileStore,
    );
    chatStore.loadSummaries();

    return TestStores._(
      directory: directory,
      chatRepository: chatRepository,
      avatarRepository: avatarRepository,
      audioRepository: audioRepository,
      fileRepository: fileRepository,
      avatarStore: avatarStore,
      audioStore: audioStore,
      fileStore: fileStore,
      chatStore: chatStore,
      avatarClient: avatarClient,
      audioClient: audioClient,
      fileClient: fileClient,
    );
  }

  Future<void> dispose() async {
    final directory = this.directory;
    if (directory == null) return;
    await Hive.close();
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  }
}

class FakeDiscoveryService extends DiscoveryService {
  FakeDiscoveryService({DeviceIdentityService? identity})
    : super(
        identity: identity ?? loadedIdentity(),
        servicePort: () => 4242,
        avatarVersion: () => null,
      );

  List<Peer> _peers = const [];

  @override
  List<Peer> get peers => _peers;

  void setPeers(List<Peer> peers) {
    _peers = peers;
    notifyListeners();
  }
}

DeviceIdentityService loadedIdentity({
  String id = 'me-0000',
  String alias = 'Mon appareil',
}) {
  return _StubIdentity(id, alias);
}

class _StubIdentity extends DeviceIdentityService {
  _StubIdentity(String id, String alias) {
    this.id = id;
    this.alias = alias;
  }

  @override
  Future<void> updateAlias(String newAlias) async {
    if (newAlias.trim().isEmpty) return;
    alias = newAlias.trim();
    notifyListeners();
  }
}

Uint8List pngBytes() => Uint8List.fromList(const [
  137,
  80,
  78,
  71,
  13,
  10,
  26,
  10,
  0,
  0,
  0,
  13,
  73,
  72,
  68,
  82,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
  1,
  8,
  6,
  0,
  0,
  0,
  31,
  21,
  196,
  137,
  0,
  0,
  0,
  10,
  73,
  68,
  65,
  84,
  120,
  156,
  99,
  0,
  1,
  0,
  0,
  5,
  0,
  1,
  13,
  10,
  45,
  180,
  0,
  0,
  0,
  0,
  73,
  69,
  78,
  68,
  174,
  66,
  96,
  130,
]);

Peer testPeer({
  String id = 'peer-1',
  String alias = 'Bob',
  String platform = 'linux',
  String ip = '192.168.1.20',
  int port = 5000,
  DateTime? lastSeen,
  String? avatarVersion,
}) {
  return Peer(
    id: id,
    alias: alias,
    platform: platform,
    ip: ip,
    port: port,
    lastSeen: lastSeen ?? DateTime(2026, 1, 1, 12),
    avatarVersion: avatarVersion,
  );
}

Widget wrapWithApp(
  Widget child, {
  required TestStores stores,
  DiscoveryService? discovery,
  DeviceIdentityService? identity,
  NotificationService? notifications,
  LocaleService? localeService,
  Locale locale = const Locale('fr'),
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<DeviceIdentityService>.value(
        value: identity ?? loadedIdentity(),
      ),
      ChangeNotifierProvider<DiscoveryService>.value(
        value: discovery ?? FakeDiscoveryService(),
      ),
      ChangeNotifierProvider.value(value: stores.chatStore),
      ChangeNotifierProvider.value(value: stores.avatarStore),
      ChangeNotifierProvider.value(value: stores.audioStore),
      ChangeNotifierProvider.value(value: stores.fileStore),
      ChangeNotifierProvider<NotificationService>.value(
        value: notifications ?? NotificationService(),
      ),
      ChangeNotifierProvider<LocaleService>.value(
        value: localeService ?? LocaleService(),
      ),
    ],
    child: Consumer<LocaleService>(
      builder: (context, service, _) => MaterialApp(
        theme: buildAppTheme(),
        locale: localeService == null ? locale : service.locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      ),
    ),
  );
}

final l10nFr = lookupAppLocalizations(const Locale('fr'));

class FakeAvatarClient implements AvatarClient {
  final Map<String, Uint8List> responses = {};
  final List<String> requestedPeerIds = [];

  @override
  Future<Uint8List?> fetch(Peer peer) async {
    requestedPeerIds.add(peer.id);
    return responses[peer.id];
  }
}

class FakeAudioClient implements AudioClient {
  final Map<String, Uint8List> responses = {};
  final List<String> requestedMessageIds = [];

  @override
  Future<Uint8List?> fetch(Peer peer, String messageId) async {
    requestedMessageIds.add(messageId);
    return responses[messageId];
  }
}

class FakeFileClient implements FileClient {
  final Map<String, List<int>> responses = {};

  final Map<String, List<int>> progressUpdates = {};

  final List<String> requestedMessageIds = [];

  bool leavePartialFileOnFailure = false;

  Completer<void>? gate;

  @override
  Future<bool> download(
    Peer peer,
    String messageId,
    String destinationPath, {
    void Function(int receivedBytes)? onProgress,
  }) async {
    requestedMessageIds.add(messageId);
    for (final received in progressUpdates[messageId] ?? const <int>[]) {
      onProgress?.call(received);
    }
    if (gate != null) await gate!.future;
    final bytes = responses[messageId];
    if (bytes == null) {
      if (leavePartialFileOnFailure) {
        await File(destinationPath).writeAsBytes([0, 0, 0]);
      }
      return false;
    }
    await File(destinationPath).writeAsBytes(bytes);
    onProgress?.call(bytes.length);
    return true;
  }
}

class FakeAudioRecorder implements AudioRecorderService {
  bool permission = true;
  Uint8List? capturedBytes = Uint8List.fromList([1, 2, 3]);
  int startCount = 0;
  int stopCount = 0;
  int cancelCount = 0;
  bool disposed = false;

  Completer<void>? startGate;

  @override
  Future<bool> hasPermission() async => permission;

  @override
  Future<void> start() async {
    startCount++;
    if (startGate != null) await startGate!.future;
  }

  @override
  Future<Uint8List?> stop() async {
    stopCount++;
    return capturedBytes;
  }

  @override
  Future<void> cancel() async {
    cancelCount++;
  }

  @override
  void dispose() => disposed = true;
}

class FakeVoicePlayer implements VoicePlayer {
  final positions = StreamController<Duration>.broadcast();
  final completions = StreamController<void>.broadcast();

  final List<String> playedPaths = [];
  final List<double> playbackRates = [];
  int pauseCount = 0;
  bool disposed = false;

  @override
  Stream<Duration> get onPositionChanged => positions.stream;

  @override
  Stream<void> get onComplete => completions.stream;

  @override
  Future<void> playFile(String path) async => playedPaths.add(path);

  @override
  Future<void> pause() async => pauseCount++;

  @override
  Future<void> setPlaybackRate(double rate) async => playbackRates.add(rate);

  @override
  void dispose() {
    disposed = true;
    positions.close();
    completions.close();
  }
}

Future<T> persist<T>(WidgetTester tester, Future<T> Function() body) async {
  final result = await tester.runAsync(body);
  await tester.pump();
  return result as T;
}

FakeAudioRecorder useFakeAudioRecorder() {
  final recorder = FakeAudioRecorder();
  debugAudioRecorderFactory = () => recorder;
  addTearDown(() => debugAudioRecorderFactory = null);
  return recorder;
}

FakeVoicePlayer useFakeVoicePlayer() {
  final player = FakeVoicePlayer();
  debugVoicePlayerFactory = () => player;
  addTearDown(() => debugVoicePlayerFactory = null);
  return player;
}

Future<void> pumpRouteTransition(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _drainRealEventLoop() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

Future<void> settleRealWork(WidgetTester tester) async {
  await tester.runAsync(_drainRealEventLoop);
  await tester.pump();
}

Future<void> pumpWidgetWithRealIO(WidgetTester tester, Widget app) async {
  await tester.runAsync(() async {
    await tester.pumpWidget(app);
    await _drainRealEventLoop();
  });
  await tester.pump();
}

Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
  await tester.runAsync(() async {
    await tester.tap(finder);
    await _drainRealEventLoop();
  });
  await tester.pump();
}

Future<void> setLargeSurface(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
