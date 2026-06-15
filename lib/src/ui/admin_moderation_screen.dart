import 'package:flutter/material.dart';

import 'common.dart';

/// Admin AI-moderation tools: scan existing posts, and test the moderator on
/// arbitrary text to see its exact verdict.
class AdminModerationScreen extends StatefulWidget {
  const AdminModerationScreen({super.key});

  @override
  State<AdminModerationScreen> createState() => _AdminModerationScreenState();
}

class _AdminModerationScreenState extends State<AdminModerationScreen> {
  final _text = TextEditingController();
  bool _testing = false;
  bool _scanning = false;
  Map<String, dynamic>? _verdict;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    setState(() {
      _testing = true;
      _verdict = null;
    });
    try {
      final res = await api.admin.moderationTest(t);
      if (mounted) setState(() => _verdict = res);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _scan() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Scan existing posts?'),
        content: const Text(
            'The AI will review recent posts and automatically remove any that '
            'break the rules. Authors are notified. This runs in the background '
            'and can take a few minutes.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Scan now')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _scanning = true);
    try {
      final res = await api.admin.moderationScan();
      if (!mounted) return;
      if (res['ok'] == true) {
        showInfo(context,
            'Scanning ${res['scanning'] ?? ''} posts — flagged ones will be removed shortly.');
      } else {
        showInfo(context, '${res['note'] ?? 'Could not start the scan.'}');
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Widget _verdictCard(Map<String, dynamic> v) {
    final scheme = Theme.of(context).colorScheme;
    if (v['ai_enabled'] != true) {
      return _banner(Icons.power_off_outlined, scheme.outline,
          'AI is off', '${v['note'] ?? 'Set GROQ_API_KEY to enable moderation.'}');
    }
    if (v['allow'] == null) {
      final lines = <String>['${v['note'] ?? 'The AI did not return a usable verdict.'}'];
      final diag = v['diagnostics'];
      if (diag is Map) {
        lines.add('');
        lines.add('Model: ${diag['text_model'] ?? '?'}');
        if (diag['error'] != null) lines.add('Error: ${diag['error']}');
        String fmt(dynamic m) {
          if (m is! Map) return '?';
          if (m['error'] != null) return 'failed: ${m['error']}';
          final detail = '${m['detail'] ?? ''}';
          return 'HTTP ${m['status']}${detail.isNotEmpty ? ' — $detail' : ''}';
        }

        if (diag['json_mode'] != null) lines.add('JSON mode: ${fmt(diag['json_mode'])}');
        if (diag['plain'] != null) lines.add('Plain call: ${fmt(diag['plain'])}');
      }
      return _banner(
          Icons.error_outline, scheme.error, 'No verdict', lines.join('\n'));
    }
    final removed = v['allow'] == false;
    return _banner(
      removed ? Icons.block : Icons.check_circle_outline,
      removed ? scheme.error : const Color(0xFF22C55E),
      removed ? 'Would be REMOVED' : 'Would be allowed',
      removed
          ? [
              if ('${v['category'] ?? ''}'.isNotEmpty) 'Category: ${v['category']}',
              if ('${v['reason'] ?? ''}'.isNotEmpty) '${v['reason']}',
            ].join('\n')
          : 'This post passes the moderation rules.',
    );
  }

  Widget _banner(IconData icon, Color color, String title, String body) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style:
                        TextStyle(color: color, fontWeight: FontWeight.bold)),
                if (body.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(body),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: const OkayAppBar(title: Text('AI moderation')),
      body: MaxWidth(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Automatic moderation',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
                'Posts are moderated automatically — new ones as they\'re posted, '
                'and existing ones by a background scan. Use this only to force an '
                'immediate pass over recent posts.',
                style: TextStyle(color: scheme.outline, fontSize: 13)),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _scanning ? null : _scan,
              icon: _scanning
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.cleaning_services_outlined),
              label: const Text('Scan recent posts now'),
            ),
            const Divider(height: 36),
            Text('Test the moderator',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
                'Paste any text to see exactly how the AI would rule on it — '
                'handy for confirming it works and tuning the rules.',
                style: TextStyle(color: scheme.outline, fontSize: 13)),
            const SizedBox(height: 10),
            TextField(
              controller: _text,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                hintText: 'Type or paste a post…',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _testing ? null : _test,
                icon: _testing
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.science_outlined),
                label: const Text('Run test'),
              ),
            ),
            if (_verdict != null) _verdictCard(_verdict!),
          ],
        ),
      ),
    );
  }
}
