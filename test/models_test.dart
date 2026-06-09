import 'package:flutter_test/flutter_test.dart';
import 'package:okayspace/okayspace_api.dart';

void main() {
  group('User.fromJson', () {
    test('parses core fields and keeps the raw payload', () {
      final user = User.fromJson({
        'user_id': 'u_1',
        'email': 'a@b.com',
        'name': 'Ada',
        'username': 'ada',
        'verified': true,
        'wallet_balance': 12.5,
        'points': 340,
        'created_at': '2026-01-02T03:04:05Z',
        'some_future_field': 'kept',
      });

      expect(user.userId, 'u_1');
      expect(user.email, 'a@b.com');
      expect(user.handle, '@ada');
      expect(user.verified, isTrue);
      expect(user.walletBalance, 12.5);
      expect(user.points, 340);
      expect(user.createdAt.year, 2026);
      expect(user.raw['some_future_field'], 'kept');
    });

    test('falls back to name when username is null', () {
      final user = User.fromJson({
        'user_id': 'u_2',
        'email': 'x@y.com',
        'name': 'No Handle',
        'username': null,
        'created_at': '2026-01-01T00:00:00Z',
      });
      expect(user.handle, 'No Handle');
    });
  });

  group('AuthResponse.fromJson', () {
    test('parses token and nested user', () {
      final auth = AuthResponse.fromJson({
        'session_token': 'tok_abc',
        'user': {
          'user_id': 'u_1',
          'email': 'a@b.com',
          'name': 'Ada',
          'created_at': '2026-01-01T00:00:00Z',
        },
      });
      expect(auth.hasToken, isTrue);
      expect(auth.sessionToken, 'tok_abc');
      expect(auth.user?.userId, 'u_1');
    });

    test('tolerates a token-less (e.g. 2FA challenge) response', () {
      final auth = AuthResponse.fromJson({'challenge_id': 'c1'});
      expect(auth.hasToken, isFalse);
      expect(auth.user, isNull);
      expect(auth.raw['challenge_id'], 'c1');
    });
  });

  group('Post.fromJson', () {
    test('parses a post with author, media and engagement', () {
      final post = Post.fromJson({
        'id': 'p_1',
        'user_id': 'u_1',
        'author': {'user_id': 'u_1', 'name': 'Ada', 'username': 'ada'},
        'text': 'hello #world',
        'hashtags': ['world'],
        'media': [
          {'type': 'image', 'url': 'https://x/1.jpg', 'width': 100}
        ],
        'likes_count': 5,
        'liked_by_me': true,
        'created_at': '2026-01-01T00:00:00Z',
      });

      expect(post.id, 'p_1');
      expect(post.author.name, 'Ada');
      expect(post.text, 'hello #world');
      expect(post.hashtags, ['world']);
      expect(post.media.single.url, 'https://x/1.jpg');
      expect(post.media.single.isVideo, isFalse);
      expect(post.likesCount, 5);
      expect(post.likedByMe, isTrue);
    });

    test('parses a recursive quote post', () {
      final post = Post.fromJson({
        'id': 'p_2',
        'user_id': 'u_2',
        'author': {'user_id': 'u_2', 'name': 'Grace'},
        'text': 'quoting this',
        'quote_of': 'p_1',
        'quoted_post': {
          'id': 'p_1',
          'user_id': 'u_1',
          'author': {'user_id': 'u_1', 'name': 'Ada'},
          'text': 'original',
          'created_at': '2026-01-01T00:00:00Z',
        },
        'created_at': '2026-01-02T00:00:00Z',
      });

      expect(post.isQuote, isTrue);
      expect(post.quotedPost?.id, 'p_1');
      expect(post.quotedPost?.text, 'original');
    });

    test('degrades gracefully on missing/odd fields', () {
      final post = Post.fromJson({'id': 'p_3'});
      expect(post.id, 'p_3');
      expect(post.text, '');
      expect(post.media, isEmpty);
      expect(post.likesCount, 0);
      expect(post.canComment, isTrue); // default
    });
  });

  group('PostCreate.toJson', () {
    test('omits unset optional fields', () {
      final json = const PostCreate(text: 'hi').toJson();
      expect(json, {'text': 'hi'});
    });

    test('serializes a reply with media', () {
      final json = const PostCreate(
        text: 'a reply',
        parentId: 'p_1',
        media: [PostMedia(type: 'image', base64: 'AAAA')],
      ).toJson();

      expect(json['parent_id'], 'p_1');
      expect((json['media'] as List).single['base64'], 'AAAA');
    });
  });
}
