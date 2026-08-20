import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// GitHub repo releases are checked against — same one release.yml publishes to.
const _repo = 'peero-app/peero';

class UpdateInfo {
  final String version;
  final String releaseUrl;

  const UpdateInfo({required this.version, required this.releaseUrl});
}

/// How this install can be updated. Only [appImage], [windows] and [macos]
/// support installing the update automatically; [manual] (notably the
/// Linux .deb, which needs root) just points at the release page.
enum UpdateInstallKind { appImage, windows, macos, manual }

@visibleForTesting
UpdateService Function()? debugUpdateServiceFactory;

UpdateService createUpdateService() =>
    debugUpdateServiceFactory?.call() ?? UpdateService();

class UpdateService {
  final http.Client _client;

  UpdateService({http.Client? client}) : _client = client ?? http.Client();

  Future<String> currentVersion() async =>
      (await PackageInfo.fromPlatform()).version;

  UpdateInstallKind installKind() {
    if (Platform.isWindows) return UpdateInstallKind.windows;
    if (Platform.isMacOS) return UpdateInstallKind.macos;
    if (Platform.isLinux && Platform.environment.containsKey('APPIMAGE')) {
      return UpdateInstallKind.appImage;
    }
    return UpdateInstallKind.manual;
  }

  /// Returns the latest release if it is newer than [currentVersion], or
  /// null if already up to date. Throws on a network/parsing failure.
  Future<UpdateInfo?> checkForUpdate() async {
    final current = await currentVersion();
    final response = await _client
        .get(Uri.parse('https://api.github.com/repos/$_repo/releases/latest'))
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw http.ClientException('GitHub API returned ${response.statusCode}');
    }
    final tag =
        (jsonDecode(response.body) as Map<String, dynamic>)['tag_name']
            as String?;
    if (tag == null) throw const FormatException('release has no tag_name');
    final latest = tag.startsWith('v') ? tag.substring(1) : tag;
    if (!_isNewer(latest, current)) return null;
    return UpdateInfo(
      version: latest,
      releaseUrl: 'https://github.com/$_repo/releases/latest',
    );
  }

  bool _isNewer(String latest, String current) {
    final l = _parts(latest);
    final c = _parts(current);
    for (var i = 0; i < 3; i++) {
      if (l[i] != c[i]) return l[i] > c[i];
    }
    return false;
  }

  List<int> _parts(String version) {
    final segments = version.split('.');
    return List.generate(
      3,
      (i) => i < segments.length ? int.tryParse(segments[i]) ?? 0 : 0,
    );
  }

  /// Downloads and installs [info] for install kinds that support it, then
  /// restarts the app (this never returns on success: the process exits).
  /// Returns false on failure, and is a no-op returning false for
  /// [UpdateInstallKind.manual].
  Future<bool> installAndRestart(UpdateInfo info) async {
    try {
      switch (installKind()) {
        case UpdateInstallKind.appImage:
          return await _updateAppImage(info);
        case UpdateInstallKind.windows:
          return await _updateWindows(info);
        case UpdateInstallKind.macos:
          return await _updateMacOS();
        case UpdateInstallKind.manual:
          return false;
      }
    } catch (_) {
      return false;
    }
  }

  Future<bool> _updateAppImage(UpdateInfo info) async {
    final path = Platform.environment['APPIMAGE'];
    if (path == null) return false;
    final response = await _client.get(
      Uri.parse(
        'https://github.com/$_repo/releases/download/v${info.version}/peero.AppImage',
      ),
    );
    if (response.statusCode != 200) return false;
    final downloaded = File('$path.new');
    await downloaded.writeAsBytes(response.bodyBytes);
    await Process.run('chmod', ['+x', downloaded.path]);
    await downloaded.rename(path);
    await Process.start(path, [], mode: ProcessStartMode.detached);
    exit(0);
  }

  Future<bool> _updateWindows(UpdateInfo info) async {
    final response = await _client.get(
      Uri.parse(
        'https://github.com/$_repo/releases/download/v${info.version}/peero-setup.exe',
      ),
    );
    if (response.statusCode != 200) return false;
    final installer = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}peero-setup.exe',
    );
    await installer.writeAsBytes(response.bodyBytes);
    await Process.start(installer.path, [
      '/VERYSILENT',
      '/SUPPRESSMSGBOXES',
    ], mode: ProcessStartMode.detached);
    exit(0);
  }

  Future<bool> _updateMacOS() async {
    final result = await Process.run('brew', ['upgrade', '--cask', 'peero']);
    if (result.exitCode != 0) return false;
    await Process.start('open', [
      '-a',
      'Peero',
    ], mode: ProcessStartMode.detached);
    exit(0);
  }

  /// Opens [url] in the system browser (used for the manual-update path).
  Future<void> openUrl(String url) async {
    if (Platform.isMacOS) {
      await Process.run('open', [url]);
    } else if (Platform.isWindows) {
      await Process.run('cmd', ['/c', 'start', '', url]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [url]);
    }
  }
}
