import 'package:flutter_test/flutter_test.dart';
import 'package:okayspace/okayspace_api.dart';

void main() {
  test('Story.fromJson parses media and expiry', () {
    final story = Story.fromJson({
      'id': 's1',
      'user_id': 'u1',
      'user_name': 'Ada',
      'type': 'video',
      'media_base64': 'AAA',
      'view_count': 3,
      'created_at': '2026-01-01T00:00:00Z',
      'expires_at': '2099-01-01T00:00:00Z',
    });
    expect(story.isVideo, isTrue);
    expect(story.viewCount, 3);
    expect(story.isExpired, isFalse);
  });

  test('ConversationView parses nested member, last message and unread', () {
    final conv = ConversationView.fromJson({
      'id': 'c1',
      'kind': 'group',
      'name': 'Team',
      'unread_count': 2,
      'members': [
        {'user_id': 'u1', 'name': 'Ada'},
        {'user_id': 'u2', 'name': 'Grace'},
      ],
      'last_message': {
        'id': 'm1',
        'conversation_id': 'c1',
        'sender_id': 'u1',
        'type': 'text',
        'text': 'hi',
        'created_at': '2026-01-01T00:00:00Z',
      },
      'created_at': '2026-01-01T00:00:00Z',
    });
    expect(conv.isGroup, isTrue);
    expect(conv.members.length, 2);
    expect(conv.lastMessage?.text, 'hi');
    expect(conv.unreadCount, 2);
  });

  test('MessageCreate.text serializes minimally', () {
    expect(MessageCreate.text('yo').toJson(), {'type': 'text', 'text': 'yo'});
  });

  test('Community / Group expose membership flags', () {
    final community = Community.fromJson({
      'id': 'c1',
      'name': 'flutter',
      'title': 'Flutter',
      'owner_id': 'u1',
      'is_member': true,
      'can_moderate': true,
      'member_count': 1200,
      'created_at': '2026-01-01T00:00:00Z',
    });
    expect(community.isMember, isTrue);
    expect(community.canModerate, isTrue);
    expect(community.memberCount, 1200);

    final group = Group.fromJson({
      'id': 'g1',
      'name': 'Hikers',
      'owner_id': 'u1',
      'my_role': 'admin',
      'created_at': '2026-01-01T00:00:00Z',
    });
    expect(group.canManage, isTrue);
  });

  test('Listing parses seller, price and engagement', () {
    final listing = Listing.fromJson({
      'id': 'l1',
      'user_id': 'u1',
      'seller': {'user_id': 'u1', 'name': 'Ada'},
      'title': 'Bike',
      'price': 99.5,
      'currency': 'CAD',
      'category': 'sports',
      'saved_by_me': true,
      'created_at': '2026-01-01T00:00:00Z',
    });
    expect(listing.seller.name, 'Ada');
    expect(listing.price, 99.5);
    expect(listing.currency, 'CAD');
    expect(listing.savedByMe, isTrue);
  });

  test('PlaceReview.fromJson parses rating, place and author', () {
    final review = PlaceReview.fromJson({
      'id': 'r1',
      'user_id': 'u1',
      'user_name': 'Ada',
      'place_key': 'geo:43.65,-79.38',
      'place_name': 'Cafe',
      'longitude': -79.38,
      'latitude': 43.65,
      'rating': 4,
      'text': 'Great spot',
      'created_at': '2026-01-01T00:00:00Z',
    });
    expect(review.rating, 4);
    expect(review.placeName, 'Cafe');
    expect(review.userName, 'Ada');
    expect(review.text, 'Great spot');
  });

  test('ReviewSummary.fromJson parses count, average and histogram', () {
    final summary = ReviewSummary.fromJson({
      'place_key': 'geo:43.65,-79.38',
      'count': 3,
      'average': 4.33,
      'distribution': {'1': 0, '2': 0, '3': 1, '4': 0, '5': 2},
    });
    expect(summary.count, 3);
    expect(summary.average, 4.33);
    expect(summary.distribution[5], 2);
    expect(summary.distribution[3], 1);
    expect(summary.distribution[1], 0);
  });

  test('WalletSummary parses balance and recent transactions', () {
    final wallet = WalletSummary.fromJson({
      'currency': 'USD',
      'balance': 42.0,
      'total_earned': 100.0,
      'recent': [
        {'id': 't1', 'type': 'tip', 'amount': 5.0, 'created_at': '2026-01-01T00:00:00Z'},
      ],
    });
    expect(wallet.balance, 42.0);
    expect(wallet.recent.single.type, 'tip');
    expect(wallet.recent.single.amount, 5.0);
  });
}
