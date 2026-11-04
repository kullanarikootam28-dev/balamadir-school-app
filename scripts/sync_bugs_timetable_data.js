#!/usr/bin/env node
/**
 * One-time data sync for the Bugs1.docx / ALL CLASS TIMETABLE FOR BMS.xlsx
 * request (Part C of the plan). Talks to Supabase's REST + Auth Admin APIs
 * directly with the service_role key — nothing here touches the Flutter app.
 *
 * SAFE BY DEFAULT: runs as a dry run and only prints what it would do.
 * Set APPLY=1 to actually write.
 *
 * Usage:
 *   SUPABASE_SERVICE_ROLE_KEY=xxxx node scripts/sync_bugs_timetable_data.js            # dry run
 *   SUPABASE_SERVICE_ROLE_KEY=xxxx APPLY=1 node scripts/sync_bugs_timetable_data.js    # apply
 *
 * Get the service_role key from Supabase Dashboard -> Settings -> API. Never
 * commit it or put it in the Flutter app — this script only ever reads it
 * from the environment for this one run.
 */

const fs = require('fs');
const path = require('path');

const SUPABASE_URL = 'https://atfyumihqsxvzzcifupg.supabase.co';
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const APPLY = process.env.APPLY === '1';

if (!SERVICE_KEY) {
  console.error('Missing SUPABASE_SERVICE_ROLE_KEY environment variable.');
  console.error('Get it from Supabase Dashboard -> Settings -> API (the "service_role" secret).');
  process.exit(1);
}

const TT_DIR = process.env.TT_DIR || 'C:/Users/NAVEEN~1/AppData/Local/Temp/tt_xlsx';

// ── low-level REST / Auth Admin helpers ─────────────────────────────────────

async function rest(method, table, { query = '', body, prefer } = {}) {
  const url = `${SUPABASE_URL}/rest/v1/${table}${query}`;
  const headers = {
    apikey: SERVICE_KEY,
    Authorization: `Bearer ${SERVICE_KEY}`,
    'Content-Type': 'application/json',
  };
  if (prefer) headers.Prefer = prefer;
  const res = await fetch(url, { method, headers, body: body ? JSON.stringify(body) : undefined });
  const text = await res.text();
  if (!res.ok) {
    throw new Error(`${method} ${table}${query} -> ${res.status}: ${text}`);
  }
  return text ? JSON.parse(text) : null;
}

async function authAdmin(method, subpath, body) {
  const url = `${SUPABASE_URL}/auth/v1/admin${subpath}`;
  const headers = {
    apikey: SERVICE_KEY,
    Authorization: `Bearer ${SERVICE_KEY}`,
    'Content-Type': 'application/json',
  };
  const res = await fetch(url, { method, headers, body: body ? JSON.stringify(body) : undefined });
  const text = await res.text();
  if (!res.ok) {
    throw new Error(`${method} auth/admin${subpath} -> ${res.status}: ${text}`);
  }
  return text ? JSON.parse(text) : null;
}

const normalizeName = (s) => s.toLowerCase().replace(/[^a-z]/g, '');

// ── Part C1 data: the real master teacher roster from Bugs1.docx screenshot ─
// oldEmail is set only for the 4 people whose email changed, so matching
// against the already-imported 18-teacher roster is exact, not fuzzy, for
// those. `isNew: true` marks the 4 teachers who don't exist yet.
const TEACHER_ROSTER = [
  { name: 'Vasantha G', email: 'vasanthakamaraj44@gmail.com', phone: '9445732062' },
  { name: 'Shanmugapriya P', email: 'shanmugap194@gmail.com', phone: '9384452985' },
  { name: 'Suganya S', email: 'prabusuganya969@gmail.com', phone: '9003599640', oldEmail: 'prabusuganya@gmail.com' },
  { name: 'Ramya D', email: 'ramyapriyaiya@gmail.com', phone: '7810094605' },
  { name: 'Manju P', email: 'pmanju32@gmail.com', phone: '9159876628', oldEmail: 'pmanju352001@gmail.com' },
  { name: 'Gayathri D', email: 'ggayu6607@gmail.com', phone: '6384501074', isNew: true },
  { name: 'Ramya S', email: 'ramyasaga7284@gmail.com', phone: '9487241408' },
  { name: 'Gomathi N', email: 'gomathin200153@gmail.com', phone: '8122419099', isNew: true },
  { name: 'Kavikala S', email: 'kavikalaselvam2000@gmail.com', phone: '8870781544' },
  { name: 'Manimala', email: 'manikarthi997@gmail.com', phone: '8072658619' },
  { name: 'Jonsirani K', email: 'jonsiranijonsi@gmail.com', phone: '8675891408' },
  { name: 'Thirushya T', email: 'thirushya0@gmail.com', phone: '6379479809' },
  { name: 'Swetha V', email: 'magashvin994@gmail.com', phone: '9042921719', oldEmail: 'swethamuthu506@gmail.com' },
  { name: 'Sathya P', email: 'kavikanmani3592@gmail.com', phone: '7806883354' },
  { name: 'Santhya K', email: 'thirumoorthy1997@gmail.com', phone: '6379660301', oldEmail: 'tm351275@gmail.com' },
  { name: 'Madheswari D', email: 'rajeshrajesh074@gmail.com', phone: '8526382356', isNew: true },
  { name: 'Suganeswari R', email: 'Navamika.karan@gmail.com', phone: '6381225580', isNew: true },
  { name: 'Indumathi R', email: 'rajindu107@gmail.com', phone: '7305717814' },
  { name: 'Nafisha K', email: 'nafisha.kaleel97@gmail.com', phone: '6374449263' },
];

