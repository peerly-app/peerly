import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peero/screens/blocked_users_screen.dart';
import 'package:peero/services/chat_repository.dart';
import 'package:peero/widgets/avatar.dart';

import '../helpers/test_harness.dart';

void main() {
  late TestStores stores;

  setUp(() => stores = TestStores.inMemory());
  tearDown(() async => stores.dispose());

  Future<void> pumpScreen(WidgetTester tester) async {
    await setLargeSurface(tester);
    await tester.pumpWidget(
      wrapWithApp(const BlockedUsersScreen(), stores: stores),
    );
    await tester.pump();
  }

  Future<void> block(String peerId, String alias) =>
      stores.chatStore.setStatus(peerId, alias, ConversationStatus.blocked);

  testWidgets('shows an empty state when nobody is blocked', (tester) async {
    await pumpScreen(tester);

    expect(find.text(l10nFr.blockedUsersEmpty), findsOneWidget);
  });

  testWidgets('lists blocked peers with their short id', (tester) async {
    await block('7f3a9c12-0000-0000-0000-000000000000', 'Bob');
    await pumpScreen(tester);

    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('7F:3A:9C'), findsOneWidget);
    expect(find.byType(Avatar), findsOneWidget);
  });

  testWidgets('does not list unblocked conversations', (tester) async {
    await block('peer-1', 'Zoe');
    await stores.chatStore.setStatus(
      'peer-2',
      'Bob',
      ConversationStatus.accepted,
    );
    await pumpScreen(tester);

    expect(find.text('Zoe'), findsOneWidget);
    expect(find.text('Bob'), findsNothing);
  });

  testWidgets('sorts by alias', (tester) async {
    await block('peer-1', 'Zoe');
    await block('peer-2', 'Alice');
    await pumpScreen(tester);

    final names = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .where((d) => d == 'Zoe' || d == 'Alice')
        .toList();

    expect(names, ['Alice', 'Zoe']);
  });

  testWidgets('unblocking clears the relationship and empties the list', (
    tester,
  ) async {
    await block('peer-1', 'Bob');
    await pumpScreen(tester);

    await tester.tap(find.text(l10nFr.unblock));
    await tester.pump();

    expect(stores.chatStore.statusFor('peer-1'), isNull);
    expect(find.text(l10nFr.blockedUsersEmpty), findsOneWidget);
  });
}
