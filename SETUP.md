# 윤비서 템플릿 설치 가이드 (로컬 실행)

처음 설치하는 분도 **이 문서만 따라 하면** 내 컴퓨터에서 윤비서를 실행하고 로그인할 수 있습니다.
설치는 크게 6단계이고, 보통 **10~15분**이면 끝납니다.

## 전체 흐름 한눈에

```
0. 필요한 프로그램 설치 (git · Node.js · Supabase CLI)
1. 코드 받기 (git clone) + npm install
2. Supabase 로그인 → 프로젝트 만들기
3. 키 조회 → .env.local 작성 → DB 테이블 생성 (db push)
4. 첫 관리자 계정 만들기 (setup:admin)   ← 회원가입 화면이 없으므로 이 단계로 로그인 계정을 만듭니다
5. 실행 (npm run dev) → http://localhost:3000 로그인
```

---

## ✨ 가장 쉬운 방법 — Claude Code 에게 맡기기

위 단계를 직접 안 하고 싶으면, **Claude Code 가 처음부터 끝까지 대신** 해 줍니다.

- **이미 이 폴더를 클론했다면:** 폴더를 Claude Code 로 열고
  > **"설치해줘"** (또는 `초기 설정 도와줘`, `/setup`)
- **아직 URL밖에 없다면:** Claude Code 에 이렇게 말하세요. 클론부터 알아서 합니다.
  > **"https://github.com/youn-yong-seung/yunbiseo-template 설치해줘"**

그러면 Claude 가 OS(Windows/맥)를 확인해 필요한 프로그램을 깔고, 클론·설치·DB 생성·관리자 계정까지
**한 단계씩 같이** 진행한 뒤, 마지막에 **로그인 ID 와 비밀번호**를 알려 줍니다.
(git·Node 설치 시 승인 팝업/마법사는 클릭 한두 번만 직접 해 주면 됩니다.)

> 막히면 언제든 **Claude Code 에게 에러 메시지를 그대로 붙여넣고** 물어보세요.
> 예: "SETUP.md 3단계 `supabase db push` 에서 에러가 났어. 같이 봐줘."

아래는 **직접(수동) 설치**하는 분을 위한 단계별 안내입니다.

---

## 0. 필요한 프로그램 (3가지)

