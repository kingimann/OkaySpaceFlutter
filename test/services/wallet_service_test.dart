import 'package:flutter_test/flutter_test.dart';
import 'package:okayspace/okayspace_api.dart';

import '../support/fake_api.dart';

void main() {
  group('WalletService', () {
    test('summary() parses the wallet payload', () async {
      final api = FakeApi()..on('GET', '/wallet', json: {'balance': 12.5, 'currency': 'USD'});
      final s = await WalletService(api.client()).summary();
      expect(s.balance, 12.5);
    });

    test('setCurrency() posts {currency}', () async {
      final api = FakeApi()..on('POST', '/wallet/currency', json: {'ok': true});
      await WalletService(api.client()).setCurrency('CAD');
      expect(api.body('/wallet/currency', method: 'POST'), {'currency': 'CAD'});
    });

    test('topupIntent() posts amount (+ optional currency)', () async {
      final api = FakeApi()..on('POST', '/wallet/topup/intent', json: {'client_secret': 'pi_x'});
      await WalletService(api.client()).topupIntent(20, currency: 'usd');
      expect(api.body('/wallet/topup/intent', method: 'POST'),
          {'amount': 20, 'currency': 'usd'});
    });

    test('sendMoney() includes the per-transfer security fields only when set', () async {
      final api = FakeApi()..on('POST', '/money/send', json: {'ok': true});
      await WalletService(api.client()).sendMoney(
        toUserId: 'u2', amount: 5, answer: '', note: 'lunch',
        securityQuestion: 'city?', securityAnswer: 'toronto',
      );
      expect(api.body('/money/send', method: 'POST'), {
        'to_user_id': 'u2',
        'amount': 5,
        'answer': '',
        'note': 'lunch',
        'security_question': 'city?',
        'security_answer': 'toronto',
      });
    });

    test('sendMoney() omits empty security fields', () async {
      final api = FakeApi()..on('POST', '/money/send', json: {'ok': true});
      await WalletService(api.client())
          .sendMoney(toUserId: 'u2', amount: 5, answer: 'a');
      final body = api.body('/money/send', method: 'POST');
      expect(body.containsKey('security_question'), isFalse);
      expect(body.containsKey('note'), isFalse);
    });

    test('payRequest() always sends answer (required by backend PayRequest)', () async {
      final api = FakeApi()
        ..on('POST', '/money/requests/r1/pay', json: {'ok': true})
        ..on('POST', '/money/requests/r2/pay', json: {'ok': true});
      final svc = WalletService(api.client());
      await svc.payRequest('r1', answer: 'secret');
      await svc.payRequest('r2');   // no answer → empty string, not omitted
      expect(api.body('/money/requests/r1/pay', method: 'POST'), {'answer': 'secret'});
      expect(api.body('/money/requests/r2/pay', method: 'POST'), {'answer': ''});
    });

    test('acceptTransfer() sends the answer when set', () async {
      final api = FakeApi()..on('POST', '/money/transfers/t1/accept', json: {'ok': true});
      await WalletService(api.client()).acceptTransfer('t1', answer: 'toronto');
      expect(api.body('/money/transfers/t1/accept', method: 'POST'), {'answer': 'toronto'});
    });

    test('setAutoDeposit() posts {enabled}', () async {
      final api = FakeApi()..on('POST', '/money/auto-deposit', json: {'enabled': true});
      await WalletService(api.client()).setAutoDeposit(true);
      expect(api.body('/money/auto-deposit', method: 'POST'), {'enabled': true});
    });
  });
}
