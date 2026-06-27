-- 오운완 - 인증 완료 승인 수 2명 -> 3명
-- Supabase SQL Editor에 붙여넣고 RUN. (CREATE OR REPLACE라 안전)
--
-- 승인 집계 트리거가 3명 이상이면 certifications.status를 approved로 바꾸도록 변경.
-- 클라이언트의 APPROVE_NEEDED=3 값과 반드시 일치해야 합니다.
-- 이미 2명으로 approved 처리된 기존 인증은 그대로 유지됩니다.

create or replace function public.bump_approvals() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  update public.certifications c
     set approvals = (select count(*) from public.certification_approvals where certification_id = c.id),
         status    = case when (select count(*) from public.certification_approvals where certification_id = c.id) >= 3
                          then 'approved' else 'pending' end
   where c.id = coalesce(new.certification_id, old.certification_id);
  return null;
end; $$;
