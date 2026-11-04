// ════════════════════════════════════════════════════════════════════════════
// One-time migration: copy every file out of the 5 Supabase Storage buckets
// into the single R2 bucket (with the old bucket name as a path prefix),
// then update every database column that referenced the old location.
//
// Dry-run by default (prints what it would do); APPLY=1 to actually write.
// All credentials come from environment variables — never hardcoded here,
// never pasted into chat. Required env vars:
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
//   R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_BUCKET
//   WORKER_URL   (e.g. https://balamandirschool.ajainawin.workers.dev)
// ════════════════════════════════════════════════════════════════════════════

const crypto = require('crypto');

const APPLY = process.env.APPLY === '1';
const SUPABASE_URL = process.env.SUPABASE_URL;
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const R2_ACCOUNT_ID = process.env.R2_ACCOUNT_ID;
const R2_ACCESS_KEY_ID = process.env.R2_ACCESS_KEY_ID;
const R2_SECRET_ACCESS_KEY = process.env.R2_SECRET_ACCESS_KEY;
const R2_BUCKET = process.env.R2_BUCKET;
const WORKER_URL = process.env.WORKER_URL;

for (const [name, value] of Object.entries({
  SUPABASE_URL, SERVICE_KEY, R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_BUCKET, WORKER_URL,
})) {
  if (!value) {
    console.error(`Missing required environment variable: ${name}`);
    process.exit(1);
  }
}

const BUCKETS = ['avatars', 'broadcast_media', 'student_documents', 'teacher_documents', 'expense_documents'];
// These two store a full old Supabase public URL in the DB; the other three
// store a bare relative path.
const PUBLIC_BUCKETS = new Set(['avatars', 'broadcast_media']);

async function supabaseFetch(path, opts = {}) {
  const res = await fetch(`${SUPABASE_URL}${path}`, {
    ...opts,
    headers: {
      Authorization: `Bearer ${SERVICE_KEY}`,
      apikey: SERVICE_KEY,
      ...opts.headers,
    },
  });
  return res;
}

// Supabase Storage's list endpoint returns one directory level per call
// (sub-folders come back as entries with id === null); since every private
// bucket here is exactly one level deep (`<ownerId>/<file>`), one round of
// recursion covers every real path.
async function listAllObjects(bucket) {
  const top = await (await supabaseFetch(`/storage/v1/object/list/${bucket}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ prefix: '', limit: 1000 }),
  })).json();

  const files = [];
  for (const entry of top) {
    if (entry.id === null) {
      // A folder — recurse one level into it.
      const nested = await (await supabaseFetch(`/storage/v1/object/list/${bucket}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ prefix: `${entry.name}/`, limit: 1000 }),
      })).json();
      for (const n of nested) {
        if (n.id !== null) files.push(`${entry.name}/${n.name}`);
      }
    } else {
      files.push(entry.name);
    }
  }
  return files;
}

async function downloadObject(bucket, path) {
  const res = await supabaseFetch(`/storage/v1/object/${bucket}/${path}`);
  if (!res.ok) throw new Error(`Download failed for ${bucket}/${path}: ${res.status}`);
  const buf = Buffer.from(await res.arrayBuffer());
  const contentType = res.headers.get('content-type') || 'application/octet-stream';
  return { buf, contentType };
}

// Minimal AWS SigV4 for a single PUT to R2 — no SDK dependency needed.
function sha256Hex(data) { return crypto.createHash('sha256').update(data).digest('hex'); }
function hmac(key, data) { return crypto.createHmac('sha256', key).update(data).digest(); }

async function uploadToR2(key, buf, contentType) {
  const host = `${R2_ACCOUNT_ID}.r2.cloudflarestorage.com`;
  const now = new Date();
  const amzDate = now.toISOString().replace(/[:-]|\.\d{3}/g, '');
  const dateStamp = amzDate.slice(0, 8);
  const canonicalUri = `/${R2_BUCKET}/${key}`;
  const payloadHash = sha256Hex(buf);
  const canonicalHeaders =
    `content-type:${contentType}\nhost:${host}\nx-amz-content-sha256:${payloadHash}\nx-amz-date:${amzDate}\n`;
  const signedHeaders = 'content-type;host;x-amz-content-sha256;x-amz-date';
  const canonicalRequest = `PUT\n${canonicalUri}\n\n${canonicalHeaders}\n${signedHeaders}\n${payloadHash}`;
  const credentialScope = `${dateStamp}/auto/s3/aws4_request`;
  const stringToSign = `AWS4-HMAC-SHA256\n${amzDate}\n${credentialScope}\n${sha256Hex(canonicalRequest)}`;
  const kDate = hmac(`AWS4${R2_SECRET_ACCESS_KEY}`, dateStamp);
  const kRegion = hmac(kDate, 'auto');
  const kService = hmac(kRegion, 's3');
  const kSigning = hmac(kService, 'aws4_request');
  const signature = hmac(kSigning, stringToSign).toString('hex');
  const authHeader =
    `AWS4-HMAC-SHA256 Credential=${R2_ACCESS_KEY_ID}/${credentialScope}, SignedHeaders=${signedHeaders}, Signature=${signature}`;

  const res = await fetch(`https://${host}${canonicalUri}`, {
    method: 'PUT',
    headers: {
      'content-type': contentType,
      'x-amz-content-sha256': payloadHash,
      'x-amz-date': amzDate,
      Authorization: authHeader,
    },
    body: buf,
  });
  if (!res.ok) throw new Error(`R2 upload failed for ${key}: ${res.status} ${await res.text()}`);
}

