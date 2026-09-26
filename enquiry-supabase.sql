-- NavMe museum enquiries: storage for enquiry.html
-- Applied to project znfwcohrpkiccibqcfpn as migration "inquiry_museum_enquiries".
-- enquiry.html calls:
--   ENDPOINT = "https://znfwcohrpkiccibqcfpn.supabase.co/rest/v1/rpc/inquiry_save_enquiry"
--   HEADERS  = {"Content-Type":"application/json", apikey:"<publishable key>"}
--
-- The page can only call inquiry_save_enquiry(). It cannot read, list or delete
-- rows, so the public key in the page gives nothing away. View the data in
-- the Supabase table editor, or export it as CSV from there.

create table if not exists public.inquiry_museum_enquiries (
  id               uuid primary key,
  status           text not null default 'draft' check (status in ('draft','complete')),
  device           text,
  event            text,
  source           text,

  -- contact
  museum           text,
  contact_name     text,
  contact_role     text,
  email            text,
  consent_findings boolean not null default false,
  consent_contact  boolean not null default false,

  -- the nine questions
  site             text,     -- Q1 kind of museum
  site_detail      text,     --    "Other" text
  org_type         text,     -- Q2 how it is run
  visitors         text,     -- Q3 visitors a year
  pain             text[],   -- Q4 what visitors struggle with (multi)
  wayfinding_today text[],   -- Q5 how they help today (multi)
  biggest_value    text,     -- Q6 biggest difference
  timing           text,     -- Q7 when live
  timing_detail    text,     --    opening / milestone date
  next_step        text,     -- Q8 best next step
  more             text,     -- Q9 free text

  -- staff-only (?staff=1)
  staff_spoke_with text,
  staff_warmth     text,
  staff_notes      text,

  started_at       timestamptz,
  updated_at       timestamptz not null,
  submitted_at     timestamptz,
  received_at      timestamptz not null default now(),
  payload          jsonb not null
);

comment on table public.inquiry_museum_enquiries is
  'Museum enquiry form (inquiry.navme.space). One row per visit, saved as a draft while filled in, then complete. Written only via inquiry_save_enquiry().';

create index if not exists inquiry_museum_enquiries_updated_idx on public.inquiry_museum_enquiries (updated_at desc);
create index if not exists inquiry_museum_enquiries_status_idx  on public.inquiry_museum_enquiries (status);

-- RLS on with no policies: the public key cannot touch the table directly.
alter table public.inquiry_museum_enquiries enable row level security;

