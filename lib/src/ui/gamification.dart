import 'package:flutter/material.dart';

import '../../okayspace_api.dart';

/// Local points / levels / badges system (the backend computes `level` and
/// `level_title` from `points`; the tier ladder and earnable achievement
/// badges are defined here, mirroring the web app's `points.ts`).

class PointsTier {
  const PointsTier(this.name, this.minLevel, this.icon, this.color);
  final String name;
  final int minLevel;
  final IconData icon;
  final Color color;
}

/// The named tier ladder, Newcomer → Mythic, keyed by the level the tier
/// begins at. The backend's per-user `level_title` stays authoritative for the
/// current label; this ladder powers the progression view.
const kPointsTiers = <PointsTier>[
  PointsTier('Newcomer', 1, Icons.spa_outlined, Color(0xFF9CA3AF)),
  PointsTier('Explorer', 2, Icons.explore_outlined, Color(0xFF22C55E)),
  PointsTier('Contributor', 5, Icons.volunteer_activism_outlined,
      Color(0xFF06B6D4)),
  PointsTier('Regular', 10, Icons.local_fire_department, Color(0xFF3B82F6)),
  PointsTier('Veteran', 20, Icons.military_tech_outlined, Color(0xFF8B5CF6)),
  PointsTier('Expert', 35, Icons.workspace_premium_outlined, Color(0xFFD946EF)),
  PointsTier('Master', 50, Icons.stars_outlined, Color(0xFFF59E0B)),
  PointsTier('Legend', 75, Icons.auto_awesome, Color(0xFFEF4444)),
  PointsTier('Mythic', 100, Icons.diamond_outlined, Color(0xFF14B8A6)),
];

/// The tier a given level falls into.
PointsTier tierForLevel(int level) {
  var result = kPointsTiers.first;
  for (final t in kPointsTiers) {
    if (level >= t.minLevel) result = t;
  }
  return result;
}

/// The next tier above [level], or null if already at the top.
PointsTier? nextTierAfter(int level) {
  for (final t in kPointsTiers) {
    if (t.minLevel > level) return t;
  }
  return null;
}

/// Inputs an achievement is evaluated against (drawn from the profile + stats).
class GamificationStats {
  const GamificationStats({
    this.points = 0,
    this.level = 0,
    this.followers = 0,
    this.following = 0,
    this.friends = 0,
    this.verified = false,
    this.idVerified = false,
    this.hasAvatar = false,
    this.hasBio = false,
    this.interests = 0,
  });

  final int points;
  final int level;
  final int followers;
  final int following;
  final int friends;
  final bool verified;
  final bool idVerified;
  final bool hasAvatar;
  final bool hasBio;
  final int interests;
}

/// An earnable badge with a criterion evaluated client-side.
class Achievement {
  const Achievement(
      this.id, this.name, this.description, this.icon, this.color, this.earned,
      {this.progress});

  final String id;
  final String name;
  final String description;
  final IconData icon;
  final Color color;

  /// Whether the user has earned it, given their stats.
  final bool Function(GamificationStats) earned;

  /// Optional 0..1 progress toward earning it (for locked badges).
  final double Function(GamificationStats)? progress;
}

double _frac(num v, num target) =>
    target <= 0 ? 1 : (v / target).clamp(0.0, 1.0).toDouble();

/// The full catalog of earnable badges.
const _gold = Color(0xFFEAB308);
const _blue = Color(0xFF3B82F6);
const _green = Color(0xFF22C55E);
const _violet = Color(0xFF8B5CF6);
const _rose = Color(0xFFE11D48);
const _cyan = Color(0xFF06B6D4);

