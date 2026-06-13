import 'package:flutter_test/flutter_test.dart';
import 'package:okayspace/okayspace_api.dart';

import '../support/fake_api.dart';

void main() {
  group('HazardsService', () {
    test('report() posts type + coordinates', () async {
      final api = FakeApi()
        ..on('POST', '/hazards',
            json: {'id': 'h1', 'type': 'police', 'longitude': 1.0, 'latitude': 2.0});
      final out = await HazardsService(api.client())
          .report('police', lat: 2.0, lng: 1.0);
      expect(api.body('/hazards', method: 'POST'),
          {'type': 'police', 'latitude': 2.0, 'longitude': 1.0});
      expect(out.type, 'police');
    });

    test('nearby() sends lat/lng and parses the hazards list', () async {
      final api = FakeApi()
        ..on('GET', '/hazards', json: {
          'hazards': [
            {'id': 'h1', 'type': 'accident', 'longitude': 1.0, 'latitude': 2.0,
             'confirmations': 3, 'status': 'active'},
          ],
          'threshold': 2,
        });
      final out = await HazardsService(api.client())
          .nearby(lat: 2.0, lng: 1.0, radius: 5000);
      final q = api.request('/hazards').url.queryParameters;
      expect(q['latitude'], '2.0');
      expect(q['longitude'], '1.0');
      expect(out.single.type, 'accident');
      expect(out.single.confirmations, 3);
    });

    test('confirm()/dismiss() hit the right sub-paths', () async {
      final api = FakeApi()
        ..on('POST', '/hazards/h1/confirm', json: {'id': 'h1', 'type': 'police'})
        ..on('POST', '/hazards/h1/dismiss', json: {'id': 'h1', 'type': 'police'});
      final svc = HazardsService(api.client());
      await svc.confirm('h1');
      await svc.dismiss('h1');
      expect(api.request('/hazards/h1/confirm', method: 'POST').method, 'POST');
      expect(api.request('/hazards/h1/dismiss', method: 'POST').method, 'POST');
    });
  });
}
