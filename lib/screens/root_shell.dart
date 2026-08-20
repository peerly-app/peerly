import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../design/colors.dart';
import '../design/typography.dart';
import '../l10n/app_localizations.dart';
import '../services/chat_store.dart';
import '../services/discovery_service.dart';
import '../utils/platform_info.dart';
import '../widgets/avatar.dart';
import '../widgets/confirm_dialog.dart';
import 'chat_screen.dart';
import 'conversations_screen.dart';
import 'nearby_screen.dart';
import 'settings_screen.dart';

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _mobileTabIndex = 0;
  String? _selectedPeerId;
  String? _selectedPeerAlias;

  @override
  Widget build(BuildContext context) {
    return isDesktopPlatform ? _buildDesktop(context) : _buildMobile(context);
  }

  Widget _buildMobile(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final screens = const [
      ConversationsScreen(),
      NearbyScreen(),
      SettingsScreen(),
    ];
    return Scaffold(
      body: IndexedStack(index: _mobileTabIndex, children: screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _mobileTabIndex,
        onDestinationSelected: (i) => setState(() => _mobileTabIndex = i),
        backgroundColor: AppColors.panel,
        indicatorColor: AppColors.accentSoft,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.chat_bubble_outline),
            selectedIcon: const Icon(Icons.chat_bubble),
            label: l10n.navMessages,
          ),
          NavigationDestination(
            icon: const Icon(Icons.wifi_tethering),
            label: l10n.navNearby,
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: l10n.navSettings,
          ),
        ],
      ),
    );
  }

  Widget _buildDesktop(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final discoveredCount = context.watch<DiscoveryService>().peers.length;
    final conversations = context.watch<ChatStore>().conversations;

    return Scaffold(
      body: Row(
        children: [
          Container(
            width: 280,
            decoration: const BoxDecoration(
              border: Border(right: BorderSide(color: AppColors.border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 8, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${l10n.navNearby.toUpperCase()} · $discoveredCount',
                          style: AppTypography.eyebrow,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.add_circle_outline,
                          color: AppColors.accent,
                          size: 20,
                        ),
                        tooltip: l10n.addDeviceTooltip,
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const NearbyScreen(),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.settings_outlined,
                          color: AppColors.textDim,
                          size: 20,
                        ),
                        tooltip: l10n.navSettings,
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SettingsScreen(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: conversations.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(18),
                          child: Text(
                            l10n.conversationsEmptySidebar,
                            style: AppTypography.body,
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          itemCount: conversations.length,
                          itemBuilder: (context, index) {
                            final c = conversations[index];
                            final active = c.peerId == _selectedPeerId;
                            return InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => setState(() {
                                _selectedPeerId = c.peerId;
                                _selectedPeerAlias = c.alias;
                              }),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 10,
                                ),
                                margin: const EdgeInsets.symmetric(vertical: 2),
                                decoration: BoxDecoration(
                                  color: active
                                      ? AppColors.accentSoft
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    Avatar(
                                      id: c.peerId,
                                      name: c.alias,
                                      diameter: 38,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            c.alias,
                                            style: const TextStyle(
                                              fontFamily: 'Inter',
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: AppColors.text,
                                            ),
                                          ),
                                          Text(
                                            conversationSubtitle(l10n, c),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontFamily: 'Inter',
                                              fontSize: 12,
                                              color: AppColors.textDim,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.close,
                                        size: 16,
                                        color: AppColors.textDim,
                                      ),
                                      tooltip: l10n.delete,
                                      visualDensity: VisualDensity.compact,
                                      onPressed: () async {
                                        final confirmed = await confirmDelete(
                                          context,
                                          title: l10n.deleteConversationTitle,
                                          body: l10n.deleteConversationBody(
                                            c.alias,
                                          ),
                                        );
                                        if (!confirmed || !context.mounted) {
                                          return;
                                        }
                                        await context
                                            .read<ChatStore>()
                                            .deleteConversation(c.peerId);
                                        if (!mounted) return;
                                        if (_selectedPeerId == c.peerId) {
                                          setState(() {
                                            _selectedPeerId = null;
                                            _selectedPeerAlias = null;
                                          });
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _selectedPeerId == null
                ? Center(
                    child: Text(
                      l10n.selectConversation,
                      style: AppTypography.body,
                    ),
                  )
                : ChatScreen(
                    key: ValueKey(_selectedPeerId),
                    peerId: _selectedPeerId!,
                    peerAlias: _selectedPeerAlias!,
                  ),
          ),
        ],
      ),
    );
  }
}
