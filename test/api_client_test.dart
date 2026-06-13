import 'package:flutter_test/flutter_test.dart';
import 'package:okayspace/okayspace_api.dart';

void main() {
  group('ApiException.fromResponse', () {
    test('extracts the backend error envelope', () {
      final e = ApiException.fromResponse(404, {
        'error': {'code': 'not_found', 'message': 'Not Found'},
      });
      expect(e.statusCode, 404);
      expect(e.code, 'not_found');
      expect(e.message, 'Not Found');
      expect(e.isNotFound, isTrue);
    });

    test('extracts code + message from a business-error detail map', () {
      // The backend uses {"detail": {"code", "message"}} for rate limits,
      // self-transfer blocks, wrong security answers, invite-required, etc.
      final e = ApiException.fromResponse(429, {
        'detail': {
          'code': 'rate_limited',
          'message': 'Too many transfers in the last hour. Try again later.',
        },
      });
      expect(e.statusCode, 429);
      expect(e.code, 'rate_limited');
      expect(e.message, 'Too many transfers in the last hour. Try again later.');
    });

    test('reads a plain string detail', () {
      final e = ApiException.fromResponse(400, {
        'detail': "You can't send money to yourself",
      });
      expect(e.message, "You can't send money to yourself");
    });

    test('prefers the top-level error envelope over detail', () {
      final e = ApiException.fromResponse(403, {
        'error': {'code': 'forbidden', 'message': 'Not allowed'},
        'detail': {'code': 'other', 'message': 'ignored'},
      });
      expect(e.code, 'forbidden');
      expect(e.message, 'Not allowed');
    });

    test('reads FastAPI 422 detail lists', () {
      final e = ApiException.fromResponse(422, {
        'detail': [
          {
            'loc': ['body', 'email'],
            'msg': 'field required',
            'type': 'value_error.missing',
          }
        ],
      });
      expect(e.statusCode, 422);
      expect(e.isValidationError, isTrue);
      expect(e.message, contains('email'));
      expect(e.message, contains('field required'));
    });

    test('flags transport failures with no response', () {
      final e = ApiException.network('Could not reach the server.');
      expect(e.statusCode, isNull);
      expect(e.isNetworkError, isTrue);
    });
  });

  group('ApiClient', () {
    test('attaches the stored bearer token and decodes JSON', () async {
      final store = InMemoryTokenStore();
      late HttpRequestData captured;
      final client = ApiClient(
        tokenStore: store,
        transport: (r) async {
          captured = r;
          return const RawResponse(200, '{"ok": true}');
        },
      );

      await client.setToken('tok_123');
      final result = await client.getJson('/auth/me');

      expect(captured.method, 'GET');
      expect(captured.headers['Authorization'], 'Bearer tok_123');
      expect(captured.url.path, endsWith('/auth/me'));
      expect(result, {'ok': true});
      expect(await client.isAuthenticated, isTrue);

      await client.clearToken();
      expect(await client.isAuthenticated, isFalse);
    });

    test('encodes the JSON body and drops null query values', () async {
      late HttpRequestData captured;
      final client = ApiClient(
        tokenStore: InMemoryTokenStore(),
        transport: (r) async {
          captured = r;
          return const RawResponse(200, '');
        },
      );

      final result = await client.postJson('/posts',
          body: {'text': 'hi'}, query: {'limit': 10, 'q': null});

      expect(captured.method, 'POST');
      expect(captured.headers['Content-Type'], 'application/json');
      expect(captured.body, '{"text":"hi"}');
      expect(captured.url.queryParameters, {'limit': '10'});
      expect(result, isNull); // empty reply body
    });

    test('throws ApiException and clears the token on 401', () async {
      final store = InMemoryTokenStore('tok_old');
      var unauthorized = false;
      final client = ApiClient(
        tokenStore: store,
        transport: (r) async => const RawResponse(401,
            '{"error":{"code":"unauthorized","message":"Session expired"}}'),
      )..onUnauthorized = () => unauthorized = true;

      await expectLater(
        client.getJson('/auth/me'),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 401)
            .having((e) => e.message, 'message', 'Session expired')),
      );
      expect(unauthorized, isTrue);
      expect(await store.read(), isNull);
    });

    test('wraps transport failures as network ApiExceptions', () async {
      final client = ApiClient(
        tokenStore: InMemoryTokenStore(),
        transport: (r) async =>
            throw TransportFailure('Could not reach the server.'),
      );

      await expectLater(
        client.getJson('/feed'),
        throwsA(isA<ApiException>()
            .having((e) => e.isNetworkError, 'isNetworkError', isTrue)),
      );
    });
  });
}
