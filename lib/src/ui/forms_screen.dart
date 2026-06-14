import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../okayspace_api.dart';
import '../core/forms_e2e.dart';
import 'common.dart';
import 'form_viewer_screen.dart';

/// Asks for a form's end-to-end passphrase (obscured). Returns null on cancel.
Future<String?> _askPassphrase(BuildContext context,
    {required String title, String? subtitle, String action = 'Unlock'}) async {
  final ctrl = TextEditingController();
  try {
    return await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (subtitle != null) ...[
              Text(subtitle,
                  style: TextStyle(color: Theme.of(context).colorScheme.outline)),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: ctrl,
              autofocus: true,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: 'Passphrase', border: OutlineInputBorder()),
              onSubmitted: (v) => Navigator.pop(context, v),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, ctrl.text),
              child: Text(action)),
        ],
      ),
    );
  } finally {
    ctrl.dispose();
  }
}

/// Field types supported by the form builder, grouped by category
/// (label, api value matching the backend, icon).
const _kFieldGroups = <(String, List<(String, String, IconData)>)>[
  ('Basic', [
    ('Short text', 'text', Icons.short_text),
    ('Paragraph', 'textarea', Icons.notes),
    ('Email', 'email', Icons.alternate_email),
    ('Phone', 'phone', Icons.phone_outlined),
    ('Number', 'number', Icons.numbers),
    ('Website', 'url', Icons.link),
  ]),
  ('Choice', [
    ('Dropdown', 'select', Icons.arrow_drop_down_circle_outlined),
    ('Single choice', 'radio', Icons.radio_button_checked),
    ('Checkboxes', 'checkbox', Icons.check_box_outlined),
  ]),
  ('Date & rating', [
    ('Date', 'date', Icons.event_outlined),
    ('Time', 'time', Icons.schedule),
    ('Rating', 'rating', Icons.star_outline),
  ]),
  ('Advanced', [
    ('Address', 'address', Icons.location_on_outlined),
    ('Signature', 'signature', Icons.draw_outlined),
    ('File / photo', 'photo', Icons.upload_file),
    ('Consent', 'consent', Icons.fact_check_outlined),
    ('Section heading', 'heading', Icons.title),
    ('Payment', 'payment', Icons.payments_outlined),
  ]),
];

/// Flat list of every field type.
final _kFieldTypes = [for (final g in _kFieldGroups) ...g.$2];

bool _hasOptions(String type) =>
    type == 'select' || type == 'radio' || type == 'checkbox';

/// Maps legacy builder type names to the backend's field types so older forms
/// (and their saved fields) keep their proper type instead of degrading.
String _migrateType(String t) => switch (t) {
      'paragraph' => 'textarea',
      'dropdown' => 'select',
      'single' => 'radio',
      'checkboxes' => 'checkbox',
      _ => t,
    };

String _typeLabel(String type) => _kFieldTypes
    .firstWhere((t) => t.$2 == type, orElse: () => (type, type, Icons.short_text))
    .$1;

IconData _fieldIcon(String type) => _kFieldTypes
    .firstWhere((t) => t.$2 == type,
        orElse: () => ('', '', Icons.short_text))
    .$3;

/// A clean, filled input style that stays visible on dark backgrounds.
InputDecoration _formDec(String label, {String? hint, IconData? icon}) =>
    InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: icon != null ? Icon(icon) : null,
      filled: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    );

Map<String, dynamic> _tf(int i, String type, String label,
        {bool required = false, List<String>? options}) =>
    {
      'id': 'f$i',
      'type': type,
      'label': label,
      'required': required,
      if (options != null) 'options': options,
    };

