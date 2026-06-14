import '../core/api_client.dart';
import '../models/json.dart';

/// Endpoints under `/forms`: custom form builder, hosted forms and
/// submission collection.
class FormsService {
  FormsService(this._client);

  final ApiClient _client;

  List<Map<String, dynamic>> _list(dynamic data, [String? key]) {
    final list = data is Map
        ? (data[key] ?? data['items'] ?? data['forms'] ?? data['data'])
        : data;
    if (list is List) {
      return list
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return const [];
  }

  /// The current user's forms.
  Future<List<Map<String, dynamic>>> forms() async =>
      _list(await _client.getJson('/forms'));

  Future<Map<String, dynamic>> form(String formId) async =>
      asMapOrNull(await _client.getJson('/forms/$formId')) ?? const {};

  /// Creates a form. [fields] follow the `FormField` schema: `id`, `type`
  /// (text/email/phone/number/paragraph/date/dropdown/single/checkboxes),
  /// `label`, `required`, `placeholder`, `options`.
  Future<Map<String, dynamic>> create({
    required String title,
    String? description,
    String? submitLabel,
    String? notifyEmail,
    String? successMessage,
    bool aiValidate = false,
    String? accent,
    required List<Map<String, dynamic>> fields,
  }) async =>
      asMapOrNull(await _client.postJson('/forms', body: {
        'title': title,
        if (description != null) 'description': description,
        if (submitLabel != null) 'submit_label': submitLabel,
        if (notifyEmail != null) 'notify_email': notifyEmail,
        if (successMessage != null) 'success_message': successMessage,
        'ai_validate': aiValidate,
        if (accent != null) 'accent': accent,
        'fields': fields,
      })) ??
      const {};

  /// Replaces a form's definition.
  Future<Map<String, dynamic>> update(
          String formId, Map<String, dynamic> body) async =>
      asMapOrNull(await _client.postJson('/forms/$formId', body: body)) ??
      const {};

  Future<void> delete(String formId) async {
    await _client.deleteJson('/forms/$formId');
  }

  /// Responses collected by a form.
  Future<List<Map<String, dynamic>>> submissions(String formId) async =>
      _list(await _client.getJson('/forms/$formId/submissions'),
          'submissions');
}
