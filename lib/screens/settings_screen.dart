import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../design/colors.dart';
import '../design/typography.dart';
import '../l10n/app_localizations.dart';
import '../services/avatar_store.dart';
import '../services/chat_store.dart';
import '../services/device_identity_service.dart';
import '../services/file_store.dart';
import '../services/locale_service.dart';
import '../services/network_info_service.dart';
import '../services/notification_service.dart';
import '../services/update_service.dart';
import '../utils/formatting.dart';
import '../widgets/avatar.dart';
import '../widgets/confirm_dialog.dart';
import 'blocked_users_screen.dart';
import 'language_screen.dart';

enum _PhotoAction { choose, remove }

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _networkInfo = NetworkInfoService();
  final _updateService = createUpdateService();
  String? _networkName;
  int? _storageBytes;
  String? _appVersion;
  bool _checkingForUpdate = false;

  @override
  void initState() {
    super.initState();
    _networkInfo.currentNetworkName().then((name) {
      if (mounted) setState(() => _networkName = name);
    });
    context.read<ChatStore>().storageBytesUsed().then((bytes) {
      if (mounted) setState(() => _storageBytes = bytes);
    });
    _updateService.currentVersion().then((version) {
      if (mounted) setState(() => _appVersion = version);
    });
  }

  String _formatBytes(AppLocalizations l10n, int? bytes) =>
      bytes == null ? '…' : formatByteSize(l10n, bytes);

  Future<void> _checkForUpdates(AppLocalizations l10n) async {
    setState(() => _checkingForUpdate = true);
    UpdateInfo? update;
    Object? error;
    try {
      update = await _updateService.checkForUpdate();
    } catch (e) {
      error = e;
    }
    if (!mounted) return;
    setState(() => _checkingForUpdate = false);

    if (error != null) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(l10n.updateCheckFailed),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.ok),
            ),
          ],
        ),
      );
      return;
    }

    if (update == null) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(l10n.updateUpToDate),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.ok),
            ),
          ],
        ),
      );
      return;
    }

    await _offerUpdate(l10n, update);
  }

  Future<void> _offerUpdate(AppLocalizations l10n, UpdateInfo update) async {
    final manual = _updateService.installKind() == UpdateInstallKind.manual;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.updateAvailableTitle),
        content: Text(
          l10n.updateAvailableBody(update.version, _appVersion ?? ''),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              manual ? l10n.updateOpenDownloadPage : l10n.updateInstallNow,
            ),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;

    if (manual) {
      await _updateService.openUrl(update.releaseUrl);
      return;
    }

    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          content: Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 16),
              Expanded(child: Text(l10n.updateInstalling)),
            ],
          ),
        ),
      ),
    );
    final installed = await _updateService.installAndRestart(update);
    // installAndRestart only returns on failure; on success the process exits.
    if (!mounted) return;
    Navigator.pop(context);
    if (!installed) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(l10n.updateInstallFailed),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.ok),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _editAlias(
    AppLocalizations l10n,
    DeviceIdentityService identity,
  ) async {
    final controller = TextEditingController(text: identity.alias);
    final newAlias = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.renameDialogTitle),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(l10n.save),
          ),
        ],
      ),
    );
    if (newAlias != null && newAlias.trim().isNotEmpty) {
      await identity.updateAlias(newAlias);
    }
  }

  Future<void> _deleteAllConversations(AppLocalizations l10n) async {
    final confirmed = await confirmDelete(
      context,
      title: l10n.deleteAllTitle,
      body: l10n.deleteAllBody,
    );
    if (!confirmed || !mounted) return;
    final chatStore = context.read<ChatStore>();
    await chatStore.deleteAllConversations();
    final bytes = await chatStore.storageBytesUsed();
    if (mounted) setState(() => _storageBytes = bytes);
  }

  Future<void> _showPhotoOptions(
    AppLocalizations l10n,
    DeviceIdentityService identity,
    AvatarStore avatarStore,
  ) async {
    final hasPhoto = avatarStore.photoBytes(identity.id) != null;
    final action = await showModalBottomSheet<_PhotoAction>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_outlined),
              title: Text(l10n.profilePhotoChoose),
              onTap: () => Navigator.pop(context, _PhotoAction.choose),
            ),
            if (hasPhoto)
              ListTile(
                leading: const Icon(
                  Icons.delete_outline,
                  color: Colors.redAccent,
                ),
                title: Text(
                  l10n.profilePhotoRemove,
                  style: const TextStyle(color: Colors.redAccent),
                ),
                onTap: () => Navigator.pop(context, _PhotoAction.remove),
              ),
          ],
        ),
      ),
    );
    if (!mounted) return;

    switch (action) {
      case _PhotoAction.choose:
        final picked = await ImagePicker().pickImage(
          source: ImageSource.gallery,
        );
        if (picked == null) return;
        final bytes = await picked.readAsBytes();
        try {
          await avatarStore.setOwnPhoto(identity.id, bytes);
        } catch (_) {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(l10n.profilePhotoInvalid)));
          }
        }
      case _PhotoAction.remove:
        await avatarStore.removeOwnPhoto(identity.id);
      case null:
        break;
    }
  }

  Future<void> _clearMedia(AppLocalizations l10n, String ownId) async {
    final confirmed = await confirmDelete(
      context,
      title: l10n.clearMediaConfirmTitle,
      body: l10n.clearMediaConfirmBody,
    );
    if (!confirmed || !mounted) return;
    final avatarStore = context.read<AvatarStore>();
    final fileStore = context.read<FileStore>();
    final chatStore = context.read<ChatStore>();
    final receivedFileIds = await chatStore
        .receivedFileIdsForAllConversations();
    await avatarStore.clearCachedPhotos(exceptPeerId: ownId);
    await fileStore.deleteMessages(receivedFileIds);
    final bytes = await chatStore.storageBytesUsed();
    if (mounted) setState(() => _storageBytes = bytes);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final identity = context.watch<DeviceIdentityService>();
    final notifications = context.watch<NotificationService>();
    final localeService = context.watch<LocaleService>();
    final avatarStore = context.watch<AvatarStore>();
    final blockedCount = context.watch<ChatStore>().blockedConversations.length;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.navSettings, style: AppTypography.screenTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: AppColors.panel,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(26),
                  onTap: () => _showPhotoOptions(l10n, identity, avatarStore),
                  child: Avatar(
                    id: identity.id,
                    name: identity.alias,
                    diameter: 52,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(identity.alias, style: AppTypography.profileName),
                      const SizedBox(height: 2),
                      Text(
                        l10n.settingsDeviceIdLabel(shortPeerId(identity.id)),
                        style: AppTypography.monoCaption,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: AppColors.panel,
              borderRadius: BorderRadius.circular(16),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _row(
                  label: l10n.settingsDeviceName,
                  value: identity.alias,
                  onTap: () => _editAlias(l10n, identity),
                ),
                _divider(),
                _row(
                  label: l10n.settingsLanguage,
                  value: languageDisplayName(localeService.locale),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const LanguageScreen()),
                  ),
                ),
                _divider(),
                _row(
                  label: l10n.settingsNetwork,
                  value: _networkName ?? l10n.settingsUnavailable,
                ),
                _divider(),
                _switchRow(
                  label: l10n.settingsNotifications,
                  value: notifications.enabled,
                  onChanged: (v) => notifications.setEnabled(v),
                ),
                _divider(),
                _row(
                  label: l10n.settingsStorage,
                  value: l10n.settingsStorageUsed(
                    _formatBytes(l10n, _storageBytes),
                  ),
                ),
                _divider(),
                _row(
                  label: l10n.settingsBlockedUsers,
                  value: '$blockedCount',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const BlockedUsersScreen(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Container(
            decoration: BoxDecoration(
              color: AppColors.panel,
              borderRadius: BorderRadius.circular(16),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                InkWell(
                  onTap: () => _deleteAllConversations(l10n),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    child: Text(
                      l10n.deleteAllSettingsLabel,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 15,
                        color: Colors.redAccent,
                      ),
                    ),
                  ),
                ),
                _divider(),
                InkWell(
                  onTap: () => _clearMedia(l10n, identity.id),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    child: Text(
                      l10n.settingsClearMedia,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 15,
                        color: Colors.redAccent,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Container(
            decoration: BoxDecoration(
              color: AppColors.panel,
              borderRadius: BorderRadius.circular(16),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _row(label: l10n.settingsVersion, value: _appVersion ?? '…'),
                _divider(),
                _row(
                  label: l10n.settingsCheckForUpdates,
                  value: _checkingForUpdate ? '…' : '',
                  onTap: _checkingForUpdate
                      ? null
                      : () => _checkForUpdates(l10n),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() => const Divider(
    color: AppColors.borderSubtle,
    height: 1,
    indent: 16,
    endIndent: 16,
  );

  Widget _row({
    required String label,
    required String value,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 15,
                  color: AppColors.text,
                ),
              ),
            ),
            Text(value, style: AppTypography.body),
            if (onTap != null) ...[
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right,
                size: 18,
                color: AppColors.border,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _switchRow({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 15,
                color: AppColors.text,
              ),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.accent,
          ),
        ],
      ),
    );
  }
}
