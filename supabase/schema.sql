-- ════════════════════════════════════════════════════════
-- 오운완 - 스키마 v2 (전체)
-- Supabase → SQL Editor 에 통째로 붙여넣고 RUN.
-- 다시 실행해도 되도록 drop 후 재생성합니다. (테스트 전 'DB 밀기' = 이 파일 재실행)
-- ════════════════════════════════════════════════════════

-- 깨끗하게 재생성
drop table if exists public.certification_approvals cascade;
drop table if exists public.certifications cascade;
drop table if exists public.exemptions cascade;
drop table if exists public.weekly_records cascade;
drop table if exists public.memberships cascade;
drop table if exists public.profiles cascade;
drop table if exists public.groups cascade;

-- ── 테이블 ───────────────────────────────────────────────
create table public.groups (
  id           uuid primary key default gen_random_uuid(),
  name         text not null,
  invite_code  text unique not null,
  capacity     int  not null default 8,
  season_no    int  not null default 1,
  season_start date not null,
  total_weeks  int  not null default 8,
  created_by   uuid references auth.users(id),
  created_at   timestamptz default now()
);

create table public.profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  nickname   text unique not null,
  created_at timestamptz default now()
);

create table public.memberships (
  id            uuid primary key default gen_random_uuid(),
  group_id      uuid not null references public.groups(id) on delete cascade,
  profile_id    uuid not null references public.profiles(id) on delete cascade,
  weekly_goal   int  not null default 4,        -- 주당 목표 (시즌마다 재설정)
  fine          int  not null default 0,        -- 누적 벌금 (표시 시 10만원 상한)
  is_admin      boolean not null default false, -- 방장 여부 (RPC로만 부여)
  leverage_left int  not null default 3,        -- 시즌당 남은 레버리지
  color         text,                           -- 가입 시 배정된 고정 아바타 색
  joined_at     timestamptz default now(),
  unique (group_id, profile_id)
);

create table public.weekly_records (
  id            uuid primary key default gen_random_uuid(),
  membership_id uuid not null references public.memberships(id) on delete cascade,
  week_no       int  not null,
  done_count    int  not null default 0,
  status        text not null default 'pending', -- pending|done|fail|exempt
  penalty       int  not null default 0,
  leveraged     boolean not null default false,  -- 이 주차에 레버리지 사용
  unique (membership_id, week_no)
);

create table public.exemptions (
  id            uuid primary key default gen_random_uuid(),
  membership_id uuid not null references public.memberships(id) on delete cascade,
  week_no       int  not null,
  created_by    uuid references auth.users(id),
  created_at    timestamptz default now(),
  unique (membership_id, week_no)
);

create table public.certifications (
  id            uuid primary key default gen_random_uuid(),
  membership_id uuid not null references public.memberships(id) on delete cascade,
  week_no       int  not null,
  photo_url     text,
  photo_type    text not null default 'photo',  -- photo(원본)|capture(캡쳐)
  capture_at    timestamptz,                     -- EXIF 촬영일시 (캡쳐면 null)
  memo          text,
  status        text not null default 'pending', -- pending|approved
  approvals     int  not null default 0,
  created_at    timestamptz default now()
);

create table public.certification_approvals (
  id              uuid primary key default gen_random_uuid(),
  certification_id uuid not null references public.certifications(id) on delete cascade,
  approver_id     uuid not null references public.profiles(id) on delete cascade,
  created_at      timestamptz default now(),
  unique (certification_id, approver_id)
);

-- ── 승인 수 집계 트리거 ──────────────────────────────────
create or replace function public.bump_approvals() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  update public.certifications c
     set approvals = (select count(*) from public.certification_approvals where certification_id = c.id),
         status    = case when (select count(*) from public.certification_approvals where certification_id = c.id) >= 2
                          then 'approved' else 'pending' end
   where c.id = coalesce(new.certification_id, old.certification_id);
  return null;
