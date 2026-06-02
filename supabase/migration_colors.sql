-- ════════════════════════════════════════════════════════
-- 멤버 고정 색상 마이그레이션 (데이터 보존 — drop 없음)
-- SQL Editor에 통째로 붙여넣고 RUN.
-- ════════════════════════════════════════════════════════

-- 1) color 컬럼 추가
alter table public.memberships add column if not exists color text;

-- 2) 가입 시 색 배정 함수 (그룹 내 미사용 색 무작위, 다 차면 무작위 재사용)
create or replace function public.pick_color(g uuid) returns text
language sql security definer set search_path=public as $$
  with pal(c) as (values ('#ef5350'),('#ec407a'),('#ab47bc'),('#7e57c2'),('#5c6bc0'),
    ('#42a5f5'),('#29b6f6'),('#26c6da'),('#26a69a'),('#66bb6a'),('#9ccc65'),('#d4e157'),
    ('#ffca28'),('#ffa726'),('#ff7043'))
  select coalesce(
    (select c from pal where c not in (select color from public.memberships where group_id=g and color is not null) order by random() limit 1),
    (select c from pal order by random() limit 1));
$$;

-- 3) 가입/생성 RPC가 색을 배정하도록 갱신
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

-- 4) 기존 멤버 백필 — 그룹별로 서로 다른 색을 흩뿌려 배정 (7칸 간격, 15색이라 안 겹침)
update public.memberships m set color = sub.c
from (
  select id,
    (array['#ef5350','#ec407a','#ab47bc','#7e57c2','#5c6bc0','#42a5f5','#29b6f6','#26c6da',
           '#26a69a','#66bb6a','#9ccc65','#d4e157','#ffca28','#ffa726','#ff7043'])
      [ ((((row_number() over (partition by group_id order by joined_at)) - 1) * 7) % 15) + 1 ] as c
  from public.memberships
) sub
where m.id = sub.id and m.color is null;
