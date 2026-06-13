/// A normalized error thrown by [ApiClient] for every failed request.
///
/// The OkaySpace backend reports errors in a few shapes: a top-level
/// `{"error": {"code", "message"}}` envelope, a business-error
/// `{"detail": {"code", "message"}}` (rate limits, self-transfer blocks, …),
/// a plain `{"detail": "message"}`, and FastAPI's `{"detail": [...]}` for
/// `422` validation. This type flattens all of those into a single,
/// predictable object, always exposing `code` and `message` when the backend
/// provides them.
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

  /// The original error (e.g. a [TransportFailure]) when relevant.
  final Object? cause;

  bool get isNetworkError => statusCode == null;
  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;
  bool get isValidationError => statusCode == 422;

  /// Builds an [ApiException] from an HTTP error response, extracting the
  /// backend's error envelope when present.
  factory ApiException.fromResponse(int statusCode, Object? data) {
    String? code;
    String? message;
    Object? details = data;

    if (data is Map) {
      final error = data['error'];
      if (error is Map) {
        code = error['code']?.toString();
        message = error['message']?.toString();
      }
      // Errors live under `detail`: a String (plain HTTPException), a List
      // (FastAPI 422 validation), or a Map {"code", "message"} which the
      // backend uses for business errors (rate limits, self-transfer blocks,
      // wrong security answer, invite-required, …).
      final detail = data['detail'];
      if (detail != null) {
        details = detail;
        if (detail is Map) {
          code ??= detail['code']?.toString();
          message ??= detail['message']?.toString();
        }
        message ??= _messageFromDetail(detail);
      }
      message ??= data['message']?.toString();
    }

    return ApiException(
      statusCode: statusCode,
      code: code,
      message: message ?? 'Request failed with status $statusCode.',
      details: details,
    );
  }

  /// A transport-level failure that produced no HTTP response.
  factory ApiException.network(String message, {Object? cause}) =>
      ApiException(statusCode: null, message: message, cause: cause);

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
