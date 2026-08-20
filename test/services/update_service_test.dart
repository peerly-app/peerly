import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus_platform_interface/package_info_data.dart';
import 'package:package_info_plus_platform_interface/package_info_platform_interface.dart';
import 'package:peero/services/update_service.dart';

void main() {
  setUpAll(() {
    PackageInfoPlatform.instance = _FakePackageInfoPlatform();
  });

  http.Client releaseClient(String tag) => MockClient((request) async {
    expect(
      request.url.toString(),
      'https://api.github.com/repos/peero-app/peero/releases/latest',
    );
    return http.Response(jsonEncode({'tag_name': tag}), 200);
  });

  group('checkForUpdate', () {
    test('returns null when already on the latest version', () async {
      final service = UpdateService(client: releaseClient('v1.0.0'));

      expect(await service.checkForUpdate(), isNull);
    });

    test('returns the release when a newer version is published', () async {
      final service = UpdateService(client: releaseClient('v1.2.0'));

      final update = await service.checkForUpdate();

      expect(update?.version, '1.2.0');
      expect(
        update?.releaseUrl,
        'https://github.com/peero-app/peero/releases/latest',
      );
    });

    test('returns null when the published version is older', () async {
      final service = UpdateService(client: releaseClient('v0.9.0'));

      expect(await service.checkForUpdate(), isNull);
    });

    test('a missing "v" prefix on the tag is tolerated', () async {
      final service = UpdateService(client: releaseClient('1.2.0'));

      expect((await service.checkForUpdate())?.version, '1.2.0');
    });

    test('throws when the GitHub API errors', () async {
      final service = UpdateService(
        client: MockClient((request) async => http.Response('', 500)),
      );

      expect(service.checkForUpdate(), throwsA(anything));
    });

    test('throws when the response has no tag_name', () async {
      final service = UpdateService(
        client: MockClient(
          (request) async => http.Response(jsonEncode({}), 200),
        ),
      );

      expect(service.checkForUpdate(), throwsA(anything));
    });
  });
}

class _FakePackageInfoPlatform extends PackageInfoPlatform {
  @override
  Future<PackageInfoData> getAll({String? baseUrl}) async {
    return PackageInfoData(
      appName: 'peero',
      packageName: 'com.sikander.peero',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
      installerStore: null,
    );
  }
}
