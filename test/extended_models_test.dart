import 'package:flutter_test/flutter_test.dart';
import 'package:okayspace/okayspace_api.dart';

void main() {
  test('RoadsideRequest parses status, vehicle and totals', () {
    final r = RoadsideRequest.fromJson({
      'id': 'r1',
      'requester_id': 'u1',
      'service': 'fuel',
      'status': 'open',
      'longitude': -79.4,
      'latitude': 43.7,
      'vehicle_make': 'Toyota',
      'vehicle_model': 'Corolla',
      'total': 34.5,
      'mine': true,
      'created_at': '2026-01-01T00:00:00Z',
    });
    expect(r.service, 'fuel');
    expect(r.isActive, isTrue);
    expect(r.vehicleMake, 'Toyota');
    expect(r.total, 34.5);
    expect(r.mine, isTrue);
  });

  test('RoadsideRequest.isActive is false when completed', () {
    final r = RoadsideRequest.fromJson({
      'id': 'r2',
      'requester_id': 'u1',
      'service': 'tow',
      'status': 'completed',
      'longitude': 0,
      'latitude': 0,
      'created_at': '2026-01-01T00:00:00Z',
    });
    expect(r.isActive, isFalse);
  });

  test('AppNotification parses actor and read state', () {
    final n = AppNotification.fromJson({
      'id': 'n1',
      'user_id': 'u1',
      'type': 'like',
      'actor_name': 'Ada',
      'post_id': 'p1',
      'read': false,
      'created_at': '2026-01-01T00:00:00Z',
    });
    expect(n.type, 'like');
    expect(n.actorName, 'Ada');
    expect(n.postId, 'p1');
    expect(n.read, isFalse);
  });

  test('OkaySpaceApi exposes all feature services', () {
    final api = OkaySpaceApi(tokenStore: InMemoryTokenStore());
    // Smoke-check that the facade wires up without throwing.
    expect(api.auth, isNotNull);
    expect(api.feed, isNotNull);
    expect(api.stories, isNotNull);
    expect(api.messaging, isNotNull);
    expect(api.communities, isNotNull);
    expect(api.groups, isNotNull);
    expect(api.marketplace, isNotNull);
    expect(api.wallet, isNotNull);
    expect(api.users, isNotNull);
    expect(api.friends, isNotNull);
    expect(api.notifications, isNotNull);
    expect(api.roadside, isNotNull);
    expect(api.payments, isNotNull);
    expect(api.ads, isNotNull);
    expect(api.support, isNotNull);
    expect(api.admin, isNotNull);
    expect(api.oauth, isNotNull);
  });
}
