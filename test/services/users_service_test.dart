import 'package:flutter_test/flutter_test.dart';
import 'package:okayspace/okayspace_api.dart';

import '../support/fake_api.dart';

void main() {
  group('UsersService', () {
    test('publicProfile() parses a PublicUser', () async {
      final api = FakeApi()..on('GET', '/users/u1/public', json: {'user_id': 'u1', 'name': 'Ada'});
      final u = await UsersService(api.client()).publicProfile('u1');
      expect(u.userId, 'u1');
      expect(u.name, 'Ada');
    });

    test('search() sends the q query and parses users', () async {
      final api = FakeApi()
        ..on('GET', '/users/search', json: [
          {'user_id': 'u1', 'name': 'Ada'},
        ]);
      final out = await UsersService(api.client()).search('ad');
      expect(out.single.userId, 'u1');
      expect(api.request('/users/search').url.queryParameters['q'], 'ad');
    });

    test('follow() POSTs to /follow', () async {
      final api = FakeApi()..on('POST', '/users/u1/follow', json: {'ok': true});
      await UsersService(api.client()).follow('u1');
      expect(api.request('/users/u1/follow').method, 'POST');
    });

    test('subscribe() includes tier only when set; unsubscribe DELETEs', () async {
      final api = FakeApi()
        ..on('POST', '/users/u1/subscribe', json: {'ok': true})
        ..on('DELETE', '/users/u1/subscribe', json: {'ok': true});
      final svc = UsersService(api.client());
      await svc.subscribe('u1', tier: 'gold');
      expect(api.body('/users/u1/subscribe', method: 'POST'), {'tier': 'gold'});
      await svc.unsubscribe('u1');
      expect(api.request('/users/u1/subscribe', method: 'DELETE').method, 'DELETE');
    });

    test('leaderboard() reads any of the list keys', () async {
      final api = FakeApi()
        ..on('GET', '/points/leaderboard', json: {
          'leaders': [
            {'user_id': 'u1', 'points': 100},
          ]
        });
      final out = await UsersService(api.client()).leaderboard();
      expect(out.single['points'], 100);
    });
  });
}
