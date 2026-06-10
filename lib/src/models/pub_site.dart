import 'json.dart';

/// A registered publisher site in the OkaySpace ad network (§10 monetize).
/// Mirrors the `/pub/sites` payload.
class PubSite {
  const PubSite({
    required this.id,
    required this.name,
    this.domain = '',
    this.siteKey = '',
    this.impressions = 0,
    this.clicks = 0,
    this.ctr = 0,
    this.earned = 0,
    required this.createdAt,
    this.raw = const {},
  });

  final String id;
  final String name;
  final String domain;
  final String siteKey;
  final int impressions;
  final int clicks;
  final double ctr;
  final num earned;
  final DateTime createdAt;
  final Map<String, dynamic> raw;

  factory PubSite.fromJson(Map<String, dynamic> json) => PubSite(
        id: asString(json['id'] ?? json['site_id']),
        name: asString(json['name'], 'Site'),
        domain: asString(json['domain']),
        siteKey: asString(json['site_key'] ?? json['key']),
        impressions: asInt(json['impressions']),
        clicks: asInt(json['clicks']),
        ctr: asDoubleOrNull(json['ctr']) ?? 0,
        earned: asDoubleOrNull(json['earned'] ?? json['earnings']) ?? 0,
        createdAt: asDate(json['created_at']),
        raw: json,
      );

  /// The embed snippet a publisher pastes into their site's HTML.
  String get embedSnippet =>
      '<script async src="https://okayspace.ca/pub/ads.js" '
      'data-site-key="$siteKey"></script>';
}
