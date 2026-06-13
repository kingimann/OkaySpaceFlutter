import 'package:flutter_test/flutter_test.dart';
import 'package:okayspace/okayspace_api.dart';

import '../support/fake_api.dart';

void main() {
  group('NotificationsService', () {
    test('list() parses notifications', () async {
      final api = FakeApi()
        ..on('GET', '/notifications', json: [
          {'id': 'n1', 'type': 'like', 'read': false},
          {'id': 'n2', 'type': 'repost', 'read': true},
        ]);
      final out = await NotificationsService(api.client()).list();
      expect(out.length, 2);
      expect(out.first.id, 'n1');
    });

    test('unreadCount() reads the count key', () async {
      final api = FakeApi()..on('GET', '/notifications/unread', json: {'count': 4});
      expect(await NotificationsService(api.client()).unreadCount(), 4);
    });

    test('unreadCount() falls back to the unread key', () async {
      final api = FakeApi()..on('GET', '/notifications/unread', json: {'unread': 7});
      expect(await NotificationsService(api.client()).unreadCount(), 7);
    });

    test('markRead() POSTs to /{id}/read', () async {
      final api = FakeApi()..on('POST', '/notifications/n1/read', json: {'ok': true});
      await NotificationsService(api.client()).markRead('n1');
      expect(api.request('/notifications/n1/read').method, 'POST');
    });

    test('markAllRead() POSTs to /read-all', () async {
      final api = FakeApi()..on('POST', '/notifications/read-all', json: {'ok': true});
      await NotificationsService(api.client()).markAllRead();
      expect(api.request('/notifications/read-all').method, 'POST');
    });

    test('dismiss() DELETEs the notification', () async {
      final api = FakeApi()..on('DELETE', '/notifications/n1', json: {'ok': true});
      await NotificationsService(api.client()).dismiss('n1');
      expect(api.request('/notifications/n1').method, 'DELETE');
    });
  });
}
