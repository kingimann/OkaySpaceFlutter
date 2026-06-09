import 'package:dio/dio.dart';

/// A normalized error thrown by [ApiClient] for every failed request.
///
/// The OkaySpace backend reports errors as
/// `{"error": {"code": "...", "message": "..."}, "detail": {...}}` and uses
/// FastAPI's `{"detail": [...]}` shape for `422` validation errors. This type
/// flattens all of those into a single, predictable object.
class ApiException implements Exception {
  ApiException({
    required this.statusCode,
    required this.message,
    this.code,
    this.details,
    this.cause,
  });

  /// HTTP status code, or `null` for transport-level failures (no response).
  final int? statusCode;

  /// Machine-readable error code from the backend (e.g. `not_found`), if any.
  final String? code;

  /// Human-readable message, always populated.
  final String message;

  /// Raw error payload for callers that need the full detail.
  final Object? details;

  /// The original error (e.g. a [DioException]) when relevant.
  final Object? cause;

  bool get isNetworkError => statusCode == null;
  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;
  bool get isValidationError => statusCode == 422;

  /// Builds an [ApiException] from a Dio failure, extracting the backend's
  /// error envelope when present.
  factory ApiException.fromDio(DioException e) {
    final response = e.response;
    final status = response?.statusCode;
    final data = response?.data;

    if (status == null) {
      return ApiException(
        statusCode: null,
        message: _transportMessage(e),
        cause: e,
      );
    }

    String? code;
    String? message;
    Object? details = data;

    if (data is Map) {
      final error = data['error'];
      if (error is Map) {
        code = error['code']?.toString();
        message = error['message']?.toString();
      }
      // FastAPI validation errors live under `detail`.
      final detail = data['detail'];
      if (detail != null) {
        details = detail;
        message ??= _messageFromDetail(detail);
      }
      message ??= data['message']?.toString();
    }

    return ApiException(
      statusCode: status,
      code: code,
      message: message ?? 'Request failed with status $status.',
      details: details,
      cause: e,
    );
  }

  static String _transportMessage(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'The connection timed out. Please try again.';
      case DioExceptionType.connectionError:
        return 'Could not reach the server. Check your connection.';
      case DioExceptionType.cancel:
        return 'The request was cancelled.';
      default:
        return e.message ?? 'A network error occurred.';
    }
  }

  /// Pulls a readable message out of FastAPI's `detail` list.
  static String? _messageFromDetail(Object detail) {
    if (detail is String) return detail;
    if (detail is List && detail.isNotEmpty) {
      final first = detail.first;
      if (first is Map && first['msg'] != null) {
        final loc = first['loc'];
        final field = loc is List && loc.isNotEmpty ? loc.last : null;
        return field != null ? '$field: ${first['msg']}' : '${first['msg']}';
      }
    }
    return null;
  }

  @override
  String toString() =>
      'ApiException($statusCode${code != null ? ' $code' : ''}): $message';
}
