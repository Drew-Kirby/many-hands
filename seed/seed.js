// Loads the AI-generated stress-test data (data.js) into YOUR Firebase project with the Admin SDK.
//
//   node seed.js            create everything (safe to run again: it clears the old seed first)
//   node seed.js --reset    only remove the seed data
//
// Needs service-account.json in this folder (Firebase console → Project settings → Service accounts →
// Generate new private key). That file is a secret: it's in .gitignore, never commit it.
//
// Every seeded login uses the password below, so you can sign in as any test member.
// Real members who already signed up (you) get 10 tasks too, so the stress test covers everyone.

import { readFileSync } from 'node:fs';
import { initializeApp, cert } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { members as memberData, issues as issueData } from './data.js';

const PASSWORD = 'ManyHands2026!';
const DOMAIN = 'manyhands.test';
const TASKS_PER_MEMBER = 10;
const MIN_ISSUES_PER_MEMBER = 5;

initializeApp({ credential: cert(JSON.parse(readFileSync(new URL('./service-account.json', import.meta.url)))) });
const auth = getAuth();
const db = getFirestore();

// Seeded random numbers, so every run produces the same community.
let seed = 403;
const rand = () => {
  seed = (seed + 0x6d2b79f5) | 0;
  let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
  t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
};
const pick = (list) => list[Math.floor(rand() * list.length)];
const shuffle = (list) => {
  const a = [...list];
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(rand() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
};

const pad = (n) => String(n).padStart(2, '0');
const isoDay = (offsetDays) => {
  const d = new Date();
  d.setDate(d.getDate() + offsetDays);
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
};
const daysAgo = (days) => Timestamp.fromDate(new Date(Date.now() - days * 86400000 - Math.floor(rand() * 8 * 3600000)));
const emailFor = (name) => `${name.toLowerCase().replace(/[^a-z ]/g, '').trim().replace(/\s+/g, '.')}@${DOMAIN}`;

// Firestore batches hold at most 500 writes.
async function commitAll(ops) {
  for (let i = 0; i < ops.length; i += 400) {
    const batch = db.batch();
    ops.slice(i, i + 400).forEach((op) => op(batch));
    await batch.commit();
  }
}

async function reset() {
  const seeded = (await db.collection('members').get()).docs.filter((d) => d.data().email?.endsWith(`@${DOMAIN}`));
  const seededIds = new Set(seeded.map((d) => d.id));
  const issues = (await db.collection('issues').get()).docs.filter((d) => seededIds.has(d.data().ownerId));
  const issueIds = new Set(issues.map((d) => d.id));
  const tasks = (await db.collection('tasks').get()).docs.filter((d) => issueIds.has(d.data().issueId));
  const taskIds = new Set(tasks.map((d) => d.id));
  const comments = (await db.collection('comments').get()).docs.filter((d) => taskIds.has(d.data().taskId) || seededIds.has(d.data().authorId));
  const issueComments = (await db.collection('issueComments').get()).docs.filter((d) => issueIds.has(d.data().issueId) || seededIds.has(d.data().authorId));
  // Tasks on real members' issues that a seeded member holds go back to Unclaimed.
  const held = (await db.collection('tasks').get()).docs.filter((d) => !taskIds.has(d.id) && seededIds.has(d.data().assigneeId));

  await commitAll([
    ...[...comments, ...issueComments, ...tasks, ...issues, ...seeded].map((d) => (b) => b.delete(d.ref)),
    ...held.map((d) => (b) => b.update(d.ref, { assigneeId: null, status: 'todo' })),
  ]);
  for (const id of seededIds) await auth.deleteUser(id).catch(() => {});
  console.log(`Removed seed data: ${seeded.length} members, ${issues.length} issues, ${tasks.length} tasks, ${comments.length + issueComments.length} comments.`);
}

async function createMembers() {
  const ops = [];
  const out = [];
  for (const [name, phone] of memberData) {
    const email = emailFor(name);
    const user = await auth.createUser({ email, password: PASSWORD, displayName: name });
    const doc = { name, email, phone, createdAt: daysAgo(60 + Math.floor(rand() * 30)) };
    ops.push((b) => b.set(db.collection('members').doc(user.uid), doc));
    out.push({ id: user.uid, ...doc });
  }
  await commitAll(ops);
  return out;
}

const commentLines = [
  'I can do this Saturday morning if that works.',
  'Picked up the supplies, they\'re in my trunk.',
  'Running about 15 minutes late, start without me.',
  'Does anyone have a truck we can borrow?',
  'Done! Took a couple photos for the newsletter.',
  'I called them and they said next week is better.',
  'Can someone double check the address?',
  'Thanks everyone, this went really well.',
  'I need one more person to help with this.',
  'Moved this to Doing, halfway there.',
  'I have extra gloves if anyone needs them.',
  'Heads up: the room is booked until 6.',
  'Got the receipts, I\'ll turn them in Monday.',
  'Can we push this back a few days?',
  'Bringing my roommate to help too.',
];

async function main() {
  if (process.argv.includes('--reset')) return reset();
  await reset();

  const seededMembers = await createMembers();
  // Real members who already signed up (you) join the stress test too.
  const real = (await db.collection('members').get()).docs
    .filter((d) => !d.data().email?.endsWith(`@${DOMAIN}`))
    .map((d) => ({ id: d.id, ...d.data() }));
  const everyone = [...seededMembers, ...real];
  console.log(`Members: ${seededMembers.length} seeded + ${real.length} existing`);

  // Issues: about a sixth resolved, a quarter in progress, the rest open. Owners are seeded members.
  const issueRefs = issueData.map(([title, description], i) => {
    const status = i % 6 === 5 ? 'resolved' : i % 4 === 1 ? 'in_progress' : 'open';
    const ref = db.collection('issues').doc();
    return {
      ref,
      id: ref.id,
      title,
      doc: {
        title,
        description,
        status,
        dueDate: rand() < 0.6 ? isoDay(status === 'resolved' ? -Math.ceil(rand() * 20) : Math.floor(rand() * 45) - 5) : null,
        ownerId: seededMembers[i % seededMembers.length].id,
        createdAt: daysAgo(10 + Math.floor(rand() * 50)),
      },
    };
  });

  // Task slots: every task title on every issue.
  const slots = shuffle(issueRefs.flatMap((issue) => issueData[issueRefs.indexOf(issue)][2].map((title) => ({ issue, title, assigneeId: null }))));
  const need = everyone.length * TASKS_PER_MEMBER;
  // If there are more members than task ideas, repeat ideas with a "(round 2)" label so everyone still gets 10.
  while (slots.length < need + 30) {
    const base = slots[slots.length % issueRefs.length];
    slots.push({ issue: base.issue, title: `${base.title} (round 2)`, assigneeId: null });
  }

  // Round-robin, so each member gets one task per round, preferring issues they don't have yet.
  const held = new Map(everyone.map((m) => [m.id, []]));
  for (let round = 0; round < TASKS_PER_MEMBER; round++) {
    for (const m of shuffle(everyone)) {
      const mine = held.get(m.id);
      const theirIssues = new Set(mine.map((s) => s.issue.id));
      const slot = slots.find((s) => !s.assigneeId && !theirIssues.has(s.issue.id)) || slots.find((s) => !s.assigneeId);
      slot.assigneeId = m.id;
      mine.push(slot);
    }
  }

  const taskOps = [];
  const taskRows = [];
  for (const s of slots) {
    const resolved = s.issue.doc.status === 'resolved';
    let status = 'todo';
    if (s.assigneeId) {
      const r = rand();
      status = resolved || r < 0.3 ? 'done' : r < 0.6 ? 'doing' : 'todo';
    }
    const ref = db.collection('tasks').doc();
    const doc = {
      issueId: s.issue.id,
      title: s.title,
      description: rand() < 0.5 ? `Part of ${s.issue.title}. Check the comments for the latest.` : '',
      status,
      assigneeId: s.assigneeId,
      dueDate: rand() < 0.65 ? isoDay(resolved ? -Math.ceil(rand() * 15) : Math.floor(rand() * 38) - 8) : null,
      createdBy: rand() < 0.7 ? s.issue.doc.ownerId : pick(seededMembers).id,
      createdAt: daysAgo(Math.floor(rand() * 9)),
    };
    taskOps.push((b) => b.set(ref, doc));
    taskRows.push({ id: ref.id, ...doc });
  }

  const commentOps = [];
  for (let i = 0; i < 140; i++) {
    const t = pick(taskRows);
    commentOps.push((b) => b.set(db.collection('comments').doc(), {
      taskId: t.id, authorId: t.assigneeId || pick(seededMembers).id, text: pick(commentLines), createdAt: daysAgo(Math.floor(rand() * 6)),
    }));
  }
  for (let i = 0; i < 50; i++) {
    const issue = pick(issueRefs);
    commentOps.push((b) => b.set(db.collection('issueComments').doc(), {
      issueId: issue.id, authorId: pick(seededMembers).id, text: pick(commentLines), createdAt: daysAgo(Math.floor(rand() * 10)),
    }));
  }

  await commitAll([...issueRefs.map((i) => (b) => b.set(i.ref, i.doc)), ...taskOps, ...commentOps]);

  // Check the assignment's requirements against what was written.
  const counts = everyone.map((m) => {
    const mine = taskRows.filter((t) => t.assigneeId === m.id);
    return { name: m.name, tasks: mine.length, issues: new Set(mine.map((t) => t.issueId)).size };
  });
  const minTasks = Math.min(...counts.map((c) => c.tasks));
  const minIssues = Math.min(...counts.map((c) => c.issues));
  console.log(`Issues: ${issueRefs.length}  Tasks: ${taskRows.length} (${taskRows.filter((t) => !t.assigneeId).length} unclaimed)  Comments: ${commentOps.length}`);
  console.log(`Every member: at least ${minTasks} tasks across at least ${minIssues} issues`);
  const ok = everyone.length >= 20 && issueRefs.length >= 60 && taskRows.length >= 200 && minTasks >= TASKS_PER_MEMBER && minIssues >= MIN_ISSUES_PER_MEMBER;
  console.log(ok ? 'All stress-test requirements met.' : 'WARNING: a requirement was not met.');
  console.log(`Test logins: any seeded email (for example ${seededMembers[0].email}), password ${PASSWORD}`);
}

main().then(() => process.exit(0)).catch((e) => {
  console.error(e);
  process.exit(1);
});