final kAchievements = <Achievement>[
  Achievement('welcome', 'Welcome aboard', 'Joined OkaySpace',
      Icons.celebration_outlined, _green, (_) => true),
  Achievement('profile_photo', 'Picture perfect', 'Set a profile photo',
      Icons.face_outlined, _blue, (s) => s.hasAvatar),
  Achievement('storyteller', 'Storyteller', 'Wrote a bio',
      Icons.menu_book_outlined, _cyan, (s) => s.hasBio),
  Achievement('curious', 'Curious mind', 'Added 3+ interests',
      Icons.interests_outlined, _violet, (s) => s.interests >= 3,
      progress: (s) => _frac(s.interests, 3)),
  Achievement('verified', 'Verified', 'Got the verified badge',
      Icons.verified_outlined, _blue, (s) => s.verified),
  Achievement('trusted', 'Trusted', 'Completed ID verification',
      Icons.badge_outlined, _violet, (s) => s.idVerified),
  Achievement('first_friends', 'Making friends', 'Reached 5 friends',
      Icons.group_outlined, _green, (s) => s.friends >= 5,
      progress: (s) => _frac(s.friends, 5)),
  Achievement('social', 'Socialite', 'Following 50 people',
      Icons.diversity_3_outlined, _cyan, (s) => s.following >= 50,
      progress: (s) => _frac(s.following, 50)),
  Achievement('rising', 'Rising star', 'Reached 10 followers',
      Icons.trending_up, _gold, (s) => s.followers >= 10,
      progress: (s) => _frac(s.followers, 10)),
  Achievement('popular', 'Crowd favourite', 'Reached 100 followers',
      Icons.groups_2_outlined, _gold, (s) => s.followers >= 100,
      progress: (s) => _frac(s.followers, 100)),
  Achievement('influencer', 'Influencer', 'Reached 1,000 followers',
      Icons.campaign_outlined, _rose, (s) => s.followers >= 1000,
      progress: (s) => _frac(s.followers, 1000)),
  Achievement('points_100', 'Point collector', 'Earned 100 points',
      Icons.toll_outlined, _green, (s) => s.points >= 100,
      progress: (s) => _frac(s.points, 100)),
  Achievement('points_1k', 'High roller', 'Earned 1,000 points',
      Icons.savings_outlined, _gold, (s) => s.points >= 1000,
      progress: (s) => _frac(s.points, 1000)),
  Achievement('points_10k', 'Point legend', 'Earned 10,000 points',
      Icons.emoji_events_outlined, _rose, (s) => s.points >= 10000,
      progress: (s) => _frac(s.points, 10000)),
  Achievement('level_5', 'Climbing', 'Reached level 5',
      Icons.stairs_outlined, _blue, (s) => s.level >= 5,
      progress: (s) => _frac(s.level, 5)),
  Achievement('level_25', 'Seasoned', 'Reached level 25',
      Icons.landscape_outlined, _violet, (s) => s.level >= 25,
      progress: (s) => _frac(s.level, 25)),
  Achievement('level_50', 'Mastery', 'Reached level 50',
      Icons.workspace_premium_outlined, _gold, (s) => s.level >= 50,
      progress: (s) => _frac(s.level, 50)),
  Achievement('mythic', 'Mythic', 'Reached level 100',
      Icons.diamond_outlined, const Color(0xFF14B8A6), (s) => s.level >= 100,
      progress: (s) => _frac(s.level, 100)),
];

/// How points are earned (display-only guidance).
const kPointWays = <(IconData, String, String)>[
  (Icons.post_add_outlined, 'Post & reply', 'Share posts and join threads'),
  (Icons.favorite_border, 'Get reactions', 'Likes and reposts on your posts'),
  (Icons.people_outline, 'Grow your circle', 'Followers and friends'),
  (Icons.local_fire_department_outlined, 'Stay active', 'Daily activity streaks'),
  (Icons.verified_outlined, 'Verify', 'Verify your email, phone & ID'),
];

/// Builds the evaluation stats from a [User] and a stats map.
GamificationStats statsFromUser(User u, Map<String, dynamic> stats) {
  int s(String k) => stats[k] is num ? (stats[k] as num).toInt() : 0;
  return GamificationStats(
    points: u.points,
    level: u.level,
    followers: s('followers'),
    following: s('following'),
    friends: s('friends'),
    verified: u.verified,
    idVerified: u.idVerified,
    hasAvatar: u.picture != null && u.picture!.isNotEmpty,
    hasBio: u.bio != null && u.bio!.isNotEmpty,
    interests: u.interests.length,
  );
}
