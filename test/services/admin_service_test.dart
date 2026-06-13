import 'package:flutter_test/flutter_test.dart';
import 'package:okayspace/okayspace_api.dart';

import '../support/fake_api.dart';

void main() {
  group('AdminService', () {
    test('users() builds the q/limit/offset query', () async {
      final api = FakeApi()..on('GET', '/admin/users', json: {'users': []});
      await AdminService(api.client()).users(query: 'ada', limit: 25);
      final q = api.request('/admin/users').url.queryParameters;
      expect(q['q'], 'ada');
      expect(q['limit'], '25');
      expect(q.containsKey('offset'), isFalse);
    });

    test('banUser()/suspendUser() post the reason/days', () async {
      final api = FakeApi()
        ..on('POST', '/admin/users/u1/ban', json: {'ok': true})
        ..on('POST', '/admin/users/u1/suspend', json: {'ok': true});
      final svc = AdminService(api.client());
      await svc.banUser('u1', reason: 'spam');
      await svc.suspendUser('u1', days: 3, reason: 'cooldown');
      expect(api.body('/admin/users/u1/ban', method: 'POST'), {'reason': 'spam'});
      expect(api.body('/admin/users/u1/suspend', method: 'POST'),
          {'days': 3, 'reason': 'cooldown'});
    });

    // The following pin the §1 admin-route fixes (singular /transaction,
    // /admin/reset/{money,analytics}, /admin/web-build, /admin/mobile-only) so
    // they can't silently regress to the old broken paths.
    test('editTransaction() PATCHes singular /transaction with ref', () async {
      final api = FakeApi()..on('PATCH', '/admin/users/u1/transaction', json: {'ok': true});
      await AdminService(api.client()).editTransaction('u1', 'txn9', {'amount': 5});
      expect(api.request('/admin/users/u1/transaction', method: 'PATCH').method, 'PATCH');
      expect(api.body('/admin/users/u1/transaction', method: 'PATCH'),
          {'ref': 'txn9', 'amount': 5});
    });

    test('deleteTransaction() DELETEs singular /transaction with ref query', () async {
      final api = FakeApi()..on('DELETE', '/admin/users/u1/transaction', json: {'ok': true});
      await AdminService(api.client()).deleteTransaction('u1', 'txn9', adjust: true);
      final q = api.request('/admin/users/u1/transaction', method: 'DELETE').url.queryParameters;
      expect(q['ref'], 'txn9');
      expect(q['adjust_balance'], 'true');
    });

    test('resetMoney()/resetAnalytics() use the slash paths', () async {
      final api = FakeApi()
        ..on('POST', '/admin/reset/money', json: {'ok': true})
        ..on('POST', '/admin/reset/analytics', json: {'ok': true});
      final svc = AdminService(api.client());
      await svc.resetMoney();
      await svc.resetAnalytics();
      expect(api.request('/admin/reset/money').method, 'POST');
      expect(api.request('/admin/reset/analytics').method, 'POST');
    });

    test('setMobileOnly() and bumpWebBuild() hit the fixed paths', () async {
      final api = FakeApi()
        ..on('POST', '/admin/mobile-only', json: {'mobile_only': true})
        ..on('POST', '/admin/web-build', json: {'web_build': 'v2'});
      final svc = AdminService(api.client());
      await svc.setMobileOnly(true);
      await svc.bumpWebBuild();
      expect(api.body('/admin/mobile-only', method: 'POST'), {'enabled': true});
      expect(api.request('/admin/web-build').method, 'POST');
    });
  });
}
