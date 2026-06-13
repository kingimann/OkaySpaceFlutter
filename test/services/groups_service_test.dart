import 'package:flutter_test/flutter_test.dart';
import 'package:okayspace/okayspace_api.dart';

import '../support/fake_api.dart';

void main() {
  group('GroupsService', () {
    test('list() parses groups', () async {
      final api = FakeApi()
        ..on('GET', '/groups', json: [
          {'id': 'g1', 'name': 'Cyclists'},
        ]);
      final out = await GroupsService(api.client()).list();
      expect(out.single.id, 'g1');
    });

    test('create() posts name (+ optional is_private)', () async {
      final api = FakeApi()..on('POST', '/groups', json: {'id': 'g9', 'name': 'New'});
      await GroupsService(api.client()).create(name: 'New', isPrivate: true);
      expect(api.body('/groups', method: 'POST'), {'name': 'New', 'is_private': true});
    });

    test('join()/leave() POST the membership paths', () async {
      final api = FakeApi()
        ..on('POST', '/groups/g1/join', json: {'id': 'g1', 'name': 'x'})
        ..on('POST', '/groups/g1/leave', json: {'id': 'g1', 'name': 'x'});
      final svc = GroupsService(api.client());
      await svc.join('g1');
      await svc.leave('g1');
      expect(api.request('/groups/g1/join').method, 'POST');
      expect(api.request('/groups/g1/leave').method, 'POST');
    });

    test('promote/demote/remove target the member sub-paths', () async {
      final api = FakeApi()
        ..on('POST', '/groups/g1/members/u1/promote', json: {'id': 'g1', 'name': 'x'})
        ..on('POST', '/groups/g1/members/u1/demote', json: {'id': 'g1', 'name': 'x'})
        ..on('DELETE', '/groups/g1/members/u1', json: {'id': 'g1', 'name': 'x'});
      final svc = GroupsService(api.client());
      await svc.promoteMember('g1', 'u1');
      await svc.demoteMember('g1', 'u1');
      await svc.removeMember('g1', 'u1');
      expect(api.request('/groups/g1/members/u1/promote').method, 'POST');
      expect(api.request('/groups/g1/members/u1/demote').method, 'POST');
      expect(api.request('/groups/g1/members/u1', method: 'DELETE').method, 'DELETE');
    });

    test('pin/unpin and request approve/reject paths', () async {
      final api = FakeApi()
        ..on('POST', '/groups/g1/pins/p1', json: {'id': 'g1', 'name': 'x'})
        ..on('DELETE', '/groups/g1/pins/p1', json: {'id': 'g1', 'name': 'x'})
        ..on('POST', '/groups/g1/requests/u1/approve', json: {'id': 'g1', 'name': 'x'})
        ..on('POST', '/groups/g1/requests/u1/reject', json: {'id': 'g1', 'name': 'x'});
      final svc = GroupsService(api.client());
      await svc.pinPost('g1', 'p1');
      await svc.unpinPost('g1', 'p1');
      await svc.approveRequest('g1', 'u1');
      await svc.rejectRequest('g1', 'u1');
      expect(api.request('/groups/g1/pins/p1', method: 'POST').method, 'POST');
      expect(api.request('/groups/g1/pins/p1', method: 'DELETE').method, 'DELETE');
      expect(api.request('/groups/g1/requests/u1/approve').method, 'POST');
      expect(api.request('/groups/g1/requests/u1/reject').method, 'POST');
    });
  });
}
