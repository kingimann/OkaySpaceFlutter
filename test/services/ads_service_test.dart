import 'package:flutter_test/flutter_test.dart';
import 'package:okayspace/okayspace_api.dart';

import '../support/fake_api.dart';

void main() {
  group('AdsService', () {
    test('promotePost() posts days/budget/cpc', () async {
      final api = FakeApi()..on('POST', '/posts/p1/promote', json: {'id': 'p1', 'promoted_until': 'x'});
      await AdsService(api.client()).promotePost('p1', days: 7, budget: 50, cpc: 0.1);
      expect(api.body('/posts/p1/promote', method: 'POST'),
          {'days': 7, 'budget': 50, 'cpc': 0.1});
    });

    test('campaignList() reads the campaigns key', () async {
      final api = FakeApi()
        ..on('GET', '/promoted/campaigns', json: {
          'campaigns': [
            {'id': 'a1', 'spent': 3.0},
          ]
        });
      final out = await AdsService(api.client()).campaignList();
      expect(out.single['id'], 'a1');
    });

    test('account() reads the ad account', () async {
      final api = FakeApi()
        ..on('GET', '/promoted/account', json: {'balance': 12.0, 'funded': true});
      final out = await AdsService(api.client()).account();
      expect(out['balance'], 12.0);
    });

    test('topup() posts {amount}', () async {
      final api = FakeApi()..on('POST', '/promoted/account/topup', json: {'balance': 32.0});
      await AdsService(api.client()).topup(20);
      expect(api.body('/promoted/account/topup', method: 'POST'), {'amount': 20});
    });

    test('next() sends placement/slot query', () async {
      final api = FakeApi()..on('GET', '/promoted/next', json: {});
      await AdsService(api.client()).next(placement: 'feed');
      final q = api.request('/promoted/next').url.queryParameters;
      expect(q['placement'], 'feed');
      expect(q.containsKey('slot'), isFalse);   // null dropped
    });
  });
}
