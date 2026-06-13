import 'package:flutter_test/flutter_test.dart';
import 'package:okayspace/okayspace_api.dart';

import '../support/fake_api.dart';

void main() {
  group('CirclesService', () {
    test('circles() parses the list envelope', () async {
      final api = FakeApi()
        ..on('GET', '/circles', json: {
          'circles': [
            {'id': 'c1', 'name': 'Work', 'member_count': 2},
            {'id': 'c2', 'name': 'Family', 'member_count': 5},
          ]
        });
      final out = await CirclesService(api.client()).circles();
      expect(out.map((c) => c['id']), ['c1', 'c2']);
    });

    test('circles() also accepts a bare list', () async {
      final api = FakeApi()
        ..on('GET', '/circles', json: [
          {'id': 'c1', 'name': 'Work'}
        ]);
      final out = await CirclesService(api.client()).circles();
      expect(out.single['name'], 'Work');
    });

    test('create() posts name + member_ids and returns the circle', () async {
      final api = FakeApi()
        ..on('POST', '/circles', json: {'id': 'c9', 'name': 'New', 'member_count': 1});
      final out = await CirclesService(api.client())
          .create(name: 'New', memberIds: ['u1']);
      expect(out['id'], 'c9');
      expect(api.body('/circles', method: 'POST'),
          {'name': 'New', 'member_ids': ['u1']});
    });

    test('update() only sends the fields that change', () async {
      final api = FakeApi()..on('PATCH', '/circles/c1', json: {'id': 'c1', 'name': 'Renamed'});
      await CirclesService(api.client())
          .update('c1', name: 'Renamed', addMemberIds: ['u2']);
      expect(api.body('/circles/c1', method: 'PATCH'),
          {'name': 'Renamed', 'add_member_ids': ['u2']});
    });

    test('members() reads the members key', () async {
      final api = FakeApi()
        ..on('GET', '/circles/c1/members', json: {
          'members': [
            {'user_id': 'u1', 'name': 'A'},
            {'user_id': 'u2', 'name': 'B'},
          ]
        });
      final out = await CirclesService(api.client()).members('c1');
      expect(out.length, 2);
    });

    test('delete() issues a DELETE', () async {
      final api = FakeApi()..on('DELETE', '/circles/c1', json: {'ok': true});
      await CirclesService(api.client()).delete('c1');
      expect(api.request('/circles/c1').method, 'DELETE');
    });
  });
}
