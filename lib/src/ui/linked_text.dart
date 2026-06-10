import 'package:flutter/material.dart';

import 'hashtag_screen.dart';

/// Renders text with tappable #hashtags (opens the hashtag screen).
/// Uses [WidgetSpan]s so there are no gesture recognizers to dispose.
class LinkedText extends StatelessWidget {
  const LinkedText(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  static final _tag = RegExp(r'#[A-Za-z0-9_]+');

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in _tag.allMatches(text)) {
      if (m.start > last) {
        spans.add(TextSpan(text: text.substring(last, m.start)));
      }
      final tag = text.substring(m.start, m.end);
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: GestureDetector(
          onTap: () => HashtagScreen.open(context, tag.substring(1)),
          child: Text(tag,
              style: (style ?? const TextStyle()).copyWith(color: primary)),
        ),
      ));
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return Text.rich(TextSpan(style: style, children: spans));
  }
}
