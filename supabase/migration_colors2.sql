-- ════════════════════════════════════════════════════════
-- 팔레트 교체 (파랑 축소 + 갈색·흰색·검정) + 기존 멤버 색 재배정
-- SQL Editor에 통째로 붙여넣고 RUN. (데이터 보존)
-- ════════════════════════════════════════════════════════

-- 1) pick_color 새 팔레트로 갱신 (이후 가입자에 적용)
create or replace function public.pick_color(g uuid) returns text
language sql security definer set search_path=public as $$
  with pal(c) as (values ('#ef5350'),('#ec407a'),('#ab47bc'),('#42a5f5'),('#26c6da'),
    ('#26a69a'),('#66bb6a'),('#9ccc65'),('#d4e157'),('#ffca28'),('#ffa726'),('#ff7043'),
    ('#a1887f'),('#ffffff'),('#212121'))
  select coalesce(
    (select c from pal where c not in (select color from public.memberships where group_id=g and color is not null) order by random() limit 1),
    (select c from pal order by random() limit 1));
$$;

-- 2) 기존 멤버 색 재배정 (새 팔레트로 그룹별 흩뿌려 덮어쓰기)
update public.memberships m set color = sub.c
from (
  select id,
    (array['#ef5350','#ec407a','#ab47bc','#42a5f5','#26c6da','#26a69a','#66bb6a','#9ccc65',
           '#d4e157','#ffca28','#ffa726','#ff7043','#a1887f','#ffffff','#212121'])
      [ ((((row_number() over (partition by group_id order by joined_at)) - 1) * 7) % 15) + 1 ] as c
  from public.memberships
) sub
where m.id = sub.id;
