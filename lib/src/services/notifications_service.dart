import '../core/api_client.dart';
import '../models/json.dart';
import '../models/notification.dart';

/// Endpoints under `/notifications`: the notification list, unread count and
/// read/dismiss actions.
class NotificationsService {
  NotificationsService(this._client);

  final ApiClient _client;

  /// All notifications, most-recent first.
  Future<List<AppNotification>> list() async => asModelList(
      await _client.getJson('/notifications'), AppNotification.fromJson);

  /// Activity feed (likes/follows/etc. on your content; raw payload).
  Future<dynamic> activity() => _client.getJson('/notifications/activity');

  /// Number of unread notifications.
  Future<int> unreadCount() async {
    final data = await _client.getJson('/notifications/unread');
    if (data is Map) return asInt(data['count'] ?? data['unread']);
    return asInt(data);
  }

  /// Marks a single notification read.
  Future<void> markRead(String notifId) async {
    await _client.postJson('/notifications/$notifId/read');
  }

  /// Marks all notifications read.
  Future<void> markAllRead() async {
    await _client.postJson('/notifications/read-all');
  }

  /// Dismisses (deletes) a notification.
  Future<void> dismiss(String notifId) async {
    await _client.deleteJson('/notifications/$notifId');
  }
}
