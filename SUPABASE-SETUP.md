# Supabase Setup — almentor Media Vault

This guide walks you through migrating from the static GitHub-Pages-only setup
to a real backend with email login and activity tracking.

**Time needed**: 15–20 minutes
**Cost**: $0 (Supabase free tier easily covers a team-internal asset library)

---

## 1) Create the Supabase project

1. Sign up at **https://supabase.com** with the email you want to be the first admin
   (e.g. `ahmedfaysalfouad@almentor.com`).
2. Click **New Project**.
   - **Name**: `almentor-media-vault` (or anything you like)
   - **Database password**: generate a strong one, save it in your password manager — you won't need it day-to-day
   - **Region**: pick the closest to your team (e.g. `eu-west-1 Ireland` or `eu-central-1 Frankfurt`)
   - **Pricing plan**: Free
3. Wait ~2 minutes for the project to provision.

---

## 2) Run the schema

1. In the Supabase dashboard sidebar, open **SQL Editor**.
2. Click **New query**.
3. Copy the entire contents of `supabase-setup.sql` (this repo) and paste it in.
4. Click **Run**.
   - You should see "Success. No rows returned" and the 103 seeded assets at the bottom.

This creates: `assets`, `events`, `allowed_emails`, `admins`, `settings` tables
plus Row-Level Security policies that enforce who can read/write what.

---

## 3) Configure authentication

1. Sidebar → **Authentication** → **Providers**.
2. **Email** provider is on by default — leave it.
3. Sidebar → **Authentication** → **URL Configuration**.
   - **Site URL**: `https://almentor-production.github.io/almentor-production/browse.html`
   - **Redirect URLs**: add **all** of these (one per line):
     ```
     https://almentor-production.github.io/almentor-production/browse.html
     https://almentor-production.github.io/almentor-production/admin.html
     http://localhost:8000/browse.html
     http://localhost:8000/admin.html
     ```
4. Click **Save**.

> The localhost URLs let you test changes locally before pushing. Remove them
> later if you don't need them.

### Optional: customize the magic-link email

Sidebar → **Authentication** → **Email Templates** → **Magic Link**.
Replace the default English copy with whatever wording fits your team.

---

## 4) Paste your keys into `config.js`

1. Sidebar → **Project Settings** → **API**.
2. Copy:
   - **Project URL** (looks like `https://abcdefghij.supabase.co`)
   - **anon public** key (a long JWT starting with `eyJ…`)
3. Open `config.js` in this repo and paste both:
   ```js
   window.SUPABASE_URL      = 'https://abcdefghij.supabase.co';
   window.SUPABASE_ANON_KEY = 'eyJ…';
   ```
4. Commit and push. The keys are **public** — Row-Level Security is what
   protects your data, not key secrecy.

---

## 5) Bootstrap yourself as the first admin

You can't promote yourself from the UI until you exist in the `admins` table,
so we do it once via SQL.

1. Open `browse.html` (or `admin.html`) on the deployed site.
2. Enter your work email and click **Send sign-in link**.
3. Open the email Supabase sent you, click the link — you'll land back on the page.
   You won't see assets yet (you're not on the allowlist).
4. Go back to Supabase → **SQL Editor** → **New query**, and run (replace the email):
   ```sql
   insert into allowed_emails (email, note) values
     ('ahmedfaysalfouad@almentor.com', 'Founding admin');

   insert into admins (user_id, email)
     select id, email from auth.users
     where lower(email) = lower('ahmedfaysalfouad@almentor.com');
   ```
5. Refresh `admin.html` — you should be in. Open **Team Access** to add teammates.

---

## 6) Push the new code, remove the old plaintext data

```bash
# From this repo's folder:
git add browse.html admin.html config.js supabase-setup.sql SUPABASE-SETUP.md index.html
git rm data.json data.enc encrypt-data.py   # no longer used
git commit -m "Migrate to Supabase backend with email auth and tracking"
git push
```

> ⚠️ **`data.json` was publicly readable for some time.** Treat any Drive
> links in it as already-known to anyone curious. Future access is gated by
> Supabase Auth + RLS, but past leakage of links can't be undone — only
> by rotating the Drive sharing settings.

If your repo history has sensitive plaintext you want gone for good, use
[`git filter-repo`](https://github.com/newren/git-filter-repo) to scrub it
before force-pushing.

---

## 7) Day-to-day operation

### As an admin
- **Edit assets**: `admin.html` → same UI as before. Each save is a single Supabase write.
- **Add a teammate**: `admin.html` → **Team Access** → paste email + note → **Grant access**. They can now magic-link in.
- **Revoke a teammate**: same screen → **Revoke**. Their next page-load will hit the "Access not granted" screen.
- **See activity**: `admin.html` → **Activity Log**. Filter by email / event type / date. Export to CSV.

### As a team member
- Open `browse.html`, enter their work email, click the link in the email Supabase sends, and they're in.
- The session lasts 1 hour by default; renewable refresh tokens keep them signed in across reloads for ~30 days.
- Every login + download + link-copy is logged with their email.

---

## 8) Hardening (optional)

### Restrict the anon key to your domain only
1. Supabase → **Project Settings** → **API** → **JWT Settings**.
2. Or use **Authentication** → **Rate Limits** to cap magic-link sends per IP.

### Custom email sender
Free tier uses Supabase's default mail (`noreply@mail.app.supabase.io`). For a
branded sender, plug in your own SMTP under
**Authentication → Email Templates → SMTP Settings**.

### Per-IP rate limiting on events insert
If you're worried about a teammate making 10k clicks/sec, add a
Postgres-side rate-limit trigger. Reach out if you want a template.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| "Setup needed — edit config.js" banner | You haven't filled in the URL and anon key. See step 4. |
| Magic link email never arrives | Check spam. Verify the email is in `auth.users` (Authentication → Users). Check Supabase email rate limits (free tier: 4/hour per user). |
| User signs in but sees "Access not granted" | They're not in `allowed_emails`. Add them from Team Access (or via SQL). |
| Magic link error: "Invalid redirect URL" | The exact URL must be in **Redirect URLs** (step 3). Check trailing slashes. |
| Admin can't edit assets | They're in `allowed_emails` but not in `admins`. Insert them (step 5). |

---

## Architecture diagram

```
┌─────────────────────────────────────────────┐
│         GitHub Pages (static files)         │
│  index.html · browse.html · admin.html      │
│  config.js (public URL + anon key only)     │
└────────────────┬────────────────────────────┘
                 │ Supabase JS SDK over HTTPS
                 ▼
┌─────────────────────────────────────────────┐
│              Supabase Cloud                  │
│  ┌────────────┐  ┌──────────────────────┐   │
│  │  Auth      │  │     Postgres         │   │
│  │  (magic    │  │  • assets            │   │
│  │   link)    │  │  • events            │   │
│  │            │  │  • allowed_emails    │   │
│  │            │  │  • admins            │   │
│  └────────────┘  │  • settings          │   │
│                  └──────────────────────┘   │
│  Row-Level Security policies enforce        │
│  who can read/write each table.             │
└─────────────────────────────────────────────┘
```
