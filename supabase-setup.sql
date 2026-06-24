-- ============================================================
-- almentor Media Vault — Supabase schema
-- Run this in: Supabase Dashboard > SQL Editor > New query > Run
-- Idempotent: safe to re-run (drops + recreates).
-- ============================================================

-- 1. Clean slate (skip if migrating data you want to keep)
drop table if exists events cascade;
drop table if exists allowed_emails cascade;
drop table if exists admins cascade;
drop table if exists settings cascade;
drop table if exists assets cascade;
drop function if exists is_allowed_email cascade;
drop function if exists is_admin cascade;

-- ============================================================
-- TABLES
-- ============================================================

create table assets (
  id            bigint primary key,
  title         text not null,
  cat           text,
  year          text,
  fmt           text default '',
  link          text default '',
  thumb         text default '',
  tags          text default '',
  descr         text default '',
  star          boolean default false,
  created_at    timestamptz default now(),
  updated_at    timestamptz default now()
);

create index assets_cat_idx on assets (cat);
create index assets_year_idx on assets (year);
create index assets_star_idx on assets (star) where star = true;

create table events (
  id            bigint generated always as identity primary key,
  user_email    text not null,
  user_id       uuid references auth.users(id) on delete set null,
  event_type    text not null check (event_type in ('login','download','copy_link')),
  asset_id      bigint,
  asset_title   text,
  user_agent    text,
  created_at    timestamptz default now()
);

create index events_user_email_idx on events (user_email);
create index events_created_at_idx on events (created_at desc);
create index events_type_idx on events (event_type);
create index events_asset_idx on events (asset_id);

create table allowed_emails (
  email         text primary key,
  note          text,
  added_at      timestamptz default now(),
  added_by      text
);

create table admins (
  user_id       uuid primary key references auth.users(id) on delete cascade,
  email         text not null,
  added_at      timestamptz default now()
);

create table settings (
  key           text primary key,
  value         jsonb not null,
  updated_at    timestamptz default now()
);

insert into settings (key, value) values (
  'banner',
  '{"url":"","title":"Production Library","subtitle":"Browse, preview & download production assets"}'::jsonb
);

-- Auto-update updated_at
create or replace function touch_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end
$$;

create trigger assets_touch before update on assets
  for each row execute function touch_updated_at();

create trigger settings_touch before update on settings
  for each row execute function touch_updated_at();

-- ============================================================
-- HELPERS (SECURITY DEFINER so RLS policies can call them)
-- ============================================================