create or replace function public.inquiry_save_enquiry(rec jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  a jsonb := coalesce(rec->'answers', '{}'::jsonb);
begin
  if jsonb_typeof(rec) <> 'object' or rec->>'id' is null then
    raise exception 'record needs an id';
  end if;
  if length(rec::text) > 20000 then
    raise exception 'record too large';
  end if;

  insert into inquiry_museum_enquiries as m
    (id, status, device, event, source,
     museum, contact_name, contact_role, email, consent_findings, consent_contact,
     site, site_detail, org_type, visitors, pain, wayfinding_today,
     biggest_value, timing, timing_detail, next_step, more,
     staff_spoke_with, staff_warmth, staff_notes,
     started_at, updated_at, submitted_at, payload)
  values
    ((rec->>'id')::uuid,
     case when rec->>'status' = 'complete' then 'complete' else 'draft' end,
     left(rec->>'device', 60),
     left(rec->>'event', 120),
     left(rec->>'source', 120),
     left(nullif(rec#>>'{contact,museum}', ''), 200),
     left(nullif(rec#>>'{contact,name}', ''), 200),
     left(nullif(rec#>>'{contact,role}', ''), 200),
     left(nullif(rec#>>'{contact,email}', ''), 200),
     coalesce((rec#>>'{consent,findings}')::boolean, false),
     coalesce((rec#>>'{consent,contact}')::boolean, false),
     -- single answers are a string, or {answer, detail} when a detail box was filled
     left(case when jsonb_typeof(a->'site') = 'object' then a#>>'{site,answer}' else a->>'site' end, 200),
     left(a#>>'{site,detail}', 500),
     left(a->>'orgtype', 200),
     left(a->>'visitors', 200),
     case when jsonb_typeof(a->'pain') = 'array'
          then array(select left(x, 200) from jsonb_array_elements_text(a->'pain') x) end,
     case when jsonb_typeof(a->'today') = 'array'
          then array(select left(x, 200) from jsonb_array_elements_text(a->'today') x) end,
     left(a->>'value', 200),
     left(case when jsonb_typeof(a->'timing') = 'object' then a#>>'{timing,answer}' else a->>'timing' end, 200),
     left(a#>>'{timing,detail}', 500),
     left(a->>'next', 200),
     left(a->>'more', 5000),
     left(nullif(rec#>>'{stand,spokeWith}', ''), 200),
     left(rec#>>'{stand,warmth}', 200),
     left(nullif(rec#>>'{stand,notes}', ''), 5000),
     (rec->>'startedAt')::timestamptz,
     coalesce((rec->>'updatedAt')::timestamptz, now()),
     (rec->>'submittedAt')::timestamptz,
     rec)
  on conflict (id) do update set
    -- a finished entry never goes back to draft
    status           = case when m.status = 'complete' then 'complete' else excluded.status end,
    device           = excluded.device,
    event            = excluded.event,
    source           = excluded.source,
    museum           = excluded.museum,
    contact_name     = excluded.contact_name,
    contact_role     = excluded.contact_role,
    email            = excluded.email,
    consent_findings = excluded.consent_findings,
    consent_contact  = excluded.consent_contact,
    site             = excluded.site,
    site_detail      = excluded.site_detail,
    org_type         = excluded.org_type,
    visitors         = excluded.visitors,
    pain             = excluded.pain,
    wayfinding_today = excluded.wayfinding_today,
    biggest_value    = excluded.biggest_value,
    timing           = excluded.timing,
    timing_detail    = excluded.timing_detail,
    next_step        = excluded.next_step,
    more             = excluded.more,
    staff_spoke_with = excluded.staff_spoke_with,
    staff_warmth     = excluded.staff_warmth,
    staff_notes      = excluded.staff_notes,
    started_at       = coalesce(m.started_at, excluded.started_at),
    updated_at       = excluded.updated_at,
    submitted_at     = coalesce(excluded.submitted_at, m.submitted_at),
    payload          = excluded.payload,
    received_at      = now()
  -- ignore a late-arriving older copy of the same entry
  where excluded.updated_at >= m.updated_at;
end;
$$;

revoke all on function public.inquiry_save_enquiry(jsonb) from public;
grant execute on function public.inquiry_save_enquiry(jsonb) to anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- Admin portal (admin.html). Applied as migration "inquiry_admin".
-- The admin password is stored only as a bcrypt hash. Every admin function
-- checks it first; nothing can be read without it. Change it from admin.html.
-- To reset a forgotten password, run in the SQL editor:
--   update inquiry_admin_config set password_hash = extensions.crypt('<new>', extensions.gen_salt('bf', 10)) where id = 1;

create table if not exists public.inquiry_admin_config (
  id            int primary key check (id = 1),
  password_hash text not null,
  updated_at    timestamptz not null default now()
);
alter table public.inquiry_admin_config enable row level security;
-- insert into public.inquiry_admin_config (id, password_hash)
--   values (1, extensions.crypt('<password>', extensions.gen_salt('bf', 10)));

create or replace function public.inquiry__check_admin(admin_password text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if admin_password is null or not exists (
    select 1 from inquiry_admin_config c
    where c.id = 1 and c.password_hash = crypt(admin_password, c.password_hash)
  ) then
    raise exception 'Invalid admin password' using errcode = '28P01';
  end if;
end; $$;
revoke all on function public.inquiry__check_admin(text) from public, anon, authenticated;

create or replace function public.inquiry_admin_login(admin_password text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
begin
  perform inquiry__check_admin(admin_password);
  return jsonb_build_object('ok', true);
end; $$;

create or replace function public.inquiry_admin_list(admin_password text)
returns setof public.inquiry_museum_enquiries
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform inquiry__check_admin(admin_password);
  return query select * from inquiry_museum_enquiries order by coalesce(submitted_at, updated_at) desc;
end; $$;

create or replace function public.inquiry_admin_delete(admin_password text, enquiry_id uuid)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  perform inquiry__check_admin(admin_password);
  delete from inquiry_museum_enquiries where id = enquiry_id;
end; $$;

create or replace function public.inquiry_admin_set_password(admin_password text, new_password text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  perform inquiry__check_admin(admin_password);
  if length(coalesce(new_password, '')) < 10 then
    raise exception 'New password must be at least 10 characters';
  end if;
  update inquiry_admin_config set password_hash = crypt(new_password, gen_salt('bf', 10)), updated_at = now() where id = 1;
end; $$;

revoke all on function public.inquiry_admin_login(text) from public;
revoke all on function public.inquiry_admin_list(text) from public;
revoke all on function public.inquiry_admin_delete(text, uuid) from public;
revoke all on function public.inquiry_admin_set_password(text, text) from public;
grant execute on function public.inquiry_admin_login(text) to anon, authenticated;
grant execute on function public.inquiry_admin_list(text) to anon, authenticated;
grant execute on function public.inquiry_admin_delete(text, uuid) to anon, authenticated;
grant execute on function public.inquiry_admin_set_password(text, text) to anon, authenticated;
