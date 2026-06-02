# 윤비서 템플릿 설치 가이드 (로컬 실행)

## ✨ 가장 쉬운 방법

이 폴더를 **Claude Code 로 열고** 이렇게만 말하세요:

> **"초기 설정 도와줘"**  (또는 `/setup` 입력)

그러면 Claude Code 가 아래 과정을 **한 단계씩 같이** 진행해 줍니다.
(직접 따라 하고 싶다면 아래 수동 가이드를 보세요.)

---

이 문서를 따라 하면 **윤비서**를 내 컴퓨터에서 실행할 수 있습니다.
막히는 부분이 있으면 **Claude Code 에게 이 문서를 보여주고 물어보세요.** 예:

> "SETUP.md 3단계를 따라 하는데 `supabase db push` 에서 에러가 났어. 같이 봐줘."

---

## 0. 미리 준비할 것

- **Node.js 20 이상** — https://nodejs.org 에서 LTS 설치
- **Supabase 계정** (무료) — https://supabase.com
- **Supabase CLI** — 설치:
  ```bash
  npm install -g supabase
  # 또는 macOS: brew install supabase/tap/supabase
  ```
- (선택) **Vercel 계정** — 나중에 인터넷에 배포하고 싶을 때

---

## 1. 코드 받기 & 패키지 설치

```bash
# (이미 클론했다면 생략)
git clone https://github.com/youn-yong-seung/yunbiseo-template.git my-secretary
cd my-secretary

npm install
```

---

## 2. Supabase 로그인 & 프로젝트 만들기 (CLI 로 한 번에)

> 대시보드에서 키를 손으로 복사할 필요 없습니다. **CLI 로 로그인 → 프로젝트 생성 → 키 조회**까지
> 끝냅니다. 가장 쉬운 길은 이 폴더를 **Claude Code 로 열고 "초기 설정 도와줘"** 라고 하는 것 —
> Claude 가 아래를 대신 처리하고 `.env.local` 까지 채워 줍니다. 직접 한다면:

```bash
# 1) 로그인 (브라우저가 열려 인증합니다)
supabase login

# 2) 내 조직 ID 확인 (id 값을 복사)
supabase orgs list

# 3) 새 프로젝트 생성 — 비밀번호는 직접 정하고 꼭 메모하세요. 한국이면 리전은 ap-northeast-2 권장
supabase projects create "yun-secretary" \
  --org-id <조직-id> --db-password <원하는-DB비밀번호> --region ap-northeast-2

# 4) 생성된 project ref 확인 (REFERENCE ID 열)
supabase projects list
```

> 새 프로젝트는 준비에 **1~2분** 걸릴 수 있습니다.
> (이미 쓰던 프로젝트가 있으면 3번을 건너뛰고 4번에서 ref 만 골라도 됩니다.)

---

## 3. 키 조회 & DB 만들기

```bash
# 1) 환경변수 파일 만들기
cp .env.example .env.local

# 2) anon / service_role 키 조회 (대시보드 복사 불필요)
supabase projects api-keys --project-ref <내-project-ref>

# 3) .env.local 을 열어 아래처럼 채웁니다 (URL 은 https://<ref>.supabase.co)
#    NEXT_PUBLIC_SUPABASE_URL=https://<내-project-ref>.supabase.co
#    NEXT_PUBLIC_SUPABASE_ANON_KEY=<anon 키>
#    SUPABASE_SERVICE_ROLE_KEY=<service_role 키>   # 🔒 비밀값 — 외부 공유 금지
#    NEXT_PUBLIC_AUTH_EMAIL_DOMAIN=example.com      # 기본값 그대로

# 4) 내 프로젝트와 연결 (2단계에서 정한 DB 비밀번호 입력)
supabase link --project-ref <내-project-ref>

# 5) 테이블/정책 생성 (한 번만 실행하면 끝)
supabase db push
```

> ✅ 성공하면 Supabase 대시보드의 **Table Editor** 에 `employees`, `customers`,
> `projects` 등 테이블이 생깁니다.

---

## 4. 첫 관리자 계정 만들기

```bash
npm run setup:admin
```

실행하면 콘솔에 **로그인 ID** 와 **비밀번호**가 출력됩니다. (기본 ID: `admin`)
직접 정하고 싶다면:

```bash
npm run setup:admin -- myid mypassword
```

---

## 5. 실행 & 로그인

```bash
npm run dev
```

브라우저에서 http://localhost:3000 → 4단계에서 받은 **ID/비밀번호**로 로그인하세요.

축하합니다! 🎉 이제 윤비서가 내 컴퓨터에서 돌아갑니다.

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
  `supabase link --project-ref ...` 를 다시 확인하세요.
- **로그인이 안 됨** → `npm run setup:admin` 을 다시 실행해 비밀번호를 확인하세요.
- **`npm run build` 실패** → `.env.local` 에 Supabase 값이 채워졌는지 확인하세요.
  (빌드 시 Supabase 연결 정보가 필요합니다.)

무엇이든 막히면 **Claude Code 에게 에러 메시지를 그대로 붙여넣고 물어보세요.**
