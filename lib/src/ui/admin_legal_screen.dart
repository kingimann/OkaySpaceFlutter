import 'package:flutter/material.dart';

import 'common.dart';

/// Admin · edit the Terms of Service and Privacy Policy.
///
/// Loads the current text from the backend, lets an admin edit both documents
/// and the effective date, and saves them (stored server-side; no redeploy).
class AdminLegalScreen extends StatefulWidget {
  const AdminLegalScreen({super.key});

  @override
  State<AdminLegalScreen> createState() => _AdminLegalScreenState();
}

class _AdminLegalScreenState extends State<AdminLegalScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  final _terms = TextEditingController();
  final _privacy = TextEditingController();
  final _effective = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final d = await api.admin.legal();
      if (!mounted) return;
      _terms.text = '${d['terms'] ?? ''}';
      _privacy.text = '${d['privacy'] ?? ''}';
      _effective.text = '${d['effective_date'] ?? ''}';
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await api.admin.updateLegal(
        terms: _terms.text,
        privacy: _privacy.text,
        effectiveDate: _effective.text.trim(),
      );
      if (mounted) showInfo(context, 'Saved');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    _terms.dispose();
    _privacy.dispose();
    _effective.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: OkayAppBar(
        title: const Text('Admin · Legal'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [Tab(text: 'Terms of Service'), Tab(text: 'Privacy Policy')],
        ),
        actions: [
          _saving
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : TextButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: TextField(
                    controller: _effective,
                    decoration: const InputDecoration(
                      labelText: 'Effective date (e.g. June 14, 2026)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabs,
                    children: [
                      _editor(_terms, 'Terms of Service'),
                      _editor(_privacy, 'Privacy Policy'),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _editor(TextEditingController c, String label) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: TextField(
        controller: c,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        keyboardType: TextInputType.multiline,
        decoration: InputDecoration(
          labelText: label,
          alignLabelWithHint: true,
          border: const OutlineInputBorder(),
          hintText: 'Write or paste the $label here…',
        ),
      ),
    );
  }
}
