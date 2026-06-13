import 'package:flutter_test/flutter_test.dart';
import 'package:okayspace/okayspace_api.dart';

import '../support/fake_api.dart';

void main() {
  group('AuthService', () {
    test('login() posts identifier+password and persists the token', () async {
      final api = FakeApi()
        ..on('POST', '/auth/login',
            json: {'session_token': 'tok_new', 'user': {'user_id': 'u1', 'name': 'Ada'}});
      final client = api.client();
      final res = await AuthService(client).login(identifier: 'me@x.com', password: 'pw');

      expect(res.sessionToken, 'tok_new');
      expect(api.body('/auth/login', method: 'POST'),
          {'identifier': 'me@x.com', 'password': 'pw'});
      // Token persisted → client is authenticated for subsequent calls.
      expect(await client.isAuthenticated, isTrue);
    });

    test('register() includes invite_code only when provided', () async {
      final api = FakeApi()
        ..on('POST', '/auth/register', json: {'session_token': 't', 'user': {'user_id': 'u1'}});
      await AuthService(api.client()).register(
        email: 'a@b.com', password: 'pw', name: 'A', username: 'a', inviteCode: 'ABC123');
      expect(api.body('/auth/register', method: 'POST'), {
        'email': 'a@b.com', 'password': 'pw', 'name': 'A', 'username': 'a',
        'invite_code': 'ABC123',
      });
    });

    test('loginWith2fa() sends identifier (matches backend TwoFALogin)', () async {
      final api = FakeApi()
        ..on('POST', '/auth/login/2fa', json: {'session_token': 't', 'user': {'user_id': 'u1'}});
      await AuthService(api.client()).loginWith2fa(identifier: 'me@x.com', code: '123456');
      // Regression guard: the backend field is `identifier`, not `challenge_id`.
      expect(api.body('/auth/login/2fa', method: 'POST'),
          {'identifier': 'me@x.com', 'code': '123456'});
    });

    test('me() fetches the current user', () async {
      final api = FakeApi()..on('GET', '/auth/me', json: {'user_id': 'u1', 'name': 'Ada'});
      final u = await AuthService(api.client()).me();
      expect(u.userId, 'u1');
    });

    test('a token-less (2FA challenge) login response is not persisted', () async {
      final api = FakeApi()
        ..on('POST', '/auth/login',
            json: {'twofa_required': true, 'identifier': 'me@x.com', 'masked_phone': '•••12'});
      final client = api.client();
      // Start unauthenticated.
      await client.clearToken();
      final res = await AuthService(client).login(identifier: 'me@x.com', password: 'pw');
      expect(res.hasToken, isFalse);
      expect(await client.isAuthenticated, isFalse);
    });
  });
}
