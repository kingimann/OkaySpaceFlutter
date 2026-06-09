import 'json.dart';

/// A user / account on OkaySpace.
///
/// The API's `User` schema carries ~70 fields (profile, shop, privacy,
/// wallet, gamification…). The most commonly used ones are typed below; the
/// complete payload is always available via [raw] so nothing is lost as the
/// schema grows.
class User {
  const User({
    required this.userId,
    required this.email,
    required this.name,
    this.username,
    this.picture,
    this.bio,
    this.headline,
    this.location,
    this.coverPhoto,
    this.accentColor,
    this.phone,
    this.phoneVerified = false,
    this.emailVerified = false,
    this.idVerified = false,
    this.twofaEnabled = false,
    this.verified = false,
    this.isPrivate = false,
    this.role = 'user',
    this.walletBalance = 0,
    this.adBalance = 0,
    this.currency = 'USD',
    this.points = 0,
    this.level = 0,
    this.levelTitle = '',
    this.needsPolicyAgreement = false,
    this.interests = const [],
    required this.createdAt,
    this.raw = const {},
  });

  final String userId;
  final String email;
  final String name;
  final String? username;
  final String? picture;
  final String? bio;
  final String? headline;
  final String? location;
  final String? coverPhoto;
  final String? accentColor;
  final String? phone;

  final bool phoneVerified;
  final bool emailVerified;
  final bool idVerified;
  final bool twofaEnabled;
  final bool verified;
  final bool isPrivate;
  final String role;

  final num walletBalance;
  final num adBalance;
  final String currency;

  final int points;
  final int level;
  final String levelTitle;

  final bool needsPolicyAgreement;
  final List<String> interests;

  final DateTime createdAt;

  /// The complete, unmodified JSON payload.
  final Map<String, dynamic> raw;

  factory User.fromJson(Map<String, dynamic> json) => User(
        userId: asString(json['user_id'] ?? json['id']),
        email: asString(json['email']),
        name: asString(json['name']),
        username: asStringOrNull(json['username']),
        picture: asStringOrNull(json['picture']),
        bio: asStringOrNull(json['bio']),
        headline: asStringOrNull(json['headline']),
        location: asStringOrNull(json['location']),
        coverPhoto: asStringOrNull(json['cover_photo']),
        accentColor: asStringOrNull(json['accent_color']),
        phone: asStringOrNull(json['phone']),
        phoneVerified: asBool(json['phone_verified']),
        emailVerified: asBool(json['email_verified']),
        idVerified: asBool(json['id_verified']),
        twofaEnabled: asBool(json['twofa_enabled']),
        verified: asBool(json['verified']),
        isPrivate: asBool(json['is_private']),
        role: asString(json['role'], 'user'),
        walletBalance: asDoubleOrNull(json['wallet_balance']) ?? 0,
        adBalance: asDoubleOrNull(json['ad_balance']) ?? 0,
        currency: asString(json['currency'], 'USD'),
        points: asInt(json['points']),
        level: asInt(json['level']),
        levelTitle: asString(json['level_title']),
        needsPolicyAgreement: asBool(json['needs_policy_agreement']),
        interests: asStringList(json['interests']),
        createdAt: asDate(json['created_at']),
        raw: json,
      );

  /// Best-effort display handle (`@username` falling back to name).
  String get handle => username != null ? '@$username' : name;

  @override
  String toString() => 'User($userId, $email)';
}