end; $$;
drop trigger if exists trg_bump_approvals on public.certification_approvals;
create trigger trg_bump_approvals
  after insert or delete on public.certification_approvals
  for each row execute function public.bump_approvals();

-- ── 권한 판별 헬퍼 (정책에서 사용) ───────────────────────
create or replace function public.is_member_of(g uuid) returns boolean
language sql security definer set search_path=public stable as $$
  select exists(select 1 from public.memberships m
                where m.group_id = g and m.profile_id = auth.uid());
$$;
create or replace function public.is_admin_of(g uuid) returns boolean
language sql security definer set search_path=public stable as $$
  select exists(select 1 from public.memberships m
                where m.group_id = g and m.profile_id = auth.uid() and m.is_admin);
$$;
create or replace function public.owns_membership(m uuid) returns boolean
language sql security definer set search_path=public stable as $$
  select exists(select 1 from public.memberships x
                where x.id = m and x.profile_id = auth.uid());
$$;

-- ── RLS ──────────────────────────────────────────────────
alter table public.groups                  enable row level security;
alter table public.profiles                enable row level security;
alter table public.memberships             enable row level security;
alter table public.weekly_records          enable row level security;
alter table public.exemptions              enable row level security;
alter table public.certifications          enable row level security;
alter table public.certification_approvals enable row level security;

-- groups: 누구나 읽기(초대코드 검증). 쓰기는 RPC(definer)만.
create policy groups_read on public.groups for select using (true);

-- profiles: 로그인 사용자 읽기 / 본인 것만 생성·수정
create policy profiles_read   on public.profiles for select using (auth.role()='authenticated');
create policy profiles_insert on public.profiles for insert with check (id = auth.uid());
create policy profiles_update on public.profiles for update using (id = auth.uid());

-- memberships: 로그인 사용자 읽기만. 생성·수정·삭제는 모두 RPC(definer) 경유
--   → is_admin 자기지정 불가 (클라이언트 직접 insert/update 차단)
create policy memberships_read on public.memberships for select using (auth.role()='authenticated');

-- weekly_records: 로그인 읽기 / 본인 멤버십 것만 쓰기
create policy wr_read   on public.weekly_records for select using (auth.role()='authenticated');
create policy wr_insert on public.weekly_records for insert with check (public.owns_membership(membership_id));
create policy wr_update on public.weekly_records for update using (public.owns_membership(membership_id));

-- certifications: 로그인 읽기 / 본인 멤버십 것만 생성
create policy cf_read   on public.certifications for select using (auth.role()='authenticated');
create policy cf_insert on public.certifications for insert with check (public.owns_membership(membership_id));
drop policy if exists cf_delete on public.certifications;
create policy cf_delete on public.certifications for delete using (public.owns_membership(membership_id));

-- approvals: 로그인 읽기 / 본인이 승인자일 때만 생성·삭제
create policy ca_read   on public.certification_approvals for select using (auth.role()='authenticated');
create policy ca_insert on public.certification_approvals for insert with check (approver_id = auth.uid());
create policy ca_delete on public.certification_approvals for delete using (approver_id = auth.uid());

-- exemptions: 로그인 읽기. 쓰기는 방장 RPC(definer)만.
create policy ex_read on public.exemptions for select using (auth.role()='authenticated');

-- ════════════════════════════════════════════════════════
-- RPC (모두 SECURITY DEFINER → RLS 우회하며 규칙은 내부에서 강제)
-- ════════════════════════════════════════════════════════

-- 초대코드 생성기: OWAN-XXXX-XXXX-XXXX (헷갈리는 0/O/1/I 제외)
create or replace function public.gen_invite_code() returns text
language plpgsql set search_path=public as $$
declare chars text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; s text := ''; i int;
begin
  for i in 1..12 loop
    s := s || substr(chars, floor(random()*length(chars))::int + 1, 1);
    if i = 4 or i = 8 then s := s || '-'; end if;
  end loop;
  return 'OWAN-' || s;
end; $$;

