import 'package:material_ui/material_ui.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'models.dart';
import 'store.dart';
import 'util.dart';

const brand = Color(0xFF1F5C4A);

// ---------------------------------------------------------------------------
// Voice-to-text. One recognizer for the whole app; a mic button appends what you say to its field.
// ---------------------------------------------------------------------------

class Voice {
  static final stt = SpeechToText();
  static bool? _ready;
  static final listening = ValueNotifier<TextEditingController?>(null);

  static Future<bool> init() async {
    if (_ready == true) return true;
    _ready = await stt.initialize(
      onStatus: (s) {
        if (s == 'done' || s == 'notListening') listening.value = null;
      },
      onError: (_) => listening.value = null,
    );
    return _ready!;
  }
}

class MicButton extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback? onDone;
  const MicButton({super.key, required this.controller, this.onDone});

  Future<void> _toggle(BuildContext context) async {
    if (Voice.listening.value == controller) {
      await Voice.stt.stop();
      Voice.listening.value = null;
      return;
    }
    final ok = await Voice.init();
    if (!ok) {
      if (context.mounted) showMessage(context, "Voice input isn't available. Check microphone permission.");
      return;
    }
    if (Voice.listening.value != null) await Voice.stt.stop();
    final before = controller.text.trimRight();
    Voice.listening.value = controller;
    await Voice.stt.listen(onResult: (r) {
      final said = r.recognizedWords;
      final text = before.isEmpty ? said : '$before $said';
      controller.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
      if (r.finalResult) {
        Voice.listening.value = null;
        onDone?.call();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingController?>(
      valueListenable: Voice.listening,
      builder: (context, active, _) {
        final on = active == controller;
        return IconButton(
          tooltip: on ? 'Stop listening' : 'Speak instead of typing',
          icon: Icon(on ? Icons.stop_circle : Icons.mic_none, color: on ? Colors.red : null),
          onPressed: () => _toggle(context),
        );
      },
    );
  }
}

class VoiceTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final int maxLines;
  final int maxLength;
  final bool required;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onVoiceDone;
  const VoiceTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.maxLines = 1,
    this.maxLength = 120,
    this.required = false,
    this.onChanged,
    this.onVoiceDone,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      minLines: maxLines > 1 ? 3 : 1,
      maxLength: maxLength,
      onChanged: onChanged,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(labelText: label, hintText: hint, suffixIcon: MicButton(controller: controller, onDone: onVoiceDone)),
      validator: required ? (v) => (v ?? '').trim().isEmpty ? 'Required' : null : null,
    );
  }
}

// ---------------------------------------------------------------------------
// Small display pieces
// ---------------------------------------------------------------------------

void showMessage(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

Future<bool> confirm(BuildContext context, String question, {String yes = 'Delete'}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      content: Text(question),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(yes)),
      ],
    ),
  );
  return ok ?? false;
}

// Runs a write, shows a friendly error if it fails, and reports whether it worked.
Future<bool> attempt(BuildContext context, Future<void> Function() action, {String? success}) async {
  try {
    await action();
    if (success != null && context.mounted) showMessage(context, success);
    return true;
  } catch (e) {
    final msg = e is Exception && e.toString().startsWith('Exception: ')
        ? e.toString().substring(11)
        : friendlyError(e);
    if (context.mounted) showMessage(context, msg);
    return false;
  }
}

class Pill extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;
  const Pill(this.text, {super.key, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 13, color: color), const SizedBox(width: 4)],
        Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

Color statusColor(String status) => switch (status) {
      'done' || 'resolved' => Colors.green.shade700,
      'doing' || 'in_progress' => Colors.blue.shade700,
      _ => Colors.grey.shade700,
    };

class StatusPill extends StatelessWidget {
  final String status;
  const StatusPill(this.status, {super.key});
  @override
  Widget build(BuildContext context) =>
      Pill(taskStatuses[status] ?? issueStatuses[status] ?? status, color: statusColor(status));
}

class DuePill extends StatelessWidget {
  final String? due;
  final String status;
  const DuePill(this.due, this.status, {super.key});
  @override
  Widget build(BuildContext context) {
    if (due == null) return const SizedBox.shrink();
    final late = isOverdue(due, status);
    return Pill(late ? 'Overdue · ${formatDue(due!)}' : 'Due ${formatDue(due!)}',
        color: late ? Colors.red.shade700 : Colors.orange.shade800, icon: Icons.event);
  }
}

