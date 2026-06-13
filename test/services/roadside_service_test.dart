import 'package:flutter_test/flutter_test.dart';
import 'package:okayspace/okayspace_api.dart';

import '../support/fake_api.dart';

void main() {
  group('RoadsideService', () {
    test('submitVerification() posts the document + vehicle fields', () async {
      final api = FakeApi()..on('POST', '/roadside/verification', json: {'status': 'pending'});
      await RoadsideService(api.client()).submitVerification(
        insurancePhoto: 'data:ins',
        ownershipPhoto: 'data:own',
        vehicleMake: 'Toyota',
      );
      // Field names must match the backend RoadsideVerifySubmit model.
      expect(api.body('/roadside/verification', method: 'POST'), {
        'insurance_photo': 'data:ins',
        'ownership_photo': 'data:own',
        'vehicle_make': 'Toyota',
      });
    });

    test('mine() parses a request list', () async {
      final api = FakeApi()
        ..on('GET', '/roadside/mine', json: [
          {'id': 'r1', 'status': 'open'},
        ]);
      final out = await RoadsideService(api.client()).mine();
      expect(out.single.id, 'r1');
    });

    test('nearby() sends lat/lng/radius_km query', () async {
      final api = FakeApi()..on('GET', '/roadside/nearby', json: []);
      await RoadsideService(api.client()).nearby(lat: 43.6, lng: -79.3, radiusKm: 25);
      final q = api.request('/roadside/nearby').url.queryParameters;
      expect(q['lat'], '43.6');
      expect(q['lng'], '-79.3');
      expect(q['radius_km'], '25.0');   // double serializes with the decimal
    });

    test('active() hits /roadside/active', () async {
      final api = FakeApi()..on('GET', '/roadside/active', body: '');
      await RoadsideService(api.client()).active();
      expect(api.request('/roadside/active').method, 'GET');
    });

    test('transitInfo() returns the full payload with stops + departures', () async {
      final api = FakeApi()
        ..on('GET', '/transit/nearby', json: {
          'configured': true,
          'stops': [
            {'name': 'Main St', 'onestop_id': 's-1', 'lat': 43.6, 'lon': -79.3},
          ],
          'departures': [
            {'stop_id': 's-1', 'route': '501', 'minutes': 4, 'realtime': true},
          ],
        });
      final out = await RoadsideService(api.client())
          .transitInfo(lat: 43.6, lng: -79.3, radius: 800);
      final q = api.request('/transit/nearby').url.queryParameters;
      expect(q['lat'], '43.6');
      expect(q['lon'], '-79.3');
      expect((out['stops'] as List).length, 1);
      expect((out['departures'] as List).first['route'], '501');
    });
  });
}
