import 'package:flutter_test/flutter_test.dart';
import 'package:okayspace/okayspace_api.dart';

import '../support/fake_api.dart';

void main() {
  group('MessagingService', () {
    test('conversations() parses the list', () async {
      final api = FakeApi()
        ..on('GET', '/conversations', json: [
          {'id': 'c1', 'kind': 'dm'},
        ]);
      final out = await MessagingService(api.client()).conversations();
      expect(out.single.id, 'c1');
    });

    test('startDirect() posts {recipient_user_id} (matches backend)', () async {
      final api = FakeApi()..on('POST', '/conversations', json: {'id': 'c1', 'kind': 'dm'});
      await MessagingService(api.client()).startDirect('u2');
      expect(api.body('/conversations', method: 'POST'), {'recipient_user_id': 'u2'});
    });

    test('createGroup() posts member_ids (+ optional name)', () async {
      final api = FakeApi()..on('POST', '/conversations/groups', json: {'id': 'c9', 'kind': 'group'});
      await MessagingService(api.client())
          .createGroup(memberIds: ['u1', 'u2'], name: 'Trip');
      expect(api.body('/conversations/groups', method: 'POST'),
          {'member_ids': ['u1', 'u2'], 'name': 'Trip'});
    });

    test('markRead() and leave() POST the right paths', () async {
      final api = FakeApi()
        ..on('POST', '/conversations/c1/read', json: {'ok': true})
        ..on('POST', '/conversations/c1/leave', json: {'ok': true});
      final svc = MessagingService(api.client());
      await svc.markRead('c1');
      await svc.leave('c1');
      expect(api.request('/conversations/c1/read').method, 'POST');
      expect(api.request('/conversations/c1/leave').method, 'POST');
    });

    test('setDisappearing() posts {seconds}', () async {
      final api = FakeApi()
        ..on('POST', '/conversations/c1/disappearing', json: {'id': 'c1', 'kind': 'dm'});
      await MessagingService(api.client()).setDisappearing('c1', 3600);
      expect(api.body('/conversations/c1/disappearing', method: 'POST'), {'seconds': 3600});
    });
  });
}
