-- ════════════════════════════════════════════════════════
-- 오운완 - 시즌 1주차 설정(닉네임 / 주당 횟수) 1회 변경
-- Supabase → SQL Editor 에 통째로 붙여넣고 RUN. (멱등 — 다시 실행 가능)
--
-- 시즌 시작 후 1주차 동안, 멤버당 딱 1회 닉네임·주당 횟수를 바꿀 수 있게 함.
-- 닉네임은 Auth 이메일(nickToEmail)과 묶여 있어 클라이언트(auth.updateUser)에서 처리하고,
-- 여기서는 '주당 횟수 저장 + 1회 소진 도장'을 한 트랜잭션으로 처리한다.
-- ════════════════════════════════════════════════════════

-- ① 이번 시즌 설정을 마쳤는지 기록 (0 = 아직, n = 시즌 n에서 완료)
--    season_no 와 비교하는 방식이라 시즌이 바뀌면 자동으로 다시 열린다
--    → start_new_season 은 손댈 필요 없음
alter table public.memberships
  add column if not exists setup_season_no int not null default 0;

-- ② 시즌 설정 확정 RPC
--    · '이대로 갈래요'      → 현재 횟수를 그대로 넘겨 호출 (도장만 찍힘)
--    · '변경할래요 → 확인'  → 새 횟수로 호출
--    1회 제한·기간 제한을 서버에서 강제 (클라이언트 콘솔 우회 차단)
create or replace function public.season_setup(p_group_id uuid, p_goal int)
returns void language plpgsql security definer set search_path=public as $$
declare v_season int; v_start date; v_close timestamptz; v_mid uuid; v_done int;
begin
  if auth.uid() is null then raise exception '로그인이 필요합니다'; end if;
  if p_goal not in (3,4,5) then raise exception '주당 횟수는 3~5회만 가능합니다'; end if;

  select season_no, season_start into v_season, v_start
    from public.groups where id = p_group_id;
  if v_season is null then raise exception '그룹을 찾을 수 없습니다'; end if;

  -- 1주차 마감(시작일 +7일 월요일 08:00 KST) 전까지만 — 클라이언트 WEEK_CLOSE_MS 와 동일 기준
  v_close := (((v_start + 7)::timestamp + interval '8 hours') at time zone 'Asia/Seoul');
  if now() >= v_close then
    raise exception '1주차가 지나 설정을 변경할 수 없습니다';
  end if;

  select id, setup_season_no into v_mid, v_done
    from public.memberships where group_id = p_group_id and profile_id = auth.uid();
  if v_mid is null then raise exception '멤버가 아닙니다'; end if;
  if v_done = v_season then raise exception '이번 시즌 설정은 이미 완료했습니다'; end if;

  update public.memberships
     set weekly_goal = p_goal, setup_season_no = v_season
   where id = v_mid;
end; $$;

-- ③ (확인용) 현재 멤버별 상태 — setup_season_no 가 전원 0 이면 정상
select p.nickname, m.weekly_goal, m.setup_season_no, g.season_no
from public.memberships m
join public.profiles p on p.id = m.profile_id
join public.groups g   on g.id = m.group_id
order by m.joined_at;
