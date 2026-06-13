import '../core/api_client.dart';
import '../models/json.dart';

/// Endpoints under `/support`: help-desk tickets and their message threads.
class SupportService {
  SupportService(this._client);

  final ApiClient _client;

  Map<String, dynamic> _map(Object? d) => asMapOrNull(d) ?? const {};

  /// The current user's support tickets.
  Future<dynamic> tickets() => _client.getJson('/support/tickets');

  /// Opens a new support ticket.
  Future<Map<String, dynamic>> createTicket({
    required String subject,
    required String message,
    String? category,
  }) async =>
      _map(await _client.postJson('/support/tickets', body: {
        'subject': subject,
        'message': message,
        if (category != null) 'category': category,
      }));

  /// A single ticket with its thread.
  Future<Map<String, dynamic>> ticket(String ticketId) async =>
      _map(await _client.getJson('/support/tickets/$ticketId'));

  /// Adds a reply to a ticket.
  Future<Map<String, dynamic>> reply(String ticketId, String message) async =>
      _map(await _client.postJson('/support/tickets/$ticketId/messages',
          body: {'text': message}));

  /// Updates a ticket's status (e.g. close/reopen).
  Future<void> setStatus(String ticketId, String status) async {
    await _client.postJson('/support/tickets/$ticketId/status',
        body: {'status': status});
  }

  /// Number of tickets with unread support replies.
  Future<int> unreadCount() async {
    final data = await _client.getJson('/support/unread-count');
    if (data is Map) return asInt(data['count'] ?? data['unread']);
    return asInt(data);
  }
}