async function updateColumn(table, idColumn, idValue, column, value) {
  await supabaseFetch(`/rest/v1/${table}?${idColumn}=eq.${idValue}`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json', Prefer: 'return=minimal' },
    body: JSON.stringify({ [column]: value }),
  });
}

async function main() {
  console.log(APPLY ? '=== APPLY MODE ===' : '=== DRY RUN (set APPLY=1 to write) ===');

  const plan = [];
  for (const bucket of BUCKETS) {
    const files = await listAllObjects(bucket);
    for (const path of files) {
      plan.push({ bucket, path, r2Key: `${bucket}/${path}` });
    }
  }

  console.log(`\nFound ${plan.length} file(s) across all 5 buckets:`);
  for (const p of plan) console.log(`  ${p.bucket}/${p.path}`);

  if (plan.length === 0) {
    console.log('\nNothing to migrate.');
  } else if (APPLY) {
    for (const p of plan) {
      const { buf, contentType } = await downloadObject(p.bucket, p.path);
      await uploadToR2(p.r2Key, buf, contentType);
      console.log(`  copied ${p.r2Key} (${buf.length} bytes)`);
    }
  } else {
    console.log('\nRe-run with APPLY=1 to actually copy these to R2.');
  }

  // ── Update database references ──────────────────────────────────────────
  console.log('\n--- Database references to update ---');

  // Public: profiles.avatar_url (old Supabase public URL -> new Worker URL)
  const profiles = await (await supabaseFetch(
    `/rest/v1/profiles?avatar_url=not.is.null&select=id,avatar_url`,
  )).json();
  for (const p of profiles) {
    const match = p.avatar_url.match(/\/avatars\/(.+)$/);
    if (!match) continue;
    const newUrl = `${WORKER_URL}/file/avatars/${match[1]}`;
    console.log(`  profiles.${p.id}.avatar_url -> ${newUrl}`);
    if (APPLY) await updateColumn('profiles', 'id', p.id, 'avatar_url', newUrl);
  }

  // Public: announcements.media_url
  const announcements = await (await supabaseFetch(
    `/rest/v1/announcements?media_url=not.is.null&select=id,media_url`,
  )).json();
  for (const a of announcements) {
    const match = a.media_url.match(/\/broadcast_media\/(.+)$/);
    if (!match) continue;
    const newUrl = `${WORKER_URL}/file/broadcast_media/${match[1]}`;
    console.log(`  announcements.${a.id}.media_url -> ${newUrl}`);
    if (APPLY) await updateColumn('announcements', 'id', a.id, 'media_url', newUrl);
  }

  // Private: student_details (prepend student_documents/ prefix)
  const studentDocColumns = ['photo_url', 'birth_certificate_url', 'aadhaar_doc_url', 'tc_url'];
  const students = await (await supabaseFetch(
    `/rest/v1/student_details?select=student_id,${studentDocColumns.join(',')}`,
  )).json();
  for (const s of students) {
    for (const col of studentDocColumns) {
      const val = s[col];
      if (val && !val.startsWith('student_documents/')) {
        const newVal = `student_documents/${val}`;
        console.log(`  student_details.${s.student_id}.${col} -> ${newVal}`);
        if (APPLY) await updateColumn('student_details', 'student_id', s.student_id, col, newVal);
      }
    }
  }

  // Private: teacher_details (prepend teacher_documents/ prefix)
  const teacherDocColumns = ['resume_url', 'certificate_url', 'id_proof_url'];
  const teachers = await (await supabaseFetch(
    `/rest/v1/teacher_details?select=teacher_id,${teacherDocColumns.join(',')}`,
  )).json();
  for (const t of teachers) {
    for (const col of teacherDocColumns) {
      const val = t[col];
      if (val && !val.startsWith('teacher_documents/')) {
        const newVal = `teacher_documents/${val}`;
        console.log(`  teacher_details.${t.teacher_id}.${col} -> ${newVal}`);
        if (APPLY) await updateColumn('teacher_details', 'teacher_id', t.teacher_id, col, newVal);
      }
    }
  }

  // Private: expenses.receipt_url (prepend expense_documents/ prefix)
  const expenses = await (await supabaseFetch(
    `/rest/v1/expenses?receipt_url=not.is.null&select=id,receipt_url`,
  )).json();
  for (const e of expenses) {
    if (!e.receipt_url.startsWith('expense_documents/')) {
      const newVal = `expense_documents/${e.receipt_url}`;
      console.log(`  expenses.${e.id}.receipt_url -> ${newVal}`);
      if (APPLY) await updateColumn('expenses', 'id', e.id, 'receipt_url', newVal);
    }
  }

  // Private: repair_requests (prepend expense_documents/ prefix — same
  // bucket as expense receipts, per the plan's shared "expense_documents"
  // category for repair paperwork)
  const repairColumns = ['quotation_url', 'bill_url', 'before_photo_url', 'after_photo_url'];
  const repairs = await (await supabaseFetch(
    `/rest/v1/repair_requests?select=id,${repairColumns.join(',')}`,
  )).json();
  for (const r of repairs) {
    for (const col of repairColumns) {
      const val = r[col];
      if (val && !val.startsWith('expense_documents/')) {
        const newVal = `expense_documents/${val}`;
        console.log(`  repair_requests.${r.id}.${col} -> ${newVal}`);
        if (APPLY) await updateColumn('repair_requests', 'id', r.id, col, newVal);
      }
    }
  }

  console.log(APPLY ? '\nMigration applied.' : '\nDry run complete. Re-run with APPLY=1 to write these changes.');
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
