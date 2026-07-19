-- ════════════════════════════════════════════════════════
-- 오운완 - 같은 사진(같은 촬영시각) 중복 인증 방지 (DB 레벨)
-- Supabase → SQL Editor 에서 순서대로 실행.
--
-- 클라이언트가 더블탭을 막지만, 멀티기기·레이스 등 어떤 경우에도
-- 같은 (membership, capture_at) 인증이 2건 생기지 않도록 DB에서 강제.
-- ⚠️ 유니크 인덱스는 기존 중복이 남아있으면 생성 실패 → 반드시 ①정리 후 ②인덱스.
-- ════════════════════════════════════════════════════════

-- ① (확인) 현재 중복 그룹 보기
select membership_id, capture_at, count(*) as cnt
from public.certifications
where capture_at is not null
group by membership_id, capture_at
having count(*) > 1;

-- ② 중복 제거 — (membership, capture_at)별로 1건만 남김
--    남길 기준: 승인 많은 것 우선, 그다음 먼저 올린 것 (나머지 삭제, 승인기록 cascade)
with ranked as (
  select id,
    row_number() over (
      partition by membership_id, capture_at
      order by approvals desc, created_at asc
    ) as rn
  from public.certifications
  where capture_at is not null
)
delete from public.certifications
where id in (select id from ranked where rn > 1);

-- ③ 유니크 인덱스 — 이후로는 같은 사진(같은 촬영시각) 중복 insert 자체를 DB가 거부
--    (capture_at NULL = 메타없는 캡쳐는 대상 제외 → 여러 개 허용)
create unique index if not exists uniq_cert_membership_capture
on public.certifications (membership_id, capture_at)
where capture_at is not null;
