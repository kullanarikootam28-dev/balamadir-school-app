// ════════════════════════════════════════════════════════════════════════════
// Balamandir School App — R2 storage gateway.
//
// Stands in for what Postgres RLS does for Supabase Storage today: since R2
// has no concept of "logged-in Supabase user," this Worker checks the
// caller's Supabase access token + profiles.role before letting them read or
// write a file, then talks to R2 through its own binding (no AWS signing
// needed — the binding is configured in the dashboard's Bindings tab).
//
// One bucket, five path prefixes (avatars/, broadcast_media/,
// student_documents/, teacher_documents/, expense_documents/) standing in
// for what used to be five separate Supabase Storage buckets.
//
// Required in the Worker's Settings → Variables:
//   SUPABASE_URL       = https://atfyumihqsxvzzcifupg.supabase.co
//   SUPABASE_ANON_KEY  = (the app's anon key — public, safe to store as a
//                         plain variable, not a secret)
// Required as a Worker SECRET (Settings → Variables → "Encrypt", not a
// plain variable — this key bypasses RLS entirely):
//   SUPABASE_SERVICE_ROLE_KEY = copy directly from Supabase dashboard
//                               (Project Settings → API → service_role) —
//                               never relay this one through chat.
// Required in Settings → Bindings:
//   BUCKET  →  R2 bucket binding pointed at balamandirschool-2026
// Required in Settings → Triggers → Cron Triggers (add both):
//   "0 0 */3 * *"  — every 3 days: keep-alive ping (pingSupabase below)
//   "0 0 1 */2 *"  — every 2 months: full data backup (runBackup below)
// ════════════════════════════════════════════════════════════════════════════

function corsHeaders() {
  return {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Authorization, Content-Type',
  };
}

// Looks up who's calling and what role they have, via Supabase's own REST
// API — the same two calls the app itself already makes (auth/v1/user, then
// profiles by id). Returns null if the token is missing/invalid.
async function getCaller(token, env) {
  if (!token) return null;
  try {
    const userResp = await fetch(`${env.SUPABASE_URL}/auth/v1/user`, {
      headers: { apikey: env.SUPABASE_ANON_KEY, Authorization: `Bearer ${token}` },
    });
    if (!userResp.ok) return null;
    const user = await userResp.json();

    const profileResp = await fetch(
      `${env.SUPABASE_URL}/rest/v1/profiles?id=eq.${user.id}&select=role,admin_access`,
      { headers: { apikey: env.SUPABASE_ANON_KEY, Authorization: `Bearer ${token}` } },
    );
    if (!profileResp.ok) return null;
    const rows = await profileResp.json();
    if (!rows.length) return null;

    // A teacher with admin access (profiles.admin_access, migration 026)
    // gets the same file rights as an admin, matching is_admin() in the DB.
    const isAdmin = rows[0].role === 'admin' || rows[0].admin_access === true;
    return { id: user.id, role: rows[0].role, isAdmin };
  } catch {
    return null;
  }
}

// Mirrors the exact read matrix from the Supabase Storage RLS policies this
// replaces (migrations 007, 009, 010, 014, 020).
function canRead(path, caller) {
  if (path.startsWith('avatars/') || path.startsWith('broadcast_media/')) return true;
  if (!caller) return false;
  if (caller.isAdmin) return true;
  if (path.startsWith('student_documents/') || path.startsWith('teacher_documents/')) {
    const ownerId = path.split('/')[1];
    return ownerId === caller.id;
  }
  return false; // expense_documents/* — admin only
}