/// Pre-built starter forms (name, icon, form map ready for the builder).
List<(String, IconData, Map<String, dynamic>)> _formTemplates() => [
      ('Contact form', Icons.contact_mail_outlined, {
        'title': 'Contact us',
        'description': 'We\'ll get back to you soon.',
        'fields': [
          _tf(1, 'text', 'Name', required: true),
          _tf(2, 'email', 'Email', required: true),
          _tf(3, 'phone', 'Phone'),
          _tf(4, 'textarea', 'Message', required: true),
        ],
      }),
      ('Event RSVP', Icons.event_available_outlined, {
        'title': 'RSVP',
        'description': 'Please let us know if you can make it.',
        'fields': [
          _tf(1, 'text', 'Full name', required: true),
          _tf(2, 'email', 'Email', required: true),
          _tf(3, 'radio', 'Will you attend?',
              required: true, options: ['Yes', 'No', 'Maybe']),
          _tf(4, 'number', 'Number of guests'),
          _tf(5, 'textarea', 'Dietary restrictions'),
        ],
      }),
      ('Feedback survey', Icons.reviews_outlined, {
        'title': 'Feedback',
        'description': 'Help us improve.',
        'fields': [
          _tf(1, 'rating', 'Overall rating', required: true),
          _tf(2, 'radio', 'Would you recommend us?',
              options: ['Definitely', 'Maybe', 'No']),
          _tf(3, 'textarea', 'What went well?'),
          _tf(4, 'textarea', 'What could be better?'),
          _tf(5, 'email', 'Email (optional)'),
        ],
      }),
      ('Job application', Icons.work_outline, {
        'title': 'Job application',
        'fields': [
          _tf(1, 'text', 'Full name', required: true),
          _tf(2, 'email', 'Email', required: true),
          _tf(3, 'phone', 'Phone', required: true),
          _tf(4, 'url', 'LinkedIn / portfolio'),
          _tf(5, 'select', 'Position',
              required: true,
              options: ['Engineering', 'Design', 'Sales', 'Support', 'Other']),
          _tf(6, 'photo', 'Resume / CV', required: true),
          _tf(7, 'textarea', 'Why do you want this role?'),
        ],
      }),
      ('Order form', Icons.shopping_bag_outlined, {
        'title': 'Place an order',
        'fields': [
          _tf(1, 'text', 'Name', required: true),
          _tf(2, 'email', 'Email', required: true),
          _tf(3, 'select', 'Size',
              required: true, options: ['Small', 'Medium', 'Large']),
          _tf(4, 'number', 'Quantity', required: true),
          _tf(5, 'address', 'Shipping address', required: true),
          _tf(6, 'textarea', 'Notes'),
          _tf(7, 'consent', 'I agree to the terms', required: true),
        ],
      }),
      ('Appointment booking', Icons.calendar_month_outlined, {
        'title': 'Book an appointment',
        'fields': [
          _tf(1, 'text', 'Name', required: true),
          _tf(2, 'phone', 'Phone', required: true),
          _tf(3, 'email', 'Email'),
          _tf(4, 'date', 'Preferred date', required: true),
          _tf(5, 'time', 'Preferred time', required: true),
          _tf(6, 'select', 'Service',
              options: ['Consultation', 'Follow-up', 'Other']),
          _tf(7, 'textarea', 'Anything we should know?'),
        ],
      }),
      ('Newsletter signup', Icons.mark_email_read_outlined, {
        'title': 'Join our newsletter',
        'fields': [
          _tf(1, 'text', 'First name'),
          _tf(2, 'email', 'Email', required: true),
          _tf(3, 'checkbox', 'Interests',
              options: ['Product news', 'Tips', 'Events', 'Offers']),
          _tf(4, 'consent', 'I agree to receive emails', required: true),
        ],
      }),
    ];

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
    final choice = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.92,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
          children: [
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text('Create a form',
                  style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            Card(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.add)),
                title: const Text('Blank form'),
                subtitle: const Text('Start from scratch'),
                onTap: () => Navigator.pop(ctx, <String, dynamic>{}),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(8, 14, 8, 6),
              child: Text('TEMPLATES',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5)),
            ),
            for (final (name, icon, form) in _formTemplates())
              Card(
                child: ListTile(
                  leading: CircleAvatar(
                      backgroundColor: Theme.of(ctx)
                          .colorScheme
                          .primaryContainer,
                      child: Icon(icon,
                          color: Theme.of(ctx).colorScheme.onPrimaryContainer)),
                  title: Text(name),
                  subtitle: Text(
                      '${(form['fields'] as List).length} fields',
                      style: TextStyle(
                          color: Theme.of(ctx).colorScheme.outline)),
                  onTap: () => Navigator.pop(ctx, form),
                ),
              ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    final existing = choice.isEmpty ? null : choice;
    final changed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => FormBuilderScreen(existing: existing)));
    if (changed == true && mounted) _reload();
  }

  void _preview(Map<String, dynamic> f) {
    final key = '${f['form_key'] ?? ''}';
    if (key.isEmpty) {
      showInfo(context, 'Save the form first to preview it.');
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FormViewerScreen(
          url: api.forms.publicLink(key), title: '${f['title'] ?? 'Form'}'),
    ));
  }

  Future<void> _copyLink(Map<String, dynamic> f) async {
    final key = '${f['form_key'] ?? ''}';
    if (key.isEmpty) {
      showInfo(context, 'No share link yet — save the form first.');
      return;
    }
    await Clipboard.setData(ClipboardData(text: api.forms.publicLink(key)));
    if (mounted) showInfo(context, 'Share link copied');
  }

  Future<void> _sendToChat(Map<String, dynamic> f) async {
    final id = '${f['id'] ?? ''}';
    if (id.isEmpty) return;
    final conv = await pickConversation(context);
    if (conv == null || !mounted) return;
    try {
      await api.messaging.send(conv.id, MessageCreate(type: 'form', formId: id));
      if (mounted) showInfo(context, 'Sent');
    } catch (e) {
      if (mounted) showError(context, e);
    }
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
                        } else if (v == 'preview') {
                          _preview(f);
                        } else if (v == 'link') {
                          _copyLink(f);
                        } else if (v == 'send') {
                          _sendToChat(f);
                        } else if (v == 'delete') {
                          _delete(f);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('Edit')),
                        PopupMenuItem(value: 'preview', child: Text('Preview')),
                        PopupMenuItem(
                            value: 'link', child: Text('Copy share link')),
                        PopupMenuItem(
                            value: 'send', child: Text('Send to a chat')),
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
  late final TextEditingController _successMessage = TextEditingController(
      text: '${widget.existing?['success_message'] ?? ''}');
  late bool _aiValidate = widget.existing?['ai_validate'] == true;
  late String? _accent = (widget.existing?['accent'] as String?);
  // End-to-end encryption: when on, responses are encrypted in the browser to
  // [_e2ePublicKey] and can only be read with the passphrase that derives the
  // matching private key (re-derivable via [_e2eSalt]).
  late bool _e2e = widget.existing?['e2e'] == true;
  late String? _e2ePublicKey = widget.existing?['e2e_public_key'] as String?;
  late String? _e2eSalt = widget.existing?['e2e_salt'] as String?;

  static const _accentChoices = <String>[
    '#00A884', '#3B82F6', '#8B5CF6', '#EC4899', '#EF4444',
    '#F97316', '#EAB308', '#14B8A6', '#0EA5E9', '#64748B',
  ];

  late final List<Map<String, dynamic>> _fields = [
    for (final f in (widget.existing?['fields'] as List? ?? const []))
      if (f is Map)
        (Map<String, dynamic>.from(f)
          ..['type'] = _migrateType('${f['type'] ?? 'text'}'))
  ];
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _submitLabel.dispose();
    _notifyEmail.dispose();
    _successMessage.dispose();
    super.dispose();
  }

  Future<void> _addOrEditField([int? index]) async {
    String? type;
    if (index == null) {
      type = await _pickFieldType();
      if (type == null) return;
    }
    if (!mounted) return;
    final field = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _FieldEditorScreen(
          existing: index != null ? _fields[index] : null,
          initialType: type,
          otherFields: [
            for (var j = 0; j < _fields.length; j++)
              if (j != index) _fields[j]
          ],
        ),
      ),
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

  /// A categorized picker of every field type.
  Future<String?> _pickFieldType() {
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.92,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
          children: [
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text('Add a field',
                  style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            for (final (group, types) in _kFieldGroups) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 12, 8, 6),
                child: Text(group.toUpperCase(),
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: Theme.of(ctx).colorScheme.outline)),
              ),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 3.2,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                children: [
                  for (final (label, value, icon) in types)
                    OutlinedButton.icon(
                      onPressed: () => Navigator.pop(ctx, value),
                      icon: Icon(icon, size: 20),
                      style: OutlinedButton.styleFrom(
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.symmetric(horizontal: 12)),
                      label: Text(label,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  bool get _hasPayment => _fields.any((f) => '${f['type']}' == 'payment');

  Future<void> _toggleE2E(bool on) async {
    if (!on) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Turn off encryption?'),
          content: const Text(
              'New responses will no longer be end-to-end encrypted. Existing '
              'encrypted responses stay locked to the original passphrase.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Turn off')),
          ],
        ),
      );
      if (ok == true) {
        setState(() {
          _e2e = false;
          _e2ePublicKey = null;
          _e2eSalt = null;
        });
      }
      return;
    }
    if (_hasPayment) {
      showInfo(context,
          'End-to-end encryption can’t be used on a form that takes payment.');
      return;
    }
    // Already set up (editing an E2E form) — keep the existing key so old
    // responses stay readable with the same passphrase.
    if (_e2ePublicKey != null && _e2eSalt != null) {
      setState(() => _e2e = true);
      return;
    }
    final pass = await _askPassphrase(context,
        title: 'Set a passphrase',
        subtitle:
            'Responses are encrypted so only you can read them — using this '
            'passphrase. We can’t recover it. If you lose it, the responses are '
            'unreadable forever. Store it somewhere safe.',
        action: 'Set passphrase');
    if (pass == null) return;
    if (pass.trim().length < 6) {
      if (mounted) showInfo(context, 'Use at least 6 characters.');
      return;
    }
    if (!mounted) return;
    final confirm = await _askPassphrase(context,
        title: 'Confirm passphrase', action: 'Confirm');
    if (confirm == null) return;
    if (confirm != pass) {
      if (mounted) showInfo(context, 'Passphrases didn’t match.');
      return;
    }
    try {
      final keys = await FormsE2E.setup(pass);
      if (!mounted) return;
      setState(() {
        _e2e = true;
        _e2ePublicKey = keys.publicKey;
        _e2eSalt = keys.salt;
      });
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty || _fields.isEmpty) {
      showInfo(context, 'Add a title and at least one field.');
      return;
    }
    if (_e2e && _hasPayment) {
      showInfo(context,
          'End-to-end encryption can’t be used on a form that takes payment. '
          'Remove the payment field or turn off encryption.');
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
        if (_successMessage.text.trim().isNotEmpty)
          'success_message': _successMessage.text.trim(),
        'ai_validate': _aiValidate,
        if (_accent != null) 'accent': _accent,
        'e2e': _e2e,
        if (_e2ePublicKey != null) 'e2e_public_key': _e2ePublicKey,
        if (_e2eSalt != null) 'e2e_salt': _e2eSalt,
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
          successMessage: _successMessage.text.trim().isEmpty
              ? null
              : _successMessage.text.trim(),
          aiValidate: _aiValidate,
          accent: _accent,
          e2e: _e2e,
          e2ePublicKey: _e2ePublicKey,
          e2eSalt: _e2eSalt,
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
        title: Text(
            widget.existing?['id'] != null ? 'Edit form' : 'New form'),
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
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w600),
              decoration: _formDec('Form title'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _description,
              maxLines: 2,
              decoration: _formDec('Description (optional)'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _submitLabel,
              decoration: _formDec('Submit button label', hint: 'Submit'),
            ),
            const SizedBox(height: 8),
            Theme(
              data: Theme.of(context)
                  .copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 8),
                leading: const Icon(Icons.tune),
                title: const Text('Settings & customization'),
                children: [
                  TextField(
                    controller: _notifyEmail,
                    keyboardType: TextInputType.emailAddress,
                    decoration: _formDec('Email responses to (optional)',
                        icon: Icons.mail_outline),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _successMessage,
                    maxLines: 2,
                    decoration: _formDec('Thank-you message (optional)',
                        hint: 'Shown after someone submits the form',
                        icon: Icons.celebration_outlined),
                  ),
                  const SizedBox(height: 6),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _aiValidate,
                    onChanged: (v) => setState(() => _aiValidate = v),
                    secondary: const Icon(Icons.verified_outlined),
                    title: const Text('AI response check'),
                    subtitle: const Text(
                        'Flag incomplete or implausible submissions'),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _e2e,
                    onChanged: (v) => _toggleE2E(v),
                    secondary: const Icon(Icons.lock_outline),
                    title: const Text('End-to-end encrypt responses'),
                    subtitle: Text(_e2e
                        ? 'On — responses can only be read with your passphrase'
                        : 'Only you can read responses; not even the server can'),
                  ),
                  if (_e2e)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline,
                              size: 16,
                              color: Theme.of(context).colorScheme.outline),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                                'Keep your passphrase safe — it can’t be recovered.',
                                style: TextStyle(
                                    fontSize: 12,
                                    color:
                                        Theme.of(context).colorScheme.outline)),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Accent colour',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final hex in _accentChoices)
                        GestureDetector(
                          onTap: () => setState(() => _accent = hex),
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: Color(int.parse('FF${hex.substring(1)}',
                                  radix: 16)),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _accent == hex
                                    ? Theme.of(context).colorScheme.onSurface
                                    : Colors.transparent,
                                width: 3,
                              ),
                            ),
                            child: _accent == hex
                                ? const Icon(Icons.check,
                                    color: Colors.white, size: 18)
                                : null,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
            const SizedBox(height: 8),
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
                  child: Text('No fields yet. Tap “Add field”.',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.outline)),
                ),
              )
            else
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: _fields.length,
                onReorder: (oldI, newI) => setState(() {
                  if (newI > oldI) newI -= 1;
                  _fields.insert(newI, _fields.removeAt(oldI));
                }),
                itemBuilder: (context, i) {
                  final f = _fields[i];
                  final type = '${f['type']}';
                  return Card(
                    key: ValueKey('${f['id'] ?? i}'),
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Icon(_fieldIcon(type)),
                      title: Text('${f['label'] ?? 'Field'}'),
                      subtitle: Text([
                        _typeLabel(type),
                        if (f['required'] == true) 'required',
                      ].join(' · ')),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 20),
                            tooltip: 'Remove',
                            onPressed: () =>
                                setState(() => _fields.removeAt(i)),
                          ),
                          ReorderableDragStartListener(
                            index: i,
                            child: const Padding(
                              padding: EdgeInsets.all(8),
                              child: Icon(Icons.drag_handle),
                            ),
                          ),
                        ],
                      ),
                      onTap: () => _addOrEditField(i),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// Add/edit one form field: type, label, required, options and type-specific
