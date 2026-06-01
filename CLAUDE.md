# Project Conventions

## Git Rules

- 커밋 메시지는 한국어로 작성한다. 화면명·기능명·변경 목적을 구체적으로 적는다.
  예: `프로젝트관리 일정 요일 표기 추가`, `고객관리 담당자 상세보기 추가`
- 작업이 끝나면 즉시 커밋한다. 미커밋 상태로 작업을 종료하지 않는다.
- push와 배포는 사용자가 명시적으로 요청할 때만 수행한다.
- 하나의 커밋에는 하나의 목적(기능, 버그 수정, 리팩터링)만 담는다.

## Supabase 마이그레이션

- 최초 설치는 `SETUP.md` 를 따른다. (`supabase link` → `supabase db push`)
- 스키마를 바꾸면 `supabase/migrations/` 에 새 마이그레이션 파일을 만들고 `supabase db push` 로 적용한다.
- DB 스키마를 바꾸는 코드(컬럼 신규/삭제, 제약 변경 등)는 항상 마이그레이션 + 적용까지 한 사이클로 끝낸다. 코드만 머지되고 DB는 안 바뀐 상태가 되지 않도록 주의.

## Font

- Pretendard만 사용한다. Geist, Inter 등 다른 폰트를 추가하지 않는다.

## UI Pattern: List -> Detail Page

- 목록 행 클릭 → 상세 페이지 이동. 목록에 수정/삭제 버튼 노출하지 않는다.
- 등록은 목록에서, 수정은 별도 편집 페이지(`/[id]/edit/page.tsx`)를 사용한다.
- 상세 페이지 브레드크럼: `{리소스명} / {항목명}`. 상단 헤더에 수정·삭제·주요 액션 배치.
- 삭제는 `confirm()` 이후 목록으로 이동한다.

## UI Pattern: StatCard 모바일

- 모바일: 라벨과 값만 표시. 아이콘·설명글은 `hidden md:flex` / `hidden md:block`으로 데스크톱 전용.
- 금액 StatCard는 `mobileValue` prop에 `formatAmountInMan()`으로 만 단위 표시.

## 메모 기능 공통 규칙

- 메모(추가/수정/삭제)는 프로젝트관리와 고객관리가 공유하는 기능이다. 한쪽을 수정하면 다른 쪽도 같이 수정한다.
- 상세 규칙은 `docs/MEMO_RULES.md` 참고.