-- 가입 시 색 배정: 그룹 내 미사용 색을 무작위로 (다 차면 무작위 재사용)
create or replace function public.pick_color(g uuid) returns text
language sql security definer set search_path=public as $$
  with pal(c) as (values ('#ef5350'),('#ec407a'),('#ab47bc'),('#42a5f5'),('#26c6da'),
    ('#26a69a'),('#66bb6a'),('#9ccc65'),('#d4e157'),('#ffca28'),('#ffa726'),('#ff7043'),
    ('#a1887f'),('#ffffff'),('#212121'))
  select coalesce(
    (select c from pal where c not in (select color from public.memberships where group_id=g and color is not null) order by random() limit 1),
    (select c from pal order by random() limit 1));
$$;

-- 그룹 생성 → 생성자가 방장(is_admin=true)
create or replace function public.create_group(
  p_name text, p_nickname text, p_capacity int,
  p_season_start date, p_total_weeks int, p_goal int
) returns public.groups
language plpgsql security definer set search_path=public as $$
declare v_uid uuid := auth.uid(); v_code text; v_group public.groups;
begin
  if v_uid is null then raise exception '로그인이 필요합니다'; end if;
  insert into public.profiles(id, nickname) values (v_uid, p_nickname)
    on conflict (id) do update set nickname = excluded.nickname;
  loop
    v_code := public.gen_invite_code();
    exit when not exists(select 1 from public.groups where invite_code = v_code);
  end loop;
  insert into public.groups(name, invite_code, capacity, season_no, season_start, total_weeks, created_by)
    values (p_name, v_code, p_capacity, 1, p_season_start, p_total_weeks, v_uid)
    returning * into v_group;
  insert into public.memberships(group_id, profile_id, weekly_goal, is_admin, color)
    values (v_group.id, v_uid, p_goal, true, public.pick_color(v_group.id));
  return v_group;
end; $$;

-- 그룹 참여 → 초대코드·정원 검증, is_admin=false 강제
create or replace function public.join_group(p_code text, p_nickname text, p_goal int)
returns public.groups
language plpgsql security definer set search_path=public as $$
declare v_uid uuid := auth.uid(); v_group public.groups; v_count int;
begin
  if v_uid is null then raise exception '로그인이 필요합니다'; end if;
  select * into v_group from public.groups where invite_code = p_code;
  if not found then raise exception '유효하지 않은 초대코드입니다'; end if;
  select count(*) into v_count from public.memberships where group_id = v_group.id;
  if v_count >= v_group.capacity then raise exception '정원이 가득 찼습니다'; end if;
  insert into public.profiles(id, nickname) values (v_uid, p_nickname)
    on conflict (id) do update set nickname = excluded.nickname;
  insert into public.memberships(group_id, profile_id, weekly_goal, is_admin, color)
    values (v_group.id, v_uid, p_goal, false, public.pick_color(v_group.id))
    on conflict (group_id, profile_id) do nothing;
  return v_group;
end; $$;

-- 본인 시즌 목표 변경 (시즌 시작 시 목표 선택용)
create or replace function public.set_my_goal(p_group_id uuid, p_goal int)
returns void language plpgsql security definer set search_path=public as $$
begin
  update public.memberships set weekly_goal = p_goal
   where group_id = p_group_id and profile_id = auth.uid();
end; $$;

-- 레버리지 사용 (본인): 남은 횟수 -1 + 해당 주차 leveraged 표시
create or replace function public.use_leverage(p_group_id uuid, p_week_no int)
returns int language plpgsql security definer set search_path=public as $$
declare v_mid uuid; v_left int;
begin
  select id, leverage_left into v_mid, v_left from public.memberships
   where group_id=p_group_id and profile_id=auth.uid();
  if v_mid is null then raise exception '멤버가 아닙니다'; end if;
  if v_left <= 0 then raise exception '남은 레버리지가 없습니다'; end if;
  update public.memberships set leverage_left = leverage_left - 1 where id = v_mid;
  insert into public.weekly_records(membership_id, week_no, leveraged)
    values (v_mid, p_week_no, true)
    on conflict (membership_id, week_no) do update set leveraged = true;
  return v_left - 1;