/// settings (placeholder, payment price, consent text…).
class _FieldEditorScreen extends StatefulWidget {
  const _FieldEditorScreen(
      {this.existing, this.initialType, this.otherFields = const []});

  final Map<String, dynamic>? existing;
  final String? initialType;
  final List<Map<String, dynamic>> otherFields;

  @override
  State<_FieldEditorScreen> createState() => _FieldEditorScreenState();
}

class _FieldEditorScreenState extends State<_FieldEditorScreen> {
  late final TextEditingController _label =
      TextEditingController(text: '${widget.existing?['label'] ?? ''}');
  late final TextEditingController _placeholder = TextEditingController(
      text: '${widget.existing?['placeholder'] ?? ''}');
  late final TextEditingController _options = TextEditingController(
      text: (widget.existing?['options'] as List? ?? const []).join(', '));
  late final TextEditingController _consentText = TextEditingController(
      text: '${widget.existing?['text'] ?? ''}');
  late final TextEditingController _amount = TextEditingController(
      text: widget.existing?['amount'] != null
          ? '${widget.existing!['amount']}'
          : '');
  late final TextEditingController _currency = TextEditingController(
      text: '${widget.existing?['currency'] ?? 'USD'}');
  late String _type =
      widget.existing?['type']?.toString() ?? widget.initialType ?? 'text';
  late bool _required = widget.existing?['required'] == true;
  late bool _amountOpen = widget.existing?['amount_open'] == true;

