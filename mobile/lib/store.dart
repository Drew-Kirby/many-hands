import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'models.dart';

final db = FirebaseFirestore.instance;
final auth = FirebaseAuth.instance;

// Live listeners on the three shared collections, like the website. A community is small enough
// (even the 200-task stress test) that keeping everything in memory keeps every screen simple and instant.
class DataStore extends ChangeNotifier {
  List<Member>? _members;
  List<Issue>? _issues;
  List<Task>? _tasks;
  final _subs = <StreamSubscription>[];

  bool get loading => _members == null || _issues == null || _tasks == null;
  List<Member> get members => _members ?? [];
  List<Issue> get issues => _issues ?? [];
  List<Task> get tasks => _tasks ?? [];

  void start() {
    stop();
    _subs.add(db.collection('members').snapshots().listen((s) {
      _members = s.docs.map(Member.fromDoc).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      notifyListeners();
    }, onError: (e) => debugPrint('members: $e')));
    _subs.add(db.collection('issues').snapshots().listen((s) {
      _issues = s.docs.map(Issue.fromDoc).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      notifyListeners();
    }, onError: (e) => debugPrint('issues: $e')));
    _subs.add(db.collection('tasks').snapshots().listen((s) {
      _tasks = s.docs.map(Task.fromDoc).toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      notifyListeners();
    }, onError: (e) => debugPrint('tasks: $e')));
  }

  void stop() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _members = null;
    _issues = null;
    _tasks = null;
  }

  Member? member(String? id) {
    if (id == null) return null;
    for (final m in members) {
      if (m.id == id) return m;
    }
    return null;
  }

  Issue? issue(String id) {
    for (final i in issues) {
      if (i.id == id) return i;
    }
    return null;
  }

  Task? task(String id) {
    for (final t in tasks) {
      if (t.id == id) return t;
    }
    return null;
  }

  String nameOf(String? id) => member(id)?.name ?? 'A former member';
  List<Task> tasksFor(String issueId) => tasks.where((t) => t.issueId == issueId).toList();
  List<Task> tasksOf(String memberId) => tasks.where((t) => t.assigneeId == memberId).toList();
  int activeCount(String memberId) => tasks.where((t) => t.assigneeId == memberId && t.status != 'done').length;
}

final store = DataStore();

// True while an account is being created, so the app doesn't flash "finish your profile" before the profile is saved.
final signingUp = ValueNotifier<bool>(false);

// ---- Writes. Each one matches a rule in firestore.rules. ----

class Api {
  static Future<void> saveNewMember(String uid, String name, String email, String phone) =>
      db.collection('members').doc(uid).set({
        'name': name,
        'email': email,
        'phone': phone,
        'createdAt': FieldValue.serverTimestamp(),
      });

  static Future<void> updateMember(String uid, {required String name, required String phone}) =>
      db.collection('members').doc(uid).update({'name': name, 'phone': phone});

  static Future<String> createIssue(String uid,
      {required String title, required String description, required String status, String? dueDate}) async {
    final ref = await db.collection('issues').add({
      'title': title,
      'description': description,
      'status': status,
      'dueDate': dueDate,
      'ownerId': uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  static Future<void> updateIssue(String id, Map<String, dynamic> patch) =>
      db.collection('issues').doc(id).update(patch);

  // The owner may delete the tasks on their own issue, so the issue and its tasks go together.
  static Future<void> deleteIssue(String id, List<String> taskIds) async {
    final batch = db.batch();
    for (final t in taskIds) {
      batch.delete(db.collection('tasks').doc(t));
    }
    batch.delete(db.collection('issues').doc(id));
    await batch.commit();
  }

  static Future<String> createTask(String uid,
      {required String issueId,
      required String title,
      required String description,
      required String status,
      String? assigneeId,
      String? dueDate}) async {
    final ref = await db.collection('tasks').add({
      'issueId': issueId,
      'title': title,
      'description': description,
      'status': status,
      'assigneeId': assigneeId,
      'dueDate': dueDate,
      'createdBy': uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  static Future<void> updateTask(String id, Map<String, dynamic> patch) =>
      db.collection('tasks').doc(id).update(patch);

  // The rules only allow a claim on an unassigned task, so this fails if someone got there first.
  static Future<void> takeTask(String id, String uid) async {
    try {
      await db.collection('tasks').doc(id).update({'assigneeId': uid});
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') throw Exception('Someone else just took this task.');
      rethrow;
    }
  }

  static Future<void> deleteTask(String id) => db.collection('tasks').doc(id).delete();

  // Task comments live in 'comments' (keyed by taskId); issue comments in 'issueComments' (keyed by issueId).
  static Stream<List<Comment>> comments(String collection, String key, String id) => db
      .collection(collection)
      .where(key, isEqualTo: id)
      .snapshots()
      .map((s) => s.docs.map(Comment.fromDoc).toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt)));

  static Future<void> addComment(String collection, String key, String id, String uid, String text) =>
      db.collection(collection).add({key: id, 'authorId': uid, 'text': text, 'createdAt': FieldValue.serverTimestamp()});

  static Future<void> updateComment(String collection, String id, String text) =>
      db.collection(collection).doc(id).update({'text': text});

  static Future<void> deleteComment(String collection, String id) => db.collection(collection).doc(id).delete();
}
