import '../core/api_client.dart';
import '../models/json.dart';
import '../models/note.dart';

/// Endpoints under `/notes`: the user's private notes.
class NotesService {
  NotesService(this._client);

  final ApiClient _client;

  Note _note(Object? d) => Note.fromJson(asMapOrNull(d) ?? const {});

  /// All of the user's notes, pinned first then most-recently updated.
  Future<List<Note>> list() async =>
      asModelList(await _client.getJson('/notes'), Note.fromJson);

  /// Creates a note.
  Future<Note> create({
    String title = '',
    String body = '',
    String? color,
    bool pinned = false,
  }) async =>
      _note(await _client.postJson('/notes', body: {
        'title': title,
        'body': body,
        if (color != null) 'color': color,
        'pinned': pinned,
      }));

  /// Updates a note (full replace of the editable fields).
  Future<Note> update(
    String id, {
    String title = '',
    String body = '',
    String? color,
    bool pinned = false,
  }) async =>
      _note(await _client.patchJson('/notes/$id', body: {
        'title': title,
        'body': body,
        if (color != null) 'color': color,
        'pinned': pinned,
      }));

  Future<void> delete(String id) async {
    await _client.deleteJson('/notes/$id');
  }
}
