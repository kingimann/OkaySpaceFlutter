/// Small, null-tolerant coercion helpers shared by the hand-written models.
///
/// The OkaySpace spec is actively evolving, so models read defensively:
/// unexpected types degrade gracefully instead of throwing.
library;

String? asStringOrNull(Object? v) => v?.toString();

String asString(Object? v, [String fallback = '']) => v?.toString() ?? fallback;

int asInt(Object? v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

int? asIntOrNull(Object? v) {
  if (v == null) return null;
  return asInt(v);
}

double? asDoubleOrNull(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

bool asBool(Object? v, [bool fallback = false]) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) return v.toLowerCase() == 'true';
  return fallback;
}

DateTime? asDateOrNull(Object? v) {
  if (v is String) return DateTime.tryParse(v);
  return null;
}

DateTime asDate(Object? v) => asDateOrNull(v) ?? DateTime.fromMillisecondsSinceEpoch(0);

List<String> asStringList(Object? v) {
  if (v is List) return v.map((e) => e.toString()).toList();
  return const [];
}

/// Maps a JSON list into model objects, skipping malformed entries.
List<T> asModelList<T>(Object? v, T Function(Map<String, dynamic>) fromJson) {
  if (v is! List) return <T>[];
  final out = <T>[];
  for (final e in v) {
    if (e is Map) out.add(fromJson(Map<String, dynamic>.from(e)));
  }
  return out;
}

Map<String, dynamic>? asMapOrNull(Object? v) {
  if (v is Map) return Map<String, dynamic>.from(v);
  return null;
}
