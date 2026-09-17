# 오운완 (오늘의 운동 완료) — 프로젝트 핸드오프

새 대화에서 이어서 작업할 때 이 문서를 먼저 읽으면 됩니다. (프로젝트 폴더: `C:\Users\ryanl\Desktop\toy_project\OOO`)

---

## 1. 한 줄 요약
학생 모임이 **서로 운동 인증**하는 **모바일 전용 웹앱(PWA)**. 사진 인증 → 단톡방 링크 공유 → 멤버 승인 → 주간 목표/벌금 집계. 시즌제(8주 등) + 방장 관리.

## 2. 기술 스택
- **프론트엔드**: 단일 `index.html` (바닐라 HTML/CSS/JS, 외부 프레임워크 없음). CDN: `@supabase/supabase-js@2`, `exifr@7`.
- **백엔드**: **Supabase** (Postgres + Auth + Storage). 브라우저에서 `supabase-js`로 직접 호출 (서버 코드 없음).
- **배포**: **GitHub Pages** (정적). `git push` → 약 1분 후 자동 빌드.
- **로컬 개발**: `.claude/serve.js` (Node 정적 서버, 포트 4321). `launch.json`에 "owan"으로 등록.

## 3. 접속/계정 정보
- **라이브 URL**: https://korbean-0311.github.io/owan/
- **GitHub**: repo `github.com/korbean-0311/owan` (public). gh CLI가 `korbean-0311`로 로그인돼 있어 `git push`로 배포.
- **Supabase**: 프로젝트 ref `tfjjvmsxefgsjiaoyble`. 키는 `supabase-config.js` (publishable 키 — 공개 안전, RLS로 보호). **service_role/secret 키는 절대 커밋 금지.**
- 키 종류: publishable(`sb_publishable_...`) 사용. supabase-js v2가 이 키 지원.

## 4. 핵심 규칙 (도메인 로직)
- **시즌 = N주**(방장이 시작일+주차수 설정). 8주 끝나면 새 시즌.
- **하루 경계 = 새벽 3시**(밤샘 운동 배려): `DAY_SHIFT_MS=3h`. 날짜 달력 표시는 `TODAY=now-3h` 기준.
- **주차 마감 = 월요일 오전 8시**: `WEEK_CLOSE_MS=8h`. `computeCurrentWeek()`와 `inWeek()`는 각 주차를 다음 월요일 08:00까지 열어둔다. 일요일 밤 인증이 월요일 이른 오전에 승인돼도 지난 주차로 집계되도록 하기 위함. (집계는 여전히 제출 시간/승인 상태 기준)
- **시즌 시작 전(오늘 < season_start) = "대기"(0주차)**: `computeCurrentWeek()`가 0 반환(하한 0). 홈은 D-day 카운트다운("D-5 · 시즌 시작 대기"), **인증·레버리지 차단**, 피드/랭킹/멤버는 "시작 대기" 문구. 대기 판정은 전부 `CURRENT_WEEK<1` 단일 기준. (`daysUntil()`/`fmtStartLabel()` 헬퍼)
- 시즌 시작 시 **주당 목표 3/4/5회** 선택, **시즌 중 변경 불가**. 단 **1주차에 한해 1회** 아래 "시즌 설정 확정" 모달에서 바꿀 수 있음.
- **시즌 설정 확정(1주차·시즌당 1회)**: 시즌 시작 후 첫 접속 시 전체화면 모달(`#seasonSetup`)이 뜸 → 1단계 `이대로 갈래요`/`변경할래요`, 2단계에서 **닉네임·주당 횟수**를 각자 본인의 현재 값이 채워진 상태로 수정 → `확인`. 닫는 길은 이 버튼들뿐(X·배경탭 없음)이고, **버튼을 누르기 전엔 소진되지 않음**(앱을 그냥 닫으면 다음 접속에 다시 뜸). 한 번 누르면 그 시즌 내내 어디에도 안 뜸 — 재진입 버튼 없음.
  - 반영 순서: **① `auth.updateUser({email})` → ② `profiles.nickname` → ③ `season_setup` RPC**(횟수+소진 도장). ①이 먼저인 이유 = 가입이 'Auth 계정 → 프로필' 순서라 프로필 없는 계정이 있을 수 있어 Auth 이메일 집합 ⊇ 프로필 닉네임 집합 → ①에서 중복이 걸리면 아무것도 안 바뀐 상태로 중단. ②가 실패하면 ①을 원래 이메일로 롤백. **③까지 성공해야 소진**(중간 실패는 기회를 까먹지 않음).
  - 소진 기록은 `memberships.setup_season_no`(0=아직). **`groups.season_no`와 비교**하므로 새 시즌마다 자동으로 다시 열림 → `start_new_season` 수정 불필요. 온보딩 직후엔 `season_setup`을 선호출해 도장을 찍어 신규 가입자에겐 안 뜸.
  - 1주차 계산이 틀어지지 않는 이유: `deriveSeason`이 `while(w<curWeek)`라 1주차엔 정산 루프가 한 번도 안 돎 → **목표/벌금 기준액을 바꿔도 소급 영향 0**.
