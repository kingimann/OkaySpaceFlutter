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

    test('scheduleMessage() wraps text in a MessageCreate body (not a bare string)', () async {
      final api = FakeApi()..on('POST', '/conversations/c1/scheduled', json: {'ok': true});
      await MessagingService(api.client())
          .scheduleMessage('c1', 'later!', DateTime.utc(2030, 1, 1, 12));
      final body = api.body('/conversations/c1/scheduled', method: 'POST');
      // Regression guard: backend ScheduledCreate.body is a MessageCreate object.
      expect(body['body'], {'type': 'text', 'text': 'later!'});
      expect(body['send_at'], '2030-01-01T12:00:00.000Z');
    });

    test('send() posts the MessageCreate payload', () async {
      final api = FakeApi()..on('POST', '/conversations/c1/messages', json: {'id': 'm1', 'type': 'text'});
      await MessagingService(api.client()).sendText('c1', 'hello');
      expect(api.body('/conversations/c1/messages', method: 'POST'),
          {'type': 'text', 'text': 'hello'});
    });

    test('setPresence() sends the typing bool the backend reads', () async {
      final api = FakeApi()
        ..on('POST', '/conversations/c1/presence', json: {'ok': true});
      final svc = MessagingService(api.client());
      await svc.setPresence('c1', 'typing');
      expect(api.body('/conversations/c1/presence', method: 'POST'),
          {'typing': true, 'state': 'typing'});
      await svc.setPresence('c1', 'idle');
      expect(api.body('/conversations/c1/presence', method: 'POST'),
          {'typing': false, 'state': 'idle'});
    });

    test('presence() GETs the conversation presence map', () async {
      final api = FakeApi()
        ..on('GET', '/conversations/c1/presence',
            json: {'typing': true, 'active': true, 'typing_ids': ['u2']});
      final svc = MessagingService(api.client());
      final p = await svc.presence('c1');
      expect(api.request('/conversations/c1/presence').method, 'GET');
      expect(p['typing'], true);
      expect(p['typing_ids'], ['u2']);
    });

    test('reactToMessage() posts {emoji}; editMessage() patches {text}', () async {
      final api = FakeApi()
        ..on('POST', '/conversations/c1/messages/m1/react', json: {'id': 'm1', 'type': 'text'})
        ..on('PATCH', '/conversations/c1/messages/m1', json: {'id': 'm1', 'type': 'text'});
      final svc = MessagingService(api.client());
      await svc.reactToMessage('c1', 'm1', '🔥');
      await svc.editMessage('c1', 'm1', 'edited');
      expect(api.body('/conversations/c1/messages/m1/react', method: 'POST'), {'emoji': '🔥'});
      expect(api.body('/conversations/c1/messages/m1', method: 'PATCH'), {'text': 'edited'});
    });
  });
}
