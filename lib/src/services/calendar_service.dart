import '../core/api_client.dart';
import '../models/json.dart';
import '../models/calendar_event.dart';

/// Endpoints under `/calendar`: the user's private calendar events.
class CalendarService {
  CalendarService(this._client);

  final ApiClient _client;

  CalendarEvent _event(Object? d) =>
      CalendarEvent.fromJson(asMapOrNull(d) ?? const {});

  /// The user's events, soonest first. Optionally limited to a [start, end)
  /// window (events overlapping the window are returned) for a month view.
  Future<List<CalendarEvent>> events({DateTime? start, DateTime? end}) async =>
      asModelList(
          await _client.getJson('/calendar/events', query: {
            if (start != null) 'start': start.toUtc().toIso8601String(),
            if (end != null) 'end': end.toUtc().toIso8601String(),
          }),
          CalendarEvent.fromJson);

  Future<CalendarEvent> create({
    required String title,
    required DateTime startAt,
    DateTime? endAt,
    bool allDay = false,
    String? notes,
    String? color,
  }) async =>
      _event(await _client.postJson('/calendar/events', body: {
        'title': title,
        'start_at': startAt.toUtc().toIso8601String(),
        if (endAt != null) 'end_at': endAt.toUtc().toIso8601String(),
        'all_day': allDay,
        if (notes != null) 'notes': notes,
        if (color != null) 'color': color,
      }));

  Future<CalendarEvent> update(
    String id, {
    required String title,
    required DateTime startAt,
    DateTime? endAt,
    bool allDay = false,
    String? notes,
    String? color,
  }) async =>
      _event(await _client.patchJson('/calendar/events/$id', body: {
        'title': title,
        'start_at': startAt.toUtc().toIso8601String(),
        if (endAt != null) 'end_at': endAt.toUtc().toIso8601String(),
        'all_day': allDay,
        if (notes != null) 'notes': notes,
        if (color != null) 'color': color,
      }));

  Future<void> delete(String id) async {
    await _client.deleteJson('/calendar/events/$id');
  }
}