- 미달성 주차 벌금: 3회→3000 / 4회→2000 / 5회→1000원 (= base).
- **연속 실패 누진**: **2주마다 2배** (배수 1,1,2,2,4,4…). `failMult(n)=2^⌊(n-1)/2⌋`. 성공하면 streak 리셋.
- **개인 누적 벌금 상한 10만원**.
- **레버리지**: 시즌당 **3회**. 이번 주를 다음 주와 합쳐 **2×목표**로 판정. 마지막 주차 불가. **실패 시 두 주 벌금 합의 2배** 부과. **이번 주 첫 인증 전에만 사용 가능** — 이번 주 인증이 1건이라도 있으면(대기 포함) 잠김(`state.certifiedThisWeek`). 클라+RPC(`use_leverage`) 양쪽 차단.
- **면제(방장)**: 특정 멤버의 특정 주차 면제 → 누진 계산에서 **건너뜀(중립)**. 면제할 주차는 **현재 주차+1부터** 선택(미리 예정 용도), **복수 선택** 가능. 면제 내역은 **사람별 병합 카드**(한 멤버의 여러 주차를 한 카드에, 주차별 개별 ✕ 해제). 면제 표시는 홈 링 카드·시즌바·주차기록 3곳 일관(현재 주차 면제는 `deriveSeason`이 'exempt'를 'cur'보다 우선).
- **인증**: 사진 업로드 → **멤버 3명 승인**해야 "완료"로 집계(홈/주차기록/벌금에 반영). 승인 전(대기)은 카운트 안 됨. 피드에서 바로 승인하지 않고, 인증 상세(사진 확대 뷰어)를 확인한 뒤 뷰어 안의 승인 버튼으로 승인.
- **승인왕 순위**: 남의 인증에 "승인" 많이 눌러준 순위(`certification_approvals.approver_id` 집계, `loadApprovalRanking`). **3주마다(3·6·9·12…주차)** 홈에 카드 노출(`isApprovalWeek`: `CURRENT_WEEK%3===0`, 그 한 주만)(전원 표시 + 피드 유도 버튼, `renderApprovalCard`). 시즌 종료 정산 화면에도 전원 표시. 승인 기록은 시즌 리셋 시 삭제(시즌 단위).
  - **랭킹 탭에서는 상시 노출**: 랭킹 화면 상단에 세그먼트(`.rank-seg`) `💰 벌금 순위` / `👏 승인왕` — 두 순위를 같은 레벨에 둠(`rankPane()`). 인원이 많아 벌금 순위 아래에 붙이면 스크롤을 안 내려 안 보게 되기 때문. 세그먼트는 `.scroll` 바깥이라 고정됨. `loadApprovalRanking()`은 이제 `refreshGroup`에서 **항상** 호출(홈 카드만 `isApprovalWeek()`로 3주마다 게이팅).
