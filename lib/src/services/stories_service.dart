import '../core/api_client.dart';
import '../models/json.dart';
import '../models/story.dart';

/// Endpoints under `/stories`: the tray, viewing, posting and replying.
class StoriesService {
  StoriesService(this._client);

  final ApiClient _client;

  /// The stories tray — one entry per user with active stories.
  Future<List<StoryTrayItem>> tray() async =>
      asModelList(await _client.getJson('/stories/tray'), StoryTrayItem.fromJson);

  /// Active stories for a given user.
  Future<List<Story>> userStories(String userId) async =>
      asModelList(await _client.getJson('/stories/user/$userId'), Story.fromJson);

  /// Posts a new story (image or video) and returns it.
  Future<Story> create(StoryMedia media, {String? caption}) async {
    final data = await _client.postJson('/stories', body: {
      'media': media.toJson(),
      if (caption != null) 'caption': caption,
    });
    return Story.fromJson(asMapOrNull(data) ?? const {});
  }

  /// Marks a story as viewed.
  Future<void> markViewed(String storyId) async {
    await _client.postJson('/stories/$storyId/view');
  }

  /// Sends a text reply to a story (delivered as a direct message).
  Future<void> reply(String storyId, String text) async {
    await _client.postJson('/stories/$storyId/reply', body: {'text': text});
  }

  /// Lists who viewed one of your stories.
  Future<List<StoryViewer>> viewers(String storyId) async => asModelList(
      await _client.getJson('/stories/$storyId/viewers'), StoryViewer.fromJson);

  /// Deletes one of your stories.
  Future<void> delete(String storyId) async {
    await _client.deleteJson('/stories/$storyId');
  }
}
