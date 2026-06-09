import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okayspace/okayspace_api.dart';

void main() {
  group('ApiException.fromDio', () {
    DioException dioError(int status, dynamic data) => DioException(
          requestOptions: RequestOptions(path: '/x'),
          response: Response(
            requestOptions: RequestOptions(path: '/x'),
            statusCode: status,
            data: data,
          ),
          type: DioExceptionType.badResponse,
        );

    test('extracts the backend error envelope', () {
      final e = ApiException.fromDio(dioError(404, {
        'error': {'code': 'not_found', 'message': 'Not Found'},
      }));
      expect(e.statusCode, 404);
      expect(e.code, 'not_found');
      expect(e.message, 'Not Found');
      expect(e.isNotFound, isTrue);
    });

    test('reads FastAPI 422 detail lists', () {
      final e = ApiException.fromDio(dioError(422, {
        'detail': [
          {
            'loc': ['body', 'email'],
            'msg': 'field required',
            'type': 'value_error.missing',
          }
        ],
      }));
      expect(e.statusCode, 422);
      expect(e.isValidationError, isTrue);
      expect(e.message, contains('email'));
      expect(e.message, contains('field required'));
    });

    test('flags transport failures with no response', () {
      final e = ApiException.fromDio(DioException(
        requestOptions: RequestOptions(path: '/x'),
        type: DioExceptionType.connectionError,
      ));
      expect(e.statusCode, isNull);
      expect(e.isNetworkError, isTrue);
    });
  });

  group('ApiClient auth header', () {
    test('attaches the stored bearer token to requests', () async {
      final store = InMemoryTokenStore();
      final dio = Dio();
      final captured = <String, dynamic>{};

      // Build the client first so its auth interceptor is registered, then add
      // a capturing interceptor that runs *after* it and short-circuits the
      // request (so nothing actually hits the network).
      final client = ApiClient(tokenStore: store, dio: dio);
      dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        captured.addAll(options.headers);
        handler.resolve(Response(
          requestOptions: options,
          statusCode: 200,
          data: {'ok': true},
        ));
      }));

      await client.setToken('tok_123');
      final result = await client.getJson('/auth/me');

      expect(captured['Authorization'], 'Bearer tok_123');
      expect(result, {'ok': true});
      expect(await client.isAuthenticated, isTrue);

      await client.clearToken();
      expect(await client.isAuthenticated, isFalse);
    });
  });
}
