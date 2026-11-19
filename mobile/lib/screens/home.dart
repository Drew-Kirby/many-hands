import 'package:material_ui/material_ui.dart';

import '../store.dart';
import '../util.dart';
import '../widgets.dart';
import 'issue_detail.dart';
import 'task_detail.dart';

class HomeScreen extends StatelessWidget {
  final ValueChanged<int> onOpenTab;
  const HomeScreen({super.key, required this.onOpenTab});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        if (store.loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        final me = auth.currentUser!.uid;
        final name = firstName(store.nameOf(me));
        final mine = store.tasksOf(me).where((t) => t.status != 'done').toList()
          ..sort((a, b) => bySoonestDue(a.dueDate, b.dueDate));
        final unclaimed = store.tasks.where((t) => t.assigneeId == null).toList()
          ..sort((a, b) => bySoonestDue(a.dueDate, b.dueDate));
        final atRisk = store.issues
            .where((i) => i.status != 'resolved' && issueHealth(store.tasksFor(i.id)).label == 'At risk')
            .toList();
        final open = store.issues.where((i) => i.status != 'resolved').length;

        return Scaffold(
          appBar: AppBar(title: const Text('Many Hands')),
          body: ListView(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text('Hi, $name.', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                _Stat('$open', 'open issues', () => onOpenTab(1)),
                const SizedBox(width: 8),
                _Stat('${unclaimed.length}', 'need someone', null),
                const SizedBox(width: 8),
                _Stat('${store.members.length}', 'members', () => onOpenTab(3)),
              ]),
            ),
            SectionTitle('Your tasks', trailing: Text('${mine.length} unfinished')),
            if (mine.isEmpty) const EmptyNote("You're all caught up. Take an unclaimed task below."),
            for (final t in mine.take(8))
              TaskTile(t, showIssue: true, onTap: () => openTask(context, t.issueId, t.id)),
            if (atRisk.isNotEmpty) ...[
              const SectionTitle('Issues at risk'),
              for (final i in atRisk.take(5))
                ListTile(
                  title: Text(i.title),
                  subtitle: Text(issueHealth(store.tasksFor(i.id)).sentence),
                  trailing: HealthPill(issueHealth(store.tasksFor(i.id))),
                  onTap: () => openIssue(context, i.id),
                ),
            ],
            const SectionTitle('Unclaimed tasks'),
            if (unclaimed.isEmpty) const EmptyNote('Every task has someone.'),
            for (final t in unclaimed.take(8))
              TaskTile(t, showIssue: true, onTap: () => openTask(context, t.issueId, t.id)),
            const SizedBox(height: 24),
          ]),
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  final String value, label;
  final VoidCallback? onTap;
  const _Stat(this.value, this.label, this.onTap);
  @override
  Widget build(BuildContext context) => Expanded(
        child: Card(
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
              child: Column(children: [
                Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
              ]),
            ),
          ),
        ),
      );
}
