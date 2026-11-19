import 'package:material_ui/material_ui.dart';

import '../models.dart';
import '../store.dart';
import '../util.dart';
import '../widgets.dart';
import 'issue_form.dart';
import 'task_detail.dart';
import 'task_form.dart';

void openIssue(BuildContext context, String id) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => IssueDetail(issueId: id)));

class IssueDetail extends StatelessWidget {
  final String issueId;
  const IssueDetail({super.key, required this.issueId});

  Future<void> _delete(BuildContext context, Issue issue, List<Task> tasks) async {
    final q = tasks.isEmpty
        ? 'Delete "${issue.title}"?'
        : 'Delete "${issue.title}" and its ${tasks.length} ${tasks.length == 1 ? 'task' : 'tasks'} for everyone?';
    if (!await confirm(context, q) || !context.mounted) return;
    final ok = await attempt(context, () => Api.deleteIssue(issue.id, tasks.map((t) => t.id).toList()),
        success: 'Issue deleted.');
    if (ok && context.mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final issue = store.issue(issueId);
        if (issue == null) {
          return Scaffold(appBar: AppBar(), body: const EmptyNote("This issue is gone. It's no longer on the board."));
        }
        final me = auth.currentUser!.uid;
        final tasks = store.tasksFor(issue.id);
        final health = issueHealth(tasks);
        final groups = groupTasks(tasks);
        final isOwner = issue.ownerId == me;

        return Scaffold(
          appBar: AppBar(title: Text(issue.title, overflow: TextOverflow.ellipsis), actions: [
            IconButton(
              tooltip: 'Edit issue',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => IssueForm(issue: issue))),
            ),
            if (isOwner)
              IconButton(
                tooltip: 'Delete issue',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _delete(context, issue, tasks),
              ),
          ]),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TaskForm(issueId: issue.id))),
            icon: const Icon(Icons.add_task),
            label: const Text('Add task'),
          ),
          body: ListView(padding: const EdgeInsets.only(bottom: 96), children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 6, runSpacing: 6, children: [
                  StatusPill(issue.status),
                  HealthPill(health),
                  DuePill(issue.dueDate, issue.status),
                ]),
                const SizedBox(height: 12),
                Text(issue.title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(issue.description.isEmpty ? 'No description yet.' : issue.description),
                const SizedBox(height: 12),
                Text('Started by ${store.nameOf(issue.ownerId)}${isOwner ? ' (you)' : ''}',
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(children: [
                      Expanded(child: Text(health.sentence)),
                      Text('${health.total - health.unassigned}/${health.total} covered',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ),
              ]),
            ),
            for (final entry in const {
              'unclaimed': 'Unclaimed',
              'todo': 'To do',
              'doing': 'Doing',
              'done': 'Done',
            }.entries) ...[
              SectionTitle(entry.value, trailing: Text('${groups[entry.key]!.length}')),
              if (groups[entry.key]!.isEmpty)
                EmptyNote(entry.key == 'unclaimed' ? 'Nothing here. Every task has someone.' : 'Nothing here yet.'),
              for (final t in groups[entry.key]!) TaskTile(t, onTap: () => openTask(context, issue.id, t.id)),
            ],
            const Divider(height: 32),
            CommentsSection(collection: 'issueComments', keyField: 'issueId', parentId: issue.id),
          ]),
        );
      },
    );
  }
}