  // Conditional logic state.
  late final Map? _rule = widget.existing?['visible_if'] as Map?;
  late bool _condOn = _rule?['field'] != null;
  late String? _condField = _rule?['field'] as String?;
  late String _condOp = '${_rule?['op'] ?? 'eq'}';
  late final TextEditingController _condValue =
      TextEditingController(text: '${_rule?['value'] ?? ''}');

  static const _condOps = <(String, String)>[
    ('eq', 'is'),
    ('ne', 'is not'),
    ('contains', 'contains'),
    ('filled', 'is filled in'),
    ('empty', 'is empty'),
  ];
  bool get _condNeedsValue => _condOp == 'eq' || _condOp == 'ne' || _condOp == 'contains';

  bool get _isHeading => _type == 'heading';
  bool get _isPlaceholderType => const {
        'text', 'textarea', 'email', 'phone', 'number', 'url'
      }.contains(_type);

  @override
  void dispose() {
    _label.dispose();
    _placeholder.dispose();
    _options.dispose();
    _consentText.dispose();
    _amount.dispose();
    _currency.dispose();
    _condValue.dispose();
    super.dispose();
  }

  void _submit() {
    if (_label.text.trim().isEmpty) return;
    final field = <String, dynamic>{
      'id': '${widget.existing?['id'] ?? DateTime.now().millisecondsSinceEpoch}',
      'type': _type,
      'label': _label.text.trim(),
      'required': !_isHeading && _required,
      if (_isPlaceholderType && _placeholder.text.trim().isNotEmpty)
        'placeholder': _placeholder.text.trim(),
      if (_hasOptions(_type))
        'options': [
          for (final o in _options.text.split(','))
            if (o.trim().isNotEmpty) o.trim()
        ],
      if (_type == 'consent') 'text': _consentText.text.trim(),
      if (_type == 'payment') ...{
        'amount': double.tryParse(_amount.text.trim()) ?? 0,
        'amount_open': _amountOpen,
        'currency': _currency.text.trim().toUpperCase(),
      },
      if (_condOn && _condField != null)
        'visible_if': {
          'field': _condField,
          'op': _condOp,
          'value': _condNeedsValue ? _condValue.text.trim() : '',
        },
    };
    Navigator.pop(context, field);
  }