- **초대코드**: 그룹 공용 코드 + 정원. 방장이 재발급 가능. **새 그룹 만들기는 숨김**(온보딩 로고 5탭 또는 `?create`).
- **로그인**: 닉네임+비밀번호. 닉네임을 `nickToEmail()`로 hex 인코딩한 이메일(`u<hex>@owan.co`)로 Supabase Auth. (한글 닉 지원 위함. ⚠️ Supabase에서 **Confirm email은 OFF 필수**(`mailer_autoconfirm=true` — 이게 켜져 있어야 닉네임 변경 시 이메일이 즉시 반영됨), 최소 비번 6자.)
  - ⚠️ **닉네임 = 로그인 ID**. 바꾸려면 `profiles.nickname`만이 아니라 **Auth 이메일도 함께** 바꿔야 함(안 그러면 화면과 로그인 ID가 어긋남). `auth.updateUser({email})`는 **세션을 무효화하지 않음** → 로그아웃되지 않고 uid도 그대로라 기존 인증·사진·벌금 기록 전부 무사(사진 경로는 `group_id/membership_id/…`, 아바타 색은 `memberships.color`라 닉네임과 무관).
  - ⚠️ `@owan.co`는 **가짜 도메인이라 비밀번호 찾기 메일이 갈 수 없음** → 닉네임을 잊고 기기를 바꾸면 복구 불가. 완화책으로 로그인 성공·닉네임 변경 시 `localStorage['owan_nick']`에 저장해 **로그인 화면 닉네임 칸을 자동 입력**(`rememberNick`/`prefillNick`).

## 5. 데이터 모델 (Supabase) — `supabase/schema.sql` 참조
- `groups`: invite_code, capacity, season_no, season_start, total_weeks, created_by
- `profiles`: id(=auth.users), nickname(unique)
- `memberships`: group_id, profile_id, weekly_goal, fine, is_admin, leverage_left, **color**(가입시 고정 배정), joined_at
- `weekly_records`: membership_id, week_no, done_count, status(pending/done/fail/exempt), leveraged
- `certifications`: membership_id, week_no, photo_url, photo_type(camera/photo/capture), capture_at, memo, status(pending/approved), approvals
- `certification_approvals`: certification_id, approver_id (트리거로 approvals 집계, **3명 이상이면 status=approved**)
- `exemptions`: membership_id, week_no

**RPC (SECURITY DEFINER, 보안 핵심)**: create_group, join_group(둘 다 색 배정 pick_color 호출), set_my_goal, use_leverage, kick_member, set_capacity, regenerate_code, exempt_week, remove_exemption, start_new_season, pick_color, gen_invite_code.
- **is_admin은 RPC로만 부여** (멤버십 직접 insert/update 차단 → 자기지정 불가).
- RLS: memberships 쓰기는 RPC만. weekly_records/certifications는 본인 것만. certifications **cf_delete**(본인 삭제) 있음.

**계산 방식(중요)**: 벌금/주차상태는 **저장하지 않고 프론트 `deriveSeason()`이 기록에서 즉석 계산**(누진·면제·레버리지·상한). done_count는 **approved 인증만** 카운트(`loadGroupData`).

## 6. 색상 시스템
- 멤버 아바타 색 = **가입 시 DB(`memberships.color`)에 영구 저장**. `pick_color(group)`이 그룹 내 미사용 색을 랜덤 배정.
- 팔레트 15색: `['#ef5350','#ec407a','#ab47bc','#42a5f5','#26c6da','#26a69a','#66bb6a','#9ccc65','#d4e157','#ffca28','#ffa726','#ff7043','#a1887f','#ffffff','#212121']` (파랑3 + 갈색/흰색/검정 포함).
- 프론트: `loadGroupData`가 DB color를 `memberColors{nickname:color}` 맵에 채움 → `colorFor(name)`이 전 화면(홈/마이/피드/랭킹/멤버) 동일 색 사용. `textOn(hex)`로 배경 명도에 따라 글자색(흰/검정) 자동.

