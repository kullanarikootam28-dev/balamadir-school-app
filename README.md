# Balamandir School App

Flutter + Supabase school management app for **Balamandir Matriculation School, B.Pudur, Mittapalli** (Uthangarai Tk, Krishnagiri Dt, Tamil Nadu).
Roles: Admin, Teacher, Student (parents share the student login). Builds for Android, Windows and Web.

Current version: see `pubspec.yaml` (`version:`) and `lib/config/app_info.dart` (`kAppVersion`). Bump both each release.
More detail: [PROJECT_CONTEXT.md](PROJECT_CONTEXT.md).

---

## 1. Accounts / services used

| Service | What it is used for | Where to log in |
|---|---|---|
| **GitHub** | Source code. Repo: `kullanarikootam28-dev/balamadir-school-app` | github.com (account `kullanarikootam28-dev`, email kulanarikootam28@gmail.com) |
| **Supabase** | Postgres DB, Auth (GoTrue), Realtime, RLS | supabase.com/dashboard, project ref `atfyumihqsxvzzcifupg` |
| **Cloudflare** | Worker (R2 gateway + cron jobs) and R2 file storage | dash.cloudflare.com |
| **Inno Setup** | Builds the Windows installer (`windows_installer.iss`) | local install |
| **Flutter / Android SDK / Gradle** | App builds | local install |
| **Node.js** | Helper scripts in `scripts/`, Supabase CLI via `npx` | local install |

## 2. Supabase

- **Project ref:** `atfyumihqsxvzzcifupg`
- **URL:** `https://atfyumihqsxvzzcifupg.supabase.co`
- **Anon (public) key** (also hard-coded in `lib/config/supabase_config.dart` and `onboarding_form.html`):
  ```
  eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImF0Znl1bWlocXN4dnp6Y2lmdXBnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODg1Mzk2ODksImV4cCI6MjEwNDExNTY4OX0.Z7rfkMj9ikjmPCbZexlWHEhsbHZxZOeouonUIeoWuZg
  ```
- **Pooler URL:** `postgresql://postgres.atfyumihqsxvzzcifupg@aws-0-ap-south-1.pooler.supabase.com:5432/postgres`
- **Service role key:** NOT in the repo. Get it from Supabase dashboard → Project Settings → API → `service_role`. It bypasses RLS, so keep it out of code. Used by the Worker and the scripts.
  - Service role key: `<paste here>`
- **Database password:** `<paste here>` (Project Settings → Database)
- **Personal access token** (for `npx supabase db push --linked`): `<paste here>` (supabase.com/dashboard/account/tokens)
- **Migrations:** `supabase/migrations/` — apply with `npx supabase db push --linked`.
- Note: `uuid_generate_v4()` is not available on this project; use `gen_random_uuid()`.

## 3. Cloudflare Worker + R2

- **Worker URL:** `https://balamandirschool.ajainawin.workers.dev` (also in `lib/services/r2_gateway_service.dart`)
- **Worker code:** `cloudflare-worker/index.js`
- **R2 bucket:** `balamandirschool-2026`, bound to the Worker as `BUCKET`
- **Path prefixes in the bucket:** `avatars/`, `broadcast_media/`, `student_documents/`, `teacher_documents/`, `expense_documents/`
- **Worker variables (Settings → Variables):**
  - `SUPABASE_URL` = `https://atfyumihqsxvzzcifupg.supabase.co`
  - `SUPABASE_ANON_KEY` = the anon key above
  - `SUPABASE_SERVICE_ROLE_KEY` = the service role key, added as an **encrypted secret**
- **Cron triggers:** `0 0 */3 * *` (keep-alive ping to Supabase every 3 days) and `0 0 1 */2 *` (full data backup every 2 months)
- **R2 S3 credentials** (only for `scripts/migrate_storage_to_r2.js`):
  - `R2_ACCOUNT_ID`: `<paste here>`
  - `R2_ACCESS_KEY_ID`: `<paste here>`
  - `R2_SECRET_ACCESS_KEY`: `<paste here>`
  - `R2_BUCKET`: `balamandirschool-2026`

## 4. Android signing

- `android/key.properties` and `android/upload-keystore.jks` exist on the dev PC but are git-ignored, so they are **not** in GitHub. **Back up both files somewhere safe.** If the keystore is lost, installed phones cannot be updated in place.
- Keystore password: `<paste here>`
- Key alias: `<paste here>`
- Key password: `<paste here>`
- Package name / applicationId: `com.example.school_management_app`

## 5. Logins (app users)

- Admin login email/password: `<paste here>`
- Student and teacher passwords are in `student_login_credentials.csv` and `teacher_login_credentials.csv` on the dev PC. These files and the student data are git-ignored and are not in GitHub.

## 6. SSH key used to push to GitHub

- Private key: `C:\Users\Naveen Ajay\.ssh\id_ed25519`, public key: `id_ed25519.pub` (comment `kulanarikootam28@gmail.com`).
- Port 22 is blocked on the dev network, so the remote uses port 443:
  `ssh://git@ssh.github.com:443/kullanarikootam28-dev/balamadir-school-app.git`
- Pushing is slow on that connection. Run it with `GIT_SSH_COMMAND="ssh -o ServerAliveInterval=15 -o ServerAliveCountMax=40"` and let it finish.

## 7. Build and release

```
flutter pub get
flutter build apk --release --split-per-abi     # Android (use the arm64 / universal APK)
flutter build windows --release                 # Windows -> build\windows\x64\runner\Release
flutter build web --release                     # Web -> build/web (not deployed yet)
```
- Windows installer: compile `windows_installer.iss` with Inno Setup. Output goes to `installer_output/`. Delete old installers.
- Stop the Android emulator before building (Gradle runs out of memory). If drive C: is full, Gradle also fails with OOM.
- Always bump the patch version and the build number each release.

## 8. Main packages

`supabase_flutter`, `flutter_riverpod`, `go_router`, `fl_chart`, `pdf`, `share_plus`, `excel`, `csv`, `file_picker`, `table_calendar`, `qr_flutter`, `mobile_scanner`, `url_launcher`, `http`, `google_fonts`. A patched copy of `gotrue` lives in `third_party/gotrue` (see `BALAMANDIR_PATCH.md` there).

## 9. Known gotchas

- The `excel` package cannot parse the school's real XLSX exports. Parse `xl/worksheets/sheet1.xml` from the zip instead.
- The Android build writes the wrong APK name unless you pass `--split-per-abi`.
- Student phone numbers in the source data are masked (`XXXXXX8402`), so WhatsApp links will not work until real numbers are collected.
