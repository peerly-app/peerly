import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../design/colors.dart';
import '../design/typography.dart';
import '../l10n/app_localizations.dart';
import '../services/chat_repository.dart';
import '../services/chat_store.dart';
import '../utils/formatting.dart';
import '../widgets/avatar.dart';
import '../widgets/confirm_dialog.dart';
import 'chat_screen.dart';
import 'nearby_screen.dart';

String conversationSubtitle(AppLocalizations l10n, ConversationSummary c) {
  return switch (c.status) {
    ConversationStatus.pendingOutgoing => l10n.conversationsRequestSentSubtitle,
    ConversationStatus.pendingIncoming =>
      l10n.conversationsRequestReceivedSubtitle,
    ConversationStatus.blocked || ConversationStatus.accepted =>
      c.lastText.isEmpty ? l10n.conversationsNewSubtitle : c.lastText,
  };
}

class ConversationsScreen extends StatelessWidget {
  const ConversationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final conversations = context.watch<ChatStore>().conversations;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.navMessages, style: AppTypography.screenTitle),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NearbyScreen()),
              ),
              child: Container(
                width: 34,
                height: 34,
                decoration: const BoxDecoration(
                  color: AppColors.accent,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.add, color: AppColors.onAccent),
              ),
            ),
          ),
        ],
      ),
      body: conversations.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  l10n.conversationsEmpty,
                  textAlign: TextAlign.center,
                  style: AppTypography.body,
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: conversations.length,
              separatorBuilder: (_, _) =>
                  const Divider(color: AppColors.borderSubtle, height: 1),
              itemBuilder: (context, index) {
                final c = conversations[index];
                return Dismissible(
                  key: ValueKey(c.peerId),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    color: Colors.redAccent,
                    child: const Icon(
                      Icons.delete_outline,
                      color: Colors.white,
                    ),
                  ),
                  confirmDismiss: (_) => confirmDelete(
                    context,
                    title: l10n.deleteConversationTitle,
                    body: l10n.deleteConversationBody(c.alias),
                  ),
                  onDismissed: (_) =>
                      context.read<ChatStore>().deleteConversation(c.peerId),
                  child: InkWell(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            ChatScreen(peerId: c.peerId, peerAlias: c.alias),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      child: Row(
                        children: [
                          Avatar(id: c.peerId, name: c.alias),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        c.alias,
                                        style: AppTypography.listTitle,
                                      ),
                                    ),
                                    Text(
                                      formatConversationTimestamp(
                                        c.lastTimestamp,
                                      ),
                                      style: const TextStyle(
                                        fontFamily: 'Inter',
                                        fontSize: 12,
                                        color: AppColors.textDim,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        conversationSubtitle(l10n, c),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppTypography.body,
                                      ),
                                    ),
                                    if (c.unreadCount > 0) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        width: 20,
                                        height: 20,
                                        alignment: Alignment.center,
                                        decoration: const BoxDecoration(
                                          color: AppColors.accent,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Text(
                                          '${c.unreadCount}',
                                          style: const TextStyle(
                                            fontFamily: 'Inter',
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.onAccent,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
