-- ════════════════════════════════════════════════════════
-- 오운완 - 시즌 2를 8주 → 12주로 연장 (2026-11-11)
-- Supabase → SQL Editor 를 비우고 통째로 붙여넣고 RUN.
--
-- 시즌 생성 때 8주로 잘못 설정한 것을 12주로 바로잡는다.
-- start_new_season 을 쓰면 기록이 지워지므로 쓰지 않고, total_weeks 만 바꾼다.
-- 1~8주 인증·주차기록·면제·레버리지·승인 기록은 week_no 기준이라 그대로 유지되고,
-- 앱은 groups.total_weeks 를 읽어 주차를 계산하므로 코드 수정 없이 9주차부터 이어진다.
-- (시즌 종료 잠금은 '마지막 주 마감이 지났는가'로 판정 → 12주 마감 12/7 08:00 까지 해제)
-- ════════════════════════════════════════════════════════

-- season_no = 2 조건: 혹시 그새 새 시즌이 시작됐다면 아무것도 바꾸지 않음
update public.groups
   set total_weeks = 12
 where id = '694bc3ab-8061-43ce-a993-808a1cb899f4'
   and season_no = 2;

-- 확인 — total_weeks 가 12 로 나오면 정상
select name, season_no, season_start, total_weeks from public.groups;
