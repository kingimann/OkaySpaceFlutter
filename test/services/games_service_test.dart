import 'package:flutter_test/flutter_test.dart';
import 'package:okayspace/okayspace_api.dart';

import '../support/fake_api.dart';

void main() {
  group('GamesService', () {
    test('games() reads the games key', () async {
      final api = FakeApi()
        ..on('GET', '/games', json: {
          'games': [
            {'id': 'g1', 'title': 'Pong'},
            {'id': 'g2', 'title': 'Snake'},
          ]
        });
      final out = await GamesService(api.client()).games();
      expect(out.map((g) => g.id), ['g1', 'g2']);
    });

    test('create() posts title + kind (+ optional fields)', () async {
      final api = FakeApi()..on('POST', '/games', json: {'id': 'g9', 'title': 'New'});
      await GamesService(api.client())
          .create(title: 'New', url: 'https://g.example/play', kind: 'url');
      expect(api.body('/games', method: 'POST'),
          {'title': 'New', 'kind': 'url', 'url': 'https://g.example/play'});
    });

    test('submitScore() posts {score} to /score', () async {
      final api = FakeApi()..on('POST', '/games/g1/score', json: {'ok': true, 'best': 10});
      await GamesService(api.client()).submitScore('g1', 10);
      expect(api.body('/games/g1/score', method: 'POST'), {'score': 10});
    });

    test('recordPlay() posts to /play', () async {
      final api = FakeApi()..on('POST', '/games/g1/play', json: {'ok': true});
      await GamesService(api.client()).recordPlay('g1');
      expect(api.request('/games/g1/play').method, 'POST');
    });

    test('leaderboard() reads the leaderboard key', () async {
      final api = FakeApi()
        ..on('GET', '/games/g1/leaderboard', json: {
          'leaderboard': [
            {'user_id': 'u1', 'score': 99},
          ]
        });
      final out = await GamesService(api.client()).leaderboard('g1');
      expect(out.single['score'], 99);
    });
  });
}
