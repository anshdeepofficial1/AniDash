import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ani_dash/core/services/notification_inbox_service.dart';
import 'package:ani_dash/core/registery/sources/anime/justanime.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NotificationInboxService Tests', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await NotificationInboxService().clear();
    });

    test(
      'Adding notification correctly tracks unread count and properties',
      () async {
        final inbox = NotificationInboxService();
        await inbox.load();
        expect(await inbox.unreadCount(), 0);

        await inbox.add(
          dedupeKey: 'notif_1',
          title: 'New Episode Released',
          body: 'Episode 5 is now available!',
          route: '/details/12345',
          mediaId: '12345',
          systemNotificationId: 101,
        );

        expect(await inbox.unreadCount(), 1);
        final items = await inbox.load();
        final item = items.first;
        expect(item.id, 'notif_1');
        expect(item.isRead, false);
        expect(item.systemNotificationId, 101);
        expect(item.route, '/details/12345');
        expect(item.mediaId, '12345');
      },
    );

    test('markRead updates read status and unread count', () async {
      final inbox = NotificationInboxService();
      await inbox.load();

      await inbox.add(
        dedupeKey: 'notif_1',
        title: 'Test 1',
        body: 'Body 1',
        systemNotificationId: 101,
      );
      await inbox.add(
        dedupeKey: 'notif_2',
        title: 'Test 2',
        body: 'Body 2',
        systemNotificationId: 102,
      );

      expect(await inbox.unreadCount(), 2);

      await inbox.markRead('notif_1');
      expect(await inbox.unreadCount(), 1);

      final items = await inbox.load();
      expect(items.firstWhere((n) => n.id == 'notif_1').isRead, true);
      expect(items.firstWhere((n) => n.id == 'notif_2').isRead, false);
    });

    test(
      'markReadByRouteOrMedia marks matching notifications automatically',
      () async {
        final inbox = NotificationInboxService();
        await inbox.load();

        await inbox.add(
          dedupeKey: 'notif_anime',
          title: 'Jujutsu Kaisen',
          body: 'Episode 24 out',
          route: '/details/999',
          mediaId: '999',
          systemNotificationId: 201,
        );

        expect(await inbox.unreadCount(), 1);

        // Navigate to /details/999
        await inbox.markReadByRouteOrMedia('/details/999', '999');

        expect(await inbox.unreadCount(), 0);
        final items = await inbox.load();
        expect(items.first.isRead, true);
      },
    );

    test('markAllRead marks all items read', () async {
      final inbox = NotificationInboxService();
      await inbox.load();

      await inbox.add(dedupeKey: '1', title: 'T1', body: 'B1');
      await inbox.add(dedupeKey: '2', title: 'T2', body: 'B2');
      expect(await inbox.unreadCount(), 2);

      await inbox.markAllRead();
      expect(await inbox.unreadCount(), 0);

      final items = await inbox.load();
      expect(items.every((n) => n.isRead), true);
    });

    test('delete removes item from inbox', () async {
      final inbox = NotificationInboxService();
      await inbox.load();

      await inbox.add(dedupeKey: 'to_delete', title: 'T', body: 'B');
      var items = await inbox.load();
      expect(items.length, 1);

      await inbox.delete('to_delete');
      items = await inbox.load();
      expect(items.isEmpty, true);
      expect(await inbox.unreadCount(), 0);
    });
  });

  group('JustAnime Provider Tests', () {
    test('automatic selection precedes concrete JustAnime servers', () async {
      final provider = JustAnimeProvider();
      final servers = await provider.getSupportedServers();
      expect(servers.sub.isNotEmpty, true);
      expect(servers.sub.first.id, 'auto');
      expect(servers.sub.any((server) => server.id == 'megaplay'), true);

      expect(servers.dub.isNotEmpty, true);
      expect(servers.dub.first.id, 'auto');
      expect(servers.dub.any((server) => server.id == 'megaplay'), true);
    });
  });
}
