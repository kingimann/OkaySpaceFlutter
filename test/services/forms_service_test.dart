import 'package:flutter_test/flutter_test.dart';
import 'package:okayspace/okayspace_api.dart';

import '../support/fake_api.dart';

void main() {
  group('FormsService', () {
    test('forms() reads the forms envelope', () async {
      final api = FakeApi()
        ..on('GET', '/forms', json: {
          'forms': [
            {'id': 'f1', 'title': 'Contact'},
          ]
        });
      final out = await FormsService(api.client()).forms();
      expect(out.single['id'], 'f1');
    });

    test('create() posts title + fields (+ optional fields only when set)', () async {
      final api = FakeApi()..on('POST', '/forms', json: {'id': 'f9', 'title': 'New'});
      await FormsService(api.client()).create(
        title: 'New',
        notifyEmail: 'me@x.com',
        fields: [
          {'id': 'q1', 'type': 'text', 'label': 'Name'},
        ],
      );
      expect(api.body('/forms', method: 'POST'), {
        'title': 'New',
        'notify_email': 'me@x.com',
        'fields': [
          {'id': 'q1', 'type': 'text', 'label': 'Name'},
        ],
      });
    });

    test('update() POSTs to /forms/{id}', () async {
      final api = FakeApi()..on('POST', '/forms/f1', json: {'id': 'f1', 'title': 'Edited'});
      await FormsService(api.client()).update('f1', {'title': 'Edited'});
      expect(api.request('/forms/f1', method: 'POST').method, 'POST');
    });

    test('submissions() reads the submissions key', () async {
      final api = FakeApi()
        ..on('GET', '/forms/f1/submissions', json: {
          'submissions': [
            {'id': 's1', 'values': {'q1': 'A'}},
          ],
          'total': 1,
        });
      final out = await FormsService(api.client()).submissions('f1');
      expect(out.single['id'], 's1');
    });

    test('delete() DELETEs the form', () async {
      final api = FakeApi()..on('DELETE', '/forms/f1', json: {'ok': true});
      await FormsService(api.client()).delete('f1');
      expect(api.request('/forms/f1').method, 'DELETE');
    });
  });
}
