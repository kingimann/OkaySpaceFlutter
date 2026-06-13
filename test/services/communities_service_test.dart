import 'package:flutter_test/flutter_test.dart';
import 'package:okayspace/okayspace_api.dart';

import '../support/fake_api.dart';

void main() {
  group('CommunitiesService', () {
    test('list() parses communities and drops null query values', () async {
      final api = FakeApi()
        ..on('GET', '/communities', json: [
          {'name': 'coffee', 'title': 'Coffee'},
          {'name': 'cars', 'title': 'Cars'},
        ]);
      final out = await CommunitiesService(api.client()).list(query: 'co');
      expect(out.map((c) => c.name), ['coffee', 'cars']);
      // q is sent, sort (null) is dropped.
      final q = api.request('/communities').url.queryParameters;
      expect(q['q'], 'co');
      expect(q.containsKey('sort'), isFalse);
    });

    test('get() fetches a single community by name', () async {
      final api = FakeApi()..on('GET', '/communities/coffee', json: {'name': 'coffee', 'title': 'Coffee'});
      final c = await CommunitiesService(api.client()).get('coffee');
      expect(c.name, 'coffee');
    });

    test('create() posts only the provided fields', () async {
      final api = FakeApi()..on('POST', '/communities', json: {'name': 'new', 'title': 'New'});
      await CommunitiesService(api.client())
          .create(name: 'new', title: 'New', rules: ['be kind']);
      expect(api.body('/communities', method: 'POST'),
          {'name': 'new', 'title': 'New', 'rules': ['be kind']});
    });

    test('join()/leave() use POST and DELETE on /join', () async {
      final api = FakeApi()
        ..on('POST', '/communities/coffee/join', json: {'joined': true})
        ..on('DELETE', '/communities/coffee/join', json: {'joined': false});
      final svc = CommunitiesService(api.client());
      await svc.join('coffee');
      await svc.leave('coffee');
      expect(api.request('/communities/coffee/join', method: 'POST').method, 'POST');
      expect(api.request('/communities/coffee/join', method: 'DELETE').method, 'DELETE');
    });

    test('favorite()/unfavorite() use POST and DELETE on /favorite', () async {
      final api = FakeApi()
        ..on('POST', '/communities/coffee/favorite', json: {'favorite': true})
        ..on('DELETE', '/communities/coffee/favorite', json: {'favorite': false});
      final svc = CommunitiesService(api.client());
      await svc.favorite('coffee');
      await svc.unfavorite('coffee');
      expect(api.request('/communities/coffee/favorite', method: 'POST').method, 'POST');
      expect(api.request('/communities/coffee/favorite', method: 'DELETE').method, 'DELETE');
    });
  });
}