## 7. 화면 구성 (data-screen)
splash(로딩) · onboard(초대코드→계정→목표 / 새그룹설정) · login · home · certify(사진찍기/사진선택 + 메타검증 + 완료시 "오운완 끝!") · feed(대기/완료 토글, 내 인증 ✕ 삭제) · rank(공동순위) · me(마이, 방장이면 방장메뉴) · seasonEnd · newSeason · records(주차 달력) · members · exempt. 사진 뷰어 오버레이.

**레이아웃 핵심**: 모바일 전체화면(데스크톱만 폰 프레임, `@media min-width:480px`). 가짜 노치/상태바 없음. **홈 상단바(.home-head)와 하단 탭바(.tabbar) 둘 다 `position:absolute` 오버레이 + `backdrop-filter` 프로스티드(반투명 비침)** → `.scroll`에 상(홈 90px)·하(calc(84px+safe)) 패딩으로 콘텐츠가 그 뒤로 스크롤. 탭바 가운데 + 버튼은 돌출 없이 세로 중앙(46px). safe-area-inset 반영(노치/홈인디케이터). 오버스크롤(러버밴드) 차단.

## 8. 로컬 개발 & 검증 방법
- 서버: Claude_Preview MCP `preview_start({name:"owan"})` → http://localhost:4321
- ⚠️ **screenshot 도구는 Supabase 상시연결로 타임아웃 잦음** → `preview_eval`로 DOM/상태를 읽어 검증 (예: `document.querySelector('.screen.active').dataset.screen`, 함수 직접 호출).
- 로그인 세션이 localStorage에 남아 자동 로그인됨.

## 9. 배포 방법
1. `git add -A && git commit -m "..."` (커밋 메시지 끝에 Co-Authored-By 라인)
2. `git push origin main`
3. ~1분 후 Pages 빌드 완료. 확인: `curl -s "https://korbean-0311.github.io/owan/?cb=$RANDOM" | grep '<찾을 문자열>'` 폴링(백그라운드 until 루프).
- CDN 전파가 엣지마다 달라 직후 1회는 옛 버전 나올 수 있음 → 몇 번 재확인.

## 10. DB 변경 시 (마이그레이션)
- 전체 초기화: `supabase/schema.sql` 재실행(drop&recreate — **데이터 전부 삭제**). 후 Auth→Users 정리.
- 데이터 보존 변경: 별도 마이그레이션 SQL 작성(ALTER/CREATE OR REPLACE/UPDATE). 예: `supabase/migration_colors.sql`, `migration_colors2.sql`, `migration_storage_delete.sql`(certs 버킷 DELETE 정책 — 본인/방장만, 사진 파일 정리용), `migration_leverage3.sql`(레버리지 2→3, 전체 초기화 시엔 schema.sql에 이미 포함), `migration_leverage_precert.sql`(use_leverage RPC에 "이번 주 첫 인증 전에만" 가드 — CREATE OR REPLACE), `migration_dedup_index.sql`(같은 촬영시각 중복 인증 정리 + 부분 유니크 인덱스), `migration_season_setup.sql`(`memberships.setup_season_no` 컬럼 + `season_setup` RPC — 1주차 설정 확정).
- ⚠️ **SQL Editor는 선택 영역이 있으면 그 부분만 실행**된다. 여러 문장짜리 파일을 돌릴 땐 에디터를 비우고 통째로 붙여넣을 것 — 실제로 `migration_season_setup.sql`에서 ALTER만 적용되고 CREATE FUNCTION이 빠지는 일이 있었음. 적용 확인은 `select count(*) from pg_proc where proname='<함수명>';`.
- publishable 키로는 DDL 불가 → **사용자가 SQL Editor에서 직접 실행**해야 함. 스키마 변경 시 프론트가 새 컬럼을 select하면 컬럼 생성 전엔 에러 → **마이그레이션 먼저, 배포 나중**.

