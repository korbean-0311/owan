-- ════════════════════════════════════════════════════════
-- 오운완 - 인증 사진 Storage 설정
-- Supabase → SQL Editor 에 붙여넣고 RUN. (멱등 — 다시 실행 가능)
-- ════════════════════════════════════════════════════════

-- 공개 버킷 'certs' 생성
insert into storage.buckets (id, name, public)
values ('certs', 'certs', true)
on conflict (id) do update set public = true;

-- 로그인 사용자는 certs 버킷에 업로드 가능
drop policy if exists certs_insert on storage.objects;
create policy certs_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'certs');

-- 누구나 읽기 (공개 버킷)
drop policy if exists certs_read on storage.objects;
create policy certs_read on storage.objects
  for select using (bucket_id = 'certs');
