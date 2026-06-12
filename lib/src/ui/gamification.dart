import 'package:flutter/material.dart';

import '../../okayspace_api.dart';
import '../core/points_ledger.dart';

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

/// The named tier ladder, Newcomer → Celestial, keyed by the level the tier
/// begins at. The backend's per-user `level_title` stays authoritative for the
/// current label; this ladder powers the progression view. Tiers must stay in
/// ascending `minLevel` order — `tierForLevel`/`nextTierAfter` rely on it.
const kPointsTiers = <PointsTier>[
  PointsTier('Newcomer', 1, Icons.spa_outlined, Color(0xFF9CA3AF)),
  PointsTier('Rookie', 2, Icons.emoji_nature_outlined, Color(0xFF84CC16)),
  PointsTier('Explorer', 3, Icons.explore_outlined, Color(0xFF22C55E)),
  PointsTier('Wanderer', 5, Icons.hiking_outlined, Color(0xFF10B981)),
  PointsTier('Scout', 7, Icons.travel_explore_outlined, Color(0xFF14B8A6)),
  PointsTier('Contributor', 10, Icons.volunteer_activism_outlined,
      Color(0xFF06B6D4)),
  PointsTier('Regular', 14, Icons.local_fire_department, Color(0xFF0EA5E9)),
  PointsTier('Enthusiast', 18, Icons.bolt_outlined, Color(0xFF3B82F6)),
  PointsTier('Trailblazer', 23, Icons.flag_outlined, Color(0xFF6366F1)),
  PointsTier('Veteran', 28, Icons.military_tech_outlined, Color(0xFF8B5CF6)),
  PointsTier('Specialist', 34, Icons.tune_outlined, Color(0xFFA855F7)),
  PointsTier('Expert', 40, Icons.workspace_premium_outlined, Color(0xFFD946EF)),
  PointsTier('Virtuoso', 47, Icons.piano_outlined, Color(0xFFEC4899)),
  PointsTier('Master', 55, Icons.stars_outlined, Color(0xFFF59E0B)),
  PointsTier('Grandmaster', 64, Icons.shield_moon_outlined, Color(0xFFF97316)),
  PointsTier('Champion', 74, Icons.emoji_events_outlined, Color(0xFFFB923C)),
  PointsTier('Hero', 85, Icons.shield_outlined, Color(0xFFEF4444)),
  PointsTier('Legend', 97, Icons.auto_awesome, Color(0xFFDC2626)),
  PointsTier('Icon', 110, Icons.star_outline, Color(0xFFBE123C)),
  PointsTier('Mythic', 125, Icons.diamond_outlined, Color(0xFF14B8A6)),
  PointsTier('Immortal', 145, Icons.all_inclusive_outlined, Color(0xFF0D9488)),
  PointsTier('Ascendant', 170, Icons.rocket_launch_outlined, Color(0xFF6D28D9)),
  PointsTier('Transcendent', 200, Icons.brightness_7_outlined,
      Color(0xFF7C3AED)),
  PointsTier('Celestial', 250, Icons.public_outlined, Color(0xFFEAB308)),
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
const _orange = Color(0xFFF97316);

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
  Achievement('champion', 'Champion', 'Reached level 75',
      Icons.emoji_events_outlined, _gold, (s) => s.level >= 75,
      progress: (s) => _frac(s.level, 75)),
  Achievement('mythic', 'Mythic', 'Reached level 125',
      Icons.diamond_outlined, const Color(0xFF14B8A6), (s) => s.level >= 125,
      progress: (s) => _frac(s.level, 125)),
  Achievement('immortal', 'Immortal', 'Reached level 145',
      Icons.all_inclusive_outlined, const Color(0xFF0D9488),
      (s) => s.level >= 145, progress: (s) => _frac(s.level, 145)),
  Achievement('celestial', 'Celestial', 'Reached level 250',
      Icons.public_outlined, _gold, (s) => s.level >= 250,
      progress: (s) => _frac(s.level, 250)),
];

/// Display metadata for a locally-tracked point source (keyed by the id used
/// in [PointsLedger.bySource]).
class PointSource {
  const PointSource(this.id, this.label, this.icon, this.color);
  final String id;
  final String label;
  final IconData icon;
  final Color color;
}

