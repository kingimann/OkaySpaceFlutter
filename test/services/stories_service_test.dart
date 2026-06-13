import 'package:flutter_test/flutter_test.dart';
import 'package:okayspace/okayspace_api.dart';

import '../support/fake_api.dart';

void main() {
  group('StoriesService', () {
    test('tray() parses tray items', () async {
      final api = FakeApi()
        ..on('GET', '/stories/tray', json: [
          {'user_id': 'u1', 'name': 'Ada', 'has_unseen': true},
        ]);
      final out = await StoriesService(api.client()).tray();
      expect(out.single.userId, 'u1');
    });

    test('create() posts media + caption', () async {
      final api = FakeApi()..on('POST', '/stories', json: {'id': 's1', 'type': 'image'});
      await StoriesService(api.client())
          .create(const StoryMedia(base64: 'AAAA', type: 'image'), caption: 'hi');
      final body = api.body('/stories', method: 'POST');
      expect(body['caption'], 'hi');
      expect((body['media'] as Map)['type'], 'image');
    });

    test('markViewed() POSTs to /view', () async {
      final api = FakeApi()..on('POST', '/stories/s1/view', json: {'viewed': true});
      await StoriesService(api.client()).markViewed('s1');
      expect(api.request('/stories/s1/view').method, 'POST');
    });

    test('reply() posts {text}', () async {
      final api = FakeApi()..on('POST', '/stories/s1/reply', json: {'ok': true});
      await StoriesService(api.client()).reply('s1', 'nice story');
      expect(api.body('/stories/s1/reply', method: 'POST'), {'text': 'nice story'});
    });

    test('delete() DELETEs the story', () async {
      final api = FakeApi()..on('DELETE', '/stories/s1', json: {'ok': true});
      await StoriesService(api.client()).delete('s1');
      expect(api.request('/stories/s1').method, 'DELETE');
    });
  });
}
