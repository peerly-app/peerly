import '../l10n/app_localizations.dart';

String formatClockDuration(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

String formatByteSize(AppLocalizations l10n, int bytes) {
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(0)} ${l10n.storageUnitKB}';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} ${l10n.storageUnitMB}';
}

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String formatConversationTimestamp(DateTime time, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  if (isSameDay(time, reference)) {
    return '${_pad(time.hour)}:${_pad(time.minute)}';
  }
  return '${_pad(time.day)}/${_pad(time.month)}';
}

String shortPeerId(String id) {
  final hex = id.replaceAll('-', '').toUpperCase();
  final chars = hex.substring(0, hex.length < 6 ? hex.length : 6);
  return chars
      .replaceAllMapped(RegExp('.{2}'), (m) => '${m.group(0)}:')
      .replaceAll(RegExp(r':$'), '');
}

String _pad(int value) => value.toString().padLeft(2, '0');
