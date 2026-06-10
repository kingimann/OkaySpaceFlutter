import 'package:flutter/material.dart';

import 'common.dart';

/// Field types supported by the form builder (label, api value, icon).
const _kFieldTypes = <(String, String, IconData)>[
  ('Text', 'text', Icons.short_text),
  ('Email', 'email', Icons.alternate_email),
  ('Phone', 'phone', Icons.phone_outlined),
  ('Number', 'number', Icons.numbers),
  ('Paragraph', 'paragraph', Icons.notes),
  ('Date', 'date', Icons.event_outlined),
  ('Dropdown', 'dropdown', Icons.arrow_drop_down_circle_outlined),
  ('Single choice', 'single', Icons.radio_button_checked),
  ('Checkboxes', 'checkboxes', Icons.check_box_outlined),
];

bool _hasOptions(String type) =>
    type == 'dropdown' || type == 'single' || type == 'checkboxes';

IconData _fieldIcon(String type) => _kFieldTypes
    .firstWhere((t) => t.$2 == type,
        orElse: () => ('', '', Icons.short_text))
    .$3;

/// The user's custom forms: build, share and collect responses.
class FormsScreen extends StatefulWidget {
  const FormsScreen({super.key});

  @override
  State<FormsScreen> createState() => _FormsScreenState();
}

class _FormsScreenState extends State<FormsScreen> {
  late Future<List<Map<String, dynamic>>> _forms;

  @override
  void initState() {
    super.initState();
    _forms = api.forms.forms();
  }

  Future<void> _reload() async {
    setState(() => _forms = api.forms.forms());
    await _forms;
  }

