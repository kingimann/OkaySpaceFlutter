import 'package:flutter/material.dart';

import 'common.dart';
import 'hashtag_screen.dart';
import 'profile_screen.dart';

/// Renders text with tappable #hashtags and @mentions.
///
/// Hashtags open the hashtag screen; mentions resolve the username to a user
/// and open their profile. Uses [WidgetSpan]s so there are no gesture
/// recognizers to dispose.
class LinkedText extends StatelessWidget {
  const LinkedText(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  static final _token = RegExp(r'[#@][A-Za-z0-9_]+');

  Future<void> _openMention(BuildContext context, String username) async {
    try {
      final user = await api.users.byUsername(username);
      final id = (user['user_id'] ?? user['id'])?.toString();
      if (id != null && id.isNotEmpty && context.mounted) {
        ProfileScreen.open(context, id);
      } else if (context.mounted) {
        showInfo(context, 'User @$username not found');
      }
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final linkStyle = (style ?? const TextStyle()).copyWith(color: primary);
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in _token.allMatches(text)) {
      if (m.start > last) {
        spans.add(TextSpan(text: text.substring(last, m.start)));
      }
      final token = text.substring(m.start, m.end);
      final name = token.substring(1);
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: GestureDetector(
          onTap: token[0] == '#'
              ? () => HashtagScreen.open(context, name)
              : () => _openMention(context, name),
          child: Text(token, style: linkStyle),
        ),
      ));
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return Text.rich(TextSpan(style: style, children: spans));
  }
}
