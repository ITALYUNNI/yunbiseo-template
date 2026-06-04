# 윤비서 템플릿 — 프로젝트 안내 (Claude Code 용)

자연어로 사내 업무를 다루는 AI 비서형 업무관리 시스템(Next.js 16 + Supabase)의 학습용 템플릿입니다.
처음 클론한 사용자는 대부분 초보자입니다. 친절하게, 한 번에 한 단계씩 안내하세요.

---

## 🚀 초기 설정 도우미

**트리거:** 사용자가 "초기 설정 도와줘", "설치 도와줘", "설치해줘", "세팅 도와줘", "처음부터 같이 해줘",
"setup", 또는 **GitHub 주소만 주며 "설치해줘"** 라고 하면 **아래 절차를 순서대로 진행**한다.
(사람용 상세본: `SETUP.md`)

### 진행 원칙
- **한 번에 한 단계.** 각 단계를 실행/안내하고, 결과를 확인한 뒤 다음으로 넘어간다. 한꺼번에 쏟아내지 않는다.
- **OS 를 먼저 파악한다.** Windows 와 macOS 는 설치 명령이 다르다(`winget` vs Homebrew/설치파일, `copy` vs `cp`).
  현재 OS 를 확인하고 그에 맞는 명령만 안내한다. 모르면 사용자에게 묻는다.
- **OS 레벨 설치는 대화형일 수 있음을 인지한다.** git·Node 설치는 UAC(윈도우) 승인 클릭이나 설치 마법사(맥)가
  뜰 수 있어 **클로드코드가 100% 무인 자동화할 수 없다.** 이 구간은 명령을 `!` 로 띄워 주고, 사용자가
  팝업을 승인/완료하도록 또렷이 안내한 뒤 결과를 확인한다. 그 다음 단계(supabase CLI~)부터는 네가 자동 처리한다.
- **⚠️ 새로 설치한 명령은 현재 세션에서 바로 안 잡힌다(특히 Windows).** winget/npm 등으로 git·Node·supabase CLI 를
  방금 깔면 **이미 떠 있는 터미널·Claude Code 세션은 PATH 가 갱신되지 않아** 같은 창에서 `! supabase ...` 하면
  `command not found`/`...은(는) 인식되지 않습니다` 가 난다. **계속 `!` 로 재시도하지 말고**, 사용자를 번거롭게 하지
  않는 순서로 아래를 시도한다:
  1. **(1순위 — 풀패스 실행) 설치된 supabase 바이너리의 전체 경로를 네가 찾아서** 그 경로로 명령을 만들어 준다.
     PATH 가 갱신 안 돼도 절대경로면 바로 실행된다. 찾는 법:
     - 전역 prefix 확인: `npm prefix -g` (npm 은 보통 같은 세션에서 동작한다). 결과를 `<P>` 라 하면 —
     - **Windows:** 바이너리는 `<P>\supabase.cmd` (예: `C:\Users\<id>\AppData\Roaming\npm\supabase.cmd`)
     - **macOS/Linux:** 바이너리는 `<P>/bin/supabase`
     - `"<풀패스>" --version` 으로 인식되는지 먼저 확인한 뒤, 이후 **모든 supabase 명령에 이 풀패스를 사용**한다.
       비대화형(`projects list/api-keys/db push`)은 네가 풀패스로 직접 실행하고, 사용자가 직접 해야 하는
       대화형은 풀패스가 박힌 명령을 그대로 제시한다. 예(Windows): `! "C:\Users\<id>\AppData\Roaming\npm\supabase.cmd" login`
  2. **(2순위 — 재시작)** 풀패스도 여의치 않으면 **VS Code/터미널을 완전히 종료 후 다시 켜고** `claude` 재실행 →
     **"이어서 설치해줘"** 로 이어간다(진행 위치는 `--version` 들로 점검). 새 cmd 창에서 직접 실행도 가능하다.
  설치 직후에는 항상 `--version`(또는 풀패스 `--version`)으로 인식 여부를 확인하고, 안 잡히면 위 순서로 처리한다.
