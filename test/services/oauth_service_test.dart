import 'package:flutter_test/flutter_test.dart';
import 'package:okayspace/okayspace_api.dart';

import '../support/fake_api.dart';

void main() {
  group('OAuthService', () {
    test('createApp() posts the app body and returns credentials', () async {
      final api = FakeApi()
        ..on('POST', '/oauth/apps',
            json: {'client_id': 'cid', 'client_secret': 'csec', 'name': 'App'});
      final out = await OAuthService(api.client()).createApp(
          {'name': 'App', 'redirect_uris': ['https://x/cb']});
      expect(out['client_id'], 'cid');
      expect(api.body('/oauth/apps', method: 'POST'),
          {'name': 'App', 'redirect_uris': ['https://x/cb']});
    });

    test('app() fetches public metadata by client id', () async {
      final api = FakeApi()..on('GET', '/oauth/app/cid', json: {'client_id': 'cid', 'name': 'App'});
      final out = await OAuthService(api.client()).app('cid');
      expect(out['name'], 'App');
    });

    test('token() exchanges a code', () async {
      final api = FakeApi()..on('POST', '/oauth/token', json: {'access_token': 'at'});
      final out = await OAuthService(api.client())
          .token({'grant_type': 'authorization_code', 'code': 'abc'});
      expect(out['access_token'], 'at');
    });

    test('revokeConnection() DELETEs the connection', () async {
      final api = FakeApi()..on('DELETE', '/oauth/connections/cid', json: {'revoked': true});
      await OAuthService(api.client()).revokeConnection('cid');
      expect(api.request('/oauth/connections/cid').method, 'DELETE');
    });

    test('deleteApp() DELETEs the app', () async {
      final api = FakeApi()..on('DELETE', '/oauth/apps/cid', json: {'deleted': true});
      await OAuthService(api.client()).deleteApp('cid');
      expect(api.request('/oauth/apps/cid').method, 'DELETE');
    });
  });
}