end; $$;

-- 멤버 내보내기 (방장만)
create or replace function public.kick_member(p_membership_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare v_group uuid;
begin
  select group_id into v_group from public.memberships where id = p_membership_id;
  if not public.is_admin_of(v_group) then raise exception '방장만 가능합니다'; end if;
  delete from public.memberships where id = p_membership_id;
end; $$;

-- 정원 변경 (방장만)
create or replace function public.set_capacity(p_group_id uuid, p_capacity int)
returns void language plpgsql security definer set search_path=public as $$
declare v_count int;
begin
  if not public.is_admin_of(p_group_id) then raise exception '방장만 가능합니다'; end if;
  select count(*) into v_count from public.memberships where group_id = p_group_id;
  if p_capacity < v_count then raise exception '정원은 현재 인원보다 작을 수 없습니다'; end if;
  update public.groups set capacity = p_capacity where id = p_group_id;
end; $$;

-- 초대코드 재발급 (방장만)
create or replace function public.regenerate_code(p_group_id uuid)
returns text language plpgsql security definer set search_path=public as $$
declare v_code text;
begin
  if not public.is_admin_of(p_group_id) then raise exception '방장만 가능합니다'; end if;
  loop
    v_code := public.gen_invite_code();
    exit when not exists(select 1 from public.groups where invite_code = v_code);
  end loop;
  update public.groups set invite_code = v_code where id = p_group_id;
  return v_code;
end; $$;

-- 주차 면제 / 해제 (방장만)
create or replace function public.exempt_week(p_membership_id uuid, p_week_no int)
returns void language plpgsql security definer set search_path=public as $$
declare v_group uuid;
begin
  select group_id into v_group from public.memberships where id = p_membership_id;
  if not public.is_admin_of(v_group) then raise exception '방장만 가능합니다'; end if;
  insert into public.exemptions(membership_id, week_no, created_by)
    values (p_membership_id, p_week_no, auth.uid())
    on conflict (membership_id, week_no) do nothing;
  insert into public.weekly_records(membership_id, week_no, status)
    values (p_membership_id, p_week_no, 'exempt')
    on conflict (membership_id, week_no) do update set status='exempt';
end; $$;

create or replace function public.remove_exemption(p_membership_id uuid, p_week_no int)
returns void language plpgsql security definer set search_path=public as $$
declare v_group uuid;
begin
  select group_id into v_group from public.memberships where id = p_membership_id;
  if not public.is_admin_of(v_group) then raise exception '방장만 가능합니다'; end if;
  delete from public.exemptions where membership_id = p_membership_id and week_no = p_week_no;
  update public.weekly_records set status='pending'
    where membership_id = p_membership_id and week_no = p_week_no and status='exempt';
end; $$;

-- 새 시즌 시작 (방장만): 시즌번호+1, 날짜/주차 갱신, 멤버 시즌상태 초기화
create or replace function public.start_new_season(p_group_id uuid, p_season_start date, p_total_weeks int)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.is_admin_of(p_group_id) then raise exception '방장만 가능합니다'; end if;
  update public.groups
     set season_no = season_no + 1, season_start = p_season_start, total_weeks = p_total_weeks
   where id = p_group_id;
  -- 시즌 데이터 초기화 (계정·멤버십은 유지)
  delete from public.weekly_records w using public.memberships m
    where w.membership_id = m.id and m.group_id = p_group_id;
  delete from public.exemptions e using public.memberships m
    where e.membership_id = m.id and m.group_id = p_group_id;
  delete from public.certifications c using public.memberships m
    where c.membership_id = m.id and m.group_id = p_group_id;
  update public.memberships set fine = 0, leverage_left = 3 where group_id = p_group_id;
end; $$;
