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

    test('placeReviewSummary() parses count/average/histogram', () async {
      final api = FakeApi()
        ..on('GET', '/reviews/summary', json: {
          'place_key': 'pk1',
          'count': 2,
          'average': 4.5,
          'distribution': {'1': 0, '2': 0, '3': 0, '4': 1, '5': 1},
        });
      final s = await GuidesService(api.client()).placeReviewSummary('pk1');
      expect(api.request('/reviews/summary').url.queryParameters['place_key'], 'pk1');
      expect(s.count, 2);
      expect(s.average, 4.5);
      expect(s.distribution[5], 1);
    });

    test('nearbyRatedPlaces() sends geo query and parses the list', () async {
      final api = FakeApi()
        ..on('GET', '/reviews/nearby', json: [
          {
            'place_key': 'pk1',
            'place_name': 'Cafe',
            'longitude': -79.4,
            'latitude': 43.7,
            'count': 3,
            'average': 4.7,
            'distance_km': 0.8,
          },
        ]);
      final out = await GuidesService(api.client())
          .nearbyRatedPlaces(lat: 43.7, lng: -79.4, radiusKm: 5);
      final q = api.request('/reviews/nearby').url.queryParameters;
      expect(q['lat'], '43.7');
      expect(q['lng'], '-79.4');
      expect(q['radius_km'], '5.0');
      expect(out.single.placeName, 'Cafe');
      expect(out.single.average, 4.7);
    });
  });
}
