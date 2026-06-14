import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'common.dart';
import 'util/file_download.dart';

/// Self-serve data backup & restore. Download a signed copy of your data, and
/// restore it later if needed. Money and account privileges are never part of
/// this — those are recovered through their own (authoritative) paths.
class DataBackupScreen extends StatefulWidget {
  const DataBackupScreen({super.key});

  @override
  State<DataBackupScreen> createState() => _DataBackupScreenState();
}

class _DataBackupScreenState extends State<DataBackupScreen> {
  bool _busy = false;

  Future<void> _download() async {
    setState(() => _busy = true);
    try {
      final bundle = await api.auth.exportData();
      final text = const JsonEncoder.withIndent('  ').convert(bundle);
      final name =
          'okayspace-backup-${DateTime.now().toIso8601String().split('T').first}.json';
      final ok = downloadText(name, text);
      if (!mounted) return;
      if (ok) {
        showInfo(context, 'Backup downloaded. Keep it somewhere safe.');
      } else {
        await Clipboard.setData(ClipboardData(text: text));
        if (mounted) {
          showInfo(context,
              'Backup copied to clipboard — paste it into a file and save it.');
        }
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final res = await FilePicker.pickFiles(
        type: FileType.custom, allowedExtensions: ['json'], withData: true);
    final bytes = res?.files.single.bytes;
    if (bytes == null || !mounted) return;
    Map<String, dynamic> bundle;
    try {
      final parsed = jsonDecode(utf8.decode(bytes));
      if (parsed is! Map) throw const FormatException('Not a backup file');
      bundle = parsed.cast<String, dynamic>();
    } catch (_) {
      showError(context, 'That doesn\'t look like a valid backup file.');
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore from backup?'),
        content: const Text(
            'This adds back any of your content that\'s missing (notes, '
            'calendar, reminders, drafts, posts). It won\'t overwrite newer '
            'data, and it never changes your balance or account settings.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Restore')),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _busy = true);
    try {
      final r = await api.auth.importData(bundle);
      if (!mounted) return;
      final restored = (r['restored'] as Map?) ?? const {};
      final total = restored.values
          .fold<int>(0, (s, v) => s + (v is num ? v.toInt() : 0));
      showInfo(context,
          total == 0 ? 'Everything was already up to date.' : 'Restored $total item(s).');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: const OkayAppBar(title: Text('Backup & restore')),
      body: MaxWidth(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Download a copy of your data to keep safe. If you ever need to, '
              'you can restore it here — it brings back your content without '
              'touching your balance or account settings.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            Card(
              child: ListTile(
                leading: const Icon(Icons.download_outlined),
                title: const Text('Download my data'),
                subtitle: const Text(
                    'Profile, notes, calendar, reminders, drafts and posts'),
                trailing: _busy ? null : const Icon(Icons.chevron_right),
                onTap: _busy ? null : _download,
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.restore_outlined),
                title: const Text('Restore from a backup'),
                subtitle: const Text('Upload a backup file you downloaded'),
                trailing: _busy ? null : const Icon(Icons.chevron_right),
                onTap: _busy ? null : _restore,
              ),
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(top: 20),
                child: Center(child: CircularProgressIndicator()),
              ),
            const SizedBox(height: 16),
            Text(
              'Your wallet balance isn\'t in the backup — it\'s recovered from '
              'your real Stripe payments, so it can\'t be tampered with.',
              style: TextStyle(color: scheme.outline, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