| 필요한 것 | Windows | macOS |
|-----------|---------|-------|
| **git** (코드 받기) | `winget install --id Git.Git -e` | `git --version` 실행 → 설치창 뜨면 진행 (또는 `xcode-select --install`) |
| **Node.js 20.9+** (빌드·실행) | `winget install --id OpenJS.NodeJS.LTS -e` | `brew install node` / 없으면 [nodejs.org](https://nodejs.org) LTS |
| **Supabase CLI** (DB) | `npm install -g supabase` | `npm install -g supabase` (또는 `brew install supabase/tap/supabase`) |

- 잘 깔렸는지 확인: `git --version`, `node -v`(v20.9 이상), `supabase --version` 이 모두 버전을 출력하면 OK.
- `winget` 이 없으면(구형 Windows) [nodejs.org](https://nodejs.org)·[git-scm.com](https://git-scm.com) 에서 설치파일로 받으세요.
- Supabase CLI 는 **Node 를 먼저 깐 뒤** 설치됩니다(`npm` 이 필요).
- **Supabase 계정**(무료)도 필요합니다 → https://supabase.com 에서 가입 (로그인은 2단계에서 CLI 가 처리).

> 💡 git·Node 설치는 승인 팝업(Windows UAC)이나 설치 마법사가 떠서 **클릭 한두 번은 직접** 해야 합니다.

---

## 1. 코드 받기 & 패키지 설치

```bash
git clone https://github.com/youn-yong-seung/yunbiseo-template.git my-secretary
cd my-secretary
npm install
```

> 이후 모든 명령은 **이 `my-secretary` 폴더 안에서** 실행합니다.

---

## 2. Supabase 로그인 & 프로젝트 만들기 (CLI 로 한 번에)

대시보드에서 키를 손으로 복사할 필요 없이, **CLI 로 로그인 → 프로젝트 생성 → 키 조회**까지 끝냅니다.

```bash
# 1) 로그인 (브라우저가 열려 인증합니다)
supabase login

# 2) 내 조직 ID 확인 (ID 열의 값을 복사)
supabase orgs list

# 3) 새 프로젝트 생성 — 비밀번호는 직접 정하고 꼭 메모하세요. 한국이면 리전은 ap-northeast-2(서울) 권장
#    (한 줄로 입력하세요 — Windows/맥 동일)
supabase projects create "yun-secretary" --org-id <조직-ID> --db-password <원하는-DB비밀번호> --region ap-northeast-2

# 4) 생성된 project ref 확인 (REFERENCE ID 열의 값을 복사)
supabase projects list
```

> 새 프로젝트는 준비에 **1~2분** 걸립니다. (이미 쓰던 빈 프로젝트가 있으면 3번을 건너뛰고 4번에서 ref 만 골라도 됩니다.)

---

## 3. 키 조회 & DB 만들기

```bash
# 1) 환경변수 파일 만들기   (Windows cmd 라면 'copy .env.example .env.local')
cp .env.example .env.local

# 2) anon / service_role 키 조회 (대시보드 복사 불필요)
supabase projects api-keys --project-ref <내-project-ref>
```

`.env.local` 을 열어 위에서 받은 값으로 아래 4줄을 채웁니다 (URL 은 `https://<ref>.supabase.co`):

```
NEXT_PUBLIC_SUPABASE_URL=https://<내-project-ref>.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=<anon 키>
SUPABASE_SERVICE_ROLE_KEY=<service_role 키>     # 🔒 비밀값 — 외부 공유 금지
NEXT_PUBLIC_AUTH_EMAIL_DOMAIN=example.com         # 기본값 그대로 두면 됩니다
```

이어서 DB(테이블·정책)를 생성합니다:

```bash
# 내 프로젝트와 연결 (2단계에서 정한 DB 비밀번호 입력)
supabase link --project-ref <내-project-ref>

# 테이블/정책 생성 — 'Do you want to push...' 물으면 Y 입력
supabase db push
```

> ✅ 성공하면 Supabase 대시보드의 **Table Editor** 에 `employees`, `customers`, `projects` 등
> 51개 테이블이 생깁니다. (이 스키마는 신규 프로젝트에서 0 에러로 적용되는 것을 검증했습니다.)

---

## 4. 첫 관리자 계정 만들기 ⭐ (로그인하려면 꼭 필요)

> **윤비서에는 회원가입 화면이 없습니다.** 로그인 계정은 아래 명령으로 만드는 **관리자 1개**로 시작하고,
> 직원은 로그인한 뒤 **[직원관리]** 화면에서 추가합니다.

가장 쉬운 방법 — **ID 와 비밀번호를 직접 정해서** 만들기 (비밀번호는 **6자 이상**):

```bash
npm run setup:admin -- admin mypassword123
```

- 로그인 **ID** 는 `admin`, 비밀번호는 `mypassword123` (원하는 값으로 바꾸세요, 6자 이상).

그냥 `npm run setup:admin` 만 실행하면 ID 는 `admin`, **비밀번호는 자동 생성**되어 화면에 출력됩니다:

```
========================================
  관리자 계정 준비 완료!
  로그인 ID : admin
  비밀번호  : Admin-1a2b3c
========================================
```

> ⚠️ 자동 생성 비밀번호는 **이 화면에 한 번만** 나옵니다. 꼭 복사/메모하세요.
> 잃어버려도 괜찮습니다 — `npm run setup:admin -- admin 새비밀번호` 를 다시 실행하면 비밀번호가 재설정됩니다.

---

## 5. 실행 & 로그인

```bash
npm run dev
```

브라우저에서 **http://localhost:3000** 접속 → 로그인 화면에서:

- **로그인 ID**: `admin`  ← 이메일이 아니라 **ID** 를 그대로 입력합니다
- **비밀번호**: 4단계에서 정한(또는 출력된) 비밀번호

축하합니다! 🎉 이제 윤비서가 내 컴퓨터에서 돌아갑니다.
(서버를 끄려면 터미널에서 `Ctrl + C`, 다시 켜려면 `npm run dev`)

---

## ✅ 설치 완료 체크리스트

- [ ] `git --version` / `node -v`(20.9+) / `supabase --version` 이 모두 나온다
- [ ] `npm install` 이 에러 없이 끝났다
- [ ] `supabase db push` 가 에러 없이 끝났고, Table Editor 에 테이블이 보인다
- [ ] `npm run setup:admin` 으로 받은 **로그인 ID/비밀번호**를 메모했다
- [ ] `npm run dev` 후 http://localhost:3000 에서 **ID `admin`** 으로 로그인된다

---

## 6. (선택) 외부 연동 켜기 — "심화"

아래 기능들은 키가 없어도 앱은 잘 돌아갑니다. 필요할 때만 설정하세요.
대부분 **[시스템설정]** 화면에서 키를 입력하면 됩니다.

| 기능 | 필요한 것 | 어디서 설정 |
|------|-----------|-------------|
| 명함관리 OCR / 입금 AI매칭 / AI견적 | Google Gemini API Key | 시스템설정 화면 |
| 세금계산서 발행 | Bolta API Key | 시스템설정 화면 |
| Slack 알림 | Slack Bot Token | 시스템설정 화면 |
| 회사 정보(견적서·재직증명서) | 직접 입력 | `src/lib/quotation-constants.ts`, `src/app/dashboard/certificates/page.tsx` |
| Google 캘린더/드라이브 | OAuth/서비스계정 키 | `.env.local` (기본 비활성) |
| Vercel 배포 | Vercel 계정 | `vercel` CLI 또는 대시보드 |

> 회사 정보(상호/대표자/사업자번호/계좌 등)는 기본적으로 비어 있습니다.
> 견적서·재직증명서에서 본인 회사 정보를 쓰려면 위 파일에서 값을 바꾸세요.

---

## 자주 막히는 곳

- **`supabase db push` 에서 권한/연결 오류** → `supabase login` 과
  `supabase link --project-ref ...` 를 다시 확인하세요. 새 프로젝트면 준비(1~2분)를 기다린 뒤 재시도.
- **로그인이 안 됨** → ① 이메일이 아니라 **ID `admin`** 으로 시도했는지 확인,
  ② `npm run setup:admin -- admin 새비밀번호` 로 비밀번호를 재설정해 다시 시도.
- **비밀번호가 너무 짧다는 오류** → 비밀번호는 **6자 이상**이어야 합니다.
- **`npm run build`/실행 실패** → `.env.local` 에 Supabase 값(URL/anon/service_role)이 채워졌는지 확인.

무엇이든 막히면 **Claude Code 에게 에러 메시지를 그대로 붙여넣고 물어보세요.**