- **대화형 명령은 사용자가 직접 실행**하게 한다 (브라우저 로그인, DB 비밀번호 입력 등). 이때
  프롬프트에 `! 명령어` 를 입력하면 이 세션에서 실행된다고 안내한다. 예: `! supabase login`
- **비밀키**는 사용자가 채팅에 붙여넣으면 네가 `.env.local` 에 적어준다. 키 값을 채팅에 도로 출력하지 않는다.
- **에러가 나면** 메시지를 그대로 읽고, 원인과 해결책을 한국어로 쉽게 설명한 뒤 다시 시도한다.
- 진행 상황을 짧게 요약해 사용자가 지금 어디쯤인지 알게 한다.

### 단계
> **핵심 방침:** 대시보드에서 키를 손으로 복사하게 하지 않는다. **supabase CLI 로 로그인→프로젝트 생성→키 조회까지
> 자동화**해서, 사용자는 브라우저 로그인과 DB 비밀번호 입력만 하면 되게 한다. 이것이 가장 빠른 설치 경로다.

0. **환경 부트스트랩 (필수 프로그램 확인·설치)** — 윤비서 실행에 필요한 3가지: **git**(코드 받기),
   **Node.js 20.9 이상 + npm**(빌드·실행), **supabase CLI**(DB). 먼저 한 번에 점검한다:
   `git --version`, `node -v`, `npm -v`, `supabase --version`. 없는 것만 OS 에 맞춰 깐다.
   - **Windows** (대부분 `winget` 사용 가능):
     - git: `winget install --id Git.Git -e`
     - Node LTS: `winget install --id OpenJS.NodeJS.LTS -e`  ← Node 가 npm·supabase CLI 의 전제
     - (winget 자체가 없으면 https://nodejs.org LTS, https://git-scm.com 설치파일 안내)
   - **macOS**:
     - git: `git --version` 을 한 번 실행하면 Xcode Command Line Tools 설치창이 뜬다(또는 `xcode-select --install`).
     - Node LTS: Homebrew 가 있으면 `brew install node`, 없으면 https://nodejs.org LTS 설치파일 안내.
   - **supabase CLI** (git·Node 가 준비된 뒤): `npm install -g supabase` — **Windows/macOS 모두 동작**한다.
     (macOS 는 `brew install supabase/tap/supabase` 도 가능.) 이 흐름은 CLI 로 프로젝트 생성·키 조회까지
     자동화하므로 CLI 설치가 **필수**다.
   - git·Node 설치는 승인 팝업/마법사가 뜰 수 있다 → `!` 로 명령을 띄우고 사용자가 완료하게 한 뒤 버전을 재확인한다.
   - **설치 직후 `--version` 으로 인식되는지 꼭 확인한다.** Windows 에서 방금 깐 명령이 `command not found`/
     `인식되지 않습니다` 로 안 잡히면 PATH 미갱신 문제다(위 진행 원칙 ⚠️ 참고). **1순위는 풀패스 실행** —
     `npm prefix -g` 로 prefix 를 구해 `<P>\supabase.cmd`(Windows)/`<P>/bin/supabase`(mac) 를 만들어 그 절대경로로
     실행하면 재시작 없이 바로 된다. 안 되면 그때 VS Code/터미널 재시작 → `claude` 재실행 → "이어서 설치해줘" 로 잇는다.
1. **코드 받기 (URL 만 받은 경우)** — 사용자가 폴더를 안 열고 GitHub 주소만 줬다면 먼저 클론한다:
   `git clone https://github.com/youn-yong-seung/yunbiseo-template.git my-secretary` 후 그 폴더로 이동한다.
   이미 이 폴더가 열려 있으면(= `package.json` 이 보이면) 이 단계는 건너뛴다. 이어서 `npm install` 을 실행한다.
2. **Supabase 로그인 (사용자가 직접 실행)** — `! supabase login` 을 `!` 로 직접 실행하도록 안내한다.
   브라우저가 열려 인증하면 토큰이 자동 저장된다. (대시보드 접속·키 복사 불필요)
3. **프로젝트 준비** — 로그인 후 네가 직접 명령으로 처리한다. 두 갈래 중 하나:
   - **새로 만들기:** `supabase orgs list -o json` 으로 조직 ID(`id`)를 확인하고(여러 개면 사용자가 고르게 한다),
     사용자에게 **DB 비밀번호**(직접 정함·메모 필수)와 **리전**(한국이면 `ap-northeast-2` 권장)을 물은 뒤,
     비밀번호가 채팅/로그에 남지 않도록 **사용자가 `!` 로 직접** 실행하게 한다:
     `! supabase projects create "yun-secretary" --org-id <org> --db-password <비밀번호> --region ap-northeast-2`
   - **기존 프로젝트 사용:** `supabase projects list -o json` 결과를 보여주고 쓸 프로젝트를 고르게 한다.
   - 어느 쪽이든 결과에서 **project ref**(`<ref>`)를 확보한다. 새 프로젝트는 준비에 1~2분 걸릴 수 있다.
4. **키 자동 조회 & `.env.local` 작성** — 네가 직접 처리한다(사용자가 키를 복사할 필요 없음):
   - `supabase projects api-keys --project-ref <ref> -o json` 으로 `anon` 과 `service_role` 키를 받는다.
   - `cp .env.example .env.local` 후 다음을 채운다: `NEXT_PUBLIC_SUPABASE_URL=https://<ref>.supabase.co`,
     `NEXT_PUBLIC_SUPABASE_ANON_KEY=<anon>`, `SUPABASE_SERVICE_ROLE_KEY=<service_role>`.
     `NEXT_PUBLIC_AUTH_EMAIL_DOMAIN` 은 기본값(example.com) 유지.
   - service_role 은 비밀값이므로 채팅에 키 값을 다시 출력하지 않는다.
5. **연결 & DB 생성** —
   - `! supabase link --project-ref <ref>` 를 사용자가 `!` 로 직접 실행한다(3단계 DB 비밀번호 입력).
   - 이어서 `supabase db push --yes` 를 실행한다(네가 실행 가능, `--yes` 로 확인 프롬프트 자동 통과).
     테이블/정책 51개가 생성된다.
   - `project not ready`/연결 오류면 프로젝트 준비(1~2분)를 기다렸다가, 또는 login/link 를 재확인 후 재시도한다.
6. **첫 관리자 생성** — 이 앱은 **회원가입 화면이 없다.** 로그인 계정은 이 단계로 만드는 관리자 1개로 시작한다.
   비밀번호를 결정적으로 만들기 위해 **ID·비밀번호를 직접 지정**해 실행한다(비밀번호는 **6자 이상**):
   `npm run setup:admin -- admin <비밀번호>`. 실행 후 **로그인 ID(`admin`)와 비밀번호**를 또렷하게 전달한다.
   (직원 추가는 로그인 후 [직원관리] 화면에서 한다고 안내한다.)
7. **실행 & 로그인** — `npm run dev` 를 백그라운드로 띄우고, http://localhost:3000 에서 로그인하라고 안내한다.
   로그인은 **이메일이 아니라 ID(`admin`)** 와 6단계 비밀번호로 한다는 점을 분명히 알린다.
8. **완료** — 축하 인사와 함께, 회사정보·외부연동(Gemini/Bolta/Slack)은 **선택(심화)** 이며
   `SETUP.md` 6장 또는 [시스템설정] 화면에서 나중에 켤 수 있다고 알린다.

### 자주 나는 문제
- **`supabase`/`node`/`git` 이 방금 설치했는데 `command not found`/`인식되지 않습니다`(특히 Windows)** →
  현재 세션 PATH 미갱신 문제다. **1순위: 풀패스 실행** — `npm prefix -g` 로 prefix 를 구해
  `<prefix>\supabase.cmd`(Windows)/`<prefix>/bin/supabase`(mac) 절대경로로 실행하면 재시작 없이 바로 된다.
  안 되면 VS Code/터미널 재시작 후 `claude` 재실행 → "이어서 설치해줘", 또는 새 cmd 창에서 실행.
- `supabase projects create`/`api-keys` 가 인증 오류 → `! supabase login` 을 먼저 했는지 확인.
- `supabase db push` 가 `project not ready`/연결 오류 → 새 프로젝트 준비(1~2분)를 기다린 뒤,
  `supabase link --project-ref <ref>` (DB 비밀번호) 를 재확인하고 재시도.
- `npm run build` 실패 → `.env.local` 의 Supabase 값(URL/anon/service_role)이 채워졌는지 확인 (빌드에 필요).
- `setup:admin` 이 비밀번호 길이 오류 → 비밀번호는 **6자 이상**이어야 한다(Supabase Auth 기본 정책).
- 로그인 안 됨 → ① 이메일이 아니라 **ID(`admin`)** 로 시도했는지 확인, ② `npm run setup:admin -- admin <새비밀번호>` 로 재설정.

---

## 포함 기능 (메뉴)

고객관리 · 프로젝트관리 · 할일관리 · 일정관리 · 미팅관리 · 명함관리 · 자료실 · 견적관리 ·
매출관리 · 입금관리 · 매입관리 · 카드사용내역 · 영업이익분석 · 재직증명서 · 법인카드 ·
직원관리 · 시스템설정

> 회사 정보(상호/대표자/사업자번호/계좌)는 비어 있다. 견적서·재직증명서를 쓰려면
> `src/lib/quotation-constants.ts`, `src/app/dashboard/certificates/page.tsx` 에서 값을 채운다.
> Google(메일/캘린더/드라이브)·세금계산서(Bolta)·Slack 코드는 기본 비활성이며 키를 넣으면 동작한다.

---

## Project Conventions

### Git Rules
- 커밋 메시지는 한국어로 작성한다. 화면명·기능명·변경 목적을 구체적으로 적는다.
  예: `프로젝트관리 일정 요일 표기 추가`, `고객관리 담당자 상세보기 추가`
- 작업이 끝나면 즉시 커밋한다. 미커밋 상태로 작업을 종료하지 않는다.
- push와 배포는 사용자가 명시적으로 요청할 때만 수행한다.
- 하나의 커밋에는 하나의 목적(기능, 버그 수정, 리팩터링)만 담는다.

### Supabase 마이그레이션
- 최초 설치는 위 "초기 설정 도우미" 또는 `SETUP.md` 를 따른다.
- 스키마를 바꾸면 `supabase/migrations/` 에 새 마이그레이션 파일을 만들고 `supabase db push` 로 적용한다.
- DB 스키마를 바꾸는 코드(컬럼 신규/삭제, 제약 변경 등)는 항상 마이그레이션 + 적용까지 한 사이클로 끝낸다.

### Font
- Pretendard만 사용한다. Geist, Inter 등 다른 폰트를 추가하지 않는다.

### UI Pattern: List -> Detail Page
- 목록 행 클릭 → 상세 페이지 이동. 목록에 수정/삭제 버튼 노출하지 않는다.
- 등록은 목록에서, 수정은 별도 편집 페이지(`/[id]/edit/page.tsx`)를 사용한다.
- 상세 페이지 브레드크럼: `{리소스명} / {항목명}`. 상단 헤더에 수정·삭제·주요 액션 배치.
- 삭제는 `confirm()` 이후 목록으로 이동한다.

### UI Pattern: StatCard 모바일
- 모바일: 라벨과 값만 표시. 아이콘·설명글은 `hidden md:flex` / `hidden md:block`으로 데스크톱 전용.
- 금액 StatCard는 `mobileValue` prop에 `formatAmountInMan()`으로 만 단위 표시.

### 메모 기능 공통 규칙
- 메모(추가/수정/삭제)는 프로젝트관리와 고객관리가 공유하는 기능이다. 한쪽을 수정하면 다른 쪽도 같이 수정한다.
- 상세 규칙은 `docs/MEMO_RULES.md` 참고.
