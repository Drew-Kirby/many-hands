import 'dart:convert';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:material_ui/material_ui.dart';

import '../store.dart';
import '../util.dart';
import '../widgets.dart';
import 'issue_detail.dart';
import 'members.dart';
import 'task_detail.dart';

// Gemini through Firebase AI Logic (Gemini Developer API). Turn it on in the Firebase console:
// AI Logic → Get started → Gemini Developer API. If Google retires this model, swap the name here.
const aiModelName = 'gemini-3.1-flash-lite';

class SearchResult {
  final String type, id, why;
  SearchResult(this.type, this.id, this.why);
}

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _query = TextEditingController();
  bool _busy = false;
  String? _summary;
  String? _note;
  List<SearchResult> _results = [];
  String? _askedFor;

  static const _examples = [
    'Which tasks are overdue?',
    'What can I help with this weekend?',
    'Who is working on food drives?',
    'Show unclaimed tasks about the park',
  ];

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  // Everything the model needs, kept compact: ids so results can be linked, names instead of uids.
  String _context() {
    final me = auth.currentUser!.uid;
    String? short(String s) => s.isEmpty ? null : (s.length > 160 ? '${s.substring(0, 160)}…' : s);
    return jsonEncode({
      'today': todayISO(),
      'currentUser': store.nameOf(me),
      'members': [for (final m in store.members) {'id': m.id, 'name': m.name, 'activeTasks': store.activeCount(m.id)}],
      'issues': [
        for (final i in store.issues)
          {
            'id': i.id,
            'title': i.title,
            'status': i.status,
            if (i.dueDate != null) 'due': i.dueDate,
            if (isOverdue(i.dueDate, i.status)) 'overdue': true,
            if (short(i.description) != null) 'about': short(i.description),
            'owner': store.nameOf(i.ownerId),
          }
      ],
      'tasks': [
        for (final t in store.tasks)
          {
            'id': t.id,
            'issueId': t.issueId,
            'title': t.title,
            'status': t.status,
            'assignee': t.assigneeId == null ? null : store.nameOf(t.assigneeId),
            if (t.assigneeId == null) 'unclaimed': true,
            if (t.dueDate != null) 'due': t.dueDate,
            if (isOverdue(t.dueDate, t.status)) 'overdue': true,
            if (short(t.description) != null) 'about': short(t.description),
          }
      ],
    });
  }

  Future<void> _ask() async {
    final q = _query.text.trim();
    if (q.isEmpty || _busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _note = _summary = null;
      _results = [];
      _askedFor = q;
    });
    try {
      // firebase_ai 5.x picks up App Check (activated in main.dart) on its own.
      final model = FirebaseAI.googleAI().generativeModel(
        model: aiModelName,
        generationConfig: GenerationConfig(responseMimeType: 'application/json', temperature: 0.2),
      );
      final prompt = '''
You are the search assistant for a volunteer community app. Turn the user's search into JSON exactly like:
{"summary": "one plain sentence answering the question, without stating a count",
 "filter": {"types": ["task" | "issue" | "member"], "overdue": true|false|null, "unclaimed": true|false|null,
            "status": ["todo","doing","done","open","in_progress","resolved"] or null, "assignee": "member name" or null,
            "dueWithinDays": number or null, "keywords": ["word", ...] or null},
 "results": [{"type": "issue" | "task" | "member", "id": "<id from the data>", "why": "short reason, max 12 words"}]}
How it is used: the app applies "filter" to the full data itself, so the filter must capture the question precisely.
- "overdue"/"late" -> overdue: true. "unclaimed"/"needs someone"/"open to take" -> unclaimed: true.
- "my"/"me" -> assignee: the currentUser. "this week" -> dueWithinDays: 7; "this weekend" -> dueWithinDays: 3.
- keywords: topic words plus close synonyms (food -> food, pantry, meal, canned, dinner). null if the question has no topic.
- Finished work (done tasks, resolved issues) is excluded unless status asks for it.
- If the question is about people, use types ["member"]. Use filter null only for questions a filter cannot express.
"results": up to 8 extra hand-picked ids for fuzzy questions (use only ids from the data); may be empty.
The data marks "overdue": true and "unclaimed": true already; never compare dates yourself.

DATA:
${_context()}

SEARCH: $q''';
      final response = await model.generateContent([Content.text(prompt)]);
      final parsed = _parse(response.text ?? '');
      // Exact matches from the filter first, then any extra picks the model added.
      final exact = parsed.$3 == null ? <SearchResult>[] : _applyFilter(parsed.$3!);
      final seen = {for (final r in exact) '${r.type}:${r.id}'};
      setState(() {
        _summary = parsed.$1;
        _results = [...exact, ...parsed.$2.where((r) => seen.add('${r.type}:${r.id}'))];
      });
    } catch (e) {
      debugPrint('AI search failed: $e');
      // Still give an answer: fall back to plain keyword matching.
      setState(() {
        _note = "AI search isn't available right now, so these are plain keyword matches.";
        _results = _keywordSearch(q);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  (String, List<SearchResult>, Map<String, dynamic>?) _parse(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'^```(json)?|```$', multiLine: true), '').trim();
    final data = jsonDecode(cleaned) as Map<String, dynamic>;
    final out = <SearchResult>[];
    for (final r in (data['results'] as List? ?? [])) {
      if (r is! Map) continue;
      final type = '${r['type']}', id = '${r['id']}', why = '${r['why'] ?? ''}';
      // Drop anything the model made up.
      final exists = switch (type) {
        'issue' => store.issue(id) != null,
        'task' => store.task(id) != null,
        'member' => store.member(id) != null,
        _ => false,
      };
      if (exists) out.add(SearchResult(type, id, why));
    }
    final filter = data['filter'];
    return ('${data['summary'] ?? ''}', out, filter is Map<String, dynamic> ? filter : null);
  }

  List<SearchResult> _applyFilter(Map<String, dynamic> f) {
    final types = (f['types'] as List?)?.map((e) => '$e').toSet() ?? {'task', 'issue'};
    final statuses = (f['status'] as List?)?.map((e) => '$e').toSet();
    final keywords = (f['keywords'] as List?)?.map((e) => '$e'.toLowerCase()).where((k) => k.isNotEmpty).toList();
    final overdue = f['overdue'] as bool?;
    final unclaimed = f['unclaimed'] as bool?;
    final within = (f['dueWithinDays'] as num?)?.toInt();
    final assigneeName = (f['assignee'] as String?)?.toLowerCase().trim();
    final lastDay = within == null ? null : toISODate(DateTime.now().add(Duration(days: within)));
    bool hasKeyword(String text) => keywords == null || keywords.any(text.toLowerCase().contains);
    bool dueOk(String? due) => lastDay == null || (due != null && due.compareTo(lastDay) <= 0);
    String? assigneeId;
    if (assigneeName != null && assigneeName.isNotEmpty) {
      for (final m in store.members) {
        if (m.name.toLowerCase() == assigneeName || m.name.toLowerCase().startsWith(assigneeName)) assigneeId = m.id;
      }
      if (assigneeId == null && store.member(auth.currentUser!.uid)?.name.toLowerCase() == assigneeName) {
        assigneeId = auth.currentUser!.uid;
      }
    }
    final out = <SearchResult>[];
    if (types.contains('task')) {
      final tasks = store.tasks.where((t) {
        if (statuses != null ? !statuses.contains(t.status) : t.status == 'done') return false;
        if (overdue != null && isOverdue(t.dueDate, t.status) != overdue) return false;
        if (unclaimed != null && (t.assigneeId == null) != unclaimed) return false;
        if (assigneeId != null && t.assigneeId != assigneeId) return false;
        if (!dueOk(t.dueDate)) return false;
        return hasKeyword('${t.title} ${t.description} ${store.issue(t.issueId)?.title ?? ''}');
      }).toList()
        ..sort((a, b) => bySoonestDue(a.dueDate, b.dueDate));
      out.addAll(tasks.map((t) => SearchResult('task', t.id,
          t.dueDate == null ? 'Matches your search' : '${isOverdue(t.dueDate, t.status) ? 'Overdue' : 'Due'} ${formatDue(t.dueDate!)}')));
    }
    if (types.contains('issue') && unclaimed != true && assigneeId == null) {
      final issues = store.issues.where((i) {
        if (statuses != null ? !statuses.contains(i.status) : i.status == 'resolved') return false;
        if (overdue != null && isOverdue(i.dueDate, i.status) != overdue) return false;
        if (!dueOk(i.dueDate)) return false;
        return hasKeyword('${i.title} ${i.description}');
      });
      out.addAll(issues.map((i) => SearchResult('issue', i.id, issueHealth(store.tasksFor(i.id)).sentence)));
    }
    if (types.contains('member')) {
      out.addAll(store.members
          .where((m) => assigneeId == null ? hasKeyword(m.name) : m.id == assigneeId)
          .map((m) => SearchResult('member', m.id, '${store.activeCount(m.id)} active tasks')));
    }
    return out;
  }

  List<SearchResult> _keywordSearch(String q) => [
        for (final i in store.issues)
          if (matchesWords('${i.title} ${i.description}', q)) SearchResult('issue', i.id, 'Issue matches your words'),
        for (final t in store.tasks)
          if (matchesWords('${t.title} ${t.description}', q)) SearchResult('task', t.id, 'Task matches your words'),
        for (final m in store.members)
          if (matchesWords(m.name, q)) SearchResult('member', m.id, 'Member name matches'),
      ].take(30).toList();

  Widget _resultTile(SearchResult r) {
    switch (r.type) {
      case 'issue':
        final i = store.issue(r.id)!;
        return ListTile(
          leading: const CircleAvatar(child: Icon(Icons.list_alt)),
          title: Text(i.title),
          subtitle: Text(r.why),
          trailing: StatusPill(i.status),
          onTap: () => openIssue(context, i.id),
        );
      case 'task':
        final t = store.task(r.id)!;
        return ListTile(
          leading: const CircleAvatar(child: Icon(Icons.check_box_outlined)),
          title: Text(t.title),
          subtitle: Text('${r.why}\n${t.assigneeId == null ? 'Unclaimed' : store.nameOf(t.assigneeId)} · ${store.issue(t.issueId)?.title ?? ''}'),
          isThreeLine: true,
          trailing: StatusPill(t.status),
          onTap: () => openTask(context, t.issueId, t.id),
        );
      default:
        final m = store.member(r.id)!;
        return ListTile(
          leading: Avatar(m.name),
          title: Text(m.name),
          subtitle: Text(r.why),
          onTap: () => openMember(context, m.id),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Ask AI')),
        body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _query,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _ask(),
              decoration: InputDecoration(
                hintText: 'Ask anything, e.g. "unclaimed tasks due this week"',
                prefixIcon: const Icon(Icons.auto_awesome),
                // Speaking a question runs the search as soon as you finish.
                suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                  MicButton(controller: _query, onDone: _ask),
                  IconButton(tooltip: 'Search', icon: const Icon(Icons.send), onPressed: _ask),
                ]),
              ),
            ),
          ),
          if (_askedFor == null) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('Search issues, tasks and members in plain English, or tap the mic and say it.'),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                for (final e in _examples)
                  ActionChip(
                    label: Text(e),
                    onPressed: () {
                      _query.text = e;
                      _ask();
                    },
                  ),
              ]),
            ),
          ],
          if (_busy) const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
          if (!_busy && _note != null)
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(_note!, style: TextStyle(color: Colors.orange.shade900))),
          if (!_busy && _summary != null && _summary!.isNotEmpty)
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              child: Padding(padding: const EdgeInsets.all(14), child: Text(_summary!)),
            ),
          if (!_busy && _askedFor != null) ...[
            SectionTitle('Results', trailing: Text('${_results.length}')),
            if (_results.isEmpty) const EmptyNote('Nothing matched. Try different words.'),
            for (final r in _results) _resultTile(r),
          ],
        ]),
      ),
    );
  }
}