create or replace function is_allowed_email()
returns boolean language sql security definer set search_path = public as $$
  select exists (
    select 1 from allowed_emails
    where lower(email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  )
$$;

create or replace function is_admin()
returns boolean language sql security definer set search_path = public as $$
  select exists (select 1 from admins where user_id = auth.uid())
$$;

-- ============================================================
-- ROW-LEVEL SECURITY
-- ============================================================

alter table assets         enable row level security;
alter table events         enable row level security;
alter table allowed_emails enable row level security;
alter table admins         enable row level security;
alter table settings       enable row level security;

-- assets: any allowed user reads; only admins write
create policy assets_select on assets for select to authenticated
  using (is_allowed_email());
create policy assets_insert on assets for insert to authenticated
  with check (is_admin());
create policy assets_update on assets for update to authenticated
  using (is_admin()) with check (is_admin());
create policy assets_delete on assets for delete to authenticated
  using (is_admin());

-- events: allowed users insert their own events; admins read all
create policy events_insert on events for insert to authenticated
  with check (
    is_allowed_email()
    and lower(user_email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
create policy events_select_admin on events for select to authenticated
  using (is_admin());

-- allowed_emails: admins only (read + write)
create policy allowed_emails_admin on allowed_emails for all to authenticated
  using (is_admin()) with check (is_admin());

-- admins: each user can see their own row (to know if they are admin); only admins can modify
create policy admins_self_read on admins for select to authenticated
  using (user_id = auth.uid() or is_admin());
create policy admins_modify on admins for insert to authenticated
  with check (is_admin());
create policy admins_update on admins for update to authenticated
  using (is_admin()) with check (is_admin());
create policy admins_delete on admins for delete to authenticated
  using (is_admin());

-- settings: any allowed user reads (so banner shows); admins write
create policy settings_select on settings for select to authenticated
  using (is_allowed_email());
create policy settings_write on settings for all to authenticated
  using (is_admin()) with check (is_admin());

-- ============================================================
-- SEED — 103 assets migrated from data.json
-- ============================================================

insert into assets (id, title, cat, year, fmt, link, thumb, tags, descr, star) values
  (1782225113941, 'NBE collage 3', 'Advanced Collage', '2024', '', 'https://drive.google.com/file/d/1ibo8nHSjdbQnZAPrfzsyBMV6hSx7NF9e/view?usp=sharing', '', '', '', FALSE),
  (1782225090372, 'NBE collage 2', 'Advanced Collage', '2023', '', 'https://drive.google.com/file/d/15J0AXmC81tVxpgNZCADrc1vFcwyFzPBI/view?usp=sharing', '', '', '', FALSE),
  (1782225066353, 'NBE collage', 'Advanced Collage', '2023', '', 'https://drive.google.com/file/d/1EYVd8eXLormZOJrpg38vyD9ySskWl5Va/view?usp=sharing', '', '', '', TRUE),
  (1782225024537, 'MOC collage', 'Advanced Collage', '2025', '', 'https://drive.google.com/file/d/1R7egAB3fODr6cXrBVbK6mlBSMeIkvHjV/view?usp=sharing', '', '', '', TRUE),
  (1782224865606, 'Turky Eltayar', 'Instructor Led', '2023', '', 'https://drive.google.com/file/d/1B1HwdRqoIf5xk0PH_5US4RSP3IFtteeU/view?usp=sharing', '', '', '', FALSE),
  (1782224808399, 'Almentor AD (AI Gamig)', 'Showreel', '2024', 'Promo', 'https://drive.google.com/file/d/1NxwvQ6UdwPkLq11axvD9JqeIjgD7VJ5F/view?usp=sharing', '', '', '', TRUE),
  (1782223182931, 'Ahmed Amin AD', 'Showreel', '2020', 'Promo', 'https://drive.google.com/file/d/1p_H7ehzTzpqBnTkxu_ALKs9ZV6ExoEXt/view?usp=sharing', '', '', '', TRUE),
  (1782222133261, 'Mawada Song', 'Promos', '2022', 'Promo', 'https://drive.google.com/file/d/1dm4kwodoHDLRTzfWNMUo3wjRR-HHvavm/view?usp=sharing', '', '', '', TRUE),
  (1782119163290, 'Mawada AI Promo', 'AI Videos', '2025', 'Promo', 'https://drive.google.com/file/d/1bzNvSjgJTnZ0TNRWQy5BwjzYbLLHssZv/view?usp=sharing', '', '', '', FALSE),
  (1782118901586, 'NBE - Unit 3 - الفرق بين غسل الأموال وتمويل الإرهاب', 'Medium Animation', '2025', 'Animation', 'https://drive.google.com/file/d/1IRApdbhRxaryb9TOYjys-rnYG_6KEJTR/view?usp=sharing', '', '', '', FALSE),
  (1782118804501, 'UNFPA', 'Medium Animation', '2025', 'Animation', 'https://drive.google.com/file/d/15JbefNuVujbfMpfrpKSZ4U73-bEVA-Sl/view?usp=sharing', '', '', '', FALSE),
  (1782118726900, 'MOC 02', 'Medium Animation', '2022', 'Animation', 'https://drive.google.com/file/d/1m8i0hPOhFBPLqrNm1H73AAZJbgCEBvAq/view?usp=sharing', '', '', '', FALSE),
  (1782118694411, 'MOC 01', 'Medium Animation', '2022', 'Animation', 'https://drive.google.com/file/d/1KqqMAaa-70ftsKkxlvZrRdo8lDY01j8s/view?usp=sharing', '', '', '', FALSE),
  (1782118442056, 'NBE - bank abbreviations', 'Basic Animation', '2022', 'Animation', 'https://drive.google.com/file/d/1AfSZqAFWKqiDw3WCBzoKnna0NirTWsW4/view?usp=sharing', '', '', '', FALSE),
  (1782118384548, 'NBE - Banking terms', 'Basic Animation', '2022', 'Animation', 'https://drive.google.com/file/d/1YrI4rZBAHO_mbAqxZMoMNZYU5fGLi7n2/view?usp=sharing', '', '', '', FALSE),
  (1782118259101, 'NBE - essential English sound pronunciation', 'Basic Animation', '2022', 'Animation', 'https://drive.google.com/file/d/1hf4uUC89cyLd1a46P3Gbw0KJtcLmrJ82/view?usp=sharing', '', '', '', FALSE),
  (1782118190265, 'NBE - everyday english expression', 'Basic Animation', '2022', 'Animation', 'https://drive.google.com/file/d/1grriEX72LJ0OM10LxV4ESc0Oa5oLPCHM/view?usp=sharing', '', '', '', FALSE),
  (1782118038676, 'NBE  E-mail writing', 'Basic Animation', '2022', 'Animation', 'https://drive.google.com/file/d/1n1pUGlAMrs13cCRGtbaj-4PjIdPEsoE3/view?usp=sharing', '', '', '', FALSE),
  (1782117825632, 'Teaser sana oula sho3''l', 'Promos', '2022', 'Promo', 'https://drive.google.com/file/d/1MJQDf-UKl7z9NvkDQytblDtm7i8h7Psr/view?usp=sharing', '', '', '', FALSE),
  (1782117730335, 'Ahmed Amin story hessas masr', 'Showreel', '2022', 'Reel', 'https://drive.google.com/file/d/1XWJ6QjJiSp4O3jNVFewE7H6vavA_xhGM/view?usp=sharing', '', '', '', FALSE),
  (1782117603889, 'Almentor Business promo saudi version', 'Showreel', '2023', 'Product Video', 'https://drive.google.com/file/d/1dsVcfqLOYT53iBEXFNAph5wqVQT2CxfH/view?usp=sharing', '', '', '', FALSE),
  (1782117092854, 'mawada promo', 'Promos', '2021', 'Promo', 'https://drive.google.com/file/d/1xMHZ-kYF8NkMZkuQv5FtCb_ZHK2zWyDL/view?usp=sharing', '', '', '', FALSE),
  (1782116955863, 'Promo Khaled ElSawy', 'Promos', '2021', 'Promo', 'https://drive.google.com/file/d/1pZYhnuH9idBWuLLzX-9MGNNIX157V7yP/view?usp=sharing', '', '', '', FALSE),
  (1782116807637, 'saudi genaric promo', 'Showreel', '2025', 'Promo', 'https://drive.google.com/file/d/1MF-CgVZnXRMNgK401aamY3iEnhN8MPTn/view?usp=sharing', '', '', '', FALSE),
  (1782116582563, 'Podcast sally & mahmoud promo', 'Promos', '2025', 'Promo', 'https://drive.google.com/file/d/1d5Z5bNIZpFP12ThWZNQ6Xv0U150TbLCo/view?usp=sharing', '', '', '', FALSE),
  (1782116283281, 'collected promos for events', 'Showreel', '2024', 'Promo', 'https://drive.google.com/file/d/1phfkVHxdYxAUOrAfmLY1CjrrEou9n0eR/view?usp=sharing', '', '', '', FALSE),
  (1782116193316, 'Mostafa Hosny promo', 'Promos', '2021', 'Promo', 'https://drive.google.com/file/d/1fwSEB7PnbY3RWSaA6ck2SEw7Wynjgl9H/view?usp=sharing', '', '', '', FALSE),
  (1782116095902, 'mawada showreel', 'Promos', '2021', 'Promo', 'https://drive.google.com/file/d/1tuHQc9n3OyADssObmlRoOExBX3U8ktPI/view?usp=sharing', '', '', '', FALSE),
  (1782116005969, 'Ahmed gamal M2amat promo', 'Promos', '2021', 'Promo', 'https://drive.google.com/file/d/1fPaCYEhJc24qOmj-k1Pqt_4vekOX099i/view?usp=sharing', '', '', '', FALSE),
  (1782115601460, 'Making khaled el Sawy', 'Promos', '2021', 'Promo', 'https://drive.google.com/file/d/1P0kuSCzHbCcP92ECO9fmpQIUyq8MrtRq/view?usp=sharing', '', '', '', FALSE),
  (1782113281787, 'Making Hameed elsha3ery', 'Promos', '2024', 'Promo', '#', '', '', '', FALSE),
  (1782113192085, 'Learner experience with almentor', 'Showreel', '2020', 'Promo', 'https://drive.google.com/file/d/1JTjpsOATgKKKrThHM5_JjvJtMYIVRwe9/view?usp=drive_link', '', '', '', FALSE),
  (1782113114724, 'Book promo', 'Promos', '2021', 'Promo', 'https://drive.google.com/file/d/1OcCPS5gmHTRGzEM9TJC4zur8HeWPhuWY/view?usp=drive_link', '', '', '', FALSE),
  (1782113035654, 'hesas masr AD', 'Showreel', '2022', 'Promo', 'https://drive.google.com/file/d/1N6JtCjsvXvY-KrZXvjgXTP1DszdsFG2S/view?usp=drive_link', '', '', '', FALSE),
  (1782112986011, 'Hamed elsha3ery', 'Promos', '2023', 'Promo', 'https://drive.google.com/file/d/1kThhK4-4A03wGUav_xnoBk9m-9XEes1I/view?usp=sharing', '', '', '', FALSE),
  (1782112703939, 'GIA AI animation', 'Advanced Animation', '2024', 'Animation', 'https://drive.google.com/file/d/1IdN3OZUb8cy41HOegkaQIUcXcGwD4r2v/view?usp=drive_link', '', '', '', FALSE),
  (1782112638203, 'ALmentor at vox cinema', 'Showreel', '2022', 'Product Video', 'https://drive.google.com/file/d/1H_3YUjGapJAVfBZ5P_KUJ2PHDo0zH9zu/view?usp=sharing', '', '', '', FALSE),
  (1782112258734, 'GIZ animation', 'Medium Animation', '2025', 'Animation', 'https://drive.google.com/file/d/13cDT6k48Rh5YqYJuRd-xbqiLkahnqKfh/view?usp=sharing', '', '', '', FALSE),
  (1782110673376, 'Financial academy', 'Advanced Drama', '2025', '', 'https://drive.google.com/file/d/1bODHgoTlY3HCLOLz6O1FSnnoGR-gDe9M/view?usp=sharing', '', '', '', FALSE),
  (1782110634870, 'Mawada Drama', 'Advanced Drama', '2018', 'Product Video', 'https://drive.google.com/file/d/1-KnBeuR5I3LC-PYTCH4bY3QMYtkj155I/view?usp=sharing', '', '', '', FALSE),
  (1782110580086, 'Almentor AD Designing', 'Showreel', '2023', 'Promo', 'https://drive.google.com/file/d/1cDyF1lAAFM2AiCD1IV24IoEAcyWCYy7w/view?usp=sharing', '', '', '', FALSE),
  (1782042874302, 'Drama Mawada _cooperative', 'Advanced Drama', '2019', '', 'https://drive.google.com/file/d/1-KnBeuR5I3LC-PYTCH4bY3QMYtkj155I/view?usp=sharing', '', '', '', FALSE),
  (1782042803868, 'photoshop Add', 'Showreel', '2024', '', 'https://drive.google.com/file/d/1cDyF1lAAFM2AiCD1IV24IoEAcyWCYy7w/view?usp=sharing', '', '', '', FALSE),
  (1782042734516, 'cover promo', 'Showreel', '2025', '', 'https://drive.google.com/file/d/1wWrj24dt-TiGhtRsw96SzDSR9idrHd8f/view?usp=sharing', '', '', '', FALSE),
  (1782042686820, 'Nesma Mahgpub Makeing', 'Promos', '2026', '', 'https://drive.google.com/file/d/1omfu2Y8l0hnx0RMCx_eJCDe1_kYwGjD5/view?usp=sharing', '', '', '', FALSE),
  (1782042565182, 'showreel almentor', 'Showreel', '2024', '', 'https://drive.google.com/file/d/1Ke1YkPDgWlWyBKLPYze2E2FEhwld2wZI/view?usp=sharing', '', '', '', FALSE),
  (1782042461953, 'b2b bundles', 'Advanced Animation', '2024', '', 'https://drive.google.com/file/d/11mNX3h_1DBB56y7uSIOlUONa18hBv49_/view?usp=sharing', '', '', '', FALSE),
  (1782042282297, 'Zahi Hawas', 'Instructor Led', '2025', '', 'https://drive.google.com/file/d/1jDZNkxpuFBzE8-x8-tjx-u0NinEsdg2l/view?usp=sharing', '', '', '', FALSE),
  (1782042188956, 'Cinematic Lighting Masterclass-Ayman Abouelmakarem', 'Promos', '2024', '', 'https://drive.google.com/file/d/1IABjdknoRd1mMohf0PAv3A3uglzKVioQ/view?usp=sharing', '', '', '', FALSE),
  (1782042005744, 'AHMED Gamal song', 'Medium Drama', '2024', '', 'https://drive.google.com/file/d/1pKmrQJwa3Eq5SgfLq7xgbZ9Lq36DC_BI/view?usp=sharing', '', '', '', FALSE),
  (1782041907307, 'Ahmed Amin - Hesas Masr Add', 'Advanced Drama', '2024', '', 'https://drive.google.com/file/d/1KQI2XZ37UMqjQkrKPnAauc0ezyAwFZ_w/view?usp=sharing', '', '', '', FALSE),
  (1782041810333, 'GIZ 2', 'Medium Animation', '2026', 'Animation', 'https://drive.google.com/file/d/1hTxoRqf5lsgLiV-6keIJiQi1o9s9qnRE/view?usp=sharing', '', '', '', FALSE),
  (1782041763949, 'Cover promo 2', 'Showreel', '2024', '', 'https://drive.google.com/file/d/1Saxue_an9U5Nv-BvjdjIwvWjCzkaru7a/view?usp=sharing', '', '', '', FALSE),
  (1782041720927, 'Ahmed Gamal', 'Instructor Led', '2024', '', 'https://drive.google.com/file/d/1UF8gRQ36hOUgAmF-sqxkECo5rlHVhjDY/view?usp=sharing', '', '', '', FALSE),
  (1782041638833, 'GIZ', 'Medium Animation', '2026', 'Animation', 'https://drive.google.com/file/d/17jbrgkeA-rx0FCEqcsp4nTuPEwClOjby/view?usp=sharing', '', '', '', FALSE),
  (1782041563556, 'MOE', 'Instructor Led', '2025', '', 'https://drive.google.com/file/d/1OcFlcf6Raozw2mc7gm7RGDsadyM_KEn7/view?usp=sharing', '', '', '', FALSE),
  (1782040062870, 'Maged El Ghamdy', 'Instructor Led', '2025', '', 'https://drive.google.com/file/d/1tFJi6xOVJnF1m4RVGYDRBcogGDacfnrg/view?usp=sharing', '', '', '', FALSE),
  (1782039954275, 'POMO 1', 'Showreel', '2024', '', 'https://drive.google.com/file/d/1LgLznAraQXrZS9Q-M8FG7xPBECMbJfgP/view?usp=sharing', '', '', '', FALSE),
  (1782039891476, 'GCA 2', 'Instructor Led', '2025', '', 'https://drive.google.com/file/d/1wx_hWdwt74TIsHrBKV6DqHf8oxdzNU8Z/view?usp=sharing', '', '', '', FALSE),
  (1782039735020, 'GCA', 'Instructor Led', '2025', '', 'https://drive.google.com/file/d/1irIbarq3KWeRX39oIpLpDYD92Y58Qqgc/view?usp=sharing', '', '', '', FALSE),
  (1782038402243, 'Abdulah ELhoty', 'Instructor Led', '2025', '', 'https://drive.google.com/file/d/1-8fCcJK3I6BkZwBjV2QHuWFTZAQLqArS/view?usp=sharing', '', '', '', FALSE),
  (1781606300015, 'Almentor AD (AI)', 'AI Videos', '2025', 'Product Video', 'https://drive.google.com/file/d/1KnNr1P4FkSjebyOA3hK9rmWsPB_dyyXy/view?usp=drive_link', '', '', '', FALSE),
  (1781606233685, 'Almentor Scenes', 'AI Videos', '2026', 'Product Video', 'https://drive.google.com/file/d/1w_YUCFxBDPpD6nWgE3at5y-8bJUY6lb0/view?usp=drive_link', '', '', '', FALSE),
  (1781606144498, 'Ziad Alaa Eldin', 'Promos', '2024', 'Promo', 'https://drive.google.com/file/d/1QlJeQ_zU86QkyOczuITofH_uM6vwjgng/view?usp=drive_link', '', '', '', FALSE),
  (1781606091723, 'Ramy Elsonbaty', 'Promos', '2024', 'Promo', 'https://drive.google.com/file/d/1a-iJ7NIne0sStAQLQuRegoDo0529rzOF/view?usp=drive_link', '', '', '', FALSE),
  (1781606061510, 'Zahi Hawas', 'Promos', '2023', 'Promo', 'https://drive.google.com/file/d/1VA_MgINBlDAyOqx-Hd4mww0hOuH28ZT4/view?usp=drive_link', '', '', '', FALSE),
  (1781606032227, 'Khaled eldesoky - Emotional Intelligence', 'Promos', '2025', 'Promo', 'https://drive.google.com/file/d/1vvq-O98rhE0xtYa9L_8qyLIjKpJqrDl1/view?usp=drive_link', '', '', '', FALSE),
  (1781605993596, 'Mohamed Farag', 'Promos', '2020', 'Promo', 'https://drive.google.com/file/d/1jJlhHjdBneNJkjsPqNvPCurB_dS9AZMp/view?usp=drive_link', '', '', '', FALSE),
  (1781605958619, 'Murad Makram', 'Promos', '2026', 'Promo', 'https://drive.google.com/file/d/1sU2SVSEFmwOW7lDQiSz8nz_bGg1J5nEB/view?usp=drive_link', '', '', '', FALSE),
  (1781605871353, 'Ihab Fikry - 100 managment concept', 'Promos', '2018', 'Promo', 'https://drive.google.com/file/d/1ucDxOhD9dJ01kdUcGFu0YK8pYR9iXKmR/view?usp=drive_link', '', '', '', FALSE),
  (1781605838167, 'Loay Hesham - AI for marketing', 'Promos', '2025', 'Promo', 'https://drive.google.com/file/d/1UzU675kEg6Zn3oqyi3adXdwhRDtl0Vh-/view?usp=drive_link', '', '', '', FALSE),
  (1781605798994, 'Abdallah Salam - waste your time', 'Promos', '2025', 'Promo', 'https://drive.google.com/file/d/135UUlqsvkYo0ZgyDLeFw9QvuN3Js9TDn/view?usp=drive_link', '', '', '', FALSE),
  (1781605759192, 'Cilmate change', 'Promos', '2025', 'Promo', 'https://drive.google.com/file/d/1rb7NMVWHEcgf3y5EkoiiI9iHj4y_ZDeI/view?usp=drive_link', '', '', '', FALSE),
  (1781605696721, 'Ahmed Gamal', 'Promos', '2022', 'Promo', 'https://drive.google.com/file/d/11FBuD6LA0_KxvwZaorr8kPkwSHAlEnK-/view?usp=drive_link', '', '', '', FALSE),
  (1781605664073, 'Almed El-awaar - Lifecoaching', 'Promos', '2018', 'Promo', 'https://drive.google.com/file/d/1tjHSQwzf5eBpBj-XocLrjfy1ra6nfrbe/view?usp=drive_link', '', '', '', FALSE),
  (1781605629366, 'Abdallah Salam', 'Promos', '2025', 'Promo', 'https://drive.google.com/file/d/1I3nWU_y3qAJgbGOJZF6eveE-Y8oNgEhq/view?usp=drive_link', '', '', '', FALSE),
  (1781530870801, 'تعليمية ٤', 'AI Videos', '2025', '', 'https://drive.google.com/file/d/1-ziksrHjf8R1BYwQ7UHbuqgFXdU2Uc0Q/view?usp=drive_link', '', '', '', FALSE),
  (1781530851983, 'تعليمية ٣', 'AI Videos', '2025', '', 'https://drive.google.com/file/d/1jX-aKsjez1ZnypwYXUv2c26NV6zD-dHS/view?usp=drive_link', '', '', '', FALSE),
  (1781530828433, 'تعليمية ٢', 'AI Videos', '2025', '', 'https://drive.google.com/file/d/1iIzVhYBFCPVYSHHIaMkJK6rJiEiFl_lH/view?usp=drive_link', '', '', '', FALSE),
  (1781530785357, 'تعليمية', 'AI Videos', '2025', 'Product Video', 'https://drive.google.com/file/d/1zZ50pZIjPlFpLnNfWrteEVGRwD2AzH63/view?usp=drive_link', '', '', '', FALSE),
  (1781530753666, 'NBO 2', 'AI Videos', '2026', 'Product Video', 'https://drive.google.com/file/d/1LuX1RYkhs2Y9-8Owb5hDvpBmobvznbgo/view?usp=drive_link', '', '', '', FALSE),
  (1781530729857, 'NBO', 'AI Videos', '2026', 'Product Video', 'https://drive.google.com/file/d/1-G0GBWof2-2VrXMrw4VByh7UM86s9Npv/view?usp=drive_link', '', '', '', FALSE),
  (1781530682273, 'Mofa3', 'AI Videos', '2025', 'Product Video', 'https://drive.google.com/file/d/18J2UCUkdPj2HyttjGUxALjFZbVJwxWow/view?usp=drive_link', '', '', '', FALSE),
  (1781530636599, 'Mofa', 'AI Videos', '2025', 'Product Video', 'https://drive.google.com/file/d/1KqLsL7RvxXSvx-BmsJS6RZBk2waO2ULU/view?usp=drive_link', '', '', '', FALSE),
  (1781528904310, 'Mofa', 'AI Videos', '2025', 'Product Video', 'https://drive.google.com/file/d/1AedPVheTNa-8y5NlUFJy2F7Xdxx5YDiY/view?usp=drive_link', '', '', '', FALSE),
  (1781528863267, 'MOE - Cartoon character 2', 'AI Videos', '2026', 'Product Video', 'https://drive.google.com/file/d/1w6n_skXthD2-e6xAIPXGIkuXqyRzqilX/view?usp=drive_link', '', '', '', FALSE),
  (1781528817525, 'MOE - Cartoon character', 'AI Videos', '2026', 'Product Video', 'https://drive.google.com/file/d/1odY4Wc2HwYRCUw-Pb6keo001L43Adv0-/view?usp=drive_link', '', '', '', FALSE),
  (1781528771738, 'Mawada', 'AI Videos', '2025', 'Product Video', 'https://drive.google.com/file/d/1o_E3UZY4eFiEA3UiXT38e1EZPsGxzLUm/view?usp=drive_link', '', '', '', FALSE),
  (1781521696250, 'NBE Project ++', 'Advanced Animation', '2023', 'Animation', 'https://drive.google.com/file/d/1EYVd8eXLormZOJrpg38vyD9ySskWl5Va/view?usp=drive_link', '', '', '', TRUE),
  (1781521620819, 'NBE project+', 'Advanced Animation', '2023', 'Animation', 'https://drive.google.com/file/d/15J0AXmC81tVxpgNZCADrc1vFcwyFzPBI/view?usp=drive_link', '', '', '', TRUE),
  (1781519723236, 'NBE project', 'Advanced Animation', '2023', 'Animation', 'https://drive.google.com/file/d/1ibo8nHSjdbQnZAPrfzsyBMV6hSx7NF9e/view?usp=drive_link', '', '', '', TRUE),
  (1781519553631, 'Almentor AD (Engilsh Version)', 'Showreel', '2023', 'Product Video', 'https://drive.google.com/file/d/1riY1j9UO8sTKJFtcLgbyZxfxipBD_3En/view?usp=drive_link', '', '', '', FALSE),
  (1781519503383, 'Almentor AD (Saudi Version)', 'Showreel', '2023', 'Product Video', 'https://drive.google.com/file/d/1BUsU9qngF_Dx_-l5xrICi-IDniQ0ZWc4/view?usp=drive_link', '', '', '', TRUE),
  (1781519405913, 'Almentor AD (Arabic Version)', 'Showreel', '2023', 'Product Video', 'https://drive.google.com/file/d/1rMvPgQX1qrocsn-LX9baAzcYUdxGI4r2/view?usp=drive_link', '', '', '', TRUE),
  (1781518517714, 'Almentor Showreel', 'Showreel', '2022', 'Product Video', 'https://drive.google.com/file/d/1JjqiIvJ2K4LO9f4EOhFYa_EN7GFMCvqj/view?usp=sharing', '', '', '', TRUE),
  (1781514081885, 'Drama FA', 'Medium Drama', '2025', 'Product Video', 'https://drive.google.com/file/d/16JAkLst5Q026gv9TG0-STBZ0gZzExAgg/view?usp=sharing', 'https://drive.google.com/file/d/16JAkLst5Q026gv9TG0-STBZ0gZzExAgg/view?usp=sharing', '', '', TRUE),
  (1780832481432, 'promo tamken', 'Promos', '2024', 'Promo', 'https://drive.google.com/file/d/1pvldkLu4SNQO8Igsd1RoOyuIdmhnksth/view?usp=sharing', '', 'مشروع عمان، برومو', '', TRUE),
  (1, 'Basic Animation – Time Management Course', 'Basic Animation', '2025', 'Tutorial', '#', '', 'education,time management,soft skills', 'Animated explainer for time management fundamentals', TRUE),
  (3, 'Instructor Led – Leadership Course', 'Instructor Led', '2025', 'Corporate Film', '#', '', 'education,leadership', 'On-camera instructor delivering leadership training', TRUE),
  (6, 'Motion Graphics – Real Estate App Promo', 'Motion Graphics', '2025', 'Promo', '#', '', 'real estate,app,motion', 'Animated promo for a real estate mobile app', TRUE),
  (7, 'Medium Animation – SaaS Product Explainer', 'Medium Animation', '2024', 'Product Video', '#', '', 'tech,saas,explainer', 'Product explainer animation for SaaS platform', FALSE),
  (10, 'Instructor Led – Digital Marketing Course', 'Instructor Led', '2023', 'Tutorial', '#', '', 'education,digital marketing', 'Full course with on-camera marketing instructor', TRUE),
  (11, 'Motion Graphics – Logo Animation', 'Motion Graphics', '2023', 'Animation', '#', '', 'branding,logo,intro', 'Brand logo reveal animation', FALSE);

-- ============================================================
-- BOOTSTRAP — run AFTER your first magic-link sign-in:
-- Replace the email then run these two statements.
-- ============================================================
--
-- insert into allowed_emails (email, note) values
--   ('your-email@almentor.com', 'Founding admin');
--
-- insert into admins (user_id, email)
--   select id, email from auth.users
--   where lower(email) = lower('your-email@almentor.com');
--
-- After that, you can manage other team emails from the admin UI.
-- ============================================================
