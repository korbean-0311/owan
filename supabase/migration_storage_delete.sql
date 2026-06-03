-- ════════════════════════════════════════════════════════
-- 오운완 - certs 버킷 DELETE 정책 (사진 파일 정리용)
-- Supabase → SQL Editor 에 붙여넣고 RUN. (멱등 — 다시 실행 가능)
--
-- 목적: 개별 인증 삭제 / 시즌 종료 시 Storage 사진 파일을 지울 수 있게 함.
--   (지금까지는 DELETE 정책이 없어 파일이 영구 누적됐음 — row만 지워지고 파일은 고아로 남음)
--
-- 경로 형식: certs/<groupId>/<membershipId>/<timestamp>.<ext>
--   → storage.foldername(name) = {groupId, membershipId}  ([1]=group, [2]=membership)
-- 권한: 본인 사진(소유 멤버십) 또는 그룹 방장만 삭제 가능.
--   owns_membership / is_admin_of 는 schema.sql 에 이미 정의된 SECURITY DEFINER 헬퍼 재사용.
-- ════════════════════════════════════════════════════════

drop policy if exists certs_delete on storage.objects;
create policy certs_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'certs'
    and array_length(storage.foldername(name), 1) >= 2
    and (
      public.owns_membership( ((storage.foldername(name))[2])::uuid )
      or public.is_admin_of(   ((storage.foldername(name))[1])::uuid )
    )
  );
