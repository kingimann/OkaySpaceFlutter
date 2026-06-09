import 'json.dart';

/// A badge shown next to a user (verified, role, achievement, etc.).
class Badge {
  const Badge({this.id, this.label, this.icon, this.color, this.raw = const {}});

  final String? id;
  final String? label;
  final String? icon;
  final String? color;

  /// Full payload for fields not modelled explicitly.
  final Map<String, dynamic> raw;

  factory Badge.fromJson(Map<String, dynamic> json) => Badge(
        id: asStringOrNull(json['id']),
        label: asStringOrNull(json['label'] ?? json['name']),
        icon: asStringOrNull(json['icon']),
        color: asStringOrNull(json['color']),
        raw: json,
      );

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        if (label != null) 'label': label,
        if (icon != null) 'icon': icon,
        if (color != null) 'color': color,
      };
}
