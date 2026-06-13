import 'package:flutter_test/flutter_test.dart';
import 'package:okayspace/okayspace_api.dart';

import '../support/fake_api.dart';

void main() {
  group('MarketplaceService', () {
    test('listings() builds the filter query and drops nulls', () async {
      final api = FakeApi()..on('GET', '/listings', json: []);
      await MarketplaceService(api.client())
          .listings(category: 'bikes', minPrice: 50, sort: 'new');
      final q = api.request('/listings').url.queryParameters;
      expect(q['category'], 'bikes');
      expect(q['min_price'], '50');
      expect(q['sort'], 'new');
      expect(q.containsKey('q'), isFalse);       // null query dropped
      expect(q.containsKey('max_price'), isFalse);
    });

    test('get() fetches one listing', () async {
      final api = FakeApi()..on('GET', '/listings/l1', json: {'id': 'l1', 'title': 'Bike'});
      final l = await MarketplaceService(api.client()).get('l1');
      expect(l.id, 'l1');
    });

    test('save()/unsave() POST and DELETE on /save', () async {
      final api = FakeApi()
        ..on('POST', '/listings/l1/save', json: {'ok': true, 'saved': true})
        ..on('DELETE', '/listings/l1/save', json: {'ok': true, 'saved': false});
      final svc = MarketplaceService(api.client());
      await svc.save('l1');
      await svc.unsave('l1');
      expect(api.request('/listings/l1/save', method: 'POST').method, 'POST');
      expect(api.request('/listings/l1/save', method: 'DELETE').method, 'DELETE');
    });

    test('addComment() posts text (+ optional parent_id)', () async {
      final api = FakeApi()
        ..on('POST', '/listings/l1/comments', json: {'id': 'c1', 'text': 'nice'});
      await MarketplaceService(api.client())
          .addComment('l1', 'nice', parentId: 'c0');
      expect(api.body('/listings/l1/comments', method: 'POST'),
          {'text': 'nice', 'parent_id': 'c0'});
    });

    test('report() posts a reason', () async {
      final api = FakeApi()..on('POST', '/listings/l1/report', json: {'ok': true});
      await MarketplaceService(api.client()).report('l1', 'spam');
      expect(api.body('/listings/l1/report', method: 'POST'), {'reason': 'spam'});
    });

    test('upsertBusiness() PUTs the changes', () async {
      final api = FakeApi()..on('PUT', '/marketplace/business', json: {'name': 'Shop'});
      await MarketplaceService(api.client()).upsertBusiness({'name': 'Shop'});
      expect(api.request('/marketplace/business', method: 'PUT').method, 'PUT');
      expect(api.body('/marketplace/business', method: 'PUT'), {'name': 'Shop'});
    });
  });
}
