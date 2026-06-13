import 'package:flutter_test/flutter_test.dart';
import 'package:okayspace/okayspace_api.dart';

import '../support/fake_api.dart';

void main() {
  group('FriendsService', () {
    test('friends() parses a PublicUser list', () async {
      final api = FakeApi()
        ..on('GET', '/friends', json: [
          {'user_id': 'u1', 'name': 'Ada'},
          {'user_id': 'u2', 'name': 'Bo'},
        ]);
      final out = await FriendsService(api.client()).friends();
      expect(out.map((u) => u.userId), ['u1', 'u2']);
      expect(out.first.name, 'Ada');
    });

    test('requests() hits /friends/requests', () async {
      final api = FakeApi()..on('GET', '/friends/requests', json: []);
      await FriendsService(api.client()).requests();
      expect(api.request('/friends/requests').method, 'GET');
    });

    test('sendRequest() POSTs to /friends/request/{id}', () async {
      final api = FakeApi()..on('POST', '/friends/request/u9', json: {'status': 'request_sent'});
      await FriendsService(api.client()).sendRequest('u9');
      expect(api.request('/friends/request/u9').method, 'POST');
    });

    test('accept() and reject() target the right paths', () async {
      final api = FakeApi()
        ..on('POST', '/friends/accept/u1', json: {'status': 'friends'})
        ..on('POST', '/friends/reject/u2', json: {'status': 'rejected'});
      final svc = FriendsService(api.client());
      await svc.accept('u1');
      await svc.reject('u2');
      expect(api.request('/friends/accept/u1').method, 'POST');
      expect(api.request('/friends/reject/u2').method, 'POST');
    });

    test('cancelRequest() and remove() issue DELETEs', () async {
      final api = FakeApi()
        ..on('DELETE', '/friends/request/u1', json: {'status': 'none'})
        ..on('DELETE', '/friends/u2', json: {'status': 'none'});
      final svc = FriendsService(api.client());
      await svc.cancelRequest('u1');
      await svc.remove('u2');
      expect(api.request('/friends/request/u1').method, 'DELETE');
      expect(api.request('/friends/u2').method, 'DELETE');
    });
  });
}
