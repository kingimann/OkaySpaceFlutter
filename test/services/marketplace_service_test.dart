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

  group('MarketplaceService — offers', () {
    test('makeOffer() posts amount (+ optional message)', () async {
      final api = FakeApi()
        ..on('POST', '/listings/l1/offers', json: {'id': 'o1', 'status': 'pending', 'amount': 40});
      await MarketplaceService(api.client()).makeOffer('l1', 40, message: 'cash today');
      expect(api.body('/listings/l1/offers', method: 'POST'),
          {'amount': 40, 'message': 'cash today'});
    });

    test('listingOffers() reads the offers key', () async {
      final api = FakeApi()
        ..on('GET', '/listings/l1/offers', json: {
          'offers': [
            {'id': 'o1', 'amount': 40, 'status': 'pending'},
          ]
        });
      final out = await MarketplaceService(api.client()).listingOffers('l1');
      expect(out.single['id'], 'o1');
    });

    test('myOffers() returns made/received', () async {
      final api = FakeApi()
        ..on('GET', '/offers', json: {'made': [{'id': 'o1'}], 'received': []});
      final out = await MarketplaceService(api.client()).myOffers();
      expect((out['made'] as List).length, 1);
    });

    test('counterOffer() posts {amount}', () async {
      final api = FakeApi()..on('POST', '/offers/o1/counter', json: {'id': 'o1', 'status': 'countered'});
      await MarketplaceService(api.client()).counterOffer('o1', 48);
      expect(api.body('/offers/o1/counter', method: 'POST'), {'amount': 48});
    });

    test('accept/decline/accept-counter/withdraw hit the right paths', () async {
      final api = FakeApi()
        ..on('POST', '/offers/o1/accept', json: {'status': 'accepted'})
        ..on('POST', '/offers/o1/decline', json: {'status': 'declined'})
        ..on('POST', '/offers/o1/accept-counter', json: {'status': 'accepted'})
        ..on('POST', '/offers/o1/withdraw', json: {'status': 'withdrawn'});
      final svc = MarketplaceService(api.client());
      await svc.acceptOffer('o1');
      await svc.declineOffer('o1');
      await svc.acceptCounter('o1');
      await svc.withdrawOffer('o1');
      expect(api.request('/offers/o1/accept', method: 'POST').method, 'POST');
      expect(api.request('/offers/o1/decline', method: 'POST').method, 'POST');
      expect(api.request('/offers/o1/accept-counter', method: 'POST').method, 'POST');
      expect(api.request('/offers/o1/withdraw', method: 'POST').method, 'POST');
    });
  });

  group('MarketplaceService — saved searches', () {
    test('saveSearch() posts only the set fields', () async {
      final api = FakeApi()
        ..on('POST', '/marketplace/saved-searches', json: {'id': 's1', 'new_count': 0});
      await MarketplaceService(api.client())
          .saveSearch(query: 'bike', category: 'vehicles', maxPrice: 200);
      expect(api.body('/marketplace/saved-searches', method: 'POST'),
          {'query': 'bike', 'category': 'vehicles', 'max_price': 200});
    });

    test('savedSearches() reads the searches key', () async {
      final api = FakeApi()
        ..on('GET', '/marketplace/saved-searches', json: {
          'searches': [
            {'id': 's1', 'name': 'Bikes', 'new_count': 3},
          ]
        });
      final out = await MarketplaceService(api.client()).savedSearches();
      expect(out.single['new_count'], 3);
    });

    test('markSearchSeen() and delete hit the right paths', () async {
      final api = FakeApi()
        ..on('POST', '/marketplace/saved-searches/s1/seen', json: {'ok': true})
        ..on('DELETE', '/marketplace/saved-searches/s1', json: {'ok': true});
      final svc = MarketplaceService(api.client());
      await svc.markSearchSeen('s1');
      await svc.deleteSavedSearch('s1');
      expect(api.request('/marketplace/saved-searches/s1/seen', method: 'POST').method, 'POST');
      expect(api.request('/marketplace/saved-searches/s1', method: 'DELETE').method, 'DELETE');
    });
  });
}
