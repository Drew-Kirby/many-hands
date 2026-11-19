import 'package:flutter/services.dart';
import 'models.dart';

// ---- Phone: always stored as (555) 123-4567, the only shape the rules accept ----

String phoneDigits(String v) {
  var d = v.replaceAll(RegExp(r'\D'), '');
  if (d.startsWith('1')) d = d.substring(1); // US area codes never start with 1
  return d.length > 10 ? d.substring(0, 10) : d;
}

String formatPhone(String v) {
  final d = phoneDigits(v);
  if (d.isEmpty) return '';
  if (d.length <= 3) return '($d';
  if (d.length <= 6) return '(${d.substring(0, 3)}) ${d.substring(3)}';
  return '(${d.substring(0, 3)}) ${d.substring(3, 6)}-${d.substring(6)}';
}

bool isValidPhone(String v) => RegExp(r'^\(\d{3}\) \d{3}-\d{4}$').hasMatch(v);

class PhoneFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final text = formatPhone(newValue.text);
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}

// ---- Due dates: calendar days as 'YYYY-MM-DD', so they never shift with time zones ----

String _pad(int n) => n.toString().padLeft(2, '0');
String toISODate(DateTime d) => '${d.year}-${_pad(d.month)}-${_pad(d.day)}';
String todayISO() => toISODate(DateTime.now());
DateTime parseISO(String iso) {
  final p = iso.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

bool isOverdue(String? due, String status) =>
    due != null && due.compareTo(todayISO()) < 0 && status != 'done' && status != 'resolved';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String formatDue(String iso) {
  final date = parseISO(iso);
  final today = parseISO(todayISO());
  final diff = date.difference(today).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  if (diff == -1) return 'Yesterday';
  final base = '${_days[date.weekday - 1]}, ${_months[date.month - 1]} ${date.day}';
  return date.year == today.year ? base : '$base, ${date.year}';
}

int bySoonestDue(String? a, String? b) {
  if (a != null && b != null) return a.compareTo(b);
  if (a != null) return -1;
  if (b != null) return 1;
  return 0;
}

String formatWhen(DateTime t) {
  final mins = DateTime.now().difference(t).inMinutes;
  if (mins < 1) return 'Just now';
  if (mins < 60) return '${mins}m ago';
  if (mins < 60 * 24) return '${mins ~/ 60}h ago';
  return '${_months[t.month - 1]} ${t.day}';
}

// ---- Issue health: computed from an issue's tasks, same labels as the website ----

class Health {
  final String label;
  final int total, unassigned;
  Health(this.label, this.total, this.unassigned);

  String get sentence {
    if (label == 'Orphaned') return 'No tasks yet. Add the first one.';
    if (label == 'Covered') return 'Every task has someone.';
    final left = '$unassigned still ${unassigned == 1 ? 'needs' : 'need'} a person.';
    if (label == 'At risk') return 'Most tasks need someone. $left';
    return '${unassigned * 2 == total ? 'Half the' : 'Most'} tasks have someone. $left';
  }
}

Health issueHealth(List<Task> tasks) {
  final total = tasks.length;
  final unassigned = tasks.where((t) => t.assigneeId == null).length;
  final String label;
  if (total == 0) {
    label = 'Orphaned';
  } else if (unassigned == 0) {
    label = 'Covered';
  } else if (unassigned > total / 2) {
    label = 'At risk';
  } else {
    label = 'Thin';
  }
  return Health(label, total, unassigned);
}

// Unclaimed wins over status: a task nobody holds still needs someone.
Map<String, List<Task>> groupTasks(List<Task> tasks) {
  final groups = <String, List<Task>>{'unclaimed': [], 'todo': [], 'doing': [], 'done': []};
  for (final t in tasks) {
    if (t.assigneeId == null) {
      groups['unclaimed']!.add(t);
    } else {
      groups[t.status]?.add(t);
    }
  }
  for (final list in groups.values) {
    list.sort((a, b) => bySoonestDue(a.dueDate, b.dueDate));
  }
  return groups;
}

String firstName(String name) => name.trim().split(RegExp(r'\s+')).first;

String initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return (parts.first[0] + parts.last[0]).toUpperCase();
}

// Plain keyword search: every word must appear. Used for list filters and as the AI search fallback.
bool matchesWords(String haystack, String query) {
  final text = haystack.toLowerCase();
  return query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).every(text.contains);
}

String friendlyError(Object e) {
  final s = e.toString();
  if (s.contains('permission-denied')) return "You don't have permission to do that.";
  if (s.contains('invalid-credential') || s.contains('wrong-password') || s.contains('user-not-found')) {
    return "That email and password don't match.";
  }
  if (s.contains('email-already-in-use')) return 'That email already has an account. Log in instead.';
  if (s.contains('weak-password')) return 'That password is too weak. Use at least 8 characters.';
  if (s.contains('invalid-email')) return "That email address doesn't look right.";
  if (s.contains('network')) return "You're offline. Try again when you're connected.";
  if (s.contains('too-many-requests')) return 'Too many tries. Wait a minute and try again.';
  return 'Something went wrong. Try again.';
}
