import 'package:flutter_test/flutter_test.dart';
import 'package:okayspace/okayspace_api.dart';

import '../support/fake_api.dart';

void main() {
  group('MonetizeService', () {
    test('sites() reads the sites key', () async {
      final api = FakeApi()
        ..on('GET', '/pub/sites', json: {
          'sites': [
            {'id': 's1', 'name': 'blog', 'site_key': 'pub_x'},
          ]
        });
      final out = await MonetizeService(api.client()).sites();
      expect(out.single.id, 's1');
    });

    test('createSite() posts name (+ domain only when set)', () async {
      final api = FakeApi()
        ..on('POST', '/pub/sites', json: {'id': 's9', 'name': 'shop', 'site_key': 'pub_y'});
      await MonetizeService(api.client()).createSite(name: 'shop', domain: 'shop.example');
      expect(api.body('/pub/sites', method: 'POST'),
          {'name': 'shop', 'domain': 'shop.example'});
    });

    test('createSite() omits an empty domain', () async {
      final api = FakeApi()..on('POST', '/pub/sites', json: {'id': 's9', 'name': 'shop', 'site_key': 'k'});
      await MonetizeService(api.client()).createSite(name: 'shop');
      expect(api.body('/pub/sites', method: 'POST'), {'name': 'shop'});
    });

    test('deleteSite() DELETEs the site', () async {
      final api = FakeApi()..on('DELETE', '/pub/sites/s1', json: {'ok': true});
      await MonetizeService(api.client()).deleteSite('s1');
      expect(api.request('/pub/sites/s1').method, 'DELETE');
    });
  });
}