// Substring (normalized) match against existing teacher full_name -> resigned.
const RESIGNED_NAME_HINTS = ['sharmila', 'abirami', 'narmadha'];

// sheet1 label -> canonical subject name used everywhere in the DB.
const SUBJECT_CANON = {
  'Tamil': 'Tamil',
  'English': 'English',
  'Mathematics': 'Mathematics',
  'EVS': 'EVS',
  'Hindi': 'Hindi',
  'Science': 'Science',
  'Social Science': 'Social Science',
  'PET': 'PET',
  'G.K': 'General Knowledge',
  'H.W': 'H.W',
  'E.E': 'E.E',
  'Maths Tables': 'Maths Tables',
  'Tamil Reading': 'Tamil Reading',
  'English Reading': 'English Reading',
};

// sheet1 canonical subject name -> sheet2 assignment-matrix column key.
// Anything not listed here (H.W, E.E, Maths Tables, *Reading) has no
// dedicated subject teacher in the source data — left teacher_id = null,
// a real gap rather than an invented assignment.
const CANON_TO_SHEET2_KEY = {
  'Tamil': 'Tamil',
  'English': 'English',
  'Mathematics': 'Maths',
  'EVS': 'EVS',
  'Hindi': 'Hindi',
  'Science': 'Science',
  'Social Science': 'Social',
  'PET': 'P.E.T',
  'General Knowledge': 'General Knowladge',
};

// All canonical subjects that must exist in `subjects` (union of sheet1 +
// sheet2-only ones like Spoken/Rhymes, which have no day-by-day periods).
const ALL_CANON_SUBJECTS = [
  ...new Set([...Object.values(SUBJECT_CANON), 'Spoken English', 'Rhymes']),
];

// sheet2 grade label -> { grade, section } as stored in `classes`. Grades
// II-X apply to every existing section of that grade (the source doesn't
// distinguish sections for these); I/UKG/LKG are split A/B explicitly.
function resolveSheet2Grade(label) {
  const table = {
    '10th': 'X', '9th': 'IX', '8th': 'VIII', '7th': 'VII', '6th': 'VI',
    '5th': 'V', '4th': 'IV', '3rd': 'III', '2nd': 'II',
  };
  if (table[label]) return { grade: table[label], section: null };
  if (label === '1st-A') return { grade: 'I', section: 'A' };
  if (label === '1st-B') return { grade: 'I', section: 'B' };
  if (label === 'U.K.G-A') return { grade: 'UKG', section: 'A' };
  if (label === 'U.K.G-B') return { grade: 'UKG', section: 'B' };
  if (label === 'L.K.G-A') return { grade: 'LKG', section: 'A' };
  if (label === 'L.K.G-B') return { grade: 'LKG', section: 'B' };
  return null;
}

const SHEET1_BLOCKS = [
  [3, 'II'], [12, 'III'], [21, 'IV'], [30, 'V'], [39, 'VI'],
  [48, 'VII'], [57, 'VIII'], [66, 'IX'], [75, 'X'],
];
const DAY_ROWS = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']; // day_of_week 1..6
const PERIOD_COLS = ['B', 'C', 'D', 'E', 'F', 'G', 'H', 'I']; // Period 1..8

