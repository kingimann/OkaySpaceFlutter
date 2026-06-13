import 'package:flutter_test/flutter_test.dart';
import 'package:okayspace/okayspace_api.dart';

import '../support/fake_api.dart';

void main() {
  group('GuidesService — places', () {
    test('places() parses a Place list', () async {
      final api = FakeApi()
        ..on('GET', '/places', json: [
          {'id': 'p1', 'title': 'Cafe', 'longitude': 1.0, 'latitude': 2.0},
        ]);
      final out = await GuidesService(api.client()).places();
      expect(out.single.title, 'Cafe');
    });

    test('addPlace() posts only the provided fields', () async {
      final api = FakeApi()
        ..on('POST', '/places', json: {'id': 'p9', 'title': 'New', 'longitude': 0.0, 'latitude': 0.0});
      await GuidesService(api.client())
          .addPlace(title: 'New', longitude: 3.0, latitude: 4.0);
      expect(api.body('/places', method: 'POST'),
          {'title': 'New', 'longitude': 3.0, 'latitude': 4.0});
    });

    test('deletePlace() issues a DELETE', () async {
      final api = FakeApi()..on('DELETE', '/places/p1', json: {'ok': true});
      await GuidesService(api.client()).deletePlace('p1');
      expect(api.request('/places/p1').method, 'DELETE');
    });
  });

  group('GuidesService — guides', () {
    test('createGuide() posts name (+ optional color/icon)', () async {
      final api = FakeApi()..on('POST', '/guides', json: {'id': 'g1', 'name': 'Faves', 'created_at': '2026-01-01T00:00:00Z'});
      await GuidesService(api.client()).createGuide(name: 'Faves', color: '#fff');
      expect(api.body('/guides', method: 'POST'), {'name': 'Faves', 'color': '#fff'});
    });

    test('addToGuide()/removeFromGuide() target the place sub-path', () async {
      final api = FakeApi()
        ..on('POST', '/guides/g1/places/p1', json: {'id': 'g1', 'name': 'x', 'created_at': '2026-01-01T00:00:00Z'})
        ..on('DELETE', '/guides/g1/places/p1', json: {'id': 'g1', 'name': 'x', 'created_at': '2026-01-01T00:00:00Z'});
      final svc = GuidesService(api.client());
      await svc.addToGuide('g1', 'p1');
      await svc.removeFromGuide('g1', 'p1');
      expect(api.request('/guides/g1/places/p1', method: 'POST').method, 'POST');
      expect(api.request('/guides/g1/places/p1', method: 'DELETE').method, 'DELETE');
    });
  });

  group('GuidesService — reviews', () {
    test('placeReviews() sends the place_key query', () async {
      final api = FakeApi()..on('GET', '/reviews', json: []);
      await GuidesService(api.client()).placeReviews('pk1');
      expect(api.request('/reviews').url.queryParameters['place_key'], 'pk1');
    });

    test('addReview() posts the rating payload', () async {
      final api = FakeApi()
        ..on('POST', '/reviews', json: {'id': 'r1', 'place_key': 'pk1', 'rating': 5});
      await GuidesService(api.client())
          .addReview(placeKey: 'pk1', placeName: 'Cafe', rating: 5, text: 'great');
      expect(api.body('/reviews', method: 'POST'),
          {'place_key': 'pk1', 'place_name': 'Cafe', 'rating': 5, 'text': 'great'});
    });
  });
}
