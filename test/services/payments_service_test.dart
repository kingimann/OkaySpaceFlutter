import 'package:flutter_test/flutter_test.dart';
import 'package:okayspace/okayspace_api.dart';

import '../support/fake_api.dart';

void main() {
  group('PaymentsService', () {
    test('config() and capabilities() hit the right paths', () async {
      final api = FakeApi()
        ..on('GET', '/payments/config', json: {'publishable_key': 'pk', 'cashout_min': 20.0})
        ..on('GET', '/capabilities', json: {'stripe_rails': true});
      final svc = PaymentsService(api.client());
      expect((await svc.config())['cashout_min'], 20.0);
      expect((await svc.capabilities())['stripe_rails'], true);
    });

    test('newIdempotencyKey() is 32 hex chars and unique per call', () {
      final a = PaymentsService.newIdempotencyKey();
      final b = PaymentsService.newIdempotencyKey();
      expect(a, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(a, isNot(equals(b)));
    });

    test('checkout() posts the body and returns the session', () async {
      final api = FakeApi()
        ..on('POST', '/payments/checkout', json: {'id': 'cs_1', 'url': 'https://pay'});
      final out = await PaymentsService(api.client())
          .checkout({'kind': 'topup', 'amount': 25});
      expect(out['id'], 'cs_1');
      expect(api.body('/payments/checkout', method: 'POST'), {'kind': 'topup', 'amount': 25});
    });

    test('payoutStatus() reads the balance fields', () async {
      final api = FakeApi()
        ..on('GET', '/payments/payouts/status',
            json: {'wallet_balance': 9.9, 'stripe_available': 0.0, 'payouts_enabled': true});
      final out = await PaymentsService(api.client()).payoutStatus();
      expect(out['wallet_balance'], 9.9);
      expect(out['payouts_enabled'], true);
    });

    test('startIdentity() POSTs the identity start', () async {
      final api = FakeApi()
        ..on('POST', '/payments/identity/start', json: {'client_secret': 'vi_x'});
      final out = await PaymentsService(api.client()).startIdentity();
      expect(out['client_secret'], 'vi_x');
      expect(api.request('/payments/identity/start').method, 'POST');
    });
  });
}
