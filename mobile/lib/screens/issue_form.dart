import 'package:material_ui/material_ui.dart';

import '../models.dart';
import '../store.dart';
import '../util.dart';
import '../widgets.dart';
import 'issue_detail.dart';

// New issue, or edit an existing one. Anyone can edit an issue's content (the rules allow it).
class IssueForm extends StatefulWidget {
  final Issue? issue;
  const IssueForm({super.key, this.issue});
  @override
  State<IssueForm> createState() => _IssueFormState();
}

class _IssueFormState extends State<IssueForm> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.issue?.title);
  late final _description = TextEditingController(text: widget.issue?.description);
  late String _status = widget.issue?.status ?? 'open';
  late String? _due = widget.issue?.dueDate;
  bool _busy = false;
  bool _dirty = false;

  bool get _isEdit => widget.issue != null;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final title = _title.text.trim();
    final description = _description.text.trim();
    String? newId;
    final ok = await attempt(context, () async {
      if (_isEdit) {
        await Api.updateIssue(widget.issue!.id,
            {'title': title, 'description': description, 'status': _status, 'dueDate': _due});
      } else {
        newId = await Api.createIssue(auth.currentUser!.uid,
            title: title, description: description, status: _status, dueDate: _due);
      }
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) return;
    _dirty = false;
    if (newId != null) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => IssueDetail(issueId: newId!)));
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _due != null ? parseISO(_due!) : now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    if (picked != null) {
      setState(() {
        _due = toISODate(picked);
        _dirty = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await confirm(context, 'Discard your changes?', yes: 'Discard') && context.mounted) {
          _dirty = false;
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(title: Text(_isEdit ? 'Edit issue' : 'New issue')),
        body: Form(
          key: _form,
          onChanged: () => _dirty = true,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            VoiceTextField(controller: _title, label: 'Title', hint: 'e.g. Spring Coat Drive', required: true),
            const SizedBox(height: 8),
            VoiceTextField(
                controller: _description, label: 'Description', hint: "What's this about? Where?", maxLines: 5, maxLength: 2000),
            const SizedBox(height: 8),
            const Text('Status', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [for (final e in issueStatuses.entries) ButtonSegment(value: e.key, label: Text(e.value))],
              selected: {_status},
              onSelectionChanged: (s) => setState(() {
                _status = s.first;
                _dirty = true;
              }),
            ),
            const SizedBox(height: 16),
            DueDateRow(
              due: _due,
              onPick: _pickDue,
              onClear: () => setState(() {
                _due = null;
                _dirty = true;
              }),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _save,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              child: Text(_busy ? 'Saving…' : _isEdit ? 'Save changes' : 'Create issue'),
            ),
          ]),
        ),
      ),
    );
  }
}

class DueDateRow extends StatelessWidget {
  final String? due;
  final VoidCallback onPick, onClear;
  const DueDateRow({super.key, required this.due, required this.onPick, required this.onClear});
  @override
  Widget build(BuildContext context) => Row(children: [
        const Icon(Icons.event),
        const SizedBox(width: 8),
        Expanded(child: Text(due == null ? 'No due date (optional)' : 'Due ${formatDue(due!)}')),
        TextButton(onPressed: onPick, child: Text(due == null ? 'Add date' : 'Change')),
        if (due != null) TextButton(onPressed: onClear, child: const Text('Clear')),
      ]);
}