  Future<void> _create() async {
    final changed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const FormBuilderScreen()));
    if (changed == true && mounted) _reload();
  }

  Future<void> _delete(Map<String, dynamic> f) async {
    final id = '${f['id'] ?? ''}';
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete form?'),
        content: Text(
            '“${f['title'] ?? 'Untitled'}” and its responses will be removed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await api.forms.delete(id);
      if (mounted) _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const OkayAppBar(title: Text('Forms')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('New form'),
      ),
      body: MaxWidth(
        child: RefreshIndicator(
          onRefresh: _reload,
          child: AsyncList<Map<String, dynamic>>(
            future: _forms,
            loading: const ListSkeleton(),
            emptyMessage:
                'No forms yet.\nBuild one to collect responses anywhere.',
            emptyIcon: Icons.assignment_outlined,
            builder: (context, items) => ListView.builder(
              padding: const EdgeInsets.only(top: 6, bottom: 88),
              itemCount: items.length,
              itemBuilder: (context, i) {
                final f = items[i];
                final fields = f['fields'] is List
                    ? (f['fields'] as List).length
                    : 0;
                final responses =
                    f['submission_count'] ?? f['responses'] ?? '';
                return Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.14),
                      child: Icon(Icons.assignment_outlined,
                          color: Theme.of(context).colorScheme.primary),
                    ),
                    title: Text('${f['title'] ?? 'Untitled'}',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                        '$fields field${fields == 1 ? '' : 's'}'
                        '${'$responses'.isNotEmpty ? ' · $responses responses' : ''}'),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) async {
                        if (v == 'edit') {
                          final changed = await Navigator.of(context)
                              .push<bool>(MaterialPageRoute(
                                  builder: (_) =>
                                      FormBuilderScreen(existing: f)));
                          if (changed == true && mounted) _reload();
                        } else if (v == 'delete') {
                          _delete(f);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('Edit')),
                        PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                    ),
                    onTap: () =>
                        Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => FormSubmissionsScreen(
                          formId: '${f['id'] ?? ''}',
                          title: '${f['title'] ?? 'Form'}'),
                    )),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Build or edit a form: title, settings and a list of typed fields.
class FormBuilderScreen extends StatefulWidget {
  const FormBuilderScreen({super.key, this.existing});

  /// When set, edits this form instead of creating a new one.
  final Map<String, dynamic>? existing;

  @override
  State<FormBuilderScreen> createState() => _FormBuilderScreenState();
}

class _FormBuilderScreenState extends State<FormBuilderScreen> {
  late final TextEditingController _title =
      TextEditingController(text: '${widget.existing?['title'] ?? ''}');
  late final TextEditingController _description =
      TextEditingController(text: '${widget.existing?['description'] ?? ''}');
  late final TextEditingController _submitLabel = TextEditingController(
      text: '${widget.existing?['submit_label'] ?? ''}');
  late final TextEditingController _notifyEmail = TextEditingController(
      text: '${widget.existing?['notify_email'] ?? ''}');

  late final List<Map<String, dynamic>> _fields = [
    for (final f in (widget.existing?['fields'] as List? ?? const []))
      if (f is Map) Map<String, dynamic>.from(f)
  ];
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _submitLabel.dispose();
    _notifyEmail.dispose();
    super.dispose();
  }

  Future<void> _addOrEditField([int? index]) async {
    final field = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) =>
          _FieldDialog(existing: index != null ? _fields[index] : null),
    );
    if (field == null) return;
    setState(() {
      if (index != null) {
        _fields[index] = field;
      } else {
        _fields.add(field);
      }
    });
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty || _fields.isEmpty) {
      showInfo(context, 'Add a title and at least one field.');
      return;
    }
    setState(() => _busy = true);
    try {
      final body = {
        'title': _title.text.trim(),
        'description': _description.text.trim(),
        'submit_label': _submitLabel.text.trim().isEmpty
            ? 'Submit'
            : _submitLabel.text.trim(),
        if (_notifyEmail.text.trim().isNotEmpty)
          'notify_email': _notifyEmail.text.trim(),
        'fields': _fields,
      };
      final existingId = '${widget.existing?['id'] ?? ''}';
      if (existingId.isNotEmpty) {
        await api.forms.update(existingId, body);
      } else {
        await api.forms.create(
          title: _title.text.trim(),
          description: _description.text.trim(),
          submitLabel: '${body['submit_label']}',
          notifyEmail: _notifyEmail.text.trim().isEmpty
              ? null
              : _notifyEmail.text.trim(),
          fields: _fields,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: OkayAppBar(
        title: Text(widget.existing != null ? 'Edit form' : 'New form'),
        actions: [
          TextButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save'),
          ),
        ],
      ),
      body: MaxWidth(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _title,
              decoration: const InputDecoration(
                  labelText: 'Form title', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _description,
              maxLines: 2,
              decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _submitLabel,
                    decoration: const InputDecoration(
                        labelText: 'Submit button label',
                        hintText: 'Submit',
                        border: OutlineInputBorder()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _notifyEmail,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                  labelText: 'Email responses to (optional)',
                  prefixIcon: Icon(Icons.mail_outline),
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Text('Fields',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold)),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _addOrEditField(),
                  icon: const Icon(Icons.add),
                  label: const Text('Add field'),
                ),
              ],
            ),
            if (_fields.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text('No fields yet.',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.outline)),
                ),
              ),
            for (var i = 0; i < _fields.length; i++)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Icon(_fieldIcon('${_fields[i]['type']}')),
                  title: Text('${_fields[i]['label'] ?? 'Field'}'),
                  subtitle: Text([
                    '${_fields[i]['type']}',
                    if (_fields[i]['required'] == true) 'required',
                  ].join(' · ')),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (i > 0)
                        IconButton(
                          icon: const Icon(Icons.arrow_upward, size: 18),
                          tooltip: 'Move up',
                          onPressed: () => setState(() =>
                              _fields.insert(i - 1, _fields.removeAt(i))),
                        ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: () =>
                            setState(() => _fields.removeAt(i)),
                      ),
                    ],
                  ),
                  onTap: () => _addOrEditField(i),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Add/edit one form field: type, label, required and options.
