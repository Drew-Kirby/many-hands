import 'package:cloud_firestore/cloud_firestore.dart';

// Field names and allowed values mirror firestore.rules exactly. Writes that drift from
// these shapes are refused by the database, so keep them in step with the rules.

const issueStatuses = {'open': 'Open', 'in_progress': 'In progress', 'resolved': 'Resolved'};
const taskStatuses = {'todo': 'To do', 'doing': 'Doing', 'done': 'Done'};

DateTime _created(Map<String, dynamic> d) =>
    (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(); // null until the server stamps it

class Member {
  final String id, name, email, phone;
  final DateTime createdAt;
  final Timestamp? createdAtRaw;
  Member(this.id, this.name, this.email, this.phone, this.createdAt, this.createdAtRaw);

  factory Member.fromDoc(DocumentSnapshot<Map<String, dynamic>> s) {
    final d = s.data() ?? {};
    return Member(s.id, (d['name'] ?? '') as String, (d['email'] ?? '') as String,
        (d['phone'] ?? '') as String, _created(d), d['createdAt'] as Timestamp?);
  }
}

class Issue {
  final String id, title, description, status, ownerId;
  final String? dueDate; // 'YYYY-MM-DD' or null
  final DateTime createdAt;
  Issue(this.id, this.title, this.description, this.status, this.ownerId, this.dueDate, this.createdAt);

  factory Issue.fromDoc(DocumentSnapshot<Map<String, dynamic>> s) {
    final d = s.data() ?? {};
    return Issue(s.id, (d['title'] ?? '') as String, (d['description'] ?? '') as String,
        (d['status'] ?? 'open') as String, (d['ownerId'] ?? '') as String, d['dueDate'] as String?, _created(d));
  }
}

class Task {
  final String id, issueId, title, description, status, createdBy;
  final String? assigneeId, dueDate;
  final DateTime createdAt;
  Task(this.id, this.issueId, this.title, this.description, this.status, this.assigneeId, this.createdBy,
      this.dueDate, this.createdAt);

  factory Task.fromDoc(DocumentSnapshot<Map<String, dynamic>> s) {
    final d = s.data() ?? {};
    return Task(
        s.id,
        (d['issueId'] ?? '') as String,
        (d['title'] ?? '') as String,
        (d['description'] ?? '') as String,
        (d['status'] ?? 'todo') as String,
        d['assigneeId'] as String?,
        (d['createdBy'] ?? '') as String,
        d['dueDate'] as String?,
        _created(d));
  }
}

class Comment {
  final String id, authorId, text;
  final DateTime createdAt;
  Comment(this.id, this.authorId, this.text, this.createdAt);

  factory Comment.fromDoc(DocumentSnapshot<Map<String, dynamic>> s) {
    final d = s.data() ?? {};
    return Comment(s.id, (d['authorId'] ?? '') as String, (d['text'] ?? '') as String, _created(d));
  }
}
