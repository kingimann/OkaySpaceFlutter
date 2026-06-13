import 'package:flutter_test/flutter_test.dart';
import 'package:okayspace/okayspace_api.dart';

import '../support/fake_api.dart';

void main() {
  group('FeedService', () {
    test('homeFeed() parses a post list', () async {
      final api = FakeApi()
        ..on('GET', '/feed/home', json: [
          {'id': 'p1', 'text': 'hi'},
          {'id': 'p2', 'text': 'yo'},
        ]);
      final out = await FeedService(api.client()).homeFeed();
      expect(out.map((p) => p.id), ['p1', 'p2']);
    });

    test('popularReels() clamps the limit to 20', () async {
      final api = FakeApi()..on('GET', '/reels/popular', json: []);
      await FeedService(api.client()).popularReels(limit: 99);
      expect(api.request('/reels/popular').url.queryParameters['limit'], '20');
    });

    test('createPlaylist() posts {name}', () async {
      final api = FakeApi()..on('POST', '/playlists', json: {'id': 'pl1', 'name': 'Faves'});
      await FeedService(api.client()).createPlaylist('Faves');
      expect(api.body('/playlists', method: 'POST'), {'name': 'Faves'});
    });

    test('addToPlaylist() posts {post_id} (matches backend PlaylistVideoAdd)', () async {
      final api = FakeApi()..on('POST', '/playlists/pl1/videos', json: {'ok': true});
      await FeedService(api.client()).addToPlaylist('pl1', 'p9');
      expect(api.body('/playlists/pl1/videos', method: 'POST'), {'post_id': 'p9'});
    });

    test('resolveVideoUrl() returns the resolved url, else the original', () async {
      final api = FakeApi()
        ..on('POST', '/media/resolve-video', json: {'url': 'https://cdn/x.mp4'});
      final resolved =
          await FeedService(api.client()).resolveVideoUrl('https://page/watch');
      expect(resolved, 'https://cdn/x.mp4');

      final api2 = FakeApi()..on('POST', '/media/resolve-video', json: {});
      final original =
          await FeedService(api2.client()).resolveVideoUrl('https://page/watch');
      expect(original, 'https://page/watch');
    });
  });
}