  InputDecoration _dec(String label,
          {String? hint, String? prefixText, IconData? icon}) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        prefixText: prefixText,
        prefixIcon: icon != null ? Icon(icon) : null,
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      );

  /// The value input for a condition: a dropdown of the controlling field's
  /// options when it has them, otherwise free text.
  Widget _condValueField() {
    final ctrl = widget.otherFields.firstWhere(
      (f) => '${f['id']}' == _condField,
      orElse: () => const <String, dynamic>{},
    );
    final options =
        (ctrl['options'] as List?)?.map((e) => '$e').toList() ?? const <String>[];
    if (options.isNotEmpty) {
      return DropdownButtonFormField<String>(
        initialValue:
            options.contains(_condValue.text) ? _condValue.text : null,
        isExpanded: true,
        decoration: _dec('Value'),
        items: [
          for (final o in options) DropdownMenuItem(value: o, child: Text(o)),
        ],
        onChanged: (v) => setState(() => _condValue.text = v ?? ''),
      );
    }
    return TextField(controller: _condValue, decoration: _dec('Value'));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: OkayAppBar(
        title: Text(widget.existing != null ? 'Edit field' : 'Add field'),
        actions: [
          TextButton(
            onPressed: _label.text.trim().isEmpty ? null : _submit,
            child: const Text('Save'),
          ),
        ],
      ),
      body: MaxWidth(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Field-type selector.
            Card(
              clipBehavior: Clip.antiAlias,
              child: DropdownButtonFormField<String>(
                initialValue: _type,
                isExpanded: true,
                decoration: _dec('Field type', icon: _fieldIcon(_type)),
                items: [
                  for (final (label, value, icon) in _kFieldTypes)
                    DropdownMenuItem(
                      value: value,
                      child: Row(children: [
                        Icon(icon, size: 18),
                        const SizedBox(width: 10),
                        Text(label),
                      ]),
                    ),
                ],
                onChanged: (v) => setState(() => _type = v ?? 'text'),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _label,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration:
                  _dec(_isHeading ? 'Section title' : 'Field label'),
            ),
            if (_isPlaceholderType) ...[
              const SizedBox(height: 14),
              TextField(
                controller: _placeholder,
                decoration: _dec('Placeholder',
                    hint: 'Hint shown inside the field'),
              ),
            ],
            if (_hasOptions(_type)) ...[
              const SizedBox(height: 14),
              TextField(
                controller: _options,
                minLines: 1,
                maxLines: 4,
                decoration: _dec('Options',
                    hint: 'Comma-separated, e.g. Red, Green, Blue'),
              ),
            ],
            if (_type == 'consent') ...[
              const SizedBox(height: 14),
              TextField(
                controller: _consentText,
                maxLines: 5,
                decoration: _dec('Agreement text',
                    hint: 'The terms the person agrees to…'),
              ),
            ],
            if (_type == 'payment') ...[
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _amount,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    decoration: _dec('Price', prefixText: '\$ '),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _currency,
                    textCapitalization: TextCapitalization.characters,
                    decoration: _dec('Currency'),
                  ),
                ),
              ]),
              const SizedBox(height: 6),
              Card(
                color: scheme.surfaceContainerHighest,
                child: SwitchListTile(
                  value: _amountOpen,
                  onChanged: (v) => setState(() => _amountOpen = v),
                  title: const Text('Let the payer choose the amount'),
                ),
              ),
            ],
            if (!_isHeading) ...[
              const SizedBox(height: 14),
              Card(
                color: scheme.surfaceContainerHighest,
                child: SwitchListTile(
                  value: _required,
                  onChanged: (v) => setState(() => _required = v),
                  secondary: const Icon(Icons.priority_high),
                  title: const Text('Required'),
                  subtitle: const Text('People must fill this in'),
                ),
              ),
            ],
            if (widget.otherFields.isNotEmpty) ...[
              const SizedBox(height: 14),
              Card(
                color: scheme.surfaceContainerHighest,
                child: Column(
                  children: [
                    SwitchListTile(
                      value: _condOn,
                      onChanged: (v) => setState(() => _condOn = v),
                      secondary: const Icon(Icons.alt_route),
                      title: const Text('Conditional visibility'),
                      subtitle:
                          const Text('Only show this field when a rule matches'),
                    ),
                    if (_condOn) ...[
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            DropdownButtonFormField<String>(
                              initialValue: widget.otherFields.any(
                                      (f) => '${f['id']}' == _condField)
                                  ? _condField
                                  : null,
                              isExpanded: true,
                              decoration: _dec('Show this field if'),
                              items: [
                                for (final f in widget.otherFields)
                                  DropdownMenuItem(
                                    value: '${f['id']}',
                                    child: Text('${f['label'] ?? 'Field'}',
                                        overflow: TextOverflow.ellipsis),
                                  ),
                              ],
                              onChanged: (v) => setState(() => _condField = v),
                            ),
                            const SizedBox(height: 10),
                            DropdownButtonFormField<String>(
                              initialValue: _condOp,
                              isExpanded: true,
                              decoration: _dec('Condition'),
                              items: [
                                for (final (value, label) in _condOps)
                                  DropdownMenuItem(
                                      value: value, child: Text(label)),
                              ],
                              onChanged: (v) =>
                                  setState(() => _condOp = v ?? 'eq'),
                            ),
                            if (_condNeedsValue) ...[
                              const SizedBox(height: 10),
                              _condValueField(),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _label.text.trim().isEmpty ? null : _submit,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(widget.existing != null
                    ? 'Save field'
                    : 'Add field'),
              ),
            ),
          ],
        ),
      ),
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
  Map<String, Map<String, dynamic>> _byId = {};
  // End-to-end state: when [_e2e] is set, each response is an opaque blob we
  // decrypt locally once the owner enters [_passphrase].
  bool _e2e = false;
  String? _e2eSalt;
  String? _passphrase;
  bool _decrypting = false;
  final Map<String, Map<String, dynamic>?> _decrypted = {};

  @override
  void initState() {
    super.initState();
    _submissions = api.forms.submissions(widget.formId);
    _loadFields();
  }

  Future<void> _loadFields() async {
    try {
      final f = await api.forms.form(widget.formId);
      final fields = (f['fields'] as List?) ?? const [];
      if (mounted) {
        setState(() {
          _byId = {
            for (final fl in fields)
              if (fl is Map) '${fl['id']}': Map<String, dynamic>.from(fl)
          };
          _e2e = f['e2e'] == true;
          _e2eSalt = f['e2e_salt'] as String?;
        });
      }
    } catch (_) {/* labels just fall back to ids */}
  }

  /// Returns the blob from a submission's values map, or null if not E2E.
  String? _e2eBlob(Map<String, dynamic> s) {
    final v = s['values'];
    final blob = (v is Map) ? v['__e2e__'] : null;
    return blob is String ? blob : null;
  }

  Future<void> _unlock() async {
    final pass = await _askPassphrase(context,
        title: 'Unlock responses',
        subtitle: 'Enter the passphrase you set for this form to read its '
            'encrypted responses.');
    if (pass == null || pass.isEmpty) return;
    setState(() => _decrypting = true);
    List<Map<String, dynamic>> items;
    try {
      items = await _submissions;
    } catch (_) {
      items = const [];
    }
    final out = <String, Map<String, dynamic>?>{};
    var decryptedAny = false;
    var sawBlob = false;
    for (final s in items) {
      final blob = _e2eBlob(s);
      if (blob == null) continue;
      sawBlob = true;
      final dec = await FormsE2E.decrypt(blob, _e2eSalt ?? '', pass);
      out['${s['id']}'] = dec;
      if (dec != null) decryptedAny = true;
    }
    if (!mounted) return;
    final wrong = sawBlob && !decryptedAny;
    setState(() {
      _decrypting = false;
      if (!wrong) {
        _passphrase = pass;
        _decrypted
          ..clear()
          ..addAll(out);
      }
    });
    if (wrong) showInfo(context, 'That passphrase didn’t match.');
  }

  /// Renders a base64 image data URL (signature / photo) as an image.
  Widget _attachment(String dataUrl) {
    try {
      final bytes = base64Decode(dataUrl.substring(dataUrl.indexOf(',') + 1));
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(bytes,
            height: 90, fit: BoxFit.contain, alignment: Alignment.centerLeft),
      );
    } catch (_) {
      return const Text('[attachment]');
    }
  }

  Future<void> _reload() async {
    setState(() => _submissions = api.forms.submissions(widget.formId));
    await _submissions;
    // Re-decrypt freshly fetched rows if we're already unlocked.
    if (_e2e && _passphrase != null) {
      final pass = _passphrase!;
      List<Map<String, dynamic>> items;
      try {
        items = await _submissions;
      } catch (_) {
        items = const [];
      }
      final out = <String, Map<String, dynamic>?>{};
      for (final s in items) {
        final blob = _e2eBlob(s);
        if (blob != null) {
          out['${s['id']}'] = await FormsE2E.decrypt(blob, _e2eSalt ?? '', pass);
        }
      }
      if (mounted) {
        setState(() => _decrypted
          ..clear()
          ..addAll(out));
      }
    }
  }

  /// The values to display for a submission, resolving any E2E blob.
  /// Returns null when the response is encrypted and still locked.
  Map<String, dynamic>? _resolveValues(Map<String, dynamic> s) {
    final raw = s['values'] is Map
        ? Map<String, dynamic>.from(s['values'] as Map)
        : <String, dynamic>{};
    if (!raw.containsKey('__e2e__')) return raw; // plaintext / at-rest only
    if (_passphrase == null) return null; // locked
    return _decrypted['${s['id']}'] ?? const {}; // decrypted (or {} if failed)
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: OkayAppBar(
        title: Text(widget.title),
        actions: [
          if (_e2e && _passphrase == null)
            IconButton(
              tooltip: 'Unlock responses',
              icon: _decrypting
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.lock_open_outlined),
              onPressed: _decrypting ? null : _unlock,
            ),
        ],
      ),
      body: MaxWidth(
        child: Column(
          children: [
            if (_e2e)
              Container(
                width: double.infinity,
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.10),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Icon(Icons.lock_outline,
                        size: 18, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _passphrase == null
                            ? 'These responses are end-to-end encrypted. Unlock to read them.'
                            : 'End-to-end encrypted — decrypted on this device only.',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    if (_passphrase == null)
                      TextButton(
                          onPressed: _decrypting ? null : _unlock,
                          child: const Text('Unlock')),
                  ],
                ),
              ),
            Expanded(
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
                      final values = _resolveValues(s);
                      final when =
                          DateTime.tryParse('${s['created_at'] ?? ''}');
                      final locked = values == null;
                      final failed = values != null &&
                          _e2eBlob(s) != null &&
                          values.isEmpty;
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
                                      color: Theme.of(context)
                                          .colorScheme
                                          .outline,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              if (locked)
                                Row(
                                  children: [
                                    Icon(Icons.lock_outline,
                                        size: 16,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .outline),
                                    const SizedBox(width: 6),
                                    Text('Encrypted — unlock to read',
                                        style: TextStyle(
                                            fontStyle: FontStyle.italic,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .outline)),
                                  ],
                                )
                              else if (failed)
                                Text('Couldn’t decrypt with this passphrase.',
                                    style: TextStyle(
                                        fontStyle: FontStyle.italic,
                                        color:
                                            Theme.of(context).colorScheme.error))
                              else
                                for (final e in values.entries)
                                  if ('${e.value}'.trim().isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                              '${_byId[e.key]?['label'] ?? e.key}',
                                              style: TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .outline,
                                                  fontSize: 12)),
                                          const SizedBox(height: 2),
                                          '${e.value}'.startsWith('data:image')
                                              ? _attachment('${e.value}')
                                              : SelectableText('${e.value}'),
                                        ],
                                      ),
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
          ],
        ),
      ),
    );
  }
}