## 11. 주요 한계/주의 (gotcha)
- **모바일 웹은 카메라 사진의 EXIF를 제거** → 촬영일 자동검증 불가. 그래서 "사진 찍기(camera 강제)=직접촬영 신뢰배지". "사진 선택(갤러리)"은 **EXIF 촬영 광학정보(FNumber/ExposureTime/ISO/FocalLength/Lens 등)로 판별** → 있으면 `photo`(✓ 카메라 사진, 촬영일로 주차검증), 없으면 `capture`(📷 화면 캡쳐·멤버 확인). ⚠️ `Make`/`Model`/`CreateDate`/`ModifyDate`는 스샷에도 붙을 수 있어서 사진 판별 기준으로 쓰지 않음. 진짜 검증은 3명 승인.
- iOS는 "사진 선택" 시 액션시트(보관함/찍기/파일)가 기본 — 웹에선 보관함 바로 열기 강제 불가.
- **카톡 공유**: Web Share API(`navigator.share`, text만) — API키 불필요. 링크(`?cert=`/`?join=`) 공유 → 받은 사람은 카톡 인앱 브라우저에서 1회 로그인 필요(인앱 브라우저 샌드박스). 데스크톱은 링크 복사 폴백.
- 현재 다중기기 실시간 동기화 없음(새로고침/화면진입 시 refresh). 주차 마감/벌금은 derive라 cron 불필요.
- **사진 저장 용량(무료 유지)**: 업로드 시 클라이언트 압축(`compressImage`, 가장 긴 변 1600px·JPEG 0.82 — 확대해도 선명). 개별 삭제(`deleteCert`)·시즌 종료(`createSeason`→start_new_season은 row만 삭제)에서 **Storage 파일도 `remove()`** 로 정리. ⚠️ 파일 삭제는 `migration_storage_delete.sql`(certs DELETE 정책) 선행 필요. 누적된 고아 파일은 다음 시즌 시작 시 자동 정리됨.

## 12. 진행 상태 / 다음 후보
- ✅ 완료: 전 기능 구현 + Supabase 연동 + PWA + GitHub Pages 배포 + 베타 피드백 다수 반영. 9명 베타테스트 중.
- ✅ 최근(2026-06): 현재주차 면제 표시(링/시즌바/주차기록 일관), **시즌 시작 전 "대기(0주차)" 상태**(D-day, 인증·레버리지 차단, 피드/랭킹/멤버 문구 통일), **면제 복수 선택 + 사람별 병합 카드**(주차별 개별 해제).
- ✅ 최근(2026-09): **시즌 2 시작**(9/14, 8주). **1주차 설정 확정 모달** — 접속 시 1회, 닉네임(Auth 이메일 동반 변경, 로그아웃 없음)·주당 횟수 변경. 로그인 닉네임 자동 입력(`owan_nick`).
- ⚠️ **홈 헤더는 `backdrop-filter` 반투명 바**라 그 아래 내용이 흐릿하게 가려진다. 헤더 높이가 닉네임 길이에 따라 79~111px로 변해 고정 여백(90px)으로는 긴 닉네임에서 첫 카드가 깔렸음 → `syncHomeHeadPad()`가 실제 헤더 높이+16px로 `.scroll` 상단 여백을 잡는다(`renderHome`/`applyIdentity`/resize에서 호출). **홈 헤더 내용을 바꾸면 이 함수가 여전히 도는지 확인할 것.**
- 다음 후보(미구현): 카톡 실연동(현재 링크공유로 충분), 다중기기 실시간(Supabase Realtime), 시즌 종료 자동화(현재 방장 수동/derive), 알림(현재 없음), 코드 리팩토링(파일 분리).

## 13. 메모리
- 영구 메모리: `C:\Users\ryanl\.claude\projects\C--Users-ryanl-Desktop-toy-project-OOO\memory\owan-project.md` (새 세션 자동 로드). 이 핸드오프와 함께 참고.
