import 'package:flutter_test/flutter_test.dart';
import 'package:okayspace/okayspace_api.dart';

import '../support/fake_api.dart';

void main() {
  group('SupportService', () {
    test('createTicket() posts subject/message/category', () async {
      final api = FakeApi()..on('POST', '/support/tickets', json: {'id': 't1', 'status': 'awaiting_staff'});
      await SupportService(api.client())
          .createTicket(subject: 'Help', message: 'broke', category: 'bug');
      expect(api.body('/support/tickets', method: 'POST'),
          {'subject': 'Help', 'message': 'broke', 'category': 'bug'});
    });

    test('reply() sends the canonical `text` field (backend TicketReply)', () async {
      final api = FakeApi()
        ..on('POST', '/support/tickets/t1/messages', json: {'id': 't1'});
      await SupportService(api.client()).reply('t1', 'any update?');
      // Regression guard: the backend model field is `text`, not `message`.
      expect(api.body('/support/tickets/t1/messages', method: 'POST'),
          {'text': 'any update?'});
    });

    test('setStatus() posts the status', () async {
      final api = FakeApi()..on('POST', '/support/tickets/t1/status', json: {'id': 't1', 'status': 'closed'});
      await SupportService(api.client()).setStatus('t1', 'closed');
      expect(api.body('/support/tickets/t1/status', method: 'POST'), {'status': 'closed'});
    });

    test('unreadCount() reads count/unread', () async {
      final api = FakeApi()..on('GET', '/support/unread-count', json: {'count': 3});
      expect(await SupportService(api.client()).unreadCount(), 3);
    });

    test('ticket() fetches a single ticket', () async {
      final api = FakeApi()..on('GET', '/support/tickets/t1', json: {'id': 't1', 'subject': 'x'});
      final t = await SupportService(api.client()).ticket('t1');
      expect(t['id'], 't1');
    });
  });
}
