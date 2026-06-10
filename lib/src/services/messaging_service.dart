import '../core/api_client.dart';
import '../models/json.dart';
import '../models/message.dart';

/// Endpoints under `/conversations` (plus `/presence` and `/calls`): direct &
/// group chats, messages and the common message actions.
class MessagingService {
  MessagingService(this._client);

  final ApiClient _client;

  ConversationView _conv(Object? d) =>
      ConversationView.fromJson(asMapOrNull(d) ?? const {});
  Message _msg(Object? d) => Message.fromJson(asMapOrNull(d) ?? const {});

  // --- Conversations ------------------------------------------------------

  /// All of the current user's conversations, most-recent first.
  Future<List<ConversationView>> conversations() async => asModelList(
      await _client.getJson('/conversations'), ConversationView.fromJson);

  /// Opens (or fetches the existing) direct conversation with a user.
  Future<ConversationView> startDirect(String recipientUserId) async =>
      _conv(await _client.postJson('/conversations',
          body: {'recipient_user_id': recipientUserId}));

  /// Creates a group conversation.
  Future<ConversationView> createGroup({
    required List<String> memberIds,
    String? name,
  }) async =>
      _conv(await _client.postJson('/conversations/groups', body: {
        'member_ids': memberIds,
        if (name != null) 'name': name,
      }));

  /// Updates a group conversation (e.g. `name`, `avatar`).
  Future<ConversationView> updateGroup(
          String convId, Map<String, dynamic> changes) async =>
      _conv(await _client.patchJson('/conversations/$convId', body: changes));

  Future<void> leave(String convId) async {
    await _client.postJson('/conversations/$convId/leave');
  }

  Future<void> delete(String convId) async {
    await _client.deleteJson('/conversations/$convId');
  }

  /// Marks the conversation as read up to now.
  Future<void> markRead(String convId) async {
    await _client.postJson('/conversations/$convId/read');
  }

  /// Sets disappearing-message TTL (seconds); 0 disables.
  Future<ConversationView> setDisappearing(String convId, int seconds) async =>
      _conv(await _client.postJson('/conversations/$convId/disappearing',
          body: {'seconds': seconds}));

  /// Sets the chat colour theme (default/ocean/sunset/forest/grape/rose/
  /// midnight/mono).
  Future<ConversationView> setTheme(String convId, String theme) async =>
      _conv(await _client.postJson('/conversations/$convId/theme',
          body: {'theme': theme}));

  /// Enables/disables read receipts for the conversation.
  Future<void> setReadReceipts(String convId, bool enabled) async {
    await _client.postJson('/conversations/$convId/receipts',
        body: {'enabled': enabled});
  }

  /// AI summary of the conversation. The client assembles the [transcript]
  /// from locally-loaded messages and the server summarizes it.
  Future<String> summarize(String convId, String transcript) async {
    final res = await _client.postJson('/conversations/$convId/summarize',
        body: {'transcript': transcript});
    if (res is Map) {
      return '${res['summary'] ?? res['text'] ?? res['result'] ?? ''}';
    }
    return '$res';
  }

  /// Lists scheduled (future) messages for the conversation.
  Future<List<Map<String, dynamic>>> scheduledMessages(String convId) async {
    final res = await _client.getJson('/conversations/$convId/scheduled');
    final v = res is Map ? (res['scheduled'] ?? res['items']) : res;
    return v is List
        ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : const [];
  }

  // --- Messages -----------------------------------------------------------

  /// Lists messages in a conversation.
  Future<List<Message>> messages(String convId,
          {Map<String, dynamic>? query}) async =>
      asModelList(
          await _client.getJson('/conversations/$convId/messages', query: query),
          Message.fromJson);

  /// Sends a message. Use [MessageCreate.text] for the common case.
  Future<Message> send(String convId, MessageCreate message) async => _msg(
      await _client.postJson('/conversations/$convId/messages',
          body: message.toJson()));

  /// Convenience helper to send a plain text message.
  Future<Message> sendText(String convId, String text) =>
      send(convId, MessageCreate.text(text));

  Future<Message> editMessage(String convId, String msgId, String text) async =>
      _msg(await _client.patchJson('/conversations/$convId/messages/$msgId',
          body: {'text': text}));

  Future<void> deleteMessage(String convId, String msgId) async {
    await _client.deleteJson('/conversations/$convId/messages/$msgId');
  }

  Future<Message> reactToMessage(
          String convId, String msgId, String emoji) async =>
      _msg(await _client.postJson(
          '/conversations/$convId/messages/$msgId/react',
          body: {'emoji': emoji}));

  Future<Message> pinMessage(String convId, String msgId) async => _msg(
      await _client.postJson('/conversations/$convId/messages/$msgId/pin'));

  Future<List<Message>> pinnedMessages(String convId) async => asModelList(
      await _client.getJson('/conversations/$convId/pinned'), Message.fromJson);

  // --- Presence & calls ---------------------------------------------------

  /// Heartbeat to keep the user marked online.
  Future<void> pingPresence() async {
    await _client.postJson('/presence/ping');
  }

  /// Updates typing/recording presence within a conversation.
  Future<void> setPresence(String convId, String state) async {
    await _client.postJson('/conversations/$convId/presence',
        body: {'state': state});
  }

  /// Rings the other participant(s) to start a call.
  Future<Map<String, dynamic>> ringCall(String convId) async =>
      asMapOrNull(await _client.postJson('/calls/$convId/ring')) ?? const {};

  /// Fetches a call/media token for a conversation.
  Future<Map<String, dynamic>> callToken(String convId) async =>
      asMapOrNull(await _client.postJson('/calls/$convId/token')) ?? const {};
}
