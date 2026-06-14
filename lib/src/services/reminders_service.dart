import '../core/api_client.dart';
import '../models/json.dart';
import '../models/reminder.dart';

/// Endpoints under `/reminders`: the user's private to-do checklist.
class RemindersService {
  RemindersService(this._client);

  final ApiClient _client;

  Reminder _one(Object? d) =>
      Reminder.fromJson(asMapOrNull(d) ?? const {});

  /// All reminders, open ones first then by due date.
  Future<List<Reminder>> list() async =>
      asModelList(await _client.getJson('/reminders'), Reminder.fromJson);

  Future<Reminder> create(String text,
          {DateTime? dueAt, bool done = false}) async =>
      _one(await _client.postJson('/reminders', body: {
        'text': text,
        if (dueAt != null) 'due_at': dueAt.toUtc().toIso8601String(),
        'done': done,
      }));

  Future<Reminder> update(String id,
          {required String text, DateTime? dueAt, bool done = false}) async =>
      _one(await _client.patchJson('/reminders/$id', body: {
        'text': text,
        if (dueAt != null) 'due_at': dueAt.toUtc().toIso8601String(),
        'done': done,
      }));

  Future<void> delete(String id) async {
    await _client.deleteJson('/reminders/$id');
  }
}