/// Known point sources, in a sensible display order. Unknown ids fall back to
/// a generic "Activity" row in the breakdown.
const kPointSources = <PointSource>[
  PointSource('quests', 'Daily quests', Icons.task_alt_outlined, _violet),
  PointSource('challenges', 'Weekly challenges', Icons.flag_outlined, _orange),
  PointSource('streak', 'Daily streak', Icons.local_fire_department, _gold),
  PointSource('online', 'Online time', Icons.schedule_outlined, _cyan),
  PointSource('posts', 'Posts & replies', Icons.post_add_outlined, _blue),
  PointSource('reactions', 'Reactions', Icons.favorite_border, _rose),
  PointSource('social', 'Connections', Icons.people_outline, _green),
];

/// A once-a-day goal that grants a claimable bonus when its target is met.
class DailyQuest {
  const DailyQuest(this.id, this.title, this.description, this.icon, this.color,
      this.target, this.reward, this.current);
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final int target;
  final int reward;

  /// Today's progress toward [target], read from the ledger.
  final int Function(PointsLedger) current;
}

/// The daily quest board. Progress is read live from [PointsLedger]; rewards
/// land in the `quests` point source when claimed.
final kDailyQuests = <DailyQuest>[
  DailyQuest('show_up', 'Show up', 'Open OkaySpace today',
      Icons.waving_hand_outlined, _gold, 1, 2, (l) => l.countedToday ? 1 : 0),
  DailyQuest('post', 'Share something', 'Make a post or reply',
      Icons.post_add_outlined, _blue, 1, 5, (l) => l.actionsToday('posts')),
  DailyQuest('react', 'Spread some love', 'React to 3 posts',
      Icons.favorite_border, _rose, 3, 4, (l) => l.actionsToday('reactions')),
  DailyQuest('connect', 'Make a connection', 'Follow someone new',
      Icons.person_add_alt_1_outlined, _green, 1, 4,
      (l) => l.actionsToday('social')),
  DailyQuest('stick_around', 'Stick around', 'Spend ~15 min in the app',
      Icons.schedule_outlined, _cyan, 3, 3, (l) => l.onlinePointsToday),
];

/// A week-long goal that grants a claimable bonus when its target is met.
/// Progress and claims reset every Monday.
class WeeklyChallenge {
  const WeeklyChallenge(this.id, this.title, this.description, this.icon,
      this.color, this.target, this.reward, this.current);
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final int target;
  final int reward;

  /// This week's progress toward [target], read from the ledger.
  final int Function(PointsLedger) current;
}

/// The weekly challenge board. Targets are bigger than daily quests and so are
/// the rewards; claimed bonuses land in the `challenges` point source.
final kWeeklyChallenges = <WeeklyChallenge>[
  WeeklyChallenge('points', 'Point hunter', 'Earn 100 points this week',
      Icons.toll_outlined, _gold, 100, 25,
      (l) => l.pointsThisCalendarWeek),
  WeeklyChallenge('goal_days', 'Goal getter', 'Hit your daily goal on 4 days',
      Icons.track_changes_outlined, _violet, 4, 20,
      (l) => l.goalDaysThisWeek),
  WeeklyChallenge('posts', 'On a roll', 'Make 7 posts or replies',
      Icons.post_add_outlined, _blue, 7, 15,
      (l) => l.actionsThisWeek('posts')),
  WeeklyChallenge('reactions', 'Hype machine', 'React to 20 posts',
      Icons.favorite_border, _rose, 20, 12,
      (l) => l.actionsThisWeek('reactions')),
  WeeklyChallenge('social', 'Networker', 'Follow 3 new people',
      Icons.person_add_alt_1_outlined, _green, 3, 10,
      (l) => l.actionsThisWeek('social')),
  WeeklyChallenge('quests', 'Quest devotee', 'Claim 12 daily quests',
      Icons.task_alt_outlined, _cyan, 12, 15,
      (l) => l.actionsThisWeek('quests')),
];

/// Looks up display metadata for a source id.
PointSource pointSourceFor(String id) => kPointSources.firstWhere(
      (s) => s.id == id,
      orElse: () => PointSource(id,
          id.isEmpty ? 'Activity' : '${id[0].toUpperCase()}${id.substring(1)}',
          Icons.bolt_outlined, _violet),
    );

/// How points are earned (display-only guidance).
const kPointWays = <(IconData, String, String)>[
  (Icons.post_add_outlined, 'Post & reply', 'Share posts and join threads'),
  (Icons.favorite_border, 'Get reactions', 'Likes and reposts on your posts'),
  (Icons.people_outline, 'Grow your circle', 'Followers and friends'),
  (Icons.schedule_outlined, 'Spend time here', 'A little for being online each day'),
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
