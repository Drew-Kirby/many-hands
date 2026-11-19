import 'package:material_ui/material_ui.dart';

import '../models.dart';
import '../store.dart';
import '../util.dart';
import '../widgets.dart';
import 'issue_form.dart';

// New task on an issue, or edit a task you hold. Anyone can create a task and assign it to anyone.
class TaskForm extends StatefulWidget {
  final String issueId;
  final Task? task;
  const TaskForm({super.key, required this.issueId, this.task});
  @override
  State<TaskForm> createState() => _TaskFormState();
}

class _TaskFormState extends State<TaskForm> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.task?.title);
  late final _description = TextEditingController(text: widget.task?.description);
  late String _status = widget.task?.status ?? 'todo';
  late String? _due = widget.task?.dueDate;
  late String? _assignee = widget.task == null ? auth.currentUser!.uid : widget.task!.assigneeId;
  bool _busy = false;
  bool _dirty = false;

  bool get _isEdit => widget.task != null;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final title = _title.text.trim();
    final description = _description.text.trim();
    final ok = await attempt(context, () async {
      if (_isEdit) {
        await Api.updateTask(widget.task!.id, {
          'title': title,
          'description': description,
          'status': _assignee == null ? 'todo' : _status,
          'assigneeId': _assignee,
          'dueDate': _due,
        });
      } else {
        await Api.createTask(auth.currentUser!.uid,
            issueId: widget.issueId,
            title: title,
            description: description,
            status: _assignee == null ? 'todo' : _status,
            assigneeId: _assignee,
            dueDate: _due);
      }
    }, success: _isEdit ? 'Task saved.' : 'Task added.');
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      _dirty = false;
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
    final me = auth.currentUser!.uid;
    final issue = store.issue(widget.issueId);
    // You first, then everyone else alphabetically, each with their current workload.
    final people = [...store.members.where((m) => m.id == me), ...store.members.where((m) => m.id != me)];
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
        appBar: AppBar(title: Text(_isEdit ? 'Edit task' : 'New task')),
        body: Form(
          key: _form,
          onChanged: () => _dirty = true,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            if (issue != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text('On: ${issue.title}', style: TextStyle(color: Colors.grey.shade700)),
              ),
            VoiceTextField(controller: _title, label: 'Title', hint: 'e.g. Bring 2 folding tables', required: true),
            const SizedBox(height: 8),
            VoiceTextField(
                controller: _description, label: 'Description', hint: 'What does this involve? Where?', maxLines: 4, maxLength: 2000),
            const SizedBox(height: 8),
            DueDateRow(
              due: _due,
              onPick: _pickDue,
              onClear: () => setState(() {
                _due = null;
                _dirty = true;
              }),
            ),
            const SizedBox(height: 16),
            if (_assignee != null) ...[
              const Text('Status', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [for (final e in taskStatuses.entries) ButtonSegment(value: e.key, label: Text(e.value))],
                selected: {_status},
                onSelectionChanged: (s) => setState(() {
                  _status = s.first;
                  _dirty = true;
                }),
              ),
              const SizedBox(height: 16),
            ],
            const Text('Assign to', style: TextStyle(fontWeight: FontWeight.w600)),
            RadioGroup<String?>(
              groupValue: _assignee,
              onChanged: (v) => setState(() {
                _assignee = v;
                _dirty = true;
              }),
              child: Column(children: [
                const RadioListTile<String?>(
                  value: null,
                  title: Text('Leave unassigned'),
                  subtitle: Text('Anyone can take it'),
                ),
                for (final p in people)
                  RadioListTile<String?>(
                    value: p.id,
                    title: Text(p.id == me ? '${p.name} (you)' : p.name),
                    subtitle: Text('${store.activeCount(p.id)} active ${store.activeCount(p.id) == 1 ? 'task' : 'tasks'}'),
                    secondary: Avatar(p.name, size: 32),
                  ),
              ]),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _save,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              child: Text(_busy ? 'Saving…' : _isEdit ? 'Save task' : 'Add task'),
            ),
            const SizedBox(height: 24),
          ]),
        ),
      ),
    );
  }
}