class _FieldDialog extends StatefulWidget {
  const _FieldDialog({this.existing});

  final Map<String, dynamic>? existing;

  @override
  State<_FieldDialog> createState() => _FieldDialogState();
}

class _FieldDialogState extends State<_FieldDialog> {
  late final TextEditingController _label =
      TextEditingController(text: '${widget.existing?['label'] ?? ''}');
  late final TextEditingController _options = TextEditingController(
      text: (widget.existing?['options'] as List? ?? const []).join(', '));
  late String _type = '${widget.existing?['type'] ?? 'text'}';
  late bool _required = widget.existing?['required'] == true;

  @override
  void dispose() {
    _label.dispose();
    _options.dispose();
    super.dispose();
  }

  void _submit() {
    if (_label.text.trim().isEmpty) return;
    final field = <String, dynamic>{
      'id': '${widget.existing?['id'] ?? DateTime.now().millisecondsSinceEpoch}',
      'type': _type,
      'label': _label.text.trim(),
      'required': _required,
      if (_hasOptions(_type))
        'options': [
          for (final o in _options.text.split(','))
            if (o.trim().isNotEmpty) o.trim()
        ],
    };
    Navigator.pop(context, field);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing != null ? 'Edit field' : 'Add field'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: const InputDecoration(
                  labelText: 'Type', border: OutlineInputBorder()),
              items: [
                for (final (label, value, icon) in _kFieldTypes)
                  DropdownMenuItem(
                    value: value,
                    child: Row(children: [
                      Icon(icon, size: 18),
                      const SizedBox(width: 8),
                      Text(label),
                    ]),
                  ),
              ],
              onChanged: (v) => setState(() => _type = v ?? 'text'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _label,
              autofocus: true,
              decoration: const InputDecoration(
                  labelText: 'Label', border: OutlineInputBorder()),
            ),
            if (_hasOptions(_type)) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _options,
                decoration: const InputDecoration(
                    labelText: 'Options (comma-separated)',
                    hintText: 'Red, Green, Blue',
                    border: OutlineInputBorder()),
              ),
            ],
            SwitchListTile(
              value: _required,
              onChanged: (v) => setState(() => _required = v),
              title: const Text('Required'),
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Done')),
      ],
    );
  }
}

/// Responses collected by a form.
class FormSubmissionsScreen extends StatefulWidget {
  const FormSubmissionsScreen(
      {super.key, required this.formId, required this.title});

  final String formId;
  final String title;

  @override
  State<FormSubmissionsScreen> createState() => _FormSubmissionsScreenState();
}

class _FormSubmissionsScreenState extends State<FormSubmissionsScreen> {
  late Future<List<Map<String, dynamic>>> _submissions;

  @override
  void initState() {
    super.initState();
    _submissions = api.forms.submissions(widget.formId);
  }

  Future<void> _reload() async {
    setState(() => _submissions = api.forms.submissions(widget.formId));
    await _submissions;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: OkayAppBar(title: Text(widget.title)),
      body: MaxWidth(
        child: RefreshIndicator(
          onRefresh: _reload,
          child: AsyncList<Map<String, dynamic>>(
            future: _submissions,
            emptyMessage: 'No responses yet.',
            emptyIcon: Icons.inbox_outlined,
            builder: (context, items) => ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              itemBuilder: (context, i) {
                final s = items[i];
                final values = s['values'] is Map
                    ? Map<String, dynamic>.from(s['values'] as Map)
                    : <String, dynamic>{};
                final when = DateTime.tryParse('${s['created_at'] ?? ''}');
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Response ${items.length - i}'
                            '${when != null ? ' · ${shortAgo(when)}' : ''}',
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.outline,
                                fontSize: 12,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        for (final e in values.entries)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text.rich(TextSpan(children: [
                              TextSpan(
                                  text: '${e.key}: ',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                              TextSpan(text: '${e.value}'),
                            ])),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
