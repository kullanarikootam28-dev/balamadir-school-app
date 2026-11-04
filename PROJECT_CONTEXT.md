# Balamandir School App — Full Project Context

This document is a complete handoff/context brief for the "Balamandir School App" — a production school-management system for **Balamandir Matriculation School, B.Pudur, Mittapalli** (Uthangarai Tk, Krishnagiri Dt, Tamil Nadu, India). Paste this into a new Claude conversation to get full context without re-explaining the project.

## 1. What this is

A Flutter + Supabase school-ERP covering students, parents, teachers, non-teaching staff, fees, exams/marks, attendance (including QR-based self-check-in), timetables, transport, announcements, complaints, messaging, reports, and analytics — for three roles: **Admin**, **Teacher**, **Student** (parents share the student login).

- **Project directory:** `F:\school app` (Windows, no git repo)
- **Package name / applicationId:** `com.example.school_management_app`
- **Display name:** Balamandir School App
- **Supabase project ref:** `atfyumihqsxvzzcifupg`
- **Supabase URL:** `https://atfyumihqsxvzzcifupg.supabase.co`
- **Backend:** Supabase (Postgres + GoTrue Auth + Storage + Realtime), all access controlled by Postgres Row Level Security (RLS) — no custom backend server.

## 2. Tech stack

- **Frontend:** Flutter (Dart), builds for **Android** (phone, primary), **Windows desktop**, and **Web** — all three from the same codebase, same Supabase backend.
- **State management:** flutter_riverpod
- **Routing:** go_router, with a `_RoleGate` at `/` that reads `profiles.role` and dispatches to the right dashboard.
- **Backend:** Supabase — Postgres tables + RLS policies (no server-side application code beyond one Postgres function for QR attendance verification).
- **Key packages:** `supabase_flutter`, `fl_chart` (charts), `pdf` + `share_plus` (PDF export/share), `excel` (Excel export), `file_picker`, `table_calendar`, `qr_flutter` (QR generation), `mobile_scanner` (QR scanning), `url_launcher` (WhatsApp deep links), `flutter_launcher_icons`.

## 3. Database schema (Supabase Postgres)

16 migrations, in `supabase/migrations/`, applied in order via `npx supabase db push --linked` (uses a personal access token, not stored in the repo). Key tables by area:

**Core identity:** `profiles` (id = auth.users.id, full_name, email, role enum: student/teacher/admin, avatar_url, phone), `classes` (grade, section, academic_year, teacher_id), `class_students` (roster), `subjects`, `class_subject_teachers`.

**Student records (022_erp / 010):** `student_details` — 1:1 with profiles for role=student, fields grounded in the school's **real EMIS export**: emis_id, admission_number, father/mother/guardian name+occupation+education, aadhaar_number, date_of_birth, gender, date_of_joining, address, pin_code, blood_group, religion, medium_of_instruction, community, mother_tongue, emergency contact, status (active/transferred/archived), document URLs (photo/birth_certificate/aadhaar/tc).

**Teacher records:** `teacher_details` — qualification, specialization, experience_years, joining_date, status, remarks, address, document URLs (resume/certificate/id_proof). Self-manageable by the teacher, full access for admin.

**Staff:** `non_teaching_staff` (full_name, designation, department, phone, salary_paise, joining_date, status, remarks).

**Academics:** `academic_years` (one `is_current` enforced via partial unique index), `exams`, `exam_subjects` (per-class/subject max_marks + pass_marks), `grades` (student × class × subject × score, now optionally linked to a formal `exam_id`), `report_card_remarks`.

