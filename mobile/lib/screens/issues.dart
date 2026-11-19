import 'package:material_ui/material_ui.dart';

import '../models.dart';
import '../store.dart';
import '../util.dart';
import '../widgets.dart';
import 'issue_detail.dart';
import 'issue_form.dart';

class IssuesScreen extends StatefulWidget {
  const IssuesScreen({super.key});
  @override
  State<IssuesScreen> createState() => _IssuesScreenState();
}

enum _Sort { newest, dueSoon, needsPeople }

class _IssuesScreenState extends State<IssuesScreen> {
  final _search = TextEditingController();
  String _view = 'active'; // active | resolved | all
  _Sort _sort = _Sort.newest;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Issue> _shown() {
    final q = _search.text.trim();
    final list = store.issues.where((i) {
      if (_view == 'active' && i.status == 'resolved') return false;
      if (_view == 'resolved' && i.status != 'resolved') return false;
      return q.isEmpty || matchesWords('${i.title} ${i.description}', q);
    }).toList();
    switch (_sort) {
      case _Sort.newest:
        break; // the store already keeps newest first
      case _Sort.dueSoon:
        list.sort((a, b) => bySoonestDue(a.dueDate, b.dueDate));
      case _Sort.needsPeople:
        list.sort((a, b) => issueHealth(store.tasksFor(b.id)).unassigned - issueHealth(store.tasksFor(a.id)).unassigned);
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final shown = _shown();
        final filtering = _view != 'all' || _search.text.trim().isNotEmpty;
        return Scaffold(
          appBar: AppBar(title: const Text('Issues'), actions: [
            PopupMenuButton<_Sort>(
              tooltip: 'Sort',
              icon: const Icon(Icons.sort),
              initialValue: _sort,
              onSelected: (s) => setState(() => _sort = s),
              itemBuilder: (_) => const [
                PopupMenuItem(value: _Sort.newest, child: Text('Newest first')),
                PopupMenuItem(value: _Sort.dueSoon, child: Text('Due soonest')),
                PopupMenuItem(value: _Sort.needsPeople, child: Text('Most unclaimed tasks')),
              ],
            ),
          ]),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const IssueForm())),
            icon: const Icon(Icons.add),
            label: const Text('New issue'),
          ),
          body: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: TextField(
                controller: _search,
                decoration: InputDecoration(
                  hintText: 'Search issues',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (_search.text.isNotEmpty)
                      IconButton(tooltip: 'Clear', icon: const Icon(Icons.close), onPressed: _search.clear),
                    MicButton(controller: _search),
                  ]),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(children: [
                Expanded(
                  child: SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: 'active', label: Text('Active')),
                      ButtonSegment(value: 'resolved', label: Text('Resolved')),
                      ButtonSegment(value: 'all', label: Text('All')),
                    ],
                    selected: {_view},
                    onSelectionChanged: (s) => setState(() => _view = s.first),
                  ),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  filtering ? 'Showing ${shown.length} of ${store.issues.length}' : '${store.issues.length} issues',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                ),
              ),
            ),
            Expanded(
              child: store.loading
                  ? const Center(child: CircularProgressIndicator())
                  : shown.isEmpty
                      ? Center(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            EmptyNote(store.issues.isEmpty ? 'No issues yet. Start the first one.' : 'No issues match.'),
                            if (filtering && store.issues.isNotEmpty)
                              TextButton(
                                onPressed: () => setState(() {
                                  _search.clear();
                                  _view = 'all';
                                }),
                                child: const Text('Show all issues'),
                              ),
                          ]),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.only(bottom: 96),
                          itemCount: shown.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, i) => IssueTile(shown[i]),
                        ),
            ),
          ]),
        );
      },
    );
  }
}

class IssueTile extends StatelessWidget {
  final Issue issue;
  const IssueTile(this.issue, {super.key});
  @override
  Widget build(BuildContext context) {
    final health = issueHealth(store.tasksFor(issue.id));
    return ListTile(
      onTap: () => openIssue(context, issue.id),
      title: Text(issue.title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          StatusPill(issue.status),
          if (issue.status != 'resolved') HealthPill(health),
          DuePill(issue.dueDate, issue.status),
          Text('${health.total} ${health.total == 1 ? 'task' : 'tasks'}', style: const TextStyle(fontSize: 12)),
        ]),
      ),
      trailing: const Icon(Icons.chevron_right),
    );
  }
}
