import 'dart:io';

import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class NetworkInfoService {
  final _networkInfo = NetworkInfo();

  Future<String?> currentNetworkName() async {
    if (Platform.isMacOS) return null;

    if (Platform.isAndroid) {
      final status = await Permission.locationWhenInUse.request();
      if (!status.isGranted) return null;
    }

    try {
      final name = await _networkInfo.getWifiName();
      return name?.replaceAll('"', '');
    } catch (_) {
      return null;
    }
  }
}
