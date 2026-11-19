import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../store.dart';
import '../util.dart';
import '../widgets.dart';
import 'task_detail.dart';

void openMember(BuildContext context, String id) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => MemberProfile(memberId: id)));

class MembersScreen extends StatefulWidget {
  const MembersScreen({super.key});
  @override
  State<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends State<MembersScreen> {
  final _search = TextEditingController();

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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final q = _search.text.trim();
        final shown = store.members
            .where((m) => q.isEmpty || matchesWords('${m.name} ${m.email} ${m.phone} ${phoneDigits(m.phone)}', q))
            .toList();
        return Scaffold(
          appBar: AppBar(title: const Text('Members')),
          body: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                controller: _search,
                decoration: InputDecoration(
                  hintText: 'Search by name, email or phone',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: MicButton(controller: _search),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('${shown.length} of ${store.members.length} members',
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
              ),
            ),
            Expanded(
              child: shown.isEmpty
                  ? const EmptyNote('No members match.')
                  : ListView.builder(
                      itemCount: shown.length,
                      itemBuilder: (context, i) {
                        final m = shown[i];
                        final active = store.activeCount(m.id);
                        return ListTile(
                          leading: Avatar(m.name),
                          title: Text(m.name),
                          subtitle: Text('${m.phone} · $active active ${active == 1 ? 'task' : 'tasks'}'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => openMember(context, m.id),
                        );
                      },
                    ),
            ),
          ]),
        );
      },
    );
  }
}

class MemberProfile extends StatelessWidget {
  final String memberId;
  const MemberProfile({super.key, required this.memberId});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final m = store.member(memberId);
        if (m == null) return Scaffold(appBar: AppBar(), body: const EmptyNote('This member is no longer here.'));
        return Scaffold(
          appBar: AppBar(title: Text(m.name)),
          body: ListView(children: [
            const SizedBox(height: 16),
            Center(child: Avatar(m.name, size: 72)),
            const SizedBox(height: 8),
            Center(
              child: Text(m.name, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            ),
            ContactTile(icon: Icons.email_outlined, text: m.email),
            ContactTile(icon: Icons.phone_outlined, text: m.phone),
            ...memberTaskSections(context, m),
          ]),
        );
      },
    );
  }
}

// Long-press copies, since the app has no dialer or mail dependency.
class ContactTile extends StatelessWidget {
  final IconData icon;
  final String text;
  const ContactTile({super.key, required this.icon, required this.text});
  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon),
        title: SelectableText(text),
        trailing: IconButton(
          tooltip: 'Copy',
          icon: const Icon(Icons.copy, size: 18),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: text));
            showMessage(context, 'Copied.');
          },
        ),
      );
}

List<Widget> memberTaskSections(BuildContext context, Member m) {
  final tasks = store.tasksOf(m.id)..sort((a, b) => bySoonestDue(a.dueDate, b.dueDate));
  final open = tasks.where((t) => t.status != 'done').toList();
  final done = tasks.where((t) => t.status == 'done').toList();
  final issueCount = tasks.map((t) => t.issueId).toSet().length;
  return [
    SectionTitle('Working on', trailing: Text('${open.length} across $issueCount ${issueCount == 1 ? 'issue' : 'issues'}')),
    if (open.isEmpty) const EmptyNote('Nothing right now.'),
    for (final t in open) TaskTile(t, showIssue: true, onTap: () => openTask(context, t.issueId, t.id)),
    SectionTitle('Done', trailing: Text('${done.length}')),
    if (done.isEmpty) const EmptyNote('Nothing finished yet.'),
    for (final t in done) TaskTile(t, showIssue: true, onTap: () => openTask(context, t.issueId, t.id)),
    const SizedBox(height: 24),
  ];
}