**Attendance:** `attendance` (student daily, with weekly auto-lock logic implemented client-side + `attendance_unlocks` table for office-staff override), `teacher_attendance` (daily, `status` + `marked_by`), plus the **QR system**: `live_qr_gate` (singleton row, current token + generated_at, overwritten every 20s by the admin's Daily Attendance Portal) and `qr_scan_log` (every scan attempt, success or failure, with reason).

**Money:** `fee_payments` (invoice_id, student_id, amount_paise, status, fee_type_id, payment_mode, receipt_number), `fee_types` (Admission/Tuition/Transport/Exam/Special).

**Transport:** `buses`, `bus_stops`, `student_transport`.

**Communication:** `announcements` (school-wide or class-scoped, category, media_url, soft-deletable), `messages` (1:1 sender/recipient chat, soft-deletable — deleted message shows "This message was removed" to the other party), `complaints` (**deliberately anonymous — no author column at all**, admin-only read, soft-deletable), `calendar_events`, `notification_log` (records every WhatsApp-reminder send attempt).

**Governance:** `audit_log` (actor, role, module, action, old/new value, timestamp — written by `AuditService.log(...)` from every sensitive mutation across the app).

**Public onboarding forms (no login required):** `parent_contact_submissions`, `teacher_detail_submissions`, `staff_detail_submissions`, `bus_detail_submissions` — staging tables an unauthenticated public form writes to (anon insert allowed, admin-only read); see §7.

**RLS pattern used throughout:** a `is_admin()` SECURITY DEFINER function (avoids RLS recursion) gates admin-all-access policies; teachers get scoped access via `class_subject_teachers`/`classes.teacher_id` joins; students see only their own rows. **Important gotcha already hit and fixed once:** any table with 2+ foreign keys to `profiles` (e.g. `announcements.author_id` + `announcements.deleted_by`) makes a bare `profiles(full_name)` PostgREST embed ambiguous (`PGRST201`) — must disambiguate as `profiles!<constraint_name>(full_name)`. Tables with this risk: `announcements`, `messages`, `teacher_attendance`, `promotions`, `report_card_remarks`, `notification_log` — check any new embed against these before shipping.

## 4. Feature inventory by role

### Admin (`lib/screens/admin/`)
User Management, Student Records (parent/guardian/demographic editor + document uploads), Non-Teaching Staff, **Teacher Records** (qualifications, assigned classes/subjects, performance metrics, document uploads, PDF/Excel export), Class Configuration (classes/subjects/teacher assignment/roster), **Timetable Setup** (per-class grid editor **+ Bulk Assign tab**: apply one subject/teacher/time-slot to multiple classes at once with a teacher-double-booking conflict check), Academic Years (create/switch-current/archive), Exam Management (exams + per-class/subject max/pass marks), Promotion (bulk-promote a roster to a new class, preserving all history), Transport (buses/stops/student assignment), School Calendar, Global Broadcasts, Spreadsheet Import (bulk class/timetable/student CSV/XLSX import with auto-account-creation), Fee Management (fee types, payment mode, receipt numbers, **WhatsApp payment-reminder button** via `wa.me` deep link), Attendance Reports (daily/monthly/annual charts + week-unlock control), Marks Reports, Rankings (student & teacher, with trend chart), Analytics (**statistics only, no AI/LLM** — weak/strong subjects, attendance-vs-score, linear-trend estimate explicitly labeled as an estimate), Global Search (name/admission#/EMIS/roll#/mobile), Audit Log, Teacher Attendance (manual marking) + **Daily Attendance Portal** (rotating QR code for self-check-in) + QR Scan Log, Complaint Reports (soft-delete, bulk-select).

### Teacher (`lib/screens/teacher/`)
Attendance Registry (weekly-lock aware), Gradebook Input (formal-exam picker with live pass/fail against configured pass_marks), Class Noticeboard (soft-deletable), Messaging Portal, My Students, My Attendance History, **Scan Attendance QR** (camera scan → calls `mark_attendance_via_qr` RPC).

### Student (`lib/screens/student/`)
Profile Overview, Attendance Calendar, Report Card (rank, teacher remarks, PDF download with school logo + signature line), Timetable (view-only), Alerts (announcements), Messages, Complaint Box (anonymous).

### Shared
Profile Detail (with WhatsApp deep-link contact), Change Password, Forgot Password / Magic Link / Set New Password.

## 5. Real data imported into production

- **324 real students** imported from the school's own 12 Excel exports (`F:\school app\Student Details\Student Details\*.xlsx`, one exact duplicate skipped), across 14 real classes (LKG–B through X–A). Full parent/guardian/demographic data populated. A handful of source records shared duplicate/placeholder admission numbers ("0000" ×4, a couple of genuine clerical duplicates) — resolved by keying on EMIS Id instead where needed.
- **18 real teachers** imported from `F:\school app\Contact Information (Responses).xlsx` (a Google Forms export) — real name, email, address, phone, qualification.
- Neither group has real login emails collected via the app yet for **parents**' own contact details (mobile/email/blood group) — that's what the public onboarding site (§7) is for.
- Generated login credentials for the imported accounts are saved locally (**not in chat, not committed**) at `F:\school app\student_login_credentials.csv` and `F:\school app\teacher_login_credentials.csv` — plaintext passwords, treat as sensitive.
- 3 pre-existing QA/demo accounts remain, now cross-linked for a coherent demo: `admin.test@schoolapp.dev`, `teacher.test@schoolapp.dev`, `student.test@schoolapp.dev`, all password `QaTest#2026` — the demo teacher teaches Grade 8–A Mathematics and the demo student is enrolled in that exact class.

## 6. Explicit product decisions (don't re-litigate without reason)

- **No SMS / no WhatsApp Business API.** No Meta Business API number acquired. WhatsApp "sending" is a `url_launcher` deep link to `wa.me/<number>?text=<message>` that opens WhatsApp with a pre-filled message for a human to tap Send — not automated delivery. Used for fee reminders and available via `NotificationService`.
- **No AI/LLM-based analytics.** The "AI Analytics" module is pure arithmetic (`AnalyticsService`): subject averages, weak/strong thresholds (<40% / ≥75%), attendance-vs-score correlation, and a linear-regression trend line explicitly labeled "estimated trend," never presented as an AI prediction. No external AI API calls anywhere in the app.
- **Deletion policy:** soft delete everywhere (`deleted_at`/`deleted_by` columns), never hard delete. Messages show a "This message was removed" placeholder to the other participant (the closest equivalent to "notify" in a 1:1 chat with no push-notification infra). Complaints and broadcasts get audit-logged soft deletes with no per-recipient notify (complaints are anonymous by design; broadcasts have no single fixed recipient).
- **QR attendance:** multiple simultaneous scans of the same 20-second code are all valid (not single-use); no offline fallback (a 20-second-lifetime code makes offline queueing pointless); no GPS/location check (the rotating time-limited code itself is the proof of presence). Verified server-side via a `SECURITY DEFINER` Postgres function (`mark_attendance_via_qr`), not trusted client-side.
- **App icon:** uses the real school crest (`assets/images/logo.png`), re-padded into `logo_icon_foreground.png` (adaptive, ~62% scale for Android's safe zone) and `logo_icon_legacy.png` (~80% scale, white background) after the original asset's content extended almost edge-to-edge and got cropped on real devices.

## 7. Public data-collection website (Claude Artifact, not part of the Flutter app)

Published at **https://claude.ai/code/artifact/5ad452d5-a4f8-412e-b2cb-67ad083263a7** ("Balamandir Details Update") — a static HTML page with 4 tabs, each posting directly to a Supabase staging table via the public anon key (RLS: public insert, admin-only read):
- **Parent/Student** — searchable autocomplete over all 324 real students (name + class + admission# shown to prevent picking the wrong same-named child) → mobile, email, blood group → `parent_contact_submissions`.
- **Teacher** — self-registration (no existing roster to pick from at the time this was built, now partially stale since the 18 teachers were imported afterward) → `teacher_detail_submissions`.
- **Staff** — self-registration → `staff_detail_submissions`.
- **Transport** — new-bus registration → `bus_detail_submissions`.

The page must be explicitly shared (Share button) before it's accessible to anyone but the owner — Artifacts are private by default. Submitted data has **not yet been merged** into the real tables (`profiles.phone/email`, `student_details.blood_group`, etc.) — that's a pending follow-up once responses come in.

## 8. Build artifacts

- **Android (phone):** `flutter build apk --release --split-per-abi` → `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` (~30MB; a **debug** build is ~186MB — always use `--release --split-per-abi` for anything beyond local testing; debug mode bundles the full Dart VM/JIT runtime and all 3 CPU architectures, release mode AOT-compiles + R8-shrinks + splits per architecture, with zero functional difference).
- **Windows desktop:** `flutter build windows --release` → `build\windows\x64\runner\Release\school_management_app.exe` + supporting DLLs (zip the whole `Release` folder — sent to the user as `BalamandirSchoolApp-Windows.zip`). Window title and icon are branded (`windows/runner/main.cpp`, `Runner.rc`).
- **Web:** `flutter build web --release` → `build/web/` — tested locally via `python -m http.server`; **not yet deployed anywhere** (no hosting tool available to Claude — user needs to drag `build/web` into Netlify/Firebase Hosting, or ask Claude to walk through it).
- This machine (the developer's, not necessarily where a future Claude session runs) has a **known Gradle/emulator memory-contention issue** — stop the Android emulator before any `flutter build` for Android, relaunch it after. Use `--split-per-abi` explicitly whenever building for the physical phone, or the output filename can silently be the stale/wrong one.

## 9. Known-fixed bugs worth remembering

- **PGRST201 ambiguous embed** on `announcements` (and pre-emptively on `teacher_attendance`) after adding `deleted_by` FKs — see §3's RLS-pattern note. Fixed by qualifying `profiles!<fk_name>(...)`.
- **Adaptive icon background showing black instead of white** — was the deliberate-but-wrong `adaptive_icon_background` hex in `pubspec.yaml`'s `flutter_launcher_icons` block, not a transparency bug in the source PNG.
- **`excel` package (v4.0.6) cannot parse the school's real XLSX exports** (`custom numFmtId` error) — worked around every time by treating `.xlsx` as a zip and parsing `xl/worksheets/sheet1.xml` (+ `xl/sharedStrings.xml` when present) directly. If the in-app Spreadsheet Import feature is ever used on this school's real files (rather than Claude-side import scripts), it may hit the same parser error — not yet verified either way.
- **`uuid_generate_v4()` not available** on this Supabase project — use Postgres's built-in `gen_random_uuid()` instead (no extension dependency).

## 10. Pending / not yet done

- Google Sheets **ongoing** sync for teachers (a one-time import from a supplied sheet was done; recurring sync was not requested/built).
- Merging onboarding-site submissions (§7) back into the real `profiles`/`student_details`/`teacher_details` tables.
- Real phone numbers for students are **masked in the source data** (`XXXXXX8402` style) — WhatsApp messaging to students/parents won't work with these until real numbers are collected (via the onboarding site or a fresh unmasked export).
- Web build not deployed to any public host yet.
- Non-teaching staff table is currently empty (no real data collected for that role yet).
- No automated tests exist; verification throughout this project has been manual (emulator/device screenshots + direct Supabase REST checks).

## 11. Where to look first in a fresh session

- `lib/app.dart` — the full route table and role-gate logic.
- `lib/config/supabase_config.dart` — project URL/anon key + a few table-name constants (not all tables are listed there; most screens reference table names as string literals directly).
- `supabase/migrations/` — read newest-first for the most current schema; each file has a comment block explaining its purpose.
- This file's §6 before proposing anything that touches notifications, AI, or deletion semantics — those are settled decisions, not open questions.
