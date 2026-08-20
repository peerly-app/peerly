import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../design/colors.dart';
import '../design/typography.dart';
import '../l10n/app_localizations.dart';
import '../services/chat_store.dart';
import '../utils/formatting.dart';
import '../widgets/avatar.dart';

class BlockedUsersScreen extends StatelessWidget {
  const BlockedUsersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final blocked = context.watch<ChatStore>().blockedConversations;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.settingsBlockedUsers,
          style: AppTypography.screenTitle,
        ),
      ),
      body: blocked.isEmpty
          ? Center(
              child: Text(l10n.blockedUsersEmpty, style: AppTypography.body),
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: blocked.length,
              separatorBuilder: (_, _) =>
                  const Divider(color: AppColors.borderSubtle, height: 1),
              itemBuilder: (context, index) {
                final c = blocked[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      Avatar(id: c.peerId, name: c.alias),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c.alias, style: AppTypography.listTitle),
                            const SizedBox(height: 2),
                            Text(
                              shortPeerId(c.peerId),
                              style: AppTypography.monoCaption,
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () => context
                            .read<ChatStore>()
                            .resetRelationship(c.peerId),
                        child: Text(l10n.unblock),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