// Mirrors the write matrix — every prefix is admin-only to write except
// broadcast_media, which teachers can also post to.
function canWrite(path, caller) {
  if (!caller) return false;
  if (caller.isAdmin) return true;
  if (path.startsWith('broadcast_media/') && caller.role === 'teacher') return true;
  return false;
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const authHeader = request.headers.get('Authorization');
    // Header is used for in-app fetches (uploads, avatar/media loads); the
    // ?token= fallback is for private documents opened in an external
    // browser via launchUrl, which can't attach a header — same trade-off
    // Supabase's own createSignedUrl already makes (token embedded in the
    // URL itself), not a new class of exposure.
    const token = authHeader?.startsWith('Bearer ')
      ? authHeader.slice(7)
      : url.searchParams.get('token');

    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: corsHeaders() });
    }

    // GET /file/<path> — download/view a file.
    if (request.method === 'GET' && url.pathname.startsWith('/file/')) {
      const path = decodeURIComponent(url.pathname.slice('/file/'.length));
      const caller = await getCaller(token, env);
      if (!canRead(path, caller)) {
        return new Response('Forbidden', { status: 403, headers: corsHeaders() });
      }
      const object = await env.BUCKET.get(path);
      if (!object) {
        return new Response('Not found', { status: 404, headers: corsHeaders() });
      }
      const headers = new Headers(corsHeaders());
      object.writeHttpMetadata(headers);
      headers.set('etag', object.httpEtag);
      return new Response(object.body, { headers });
    }

    // POST /upload?path=<path> — body is the raw file bytes.
    if (request.method === 'POST' && url.pathname === '/upload') {
      const path = url.searchParams.get('path');
      if (!path) {
        return new Response('Missing path', { status: 400, headers: corsHeaders() });
      }
      const caller = await getCaller(token, env);
      if (!canWrite(path, caller)) {
        return new Response('Forbidden', { status: 403, headers: corsHeaders() });
      }
      const contentType = request.headers.get('Content-Type') || 'application/octet-stream';
      await env.BUCKET.put(path, request.body, { httpMetadata: { contentType } });
      return new Response(JSON.stringify({ success: true, path }), {
        headers: { ...corsHeaders(), 'Content-Type': 'application/json' },
      });
    }

    return new Response('Not found', { status: 404, headers: corsHeaders() });
  },

  // Two Cron Triggers point at this same handler — event.cron tells them
  // apart. Set up both in the dashboard under Settings → Triggers.
  async scheduled(event, env, ctx) {
    if (event.cron === BACKUP_CRON) {
      ctx.waitUntil(runBackup(env));
    } else {
      ctx.waitUntil(pingSupabase(env));
    }
  },
};

// Cron schedule string for the backup job — every 2 months, midnight on the
// 1st (Jan/Mar/May/Jul/Sep/Nov). Anything else that fires scheduled() is
// treated as the keep-alive ping.
const BACKUP_CRON = '0 0 1 */2 *';

// A real query against the database counts as activity and resets
// Supabase's 7-day inactivity pause clock — this is the only thing
// standing between the free tier and going offline over a long school
// holiday.
async function pingSupabase(env) {
  await fetch(`${env.SUPABASE_URL}/rest/v1/profiles?select=id&limit=1`, {
    headers: { apikey: env.SUPABASE_ANON_KEY, Authorization: `Bearer ${env.SUPABASE_ANON_KEY}` },
  });
}

// Every real, hard-to-regenerate table (people, records, finance,
// communication, transport, HR) — deliberately excludes pure logs and
// ephemeral state (qr scan log, in-app notifications, the live QR gate,
// onboarding staging tables) to stay well under the free plan's 50
// external-subrequest-per-invocation cap. 33 tables here, ~17 to spare.
const BACKUP_TABLES = [
  'profiles', 'student_details', 'teacher_details', 'non_teaching_staff',
  'academic_years', 'classes', 'subjects', 'class_subject_teachers', 'class_students', 'timetable_slots',
  'attendance', 'teacher_attendance', 'grades', 'exams', 'exam_subjects', 'report_card_remarks', 'promotions',
  'attendance_unlocks', 'fee_types', 'fee_payments', 'app_settings', 'expense_categories', 'expenses',
  'repair_requests', 'announcements', 'messages', 'complaints',
  'buses', 'bus_stops', 'student_transport', 'calendar_events',
  'teacher_leaves', 'audit_log',
];

// Logical (not binary pg_dump) backup: every row of every table above, as
// JSON, one file per table under backups/<date>/. Needs the service_role
// key (a Worker Secret, not a plain Variable) — export_table_json is only
// executable by service_role. One bad table is skipped, not fatal, so a
// single table's hiccup doesn't lose the other 32.
//
// Goes through the export_table_json RPC (025_backup_export_function.sql)
// rather than a plain table read: PostgREST caps plain reads at 1000 rows
// no matter what `limit` says, which would silently truncate attendance and
// audit_log. The RPC returns the whole table as one JSON value in one
// request, keeping each table to a single subrequest.
async function runBackup(env) {
  const date = new Date().toISOString().slice(0, 10);
  for (const table of BACKUP_TABLES) {
    try {
      const resp = await fetch(`${env.SUPABASE_URL}/rest/v1/rpc/export_table_json`, {
        method: 'POST',
        headers: {
          apikey: env.SUPABASE_SERVICE_ROLE_KEY,
          Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ p_table: table }),
      });
      if (!resp.ok) continue;
      // Raw bytes straight through — no JSON parsing, to stay inside the
      // free plan's CPU budget even for large tables.
      const body = await resp.arrayBuffer();
      await env.BUCKET.put(`backups/${date}/${table}.json`, body, {
        httpMetadata: { contentType: 'application/json' },
      });
    } catch {
      // Best-effort — move on to the next table rather than losing the
      // whole backup over one failure.
    }
  }
}