async function main() {
  console.log(APPLY ? '=== APPLY MODE ===' : '=== DRY RUN (set APPLY=1 to write) ===');

  // ── load already-extracted spreadsheet data ───────────────────────────
  const sheet1 = JSON.parse(fs.readFileSync(path.join(TT_DIR, 'sheet1_full.json'), 'utf8'));
  const sheet2 = JSON.parse(fs.readFileSync(path.join(TT_DIR, 'sheet2_full.json'), 'utf8'));
  const byR1 = {};
  for (const row of sheet1) byR1[row.r] = row.cells;
  const byR2 = {};
  for (const row of sheet2) byR2[row.r] = row.cells;

  // ── fetch current state ────────────────────────────────────────────────
  const teachers = await rest('GET', 'profiles', { query: '?role=eq.teacher&select=id,full_name,email,phone' });
  const teacherDetails = await rest('GET', 'teacher_details', { query: '?select=teacher_id,status' });
  const detailsByTeacher = new Map(teacherDetails.map((d) => [d.teacher_id, d]));
  console.log(`\nFound ${teachers.length} existing teacher profiles.`);

  const byNormName = new Map();
  for (const t of teachers) {
    const key = normalizeName(t.full_name);
    if (!byNormName.has(key)) byNormName.set(key, []);
    byNormName.get(key).push(t);
  }
  const byEmail = new Map(teachers.map((t) => [t.email.toLowerCase(), t]));

  // ── C1: resolve roster matches ──────────────────────────────────────────
  const plan = { updates: [], creates: [], resignations: [], errors: [] };

  for (const entry of TEACHER_ROSTER) {
    if (entry.isNew) {
      plan.creates.push(entry);
      continue;
    }
    let match = null;
    if (entry.oldEmail) {
      match = byEmail.get(entry.oldEmail.toLowerCase());
      if (!match) plan.errors.push(`${entry.name}: expected existing account at old email ${entry.oldEmail}, not found`);
    } else if (byEmail.has(entry.email.toLowerCase())) {
      match = byEmail.get(entry.email.toLowerCase());
    } else {
      const candidates = byNormName.get(normalizeName(entry.name)) || [];
      if (candidates.length === 1) {
        match = candidates[0];
      } else if (candidates.length === 0) {
        plan.errors.push(`${entry.name}: no existing account found by email or name match — check spelling`);
      } else {
        plan.errors.push(`${entry.name}: ${candidates.length} ambiguous name matches (${candidates.map((c) => c.email).join(', ')}) — resolve manually`);
      }
    }
    if (match) plan.updates.push({ entry, existing: match });
  }

  const matchedIds = new Set(plan.updates.map((u) => u.existing.id));
  for (const t of teachers) {
    if (matchedIds.has(t.id)) continue;
    const norm = normalizeName(t.full_name);
    if (RESIGNED_NAME_HINTS.some((hint) => norm.includes(hint))) {
      plan.resignations.push(t);
    }
  }

  // ── print dry-run report ────────────────────────────────────────────────
  console.log('\n--- C1: Teacher roster plan ---');
  console.log(`${plan.updates.length} existing accounts to update (email/phone/password reset to phone):`);
  for (const { entry, existing } of plan.updates) {
    const emailChange = existing.email.toLowerCase() !== entry.email.toLowerCase() ? ` (email ${existing.email} -> ${entry.email})` : '';
    console.log(`  - ${entry.name}: ${existing.full_name} <${existing.email}>${emailChange}`);
  }
  console.log(`${plan.creates.length} new accounts to create:`);
  for (const entry of plan.creates) console.log(`  - ${entry.name} <${entry.email}>`);
  console.log(`${plan.resignations.length} accounts to mark resigned:`);
  for (const t of plan.resignations) console.log(`  - ${t.full_name} <${t.email}>`);
  if (plan.errors.length) {
    console.log(`\n!! ${plan.errors.length} UNRESOLVED — these will be skipped, fix manually:`);
    for (const e of plan.errors) console.log(`  - ${e}`);
  }

  async function upsertTeacherDetailsStatus(teacherId, status) {
    if (detailsByTeacher.has(teacherId)) {
      await rest('PATCH', 'teacher_details', { query: `?teacher_id=eq.${teacherId}`, body: { status } });
    } else {
      await rest('POST', 'teacher_details', { body: { teacher_id: teacherId, status } });
      detailsByTeacher.set(teacherId, { teacher_id: teacherId, status });
    }
  }

  // Canonical roster name -> teacher id, used to resolve C4/C5 assignments.
  // Built from the roster plan itself (not the DB's pre-update full_name),
  // since the sheet2/sheet1 spreadsheets spell names the same way the
  // roster does, not the way they're currently stored in profiles.
  const rosterIdMap = new Map();
  if (APPLY) {
    for (const { entry, existing } of plan.updates) {
      await authAdmin('PUT', `/users/${existing.id}`, { email: entry.email, password: entry.phone, email_confirm: true });
      await rest('PATCH', 'profiles', { query: `?id=eq.${existing.id}`, body: { email: entry.email, phone: entry.phone, full_name: entry.name } });
      await upsertTeacherDetailsStatus(existing.id, 'active');
      rosterIdMap.set(normalizeName(entry.name), existing.id);
      console.log(`updated ${entry.name}`);
    }
    for (const entry of plan.creates) {
      const created = await authAdmin('POST', '/users', { email: entry.email, password: entry.phone, email_confirm: true });
      const newId = created.id;
      await rest('POST', 'profiles', { body: { id: newId, full_name: entry.name, email: entry.email, phone: entry.phone, role: 'teacher' } });
      await upsertTeacherDetailsStatus(newId, 'active');
      rosterIdMap.set(normalizeName(entry.name), newId);
      console.log(`created ${entry.name} (${newId})`);
    }
    for (const t of plan.resignations) {
      await upsertTeacherDetailsStatus(t.id, 'resigned');
      console.log(`marked resigned: ${t.full_name}`);
    }
  } else {
    for (const { entry, existing } of plan.updates) rosterIdMap.set(normalizeName(entry.name), existing.id);
    for (const entry of plan.creates) rosterIdMap.set(normalizeName(entry.name), '(pending-new-account)');
  }

  function resolveTeacherId(name) {
    if (!name || name === '/----/' || name === 'Vimala') return null;
    const id = rosterIdMap.get(normalizeName(name));
    if (!id) console.log(`  !! no teacher account found for "${name}" — leaving that slot unassigned`);
    return id || null;
  }

  // ── C2: UKG-A / UKG-B classes ────────────────────────────────────────────
  const classes = await rest('GET', 'classes', { query: '?select=id,grade,section,academic_year' });
  const academicYearCounts = {};
  for (const c of classes) academicYearCounts[c.academic_year] = (academicYearCounts[c.academic_year] || 0) + 1;
  const academicYear = Object.entries(academicYearCounts).sort((a, b) => b[1] - a[1])[0]?.[0] || String(new Date().getFullYear());

  console.log(`\n--- C2: UKG classes (academic_year ${academicYear}) ---`);
  const ukgToCreate = ['A', 'B'].filter(
    (section) => !classes.some((c) => c.grade === 'UKG' && c.section === section && c.academic_year === academicYear),
  );
  console.log(ukgToCreate.length ? `Creating UKG-${ukgToCreate.join(', UKG-')}` : 'UKG-A and UKG-B already exist');
  for (const section of ukgToCreate) {
    if (APPLY) {
      const [created] = await rest('POST', 'classes', {
        body: { grade: 'UKG', section, academic_year: academicYear },
        prefer: 'return=representation',
      });
      classes.push(created);
    } else {
      // placeholder so the dry-run preview below reflects the real class count
      classes.push({ id: '(pending-new-class)', grade: 'UKG', section, academic_year: academicYear });
    }
  }

  // ── C3: ensure subjects exist ────────────────────────────────────────────
  const subjects = await rest('GET', 'subjects', { query: '?select=id,name' });
  const subjectByName = new Map(subjects.map((s) => [s.name, s]));
  const subjectsToCreate = ALL_CANON_SUBJECTS.filter((name) => !subjectByName.has(name));
  console.log(`\n--- C3: Subjects ---`);
  console.log(subjectsToCreate.length ? `Creating: ${subjectsToCreate.join(', ')}` : 'All required subjects already exist');
  for (const name of subjectsToCreate) {
    if (APPLY) {
      const [created] = await rest('POST', 'subjects', { body: { name }, prefer: 'return=representation' });
      subjectByName.set(name, created);
    } else {
      // placeholder so the dry-run preview below reflects the real subject count
      subjectByName.set(name, { id: '(pending-new-subject)', name });
    }
  }

  // ── C4: class_subject_teachers from sheet2 matrix ────────────────────────
  console.log('\n--- C4: Subject-teacher assignments (skipping all Vimala/blank rows) ---');
  // gradeAssignments[gradeRoman][sheet2Key] = teacherId  (grade-wide, II-X)
  const gradeAssignments = {};
  const sectionAssignments = {}; // `${grade}|${section}` -> { sheet2Key: teacherId }
  const c4Writes = [];

  for (let r = 1; r <= 18; r++) {
    const row = byR2[r];
    if (!row || !row.A) continue;
    const resolved = resolveSheet2Grade(row.A);
    if (!resolved) continue;
    const headerRow = r <= 6 ? byR2[1] : r <= 11 ? byR2[7] : byR2[12];
    const target = resolved.section ? (sectionAssignments[`${resolved.grade}|${resolved.section}`] ??= {}) : (gradeAssignments[resolved.grade] ??= {});
    for (const col of ['B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J']) {
      const sheet2Key = headerRow[col];
      const teacherName = row[col];
      if (!sheet2Key || !teacherName || teacherName === '/----/' || teacherName === 'Vimala') continue;
      const teacherId = resolveTeacherId(teacherName);
      target[sheet2Key] = teacherId;
      if (!teacherId) continue;
      // resolve which subjects table row this sheet2 column maps to
      const canonName = Object.entries(CANON_TO_SHEET2_KEY).find(([, v]) => v === sheet2Key)?.[0]
        || (sheet2Key === 'Spoken' ? 'Spoken English' : sheet2Key === 'Rhymes' ? 'Rhymes' : null);
      if (!canonName) continue;
      const subjectId = subjectByName.get(canonName)?.id;
      if (!subjectId) continue;
      const targetClasses = resolved.section
        ? classes.filter((c) => c.grade === resolved.grade && c.section === resolved.section && c.academic_year === academicYear)
        : classes.filter((c) => c.grade === resolved.grade && c.academic_year === academicYear);
      for (const cls of targetClasses) {
        c4Writes.push({ class_id: cls.id, subject_id: subjectId, teacher_id: teacherId, label: `${row.A} ${canonName} -> ${teacherName}` });
      }
    }
  }
  console.log(`${c4Writes.length} class_subject_teachers rows to upsert`);
  if (APPLY) {
    for (const w of c4Writes) {
      await rest('POST', 'class_subject_teachers', {
        query: '?on_conflict=class_id,subject_id',
        body: { class_id: w.class_id, subject_id: w.subject_id, teacher_id: w.teacher_id },
        prefer: 'resolution=merge-duplicates',
      });
    }
    console.log('C4 applied.');
  }

  // ── C5: timetable_slots for classes II-X from sheet1 ─────────────────────
  // No clock times in the source spreadsheet — day_of_week/period_number are
  // the only ordering the data supports, so start_time/end_time are left
  // null rather than invented (019_nullable_timetable_times.sql).
  console.log('\n--- C5: Weekly timetable (classes II-X, period numbers only — no clock times in source) ---');
  const c5Writes = [];
  let skippedUnclear = 0;
  for (const [titleRow, gradeRoman] of SHEET1_BLOCKS) {
    const targetClasses = classes.filter((c) => c.grade === gradeRoman && c.academic_year === academicYear);
    if (targetClasses.length === 0) {
      console.log(`  !! no class found for grade ${gradeRoman} — skipping its timetable`);
      continue;
    }
    for (let d = 0; d < DAY_ROWS.length; d++) {
      const row = byR1[titleRow + 2 + d];
      if (!row) continue;
      for (let p = 0; p < PERIOD_COLS.length; p++) {
        const label = row[PERIOD_COLS[p]];
        if (!label || label === '?') {
          if (label === '?') skippedUnclear++;
          continue;
        }
        const canonName = SUBJECT_CANON[label];
        if (!canonName) continue;
        const subjectId = subjectByName.get(canonName)?.id;
        const sheet2Key = CANON_TO_SHEET2_KEY[canonName];
        const teacherId = sheet2Key ? (gradeAssignments[gradeRoman]?.[sheet2Key] || null) : null;
        for (const cls of targetClasses) {
          c5Writes.push({
            class_id: cls.id,
            day_of_week: d + 1,
            period_number: p + 1,
            subject_id: subjectId || null,
            teacher_id: teacherId,
            start_time: null,
            end_time: null,
          });
        }
      }
    }
  }
  console.log(`${c5Writes.length} timetable_slots rows to upsert (${skippedUnclear} unclear "?" cells left blank)`);
  if (APPLY) {
    for (const w of c5Writes) {
      await rest('POST', 'timetable_slots', {
        query: '?on_conflict=class_id,day_of_week,period_number',
        body: w,
        prefer: 'resolution=merge-duplicates',
      });
    }
    console.log('C5 applied.');
  }

  if (!APPLY) {
    console.log('\nDry run complete. Review the plan above, then re-run with APPLY=1 to write these changes.');
  } else {
    console.log('\nAll changes applied.');
  }
}

main().catch((err) => {
  console.error('\nFAILED:', err.message);
  process.exit(1);
});
