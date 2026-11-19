import 'package:material_ui/material_ui.dart';

import '../models.dart';
import '../store.dart';
import '../util.dart';
import '../widgets.dart';
import 'issue_detail.dart';
import 'members.dart';
import 'task_form.dart';

void openTask(BuildContext context, String issueId, String taskId) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => TaskDetail(taskId: taskId)));

class TaskDetail extends StatefulWidget {
  final String taskId;
  const TaskDetail({super.key, required this.taskId});
  @override
  State<TaskDetail> createState() => _TaskDetailState();
}

class _TaskDetailState extends State<TaskDetail> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, {String? success}) async {
    setState(() => _busy = true);
    await attempt(context, action, success: success);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _delete(Task task) async {
    if (!await confirm(context, 'Delete this task for everyone?') || !mounted) return;
    final ok = await attempt(context, () => Api.deleteTask(task.id), success: 'Task deleted.');
    if (ok && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final task = store.task(widget.taskId);
        if (task == null) {
          return Scaffold(appBar: AppBar(), body: const EmptyNote("This task is gone. It's no longer on the board."));
        }
        final me = auth.currentUser!.uid;
        final mine = task.assigneeId == me;
        final issue = store.issue(task.issueId);
        final issueOwner = issue?.ownerId == me;
        final assignee = task.assigneeId == null ? null : store.nameOf(task.assigneeId);

        return Scaffold(
          appBar: AppBar(title: Text(task.title, overflow: TextOverflow.ellipsis), actions: [
            if (mine)
              IconButton(
                tooltip: 'Edit task',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => TaskForm(issueId: task.issueId, task: task))),
              ),
            if (mine || issueOwner)
              IconButton(tooltip: 'Delete task', icon: const Icon(Icons.delete_outline), onPressed: () => _delete(task)),
          ]),
          body: ListView(children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 6, runSpacing: 6, children: [StatusPill(task.status), DuePill(task.dueDate, task.status)]),
                const SizedBox(height: 12),
                Text(task.title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                if (assignee != null)
                  ActionChip(
                    avatar: Avatar(assignee, size: 24),
                    label: Text('Assigned to ${mine ? 'you' : assignee}'),
                    onPressed: () => openMember(context, task.assigneeId!),
                  )
                else
                  Card(
                    child: ListTile(
                      title: const Text("No one yet. Take it and it's yours."),
                      trailing: FilledButton(
                        onPressed: _busy ? null : () => _run(() => Api.takeTask(task.id, me), success: "It's yours."),
                        child: const Text('Take it'),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Description', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(task.description.isEmpty ? 'No description yet.' : task.description),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: issue == null ? null : () => openIssue(context, issue.id),
                        child: Text('Part of ${issue?.title ?? 'a deleted issue'} · created by ${store.nameOf(task.createdBy)}',
                            style: const TextStyle(fontSize: 12, color: brand)),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 12),
                if (mine) ...[
                  const Text('Update status', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: [for (final e in taskStatuses.entries) ButtonSegment(value: e.key, label: Text(e.value))],
                    selected: {task.status},
                    onSelectionChanged: _busy ? null : (s) => _run(() => Api.updateTask(task.id, {'status': s.first})),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    icon: const Icon(Icons.undo),
                    label: const Text('Give it back'),
                    onPressed: _busy
                        ? null
                        : () async {
                            if (await confirm(context, 'Give this task back? It goes back to Unclaimed.', yes: 'Give it back')) {
                              _run(() => Api.updateTask(task.id, {'assigneeId': null, 'status': 'todo'}));
                            }
                          },
                  ),
                ] else if (issueOwner) ...[
                  // Issue owners can reassign any task on their issue (assignee and status only).
                  DropdownButtonFormField<String?>(
                    initialValue: task.assigneeId,
                    decoration: const InputDecoration(labelText: 'Assigned to (you own this issue)'),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('Unassigned')),
                      for (final m in store.members)
                        DropdownMenuItem<String?>(
                          value: m.id,
                          child: Text('${m.name}${m.id == me ? ' (you)' : ''} · ${store.activeCount(m.id)} active'),
                        ),
                    ],
                    onChanged: _busy
                        ? null
                        : (id) => _run(() => Api.updateTask(task.id, {
                              'assigneeId': id,
                              if (id == null) 'status': 'todo',
                            })),
                  ),
                ] else
                  Row(children: [
                    const Icon(Icons.lock_outline, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(task.assigneeId == null
                          ? 'Whoever takes this task can edit or delete it.'
                          : 'Only ${firstName(assignee!)} can edit, update or delete this task.'),
                    ),
                  ]),
              ]),
            ),
            const Divider(),
            CommentsSection(collection: 'comments', keyField: 'taskId', parentId: task.id),
          ]),
        );
      },
    );
  }
}