class HealthPill extends StatelessWidget {
  final Health health;
  const HealthPill(this.health, {super.key});
  @override
  Widget build(BuildContext context) {
    final color = switch (health.label) {
      'Covered' => Colors.green.shade700,
      'Thin' => Colors.orange.shade800,
      'At risk' => Colors.red.shade700,
      _ => Colors.grey.shade700,
    };
    return Pill(health.label, color: color);
  }
}

class Avatar extends StatelessWidget {
  final String name;
  final double size;
  const Avatar(this.name, {super.key, this.size = 36});
  @override
  Widget build(BuildContext context) {
    final hue = (name.codeUnits.fold<int>(0, (a, b) => a + b) * 37) % 360;
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: HSLColor.fromAHSL(1, hue.toDouble(), 0.45, 0.88).toColor(),
      child: Text(initials(name),
          style: TextStyle(fontSize: size * 0.36, fontWeight: FontWeight.w700, color: Colors.black87)),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Row(children: [
          Expanded(child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
          if (trailing != null) trailing!,
        ]),
      );
}

class EmptyNote extends StatelessWidget {
  final String text;
  const EmptyNote(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text(text, style: TextStyle(color: Colors.grey.shade700)),
      );
}

// ---------------------------------------------------------------------------
// Task row used on Home, issue detail, member profiles and search results
// ---------------------------------------------------------------------------

class TaskTile extends StatelessWidget {
  final Task task;
  final VoidCallback onTap;
  final bool showIssue;
  const TaskTile(this.task, {super.key, required this.onTap, this.showIssue = false});

  @override
  Widget build(BuildContext context) {
    final who = task.assigneeId == null ? 'Unclaimed' : store.nameOf(task.assigneeId);
    final issueTitle = store.issue(task.issueId)?.title;
    return ListTile(
      onTap: onTap,
      leading: task.assigneeId == null
          ? const CircleAvatar(child: Icon(Icons.person_outline))
          : Avatar(who),
      title: Text(task.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          StatusPill(task.status),
          DuePill(task.dueDate, task.status),
          Text(showIssue && issueTitle != null ? '$who · $issueTitle' : who, style: const TextStyle(fontSize: 12)),
        ]),
      ),
      trailing: const Icon(Icons.chevron_right),
    );
  }
}

// ---------------------------------------------------------------------------
// Comments, shared by tasks ('comments' / taskId) and issues ('issueComments' / issueId)
// ---------------------------------------------------------------------------

class CommentsSection extends StatefulWidget {
  final String collection, keyField, parentId;
  const CommentsSection({super.key, required this.collection, required this.keyField, required this.parentId});
  @override
  State<CommentsSection> createState() => _CommentsSectionState();
}

class _CommentsSectionState extends State<CommentsSection> {
  final _draft = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    final text = _draft.text.trim();
    if (text.isEmpty) return;
    setState(() => _busy = true);
    final ok = await attempt(context,
        () => Api.addComment(widget.collection, widget.keyField, widget.parentId, auth.currentUser!.uid, text));
    if (ok) _draft.clear();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _edit(Comment c) async {
    final ctrl = TextEditingController(text: c.text);
    final text = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Edit comment'),
        content: VoiceTextField(controller: ctrl, label: 'Comment', maxLines: 4, maxLength: 2000),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, ctrl.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (text != null && text.isNotEmpty && mounted) {
      await attempt(context, () => Api.updateComment(widget.collection, c.id, text));
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = auth.currentUser!.uid;
    return StreamBuilder<List<Comment>>(
      stream: Api.comments(widget.collection, widget.keyField, widget.parentId),
      builder: (context, snap) {
        final list = snap.data ?? [];
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SectionTitle('Comments', trailing: Text('${list.length}')),
          if (list.isEmpty) const EmptyNote('No comments yet.'),
          for (final c in list)
            ListTile(
              leading: Avatar(store.nameOf(c.authorId), size: 32),
              title: Text('${store.nameOf(c.authorId)}${c.authorId == me ? ' (you)' : ''}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              subtitle: Text('${c.text}\n${formatWhen(c.createdAt)}'),
              isThreeLine: true,
              trailing: c.authorId == me
                  ? PopupMenuButton<String>(
                      onSelected: (v) async {
                        if (v == 'edit') _edit(c);
                        if (v == 'delete' && await confirm(context, 'Delete this comment?') && context.mounted) {
                          await attempt(context, () => Api.deleteComment(widget.collection, c.id));
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('Edit')),
                        PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                    )
                  : null,
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: VoiceTextField(controller: _draft, label: 'Add a comment', maxLength: 2000, maxLines: 3)),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: FilledButton(onPressed: _busy ? null : _post, child: const Text('Post')),
              ),
            ]),
          ),
        ]);
      },
    );
  }
}
