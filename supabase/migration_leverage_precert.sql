-- ════════════════════════════════════════════════════════
-- 오운완 - 레버리지: 이번 주 첫 인증 전에만 사용 가능
-- Supabase → SQL Editor 에 붙여넣고 RUN. (CREATE OR REPLACE — 멱등, 안전)
--
-- 이번 주에 인증(대기·완료 무관)이 하나라도 있으면 use_leverage 차단.
-- (클라이언트도 동일 차단하지만, API 우회 방지용 DB-레벨 가드)
-- ════════════════════════════════════════════════════════

create or replace function public.use_leverage(p_group_id uuid, p_week_no int)
returns int language plpgsql security definer set search_path=public as $$
declare v_mid uuid; v_left int;
begin
  select id, leverage_left into v_mid, v_left from public.memberships
   where group_id=p_group_id and profile_id=auth.uid();
  if v_mid is null then raise exception '멤버가 아닙니다'; end if;
  if v_left <= 0 then raise exception '남은 레버리지가 없습니다'; end if;
  -- 이번 주 첫 인증 전에만 사용 가능 (대기 포함 인증이 하나라도 있으면 차단)
  if exists(select 1 from public.certifications where membership_id = v_mid and week_no = p_week_no) then
    raise exception '이번 주에 이미 인증이 있어 레버리지를 쓸 수 없습니다';
  end if;
  update public.memberships set leverage_left = leverage_left - 1 where id = v_mid;
  insert into public.weekly_records(membership_id, week_no, leveraged)
    values (v_mid, p_week_no, true)
    on conflict (membership_id, week_no) do update set leveraged = true;
  return v_left - 1;
end; $$;
