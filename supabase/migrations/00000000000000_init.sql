-- ============================================================
-- source: 20260304210000_api_keys.sql
-- ============================================================
-- API Keys 테이블
CREATE TABLE api_keys (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL,
  key_hash TEXT NOT NULL UNIQUE,
  key_prefix TEXT NOT NULL,
  created_by TEXT NOT NULL,
  last_used_at TIMESTAMPTZ,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- RLS 정책: 인증된 사용자만 CRUD 가능
ALTER TABLE api_keys ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can view api_keys"
  ON api_keys FOR SELECT
  USING (auth.role() = 'authenticated');

CREATE POLICY "Authenticated users can insert api_keys"
  ON api_keys FOR INSERT
  WITH CHECK (auth.role() = 'authenticated');

CREATE POLICY "Authenticated users can update api_keys"
  ON api_keys FOR UPDATE
  USING (auth.role() = 'authenticated');

CREATE POLICY "Authenticated users can delete api_keys"
  ON api_keys FOR DELETE
  USING (auth.role() = 'authenticated');

-- updated_at 트리거 (기존 함수 재사용)
CREATE TRIGGER api_keys_updated_at
  BEFORE UPDATE ON api_keys
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at();


-- ============================================================
-- source: 20260304220000_employee_type.sql
-- ============================================================
-- 직원구분(관리자/직원) 컬럼 추가
ALTER TABLE employees
  ADD COLUMN IF NOT EXISTS employee_type TEXT;

UPDATE employees
SET employee_type = COALESCE(employee_type, '직원');

ALTER TABLE employees
  ALTER COLUMN employee_type SET DEFAULT '직원';

ALTER TABLE employees
  ALTER COLUMN employee_type SET NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'employees_employee_type_check'
  ) THEN
    ALTER TABLE employees
      ADD CONSTRAINT employees_employee_type_check
      CHECK (employee_type IN ('관리자', '직원'));
  END IF;
END;
$$;

-- 관례적으로 admin 계정은 관리자 처리
UPDATE employees
SET employee_type = '관리자'
WHERE employee_type = '직원'
  AND (
    login_id = 'admin'
    OR email ILIKE 'admin@%'
  );


-- ============================================================
-- source: 20260304230800_customers_project_mapping.sql
-- ============================================================
-- 고객관리 + 고객:프로젝트(1:N) 매핑

-- updated_at 트리거 함수 보장
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 고객 테이블 생성
CREATE TABLE IF NOT EXISTS customers (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  customer_type TEXT NOT NULL DEFAULT '회사' CHECK (customer_type IN ('회사', '개인')),
  name TEXT NOT NULL,
  business_number TEXT UNIQUE,
  contact_name TEXT,
  contact_email TEXT,
  contact_phone TEXT,
  address TEXT,
  memo TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE customers ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'customers' AND policyname = 'Authenticated users can view customers'
  ) THEN
    CREATE POLICY "Authenticated users can view customers"
      ON customers FOR SELECT USING (auth.role() = 'authenticated');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'customers' AND policyname = 'Authenticated users can insert customers'
  ) THEN
    CREATE POLICY "Authenticated users can insert customers"
      ON customers FOR INSERT WITH CHECK (auth.role() = 'authenticated');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'customers' AND policyname = 'Authenticated users can update customers'
  ) THEN
    CREATE POLICY "Authenticated users can update customers"
      ON customers FOR UPDATE USING (auth.role() = 'authenticated');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'customers' AND policyname = 'Authenticated users can delete customers'
  ) THEN
    CREATE POLICY "Authenticated users can delete customers"
      ON customers FOR DELETE USING (auth.role() = 'authenticated');
  END IF;
END;
$$;

DROP TRIGGER IF EXISTS customers_updated_at ON customers;
CREATE TRIGGER customers_updated_at
  BEFORE UPDATE ON customers
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at();

-- 프로젝트에 customer_id 추가 (고객 1 : 프로젝트 N)
ALTER TABLE projects
  ADD COLUMN IF NOT EXISTS customer_id UUID REFERENCES customers(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_projects_customer_id ON projects(customer_id);

-- 기존 프로젝트 client(고객사명) -> 고객 마스터로 1회 이관
WITH legacy_clients AS (
  SELECT DISTINCT TRIM(client) AS client_name
  FROM projects
  WHERE client IS NOT NULL AND TRIM(client) <> ''
)
INSERT INTO customers (customer_type, name)
SELECT '회사', lc.client_name
FROM legacy_clients lc
WHERE NOT EXISTS (
  SELECT 1
  FROM customers c
  WHERE c.name = lc.client_name
);

-- 기존 프로젝트를 고객과 매칭
UPDATE projects p
SET customer_id = c.id
FROM (
  SELECT DISTINCT ON (name) id, name
  FROM customers
  ORDER BY name, created_at ASC
) c
WHERE p.customer_id IS NULL
  AND p.client IS NOT NULL
  AND TRIM(p.client) = c.name;


-- ============================================================
-- source: 20260304233500_revenues_global_management.sql
-- ============================================================
-- 매출 글로벌 관리 확장
-- 1) 프로젝트 미연결 매출 허용 (project_id nullable)
-- 2) 프로젝트 삭제 시 매출 보존 (FK ON DELETE SET NULL)

ALTER TABLE revenues
  ALTER COLUMN project_id DROP NOT NULL;

ALTER TABLE revenues
  DROP CONSTRAINT IF EXISTS revenues_project_id_fkey;

ALTER TABLE revenues
  ADD CONSTRAINT revenues_project_id_fkey
  FOREIGN KEY (project_id)
  REFERENCES projects(id)
  ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_revenues_project_id ON revenues(project_id);


-- ============================================================
-- source: 20260304235500_api_keys_settings.sql
-- ============================================================
-- 설정 화면에서 관리할 API 키 저장소

-- api_keys 테이블은 이미 20260304210000_api_keys.sql 에서 생성됨
-- 기존 컬럼명에 맞춰 인덱스만 추가
CREATE INDEX IF NOT EXISTS idx_api_keys_name_active ON api_keys(name, is_active);

ALTER TABLE api_keys ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'api_keys' AND policyname = 'Authenticated users can view api_keys'
  ) THEN
    CREATE POLICY "Authenticated users can view api_keys"
      ON api_keys FOR SELECT USING (auth.role() = 'authenticated');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'api_keys' AND policyname = 'Authenticated users can insert api_keys'
  ) THEN
    CREATE POLICY "Authenticated users can insert api_keys"
      ON api_keys FOR INSERT WITH CHECK (auth.role() = 'authenticated');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'api_keys' AND policyname = 'Authenticated users can update api_keys'
  ) THEN
    CREATE POLICY "Authenticated users can update api_keys"
      ON api_keys FOR UPDATE USING (auth.role() = 'authenticated');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'api_keys' AND policyname = 'Authenticated users can delete api_keys'
  ) THEN
    CREATE POLICY "Authenticated users can delete api_keys"
      ON api_keys FOR DELETE USING (auth.role() = 'authenticated');
  END IF;
END;
$$;

-- updated_at 트리거 함수 보장
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS api_keys_updated_at ON api_keys;
CREATE TRIGGER api_keys_updated_at
  BEFORE UPDATE ON api_keys
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at();


-- ============================================================
-- source: 20260305100000_customer_contacts.sql
-- ============================================================
-- 담당자 테이블 생성
CREATE TABLE IF NOT EXISTS customer_contacts (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  customer_id UUID NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  position TEXT,
  phone TEXT,
  email TEXT,
  memo TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- RLS
ALTER TABLE customer_contacts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can manage customer_contacts"
  ON customer_contacts FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);

-- updated_at 트리거
CREATE TRIGGER set_customer_contacts_updated_at
  BEFORE UPDATE ON customer_contacts
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at();

-- 인덱스
CREATE INDEX idx_customer_contacts_customer_id ON customer_contacts(customer_id);

-- 기존 contact 데이터를 customer_contacts로 마이그레이션
INSERT INTO customer_contacts (customer_id, name, phone, email)
SELECT id, contact_name, contact_phone, contact_email
FROM customers
WHERE contact_name IS NOT NULL AND contact_name != '';


-- ============================================================
-- source: 20260305120000_project_code_format.sql
-- ============================================================
-- 프로젝트 번호 체계 변경: PYYMM-NNN → YY-N

-- 1. 자동생성 함수 업데이트
CREATE OR REPLACE FUNCTION generate_project_number()
RETURNS TEXT AS $$
DECLARE
  yy TEXT;
  seq INT;
BEGIN
  yy := TO_CHAR(NOW(), 'YY');
  SELECT COALESCE(MAX(
    CAST(SPLIT_PART(project_number, '-', 2) AS INT)
  ), 0) + 1
  INTO seq
  FROM projects
  WHERE project_number LIKE yy || '-%'
    AND SPLIT_PART(project_number, '-', 2) ~ '^\d+$';

  RETURN yy || '-' || seq::TEXT;
END;
$$ LANGUAGE plpgsql;

-- 2. 기존 프로젝트 번호 마이그레이션
-- PYYMM-NNN → YY-순번 (생성일 기준 연도별 순번 재부여)
WITH numbered AS (
  SELECT
    id,
    SUBSTRING(project_number FROM 2 FOR 2) AS yy,
    ROW_NUMBER() OVER (
      PARTITION BY SUBSTRING(project_number FROM 2 FOR 2)
      ORDER BY created_at
    ) AS seq
  FROM projects
  WHERE project_number ~ '^P\d{4}-\d{3}$'
)
UPDATE projects
SET project_number = numbered.yy || '-' || numbered.seq::TEXT
FROM numbered
WHERE projects.id = numbered.id;


-- ============================================================
-- source: 20260305130000_schedule_category.sql
-- ============================================================
-- Replace color column with category column on schedules table
-- Map existing color values to categories where possible

ALTER TABLE schedules ADD COLUMN category TEXT NOT NULL DEFAULT 'other';

-- Map existing colors to categories
UPDATE schedules SET category = CASE color
  WHEN '#3b82f6' THEN 'meeting'
  WHEN '#8b5cf6' THEN 'lecture'
  WHEN '#f59e0b' THEN 'business_trip'
  WHEN '#22c55e' THEN 'vacation'
  WHEN '#ef4444' THEN 'deadline'
  ELSE 'other'
END;

ALTER TABLE schedules DROP COLUMN color;


-- ============================================================
-- source: 20260306071008_add_chat_usage_logs.sql
-- ============================================================
create table chat_usage_logs (
  id uuid primary key default gen_random_uuid(),
  user_auth_uid uuid not null,
  user_message text not null,
  assistant_message text,
  model text not null default 'claude-sonnet-4-6',
  input_tokens int not null default 0,
  output_tokens int not null default 0,
  input_cost numeric(10,6) not null default 0,
  output_cost numeric(10,6) not null default 0,
  total_cost numeric(10,6) not null default 0,
  tool_calls_count int not null default 0,
  created_at timestamptz not null default now()
);

create index idx_chat_usage_logs_user on chat_usage_logs (user_auth_uid);
create index idx_chat_usage_logs_created on chat_usage_logs (created_at desc);

alter table chat_usage_logs enable row level security;

create policy "Authenticated users can read all chat usage logs"
  on chat_usage_logs for select
  to authenticated
  using (true);

create policy "Authenticated users can insert own chat usage logs"
  on chat_usage_logs for insert
  to authenticated
  with check (auth.uid() = user_auth_uid);


-- ============================================================
-- source: 20260306071728_add_system_settings.sql
-- ============================================================
create table system_settings (
  key text primary key,
  value text not null,
  updated_at timestamptz not null default now()
);

alter table system_settings enable row level security;

create policy "Authenticated users can read system settings"
  on system_settings for select
  to authenticated
  using (true);

create policy "Authenticated users can upsert system settings"
  on system_settings for all
  to authenticated
  using (true)
  with check (true);

-- Default chat model
insert into system_settings (key, value) values ('chat_model', 'claude-sonnet-4-6');


-- ============================================================
-- source: 20260306100000_schedules.sql
-- ============================================================
-- ============================================
-- 일정(스케줄) 테이블
-- ============================================
CREATE TABLE schedules (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  title TEXT NOT NULL,
  description TEXT,
  start_at TIMESTAMPTZ NOT NULL,
  end_at TIMESTAMPTZ NOT NULL,
  all_day BOOLEAN DEFAULT FALSE,
  color TEXT DEFAULT '#3b82f6',
  location TEXT,
  created_by UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_schedules_start_at ON schedules(start_at);
CREATE INDEX idx_schedules_end_at ON schedules(end_at);
CREATE INDEX idx_schedules_created_by ON schedules(created_by);

ALTER TABLE schedules ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can view schedules"
  ON schedules FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "Authenticated users can insert schedules"
  ON schedules FOR INSERT WITH CHECK (auth.role() = 'authenticated');
CREATE POLICY "Authenticated users can update schedules"
  ON schedules FOR UPDATE USING (auth.role() = 'authenticated');
CREATE POLICY "Authenticated users can delete schedules"
  ON schedules FOR DELETE USING (auth.role() = 'authenticated');

CREATE TRIGGER schedules_updated_at
  BEFORE UPDATE ON schedules
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at();

-- ============================================
-- 일정 참석자 (다대다)
-- ============================================
CREATE TABLE schedule_attendees (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  schedule_id UUID NOT NULL REFERENCES schedules(id) ON DELETE CASCADE,
  employee_id UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(schedule_id, employee_id)
);

CREATE INDEX idx_schedule_attendees_schedule_id ON schedule_attendees(schedule_id);
CREATE INDEX idx_schedule_attendees_employee_id ON schedule_attendees(employee_id);

ALTER TABLE schedule_attendees ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can view schedule_attendees"
  ON schedule_attendees FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "Authenticated users can insert schedule_attendees"
  ON schedule_attendees FOR INSERT WITH CHECK (auth.role() = 'authenticated');
CREATE POLICY "Authenticated users can update schedule_attendees"
  ON schedule_attendees FOR UPDATE USING (auth.role() = 'authenticated');
CREATE POLICY "Authenticated users can delete schedule_attendees"
  ON schedule_attendees FOR DELETE USING (auth.role() = 'authenticated');


-- ============================================================
-- source: 20260306110000_tax_invoice_not_required.sql
-- ============================================================
-- Add tax_invoice_not_required column to revenues table
ALTER TABLE revenues
  ADD COLUMN tax_invoice_not_required boolean NOT NULL DEFAULT false;


-- ============================================================
-- source: 20260306120000_leads.sql
-- ============================================================
-- Lead Management table
CREATE TABLE leads (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- 기본 정보 (폼 필드)
  company_name TEXT NOT NULL,
  contact_name TEXT NOT NULL,
  phone TEXT NOT NULL,
  email TEXT,
  position TEXT,

  -- 문의 정보
  referral_source TEXT,
  industry TEXT,
  automation_areas TEXT[],
  budget TEXT,
  desired_timeline TEXT,
  inquiry_detail TEXT,

  -- 관리 정보
  status TEXT NOT NULL DEFAULT '신규'
    CHECK (status IN ('신규', '상담중', '견적발송', '계약완료', '실패', '보류')),
  source TEXT NOT NULL DEFAULT '폼문의'
    CHECK (source IN ('폼문의', '전화', '이메일', '소개', '기타')),
  assigned_to UUID REFERENCES employees(id) ON DELETE SET NULL,

  -- 전환 연결
  customer_id UUID REFERENCES customers(id) ON DELETE SET NULL,

  -- 메모
  memo TEXT,

  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_leads_status ON leads(status);
CREATE INDEX idx_leads_customer_id ON leads(customer_id);
CREATE INDEX idx_leads_assigned_to ON leads(assigned_to);

-- updated_at trigger
CREATE TRIGGER set_leads_updated_at
  BEFORE UPDATE ON leads
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at();

-- RLS
ALTER TABLE leads ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can select leads"
  ON leads FOR SELECT TO authenticated USING (true);

CREATE POLICY "Authenticated users can insert leads"
  ON leads FOR INSERT TO authenticated WITH CHECK (true);

CREATE POLICY "Authenticated users can update leads"
  ON leads FOR UPDATE TO authenticated USING (true) WITH CHECK (true);

CREATE POLICY "Authenticated users can delete leads"
  ON leads FOR DELETE TO authenticated USING (true);


-- ============================================================
-- source: 20260307094738_add_task_sort_order.sql
-- ============================================================
-- Add sort_order column for drag-and-drop reordering
ALTER TABLE tasks ADD COLUMN sort_order integer NOT NULL DEFAULT 0;

-- Initialize sort_order based on created_at (oldest first = lowest number)
WITH numbered AS (
  SELECT id, ROW_NUMBER() OVER (ORDER BY created_at ASC) AS rn
  FROM tasks
)
UPDATE tasks SET sort_order = numbered.rn FROM numbered WHERE tasks.id = numbered.id;

-- Index for efficient ordering
CREATE INDEX idx_tasks_sort_order ON tasks (category, sort_order);


-- ============================================================
-- source: 20260307100000_app_logs.sql
-- ============================================================
CREATE TABLE app_logs (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  level TEXT NOT NULL DEFAULT 'INFO' CHECK (level IN ('INFO', 'ERROR')),
  action TEXT NOT NULL,
  resource TEXT,
  resource_id TEXT,
  message TEXT NOT NULL,
  actor_id TEXT,
  actor_name TEXT,
  ip_address TEXT,
  details JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_app_logs_created_at ON app_logs(created_at DESC);
CREATE INDEX idx_app_logs_level ON app_logs(level);

ALTER TABLE app_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "auth_select" ON app_logs FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "auth_insert" ON app_logs FOR INSERT WITH CHECK (auth.role() = 'authenticated');


-- ============================================================
-- source: 20260307120000_imweb_tax_invoice_not_required.sql
-- ============================================================
-- 아임웹 채널 매출은 세금계산서 발행 불필요
-- 기존 아임웹 매출 전체 업데이트
UPDATE revenues
SET tax_invoice_not_required = true
WHERE channel = '아임웹';


-- ============================================================
-- source: 20260307130000_add_expected_payment_date.sql
-- ============================================================
ALTER TABLE revenues ADD COLUMN IF NOT EXISTS expected_payment_date date;


-- ============================================================
-- source: 20260307150000_agent_memories.sql
-- ============================================================
create table if not exists agent_memories (
  id uuid primary key default gen_random_uuid(),
  user_auth_uid uuid not null,
  namespace text not null,
  key text not null,
  value jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_auth_uid, namespace, key)
);

create index if not exists idx_agent_memories_user_namespace
  on agent_memories (user_auth_uid, namespace);

alter table agent_memories enable row level security;

create policy "Authenticated users can read own agent memories"
  on agent_memories for select
  to authenticated
  using (auth.uid() = user_auth_uid);

create policy "Authenticated users can write own agent memories"
  on agent_memories for all
  to authenticated
  using (auth.uid() = user_auth_uid)
  with check (auth.uid() = user_auth_uid);

create trigger agent_memories_updated_at
  before update on agent_memories
  for each row
  execute function update_updated_at();


-- ============================================================
-- source: 20260307153000_employee_last_login_at.sql
-- ============================================================
ALTER TABLE employees
  ADD COLUMN IF NOT EXISTS last_login_at TIMESTAMPTZ;


-- ============================================================
-- source: 20260308100000_quotations.sql
-- ============================================================
-- 견적 관리 테이블

-- 0. updated_at 트리거 함수 (없으면 생성)
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 1. quotations 테이블
CREATE TABLE quotations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  quotation_number TEXT UNIQUE NOT NULL,
  quotation_date DATE NOT NULL DEFAULT CURRENT_DATE,
  valid_until DATE,
  status TEXT NOT NULL DEFAULT '작성중'
    CHECK (status IN ('작성중', '발송완료', '수락', '거절', '만료')),

  -- 수신자
  customer_id UUID REFERENCES customers(id) ON DELETE SET NULL,
  recipient_name TEXT NOT NULL,
  recipient_contact_name TEXT,
  recipient_phone TEXT,
  recipient_address TEXT,

  -- 공급자
  supplier_name TEXT NOT NULL DEFAULT '',
  supplier_representative TEXT NOT NULL DEFAULT '',
  supplier_business_number TEXT NOT NULL DEFAULT '',
  supplier_phone TEXT NOT NULL DEFAULT '',
  supplier_manager TEXT NOT NULL DEFAULT '',
  supplier_address TEXT DEFAULT '',
  supplier_business_type TEXT DEFAULT '',
  supplier_business_category TEXT DEFAULT '',

  -- 합계 (비정규화)
  supply_total BIGINT NOT NULL DEFAULT 0,
  vat_total BIGINT NOT NULL DEFAULT 0,
  grand_total BIGINT NOT NULL DEFAULT 0,

  -- 조건
  payment_terms TEXT,
  delivery_terms TEXT,
  bank_account TEXT NOT NULL DEFAULT '',
  memo TEXT,

  -- 연결
  project_id UUID REFERENCES projects(id) ON DELETE SET NULL,

  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 2. quotation_items 테이블
CREATE TABLE quotation_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  quotation_id UUID NOT NULL REFERENCES quotations(id) ON DELETE CASCADE,
  sort_order INT NOT NULL DEFAULT 0,
  item_name TEXT NOT NULL,
  specification TEXT DEFAULT '',
  unit TEXT NOT NULL DEFAULT '식',
  quantity INT NOT NULL DEFAULT 1,
  unit_price BIGINT NOT NULL DEFAULT 0,
  supply_amount BIGINT NOT NULL DEFAULT 0,
  remark TEXT DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 3. 견적번호 자동생성 함수
CREATE OR REPLACE FUNCTION generate_quotation_number()
RETURNS TEXT AS $$
DECLARE
  yymm TEXT;
  seq INT;
BEGIN
  yymm := TO_CHAR(NOW(), 'YYMM');
  SELECT COALESCE(MAX(
    CAST(SPLIT_PART(quotation_number, '-', 3) AS INT)
  ), 0) + 1
  INTO seq
  FROM quotations
  WHERE quotation_number LIKE 'QT-' || yymm || '-%'
    AND SPLIT_PART(quotation_number, '-', 3) ~ '^\d+$';

  RETURN 'QT-' || yymm || '-' || LPAD(seq::TEXT, 3, '0');
END;
$$ LANGUAGE plpgsql;

-- 4. updated_at 트리거
CREATE TRIGGER set_quotations_updated_at
  BEFORE UPDATE ON quotations
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER set_quotation_items_updated_at
  BEFORE UPDATE ON quotation_items
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- 5. 인덱스
CREATE INDEX idx_quotations_status ON quotations(status);
CREATE INDEX idx_quotations_quotation_date ON quotations(quotation_date);
CREATE INDEX idx_quotations_customer_id ON quotations(customer_id);
CREATE INDEX idx_quotations_project_id ON quotations(project_id);
CREATE INDEX idx_quotation_items_quotation_id ON quotation_items(quotation_id);

-- 6. RLS
ALTER TABLE quotations ENABLE ROW LEVEL SECURITY;
ALTER TABLE quotation_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can manage quotations"
  ON quotations FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);

CREATE POLICY "Authenticated users can manage quotation_items"
  ON quotation_items FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);


-- ============================================================
-- source: 20260308120000_schedule_project_link.sql
-- ============================================================
ALTER TABLE schedules
ADD COLUMN IF NOT EXISTS project_id UUID REFERENCES projects(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_schedules_project_id ON schedules(project_id);


-- ============================================================
-- source: 20260308123000_task_project_link.sql
-- ============================================================
ALTER TABLE tasks
ADD COLUMN IF NOT EXISTS project_id UUID REFERENCES projects(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_tasks_project_id ON tasks(project_id);


-- ============================================================
-- source: 20260309090000_revenue_tax_invoice_workflow.sql
-- ============================================================
alter table revenues
  add column if not exists tax_invoice_issue_status text not null default 'not_issued',
  add column if not exists tax_invoice_issuance_key text,
  add column if not exists tax_invoice_client_reference_id text,
  add column if not exists tax_invoice_issue_requested_at timestamptz,
  add column if not exists tax_invoice_issued_at timestamptz,
  add column if not exists tax_invoice_last_webhook_at timestamptz,
  add column if not exists tax_invoice_url text,
  add column if not exists tax_invoice_nts_transaction_id text,
  add column if not exists tax_invoice_error_code text,
  add column if not exists tax_invoice_error_message text,
  add column if not exists tax_invoice_request_payload jsonb,
  add column if not exists tax_invoice_last_payload jsonb;

update revenues
set tax_invoice_issue_status =
  case
    when is_tax_invoice_issued then 'issued'
    else 'not_issued'
  end
where tax_invoice_issue_status is distinct from
  case
    when is_tax_invoice_issued then 'issued'
    else 'not_issued'
  end;

alter table revenues
  drop constraint if exists revenues_tax_invoice_issue_status_check;

alter table revenues
  add constraint revenues_tax_invoice_issue_status_check
  check (tax_invoice_issue_status in ('not_issued', 'issuing', 'issued', 'failed'));

create index if not exists idx_revenues_tax_invoice_issue_status
  on revenues(tax_invoice_issue_status);

create index if not exists idx_revenues_tax_invoice_issuance_key
  on revenues(tax_invoice_issuance_key)
  where tax_invoice_issuance_key is not null;

create index if not exists idx_revenues_tax_invoice_client_reference_id
  on revenues(tax_invoice_client_reference_id)
  where tax_invoice_client_reference_id is not null;


-- ============================================================
-- source: 20260309100000_project_types.sql
-- ============================================================
-- 프로젝트 유형 테이블
CREATE TABLE project_types (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL UNIQUE,
  sort_order INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 기본 유형 삽입
INSERT INTO project_types (name, sort_order) VALUES
  ('에이전시', 1),
  ('강의', 2),
  ('구독', 3);

-- projects 테이블에 type_id 컬럼 추가
ALTER TABLE projects ADD COLUMN type_id UUID REFERENCES project_types(id) ON DELETE SET NULL;

-- RLS
ALTER TABLE project_types ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated users can read project_types"
  ON project_types FOR SELECT TO authenticated USING (true);
CREATE POLICY "Authenticated users can insert project_types"
  ON project_types FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "Authenticated users can update project_types"
  ON project_types FOR UPDATE TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "Authenticated users can delete project_types"
  ON project_types FOR DELETE TO authenticated USING (true);


-- ============================================================
-- source: 20260309110000_add_customer_representative_name.sql
-- ============================================================
ALTER TABLE customers
  ADD COLUMN IF NOT EXISTS representative_name TEXT;


-- ============================================================
-- source: 20260309113000_project_notes.sql
-- ============================================================
create table if not exists project_notes (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references projects(id) on delete cascade,
  title text,
  content text,
  link_url text,
  author_employee_id uuid references employees(id) on delete set null,
  author_name text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (
    coalesce(
      nullif(btrim(title), ''),
      nullif(btrim(content), ''),
      nullif(btrim(link_url), '')
    ) is not null
  )
);

create index if not exists idx_project_notes_project_id_created_at
  on project_notes (project_id, created_at desc);

alter table project_notes enable row level security;

create policy "Authenticated users can select project notes"
  on project_notes for select
  to authenticated
  using (true);

create policy "Authenticated users can insert project notes"
  on project_notes for insert
  to authenticated
  with check (true);

create policy "Authenticated users can update project notes"
  on project_notes for update
  to authenticated
  using (true);

create policy "Authenticated users can delete project notes"
  on project_notes for delete
  to authenticated
  using (true);

drop trigger if exists project_notes_updated_at on project_notes;

create trigger project_notes_updated_at
  before update on project_notes
  for each row
  execute function update_updated_at();


-- ============================================================
-- source: 20260310100000_project_status_planned.sql
-- ============================================================
-- Add "진행예정" status to projects and update default
ALTER TABLE projects ALTER COLUMN status SET DEFAULT '진행예정';


-- ============================================================
-- source: 20260310101500_lead_comments_update_delete_policies.sql
-- ============================================================
create policy "Authenticated users can update lead comments"
  on lead_comments for update
  to authenticated
  using (true)
  with check (true);

create policy "Authenticated users can delete lead comments"
  on lead_comments for delete
  to authenticated
  using (true);


-- ============================================================
-- source: 20260310103000_add_meeting_summary.sql
-- ============================================================
ALTER TABLE meetings
ADD COLUMN IF NOT EXISTS summary TEXT NOT NULL DEFAULT '';


-- ============================================================
-- source: 20260310123000_refund_tax_invoice_not_required.sql
-- ============================================================
-- 환불 매출은 세금계산서 발행 대상이 아님
UPDATE revenues
SET
  tax_invoice_not_required = TRUE,
  is_tax_invoice_issued = FALSE,
  tax_invoice_date = NULL,
  tax_invoice_issue_status = 'not_issued',
  tax_invoice_issue_requested_at = NULL,
  tax_invoice_issued_at = NULL,
  tax_invoice_url = NULL,
  tax_invoice_nts_transaction_id = NULL,
  tax_invoice_error_code = NULL,
  tax_invoice_error_message = NULL
WHERE total_amount < 0
  AND (
    COALESCE(tax_invoice_not_required, FALSE) = FALSE
    OR COALESCE(is_tax_invoice_issued, FALSE) = TRUE
    OR tax_invoice_date IS NOT NULL
    OR COALESCE(tax_invoice_issue_status, 'not_issued') <> 'not_issued'
  );


-- ============================================================
-- source: 20260310123100_tasks_status_refactor.sql
-- ============================================================
ALTER TABLE tasks DROP CONSTRAINT IF EXISTS tasks_status_check;
ALTER TABLE tasks DROP CONSTRAINT IF EXISTS tasks_category_check;

UPDATE tasks
SET status = CASE
  WHEN status = '보류' THEN '취소'
  WHEN category = 'backlog' AND status = '대기' THEN '백로그'
  WHEN status = '대기' THEN '할 일'
  ELSE status
END;

DROP INDEX IF EXISTS idx_tasks_sort_order;

ALTER TABLE tasks
  DROP COLUMN IF EXISTS category;

ALTER TABLE tasks
  ALTER COLUMN status SET DEFAULT '할 일';

ALTER TABLE tasks
  ADD CONSTRAINT tasks_status_check
  CHECK (status IN ('백로그', '할 일', '진행중', '완료', '취소'));

CREATE INDEX IF NOT EXISTS idx_tasks_sort_order ON tasks(sort_order);


-- ============================================================
-- source: 20260310140000_business_cards.sql
-- ============================================================
create table business_cards (
  id uuid default gen_random_uuid() primary key,
  name text not null,
  company_name text,
  position text,
  email text,
  phone text,
  input_method text not null default 'manual' check (input_method in ('photo', 'manual')),
  image_name text,
  image_mime_type text,
  image_base64 text,
  ocr_raw_text text,
  created_by uuid references employees(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index idx_business_cards_created_at on business_cards(created_at desc);
create index idx_business_cards_name on business_cards(name);
create index idx_business_cards_company_name on business_cards(company_name);
create index idx_business_cards_email on business_cards(email);
create index idx_business_cards_phone on business_cards(phone);

alter table business_cards enable row level security;

create policy "Authenticated users can view business_cards"
  on business_cards for select
  to authenticated
  using (true);

create policy "Authenticated users can insert business_cards"
  on business_cards for insert
  to authenticated
  with check (true);

create policy "Authenticated users can update business_cards"
  on business_cards for update
  to authenticated
  using (true)
  with check (true);

create policy "Authenticated users can delete business_cards"
  on business_cards for delete
  to authenticated
  using (true);

create trigger business_cards_updated_at
  before update on business_cards
  for each row
  execute function update_updated_at();


-- ============================================================
-- source: 20260310143000_gemini_usage_logs.sql
-- ============================================================
create table gemini_usage_logs (
  id uuid primary key default gen_random_uuid(),
  user_auth_uid uuid not null,
  feature text not null default 'business_card_ocr',
  model text not null,
  input_tokens int not null default 0,
  output_tokens int not null default 0,
  input_cost numeric(10,6) not null default 0,
  output_cost numeric(10,6) not null default 0,
  total_cost numeric(10,6) not null default 0,
  image_count int not null default 1,
  request_summary text,
  created_at timestamptz not null default now()
);

create index idx_gemini_usage_logs_user on gemini_usage_logs(user_auth_uid);
create index idx_gemini_usage_logs_feature on gemini_usage_logs(feature);
create index idx_gemini_usage_logs_created on gemini_usage_logs(created_at desc);

alter table gemini_usage_logs enable row level security;

create policy "Authenticated users can read all gemini usage logs"
  on gemini_usage_logs for select
  to authenticated
  using (true);

create policy "Authenticated users can insert own gemini usage logs"
  on gemini_usage_logs for insert
  to authenticated
  with check (auth.uid() = user_auth_uid);


-- ============================================================
-- source: 20260310161000_business_cards_address_and_drive.sql
-- ============================================================
alter table business_cards
  add column if not exists address text,
  add column if not exists drive_file_id text,
  add column if not exists drive_web_view_link text,
  add column if not exists drive_web_content_link text;


-- ============================================================
-- source: 20260310222000_employee_slack_id_schedule_reminder.sql
-- ============================================================
ALTER TABLE employees
  ADD COLUMN IF NOT EXISTS slack_id TEXT;

-- 직원별 Slack 멤버 ID는 직원관리 화면에서 직접 입력합니다.

ALTER TABLE schedules
  ADD COLUMN IF NOT EXISTS slack_reminder_sent_at TIMESTAMPTZ;

CREATE OR REPLACE FUNCTION reset_schedule_slack_reminder_sent_at()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'UPDATE' AND (
    NEW.start_at IS DISTINCT FROM OLD.start_at OR
    NEW.end_at IS DISTINCT FROM OLD.end_at OR
    NEW.all_day IS DISTINCT FROM OLD.all_day
  ) THEN
    NEW.slack_reminder_sent_at = NULL;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS schedules_reset_slack_reminder_sent_at ON schedules;

CREATE TRIGGER schedules_reset_slack_reminder_sent_at
  BEFORE UPDATE ON schedules
  FOR EACH ROW
  EXECUTE FUNCTION reset_schedule_slack_reminder_sent_at();

CREATE INDEX IF NOT EXISTS idx_schedules_slack_reminder_pending
  ON schedules(start_at)
  WHERE slack_reminder_sent_at IS NULL AND all_day = FALSE;


-- ============================================================
-- source: 20260311100000_revenue_channel_product.sql
-- ============================================================
-- 매출 테이블에 판매채널/상품 관련 컬럼 추가
ALTER TABLE revenues
  ADD COLUMN channel TEXT,
  ADD COLUMN product_name TEXT,
  ADD COLUMN external_order_id TEXT;

-- 채널별 조회 인덱스
CREATE INDEX idx_revenues_channel ON revenues(channel);


-- ============================================================
-- source: 20260312090000_add_customer_id_to_meetings.sql
-- ============================================================
ALTER TABLE meetings
ADD COLUMN customer_id UUID REFERENCES customers(id) ON DELETE SET NULL;

CREATE INDEX idx_meetings_customer_id ON meetings(customer_id);


-- ============================================================
-- source: 20260312100000_contracts.sql
-- ============================================================
-- 계약 관리

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TABLE contract_templates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  description TEXT,
  title_template TEXT NOT NULL DEFAULT '{{contract_title}}',
  body_template TEXT NOT NULL DEFAULT '{{contract_body}}',
  default_variables JSONB NOT NULL DEFAULT '{}'::jsonb,
  owner_auth_uid UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE contracts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  template_id UUID REFERENCES contract_templates(id) ON DELETE SET NULL,
  customer_id UUID REFERENCES customers(id) ON DELETE SET NULL,
  project_id UUID REFERENCES projects(id) ON DELETE SET NULL,

  title TEXT NOT NULL,
  content TEXT NOT NULL,
  variables JSONB NOT NULL DEFAULT '{}'::jsonb,
  status TEXT NOT NULL DEFAULT '작성중'
    CHECK (status IN ('작성중', '발송완료', '완료', '취소')),

  customer_name TEXT,
  customer_phone TEXT,
  customer_email TEXT,

  owner_auth_uid UUID,
  owner_name TEXT,
  owner_email TEXT,

  internal_sign_type TEXT CHECK (internal_sign_type IN ('서명', '도장')),
  internal_signer_name TEXT,
  internal_signature_data TEXT,
  internal_signed_at TIMESTAMPTZ,

  customer_sign_type TEXT CHECK (customer_sign_type IN ('서명', '도장')),
  customer_signer_name TEXT,
  customer_signature_data TEXT,
  customer_signed_at TIMESTAMPTZ,

  sign_token TEXT,
  sign_requested_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,

  pdf_file_name TEXT,
  pdf_size_bytes INTEGER,
  pdf_sha256 TEXT,
  pdf_generated_at TIMESTAMPTZ,

  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE contract_audit_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  contract_id UUID NOT NULL REFERENCES contracts(id) ON DELETE CASCADE,
  action TEXT NOT NULL,
  actor_type TEXT NOT NULL DEFAULT 'system'
    CHECK (actor_type IN ('internal', 'customer', 'system')),
  actor_id TEXT,
  actor_name TEXT,
  actor_email TEXT,
  ip_address TEXT,
  user_agent TEXT,
  details JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER set_contract_templates_updated_at
  BEFORE UPDATE ON contract_templates
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER set_contracts_updated_at
  BEFORE UPDATE ON contracts
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

CREATE UNIQUE INDEX idx_contracts_sign_token
  ON contracts(sign_token)
  WHERE sign_token IS NOT NULL;

CREATE INDEX idx_contracts_status ON contracts(status);
CREATE INDEX idx_contracts_customer_id ON contracts(customer_id);
CREATE INDEX idx_contract_audit_logs_contract_id ON contract_audit_logs(contract_id);
CREATE INDEX idx_contract_audit_logs_created_at ON contract_audit_logs(created_at DESC);

ALTER TABLE contract_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE contracts ENABLE ROW LEVEL SECURITY;
ALTER TABLE contract_audit_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can manage contract_templates"
  ON contract_templates FOR ALL TO authenticated
  USING (true)
  WITH CHECK (true);

CREATE POLICY "Authenticated users can manage contracts"
  ON contracts FOR ALL TO authenticated
  USING (true)
  WITH CHECK (true);

CREATE POLICY "Authenticated users can select contract_audit_logs"
  ON contract_audit_logs FOR SELECT TO authenticated
  USING (true);

CREATE POLICY "Authenticated users can insert contract_audit_logs"
  ON contract_audit_logs FOR INSERT TO authenticated
  WITH CHECK (true);


-- ============================================================
-- source: 20260313100000_deposits.sql
-- ============================================================
-- 입금관리 테이블
create table if not exists public.deposits (
  id uuid primary key default gen_random_uuid(),
  deposit_date date not null,
  amount integer not null check (amount > 0),
  depositor_name text not null,
  bank_name text,
  account_alias text,
  revenue_id uuid references public.revenues(id) on delete set null,
  source text not null default 'manual' check (source in ('webhook', 'manual')),
  raw_message text,
  memo text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- updated_at 트리거
create trigger set_deposits_updated_at
  before update on public.deposits
  for each row
  execute function update_updated_at();

-- RLS
alter table public.deposits enable row level security;

create policy "Authenticated users can read deposits"
  on public.deposits for select
  to authenticated
  using (true);

create policy "Authenticated users can insert deposits"
  on public.deposits for insert
  to authenticated
  with check (true);

create policy "Authenticated users can update deposits"
  on public.deposits for update
  to authenticated
  using (true)
  with check (true);

create policy "Authenticated users can delete deposits"
  on public.deposits for delete
  to authenticated
  using (true);

-- Service role (webhook API용) full access
create policy "Service role full access on deposits"
  on public.deposits for all
  to service_role
  using (true)
  with check (true);


-- ============================================================
-- source: 20260314100000_quotation_versioning.sql
-- ============================================================
-- 견적서 번호 체계 변경 (Q2603-K1 형태) + 버전 관리

-- 1. version, parent_id 컬럼 추가
ALTER TABLE quotations
  ADD COLUMN version INT NOT NULL DEFAULT 1,
  ADD COLUMN parent_id UUID REFERENCES quotations(id) ON DELETE SET NULL;

CREATE INDEX idx_quotations_parent_id ON quotations(parent_id);

-- 2. 견적번호 생성 함수 변경: Q{YYMM}-{letter}{digit} 형태
CREATE OR REPLACE FUNCTION generate_quotation_number()
RETURNS TEXT AS $$
DECLARE
  yymm TEXT;
  letters TEXT := 'ABCDEFGHJKLMNPQRSTUVWXYZ';  -- I, O 제외 (1, 0과 혼동)
  digits TEXT := '123456789';                    -- 0 제외
  letter CHAR(1);
  digit CHAR(1);
  candidate TEXT;
  attempts INT := 0;
BEGIN
  yymm := TO_CHAR(NOW(), 'YYMM');

  LOOP
    letter := SUBSTR(letters, FLOOR(RANDOM() * LENGTH(letters) + 1)::INT, 1);
    digit := SUBSTR(digits, FLOOR(RANDOM() * LENGTH(digits) + 1)::INT, 1);
    candidate := 'Q' || yymm || '-' || letter || digit;

    -- 중복 확인
    IF NOT EXISTS (SELECT 1 FROM quotations WHERE quotation_number = candidate) THEN
      RETURN candidate;
    END IF;

    attempts := attempts + 1;
    IF attempts > 100 THEN
      RAISE EXCEPTION 'Failed to generate unique quotation number after 100 attempts';
    END IF;
  END LOOP;
END;
$$ LANGUAGE plpgsql;


-- ============================================================
-- source: 20260315100000_employee_login_security.sql
-- ============================================================
-- 직원 로그인 보안(무차별 대입 방지)

ALTER TABLE employees
  ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS failed_login_count INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS failed_login_window_started_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS last_failed_login_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS last_login_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_employees_is_active ON employees(is_active);
CREATE INDEX IF NOT EXISTS idx_employees_login_id ON employees(login_id);


-- ============================================================
-- source: 20260315110000_tasks.sql
-- ============================================================
-- 업무 관리 테이블
create table if not exists public.tasks (
  id uuid default gen_random_uuid() primary key,
  title text not null,
  description text,
  category text not null default 'todo' check (category in ('todo', 'backlog')),
  status text not null default '대기' check (status in ('대기', '진행중', '완료', '보류')),
  priority text not null default '보통' check (priority in ('높음', '보통', '낮음')),
  assigned_to uuid references public.employees(id) on delete set null,
  due_date date,
  created_by uuid references public.employees(id) on delete set null,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table public.tasks enable row level security;

create policy "Authenticated users can manage tasks"
  on public.tasks
  for all
  to authenticated
  using (true)
  with check (true);


-- ============================================================
-- source: 20260315113000_tasks_updated_at_trigger.sql
-- ============================================================
-- tasks.updated_at 자동 갱신 트리거

drop trigger if exists tasks_updated_at on public.tasks;

create trigger tasks_updated_at
  before update on public.tasks
  for each row
  execute function update_updated_at();


-- ============================================================
-- source: 20260316100000_schedule_categories_table.sql
-- ============================================================
-- 일정 유형 관리 테이블
CREATE TABLE IF NOT EXISTS schedule_categories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  value TEXT NOT NULL UNIQUE,
  label TEXT NOT NULL,
  color TEXT NOT NULL DEFAULT '#6b7280',
  sort_order INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE schedule_categories ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can read schedule_categories"
  ON schedule_categories FOR SELECT TO authenticated USING (true);

CREATE POLICY "Authenticated users can manage schedule_categories"
  ON schedule_categories FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- 기본 데이터 삽입
INSERT INTO schedule_categories (value, label, color, sort_order) VALUES
  ('meeting', '미팅', '#3b82f6', 1),
  ('lecture', '강의', '#8b5cf6', 2),
  ('business_trip', '출장', '#f59e0b', 3),
  ('vacation', '휴가', '#22c55e', 4),
  ('deadline', '마감', '#ef4444', 5),
  ('other', '기타', '#6b7280', 6)
ON CONFLICT (value) DO NOTHING;


-- ============================================================
-- source: 20260317100000_revenue_allow_negative.sql
-- ============================================================
-- 환불 매출 처리를 위해 음수 금액 허용
-- 기존 CHECK 제약조건이 있으면 제거
ALTER TABLE revenues DROP CONSTRAINT IF EXISTS revenues_total_amount_check;
ALTER TABLE revenues DROP CONSTRAINT IF EXISTS revenues_supply_amount_check;
ALTER TABLE revenues DROP CONSTRAINT IF EXISTS revenues_vat_amount_check;


-- ============================================================
-- source: 20260317110000_project_assignees.sql
-- ============================================================
CREATE TABLE project_assignees (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  employee_id UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(project_id, employee_id)
);

CREATE INDEX idx_project_assignees_project_id ON project_assignees(project_id);
CREATE INDEX idx_project_assignees_employee_id ON project_assignees(employee_id);

ALTER TABLE project_assignees ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can view project_assignees"
  ON project_assignees FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "Authenticated users can insert project_assignees"
  ON project_assignees FOR INSERT WITH CHECK (auth.role() = 'authenticated');
CREATE POLICY "Authenticated users can update project_assignees"
  ON project_assignees FOR UPDATE USING (auth.role() = 'authenticated');
CREATE POLICY "Authenticated users can delete project_assignees"
  ON project_assignees FOR DELETE USING (auth.role() = 'authenticated');

INSERT INTO project_assignees (project_id, employee_id)
SELECT DISTINCT p.id, e.id
FROM projects p
CROSS JOIN LATERAL regexp_split_to_table(COALESCE(p.manager, ''), '\s*,\s*') AS manager_name
JOIN employees e ON e.name = manager_name
WHERE manager_name <> ''
ON CONFLICT (project_id, employee_id) DO NOTHING;


-- ============================================================
-- source: 20260317113000_schedule_agent_guards.sql
-- ============================================================
create or replace function public.replace_schedule_attendees_atomic(
  p_schedule_ids uuid[],
  p_attendee_ids uuid[],
  p_actor_employee_id uuid,
  p_is_admin boolean default false
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  accessible_count integer;
  requested_count integer;
begin
  requested_count := coalesce(array_length(p_schedule_ids, 1), 0);

  if requested_count = 0 then
    return;
  end if;

  if not p_is_admin then
    select count(distinct s.id)
      into accessible_count
    from schedules s
    left join schedule_attendees sa
      on sa.schedule_id = s.id
    where s.id = any(p_schedule_ids)
      and (s.created_by = p_actor_employee_id or sa.employee_id = p_actor_employee_id);

    if accessible_count <> requested_count then
      raise exception 'schedule access denied';
    end if;
  end if;

  delete from schedule_attendees
  where schedule_id = any(p_schedule_ids);

  if coalesce(array_length(p_attendee_ids, 1), 0) = 0 then
    return;
  end if;

  insert into schedule_attendees (schedule_id, employee_id)
  select schedule_id, employee_id
  from unnest(p_schedule_ids) as schedule_id
  cross join unnest(p_attendee_ids) as employee_id;
end;
$$;


-- ============================================================
-- source: 20260317113100_schedule_agent_guards_grant.sql
-- ============================================================
grant execute on function public.replace_schedule_attendees_atomic(uuid[], uuid[], uuid, boolean) to authenticated;


-- ============================================================
-- source: 20260317113200_task_assignees.sql
-- ============================================================
CREATE TABLE task_assignees (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  task_id UUID NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  employee_id UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(task_id, employee_id)
);

CREATE INDEX idx_task_assignees_task_id ON task_assignees(task_id);
CREATE INDEX idx_task_assignees_employee_id ON task_assignees(employee_id);

ALTER TABLE task_assignees ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can view task_assignees"
  ON task_assignees FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "Authenticated users can insert task_assignees"
  ON task_assignees FOR INSERT WITH CHECK (auth.role() = 'authenticated');
CREATE POLICY "Authenticated users can update task_assignees"
  ON task_assignees FOR UPDATE USING (auth.role() = 'authenticated');
CREATE POLICY "Authenticated users can delete task_assignees"
  ON task_assignees FOR DELETE USING (auth.role() = 'authenticated');

INSERT INTO task_assignees (task_id, employee_id)
SELECT id, assigned_to
FROM tasks
WHERE assigned_to IS NOT NULL
ON CONFLICT (task_id, employee_id) DO NOTHING;


-- ============================================================
-- source: 20260317113300_lead_comments.sql
-- ============================================================
create table if not exists lead_comments (
  id uuid primary key default gen_random_uuid(),
  lead_id uuid not null references leads(id) on delete cascade,
  author_employee_id uuid references employees(id) on delete set null,
  author_name text not null,
  content text not null check (char_length(btrim(content)) > 0),
  created_at timestamptz not null default now()
);

create index if not exists idx_lead_comments_lead_id_created_at
  on lead_comments (lead_id, created_at desc);

alter table lead_comments enable row level security;

create policy "Authenticated users can select lead comments"
  on lead_comments for select
  to authenticated
  using (true);

create policy "Authenticated users can insert lead comments"
  on lead_comments for insert
  to authenticated
  with check (true);


-- ============================================================
-- source: 20260317113400_suggestions_board.sql
-- ============================================================
create table if not exists suggestion_posts (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(btrim(title)) > 0),
  content text not null check (char_length(btrim(content)) > 0),
  author_employee_id uuid references employees(id) on delete set null,
  author_name text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_suggestion_posts_created_at
  on suggestion_posts (created_at desc);

alter table suggestion_posts enable row level security;

create policy "Authenticated users can select suggestion posts"
  on suggestion_posts for select
  to authenticated
  using (true);

create policy "Authenticated users can insert suggestion posts"
  on suggestion_posts for insert
  to authenticated
  with check (true);

create policy "Authenticated users can update suggestion posts"
  on suggestion_posts for update
  to authenticated
  using (true);

create policy "Authenticated users can delete suggestion posts"
  on suggestion_posts for delete
  to authenticated
  using (true);

drop trigger if exists suggestion_posts_updated_at on suggestion_posts;

create trigger suggestion_posts_updated_at
  before update on suggestion_posts
  for each row
  execute function update_updated_at();

create table if not exists suggestion_comments (
  id uuid primary key default gen_random_uuid(),
  suggestion_id uuid not null references suggestion_posts(id) on delete cascade,
  author_employee_id uuid references employees(id) on delete set null,
  author_name text not null,
  content text not null check (char_length(btrim(content)) > 0),
  created_at timestamptz not null default now()
);

create index if not exists idx_suggestion_comments_suggestion_id_created_at
  on suggestion_comments (suggestion_id, created_at desc);

alter table suggestion_comments enable row level security;

create policy "Authenticated users can select suggestion comments"
  on suggestion_comments for select
  to authenticated
  using (true);

create policy "Authenticated users can insert suggestion comments"
  on suggestion_comments for insert
  to authenticated
  with check (true);

create policy "Authenticated users can update suggestion comments"
  on suggestion_comments for update
  to authenticated
  using (true);

create policy "Authenticated users can delete suggestion comments"
  on suggestion_comments for delete
  to authenticated
  using (true);


-- ============================================================
-- source: 20260317113500_suggestion_status_workflow.sql
-- ============================================================
alter table suggestion_posts
  add column if not exists status text not null default '대기중';

alter table suggestion_posts
  drop constraint if exists suggestion_posts_status_check;

alter table suggestion_posts
  add constraint suggestion_posts_status_check
  check (status in ('대기중', '검토중', '개선중', '개선완료', '반려'));

alter table suggestion_comments
  add column if not exists comment_type text not null default 'comment',
  add column if not exists status_from text,
  add column if not exists status_to text;

alter table suggestion_comments
  drop constraint if exists suggestion_comments_comment_type_check;

alter table suggestion_comments
  add constraint suggestion_comments_comment_type_check
  check (comment_type in ('comment', 'status_change'));


-- ============================================================
-- source: 20260317113600_api_keys_encrypted_storage.sql
-- ============================================================
alter table api_keys
  add column if not exists key_encrypted text;


-- ============================================================
-- source: 20260318120000_resource_library_posts.sql
-- ============================================================
CREATE TABLE resource_library_posts (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  title TEXT NOT NULL,
  content TEXT NOT NULL,
  drive_folder_id TEXT,
  author_employee_id UUID REFERENCES employees(id) ON DELETE SET NULL,
  author_name TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_resource_library_posts_created_at
  ON resource_library_posts(created_at DESC);

ALTER TABLE resource_library_posts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can view resource_library_posts"
  ON resource_library_posts FOR SELECT
  USING (auth.role() = 'authenticated');

CREATE POLICY "Authenticated users can insert resource_library_posts"
  ON resource_library_posts FOR INSERT
  WITH CHECK (auth.role() = 'authenticated');

CREATE POLICY "Authenticated users can update resource_library_posts"
  ON resource_library_posts FOR UPDATE
  USING (auth.role() = 'authenticated');

CREATE POLICY "Authenticated users can delete resource_library_posts"
  ON resource_library_posts FOR DELETE
  USING (auth.role() = 'authenticated');

CREATE TRIGGER resource_library_posts_updated_at
  BEFORE UPDATE ON resource_library_posts
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at();


-- ============================================================
-- source: 20260318130000_google_oauth_tokens.sql
-- ============================================================
create table if not exists google_oauth_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  gmail_email text not null,
  access_token text not null,
  refresh_token text not null,
  token_expiry timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id)
);

alter table google_oauth_tokens enable row level security;

create policy "본인 토큰만 접근" on google_oauth_tokens
  for all using (auth.uid() = user_id);

create or replace function update_google_oauth_tokens_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger trg_google_oauth_tokens_updated_at
  before update on google_oauth_tokens
  for each row execute function update_google_oauth_tokens_updated_at();


-- ============================================================
-- source: 20260318140000_gmail_global_token.sql
-- ============================================================
-- is_global 컬럼 추가
ALTER TABLE google_oauth_tokens ADD COLUMN IF NOT EXISTS is_global boolean NOT NULL DEFAULT false;

-- 전역 토큰은 하나만 존재하도록 partial unique index
CREATE UNIQUE INDEX IF NOT EXISTS idx_google_oauth_tokens_one_global
  ON google_oauth_tokens(is_global) WHERE is_global = true;

-- 기존 RLS 정책 제거 후 재설정
DROP POLICY IF EXISTS "본인 토큰만 접근" ON google_oauth_tokens;

-- 읽기: 본인 토큰 또는 전역 토큰
CREATE POLICY "토큰 읽기" ON google_oauth_tokens
  FOR SELECT USING (auth.uid() = user_id OR is_global = true);

-- 쓰기/수정/삭제: 본인 토큰만
CREATE POLICY "토큰 쓰기" ON google_oauth_tokens
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "토큰 수정" ON google_oauth_tokens
  FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "토큰 삭제" ON google_oauth_tokens
  FOR DELETE USING (auth.uid() = user_id);

-- 현재 저장된 토큰을 전역 토큰으로 설정
UPDATE google_oauth_tokens SET is_global = true;


-- ============================================================
-- source: 20260319100000_add_lead_id_to_meetings.sql
-- ============================================================
-- meetings 테이블에 lead_id 컬럼 추가
ALTER TABLE meetings
  ADD COLUMN IF NOT EXISTS lead_id UUID REFERENCES leads(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_meetings_lead_id ON meetings(lead_id);


-- ============================================================
-- source: 20260319143000_google_calendar_sync.sql
-- ============================================================
ALTER TABLE schedules
  ADD COLUMN IF NOT EXISTS google_calendar_id TEXT,
  ADD COLUMN IF NOT EXISTS google_event_id TEXT,
  ADD COLUMN IF NOT EXISTS google_event_status TEXT NOT NULL DEFAULT 'none',
  ADD COLUMN IF NOT EXISTS google_etag TEXT,
  ADD COLUMN IF NOT EXISTS google_updated_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS sync_source TEXT NOT NULL DEFAULT 'local';

CREATE UNIQUE INDEX IF NOT EXISTS idx_schedules_google_event_unique
  ON schedules (google_calendar_id, google_event_id)
  WHERE google_event_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS google_calendar_sync_states (
  calendar_id TEXT PRIMARY KEY,
  sync_token TEXT,
  channel_id TEXT,
  channel_resource_id TEXT,
  channel_token TEXT,
  channel_expiration TIMESTAMPTZ,
  last_synced_at TIMESTAMPTZ,
  last_message_number BIGINT,
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE google_calendar_sync_states ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can view google calendar sync states"
  ON google_calendar_sync_states FOR SELECT
  USING (auth.role() = 'authenticated');

CREATE POLICY "Authenticated users can insert google calendar sync states"
  ON google_calendar_sync_states FOR INSERT
  WITH CHECK (auth.role() = 'authenticated');

CREATE POLICY "Authenticated users can update google calendar sync states"
  ON google_calendar_sync_states FOR UPDATE
  USING (auth.role() = 'authenticated');

CREATE POLICY "Authenticated users can delete google calendar sync states"
  ON google_calendar_sync_states FOR DELETE
  USING (auth.role() = 'authenticated');

CREATE TRIGGER google_calendar_sync_states_updated_at
  BEFORE UPDATE ON google_calendar_sync_states
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at();


-- ============================================================
-- source: 20260320100000_lead_type_education_fields.sql
-- ============================================================
-- 리드 유형 구분 및 교육 관련 필드 추가
ALTER TABLE leads
  ADD COLUMN lead_type TEXT NOT NULL DEFAULT '개발'
    CHECK (lead_type IN ('개발', '교육')),
  ADD COLUMN edu_schedule TEXT,
  ADD COLUMN edu_filming_schedule TEXT,
  ADD COLUMN edu_delivery_mode TEXT
    CHECK (edu_delivery_mode IN ('온라인', '오프라인', '혼합')),
  ADD COLUMN edu_hourly_rate INTEGER,
  ADD COLUMN edu_estimated_hours NUMERIC(6,1),
  ADD COLUMN edu_estimated_total INTEGER;

-- 유형별 조회를 위한 인덱스
CREATE INDEX idx_leads_lead_type ON leads(lead_type);


-- ============================================================
-- source: 20260321100000_schedule_recurrence.sql
-- ============================================================
-- 일정 반복 기능 지원을 위한 컬럼 추가
ALTER TABLE schedules
  ADD COLUMN recurrence_type TEXT NOT NULL DEFAULT 'none'
    CHECK (recurrence_type IN ('none', 'daily', 'weekly', 'monthly')),
  ADD COLUMN recurrence_end_date DATE,
  ADD COLUMN recurrence_group_id UUID;

-- 반복 그룹 조회용 인덱스
CREATE INDEX idx_schedules_recurrence_group ON schedules (recurrence_group_id)
  WHERE recurrence_group_id IS NOT NULL;

COMMENT ON COLUMN schedules.recurrence_type IS '반복 유형: none(없음), daily(매일), weekly(매주), monthly(매월)';
COMMENT ON COLUMN schedules.recurrence_end_date IS '반복 종료 날짜';
COMMENT ON COLUMN schedules.recurrence_group_id IS '같은 반복 규칙에서 생성된 일정끼리 묶는 그룹 ID';


-- ============================================================
-- source: 20260322100000_project_types_drive_folder.sql
-- ============================================================
-- project_types 테이블에 drive_folder_id 컬럼 추가
ALTER TABLE project_types ADD COLUMN drive_folder_id TEXT;


-- ============================================================
-- source: 20260322110000_meeting_drive_file.sql
-- ============================================================
-- 미팅에 Drive 파일 ID 저장 (전사록/요약본 파일)
ALTER TABLE meetings ADD COLUMN drive_file_id TEXT;


-- ============================================================
-- source: 20260322120000_gmail_token_update_policy.sql
-- ============================================================
-- 글로벌 토큰은 모든 인증 사용자가 갱신 가능하도록 정책 수정
DROP POLICY IF EXISTS "토큰 수정" ON google_oauth_tokens;

CREATE POLICY "토큰 수정" ON google_oauth_tokens
  FOR UPDATE USING (auth.uid() = user_id OR is_global = true);


-- ============================================================
-- source: 20260322130000_fix_google_event_unique_index.sql
-- ============================================================
-- 부분 인덱스(WHERE 절 포함)는 ON CONFLICT에서 사용 불가하므로
-- 일반 유니크 인덱스로 교체 (PostgreSQL에서 NULL은 DISTINCT 처리되므로 안전)
DROP INDEX IF EXISTS idx_schedules_google_event_unique;

CREATE UNIQUE INDEX idx_schedules_google_event_unique
  ON schedules (google_calendar_id, google_event_id);


-- ============================================================
-- source: 20260322140000_schedule_google_meet_link.sql
-- ============================================================
ALTER TABLE schedules
  ADD COLUMN IF NOT EXISTS google_meet_link TEXT;


-- ============================================================
-- source: 20260330100000_schedule_customer_lead_link.sql
-- ============================================================
ALTER TABLE schedules
ADD COLUMN IF NOT EXISTS customer_id UUID REFERENCES customers(id) ON DELETE SET NULL;

ALTER TABLE schedules
ADD COLUMN IF NOT EXISTS lead_id UUID REFERENCES leads(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_schedules_customer_id ON schedules(customer_id);
CREATE INDEX IF NOT EXISTS idx_schedules_lead_id ON schedules(lead_id);


-- ============================================================
-- source: 20260330110000_revenue_type_id.sql
-- ============================================================
-- 매출 건별 유형 직접 지정 (프로젝트 유형과 별도)
ALTER TABLE revenues ADD COLUMN type_id UUID REFERENCES project_types(id) ON DELETE SET NULL;

-- 기존 매출에 프로젝트 유형 복사
UPDATE revenues r
SET type_id = p.type_id
FROM projects p
WHERE r.project_id = p.id AND p.type_id IS NOT NULL;


-- ============================================================
-- source: 20260413113000_backfill_meeting_started_at_kst.sql
-- ============================================================
-- Backfill meeting started_at for legacy Zapier/API imports.
--
-- Legacy imports stored Seoul wall-clock time in started_at as if it were UTC.
-- The current Zapier flow now sends create_time formatted in Asia/Seoul, and
-- the API interprets timezone-less values as KST (+09:00), so only historical
-- imported rows need correction.
--
-- We only target rows where started_at differs from created_at. UI-created
-- meetings use the database default and keep started_at == created_at.
--
-- A backup table is created so the migration is effectively idempotent:
-- reruns will not shift rows twice because updates only apply when the current
-- started_at still matches the original backed-up value.

CREATE TABLE IF NOT EXISTS public._meeting_started_at_backfill_20260413 (
  meeting_id UUID PRIMARY KEY REFERENCES public.meetings(id) ON DELETE CASCADE,
  original_started_at TIMESTAMPTZ NOT NULL,
  original_created_at TIMESTAMPTZ NOT NULL,
  backed_up_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO public._meeting_started_at_backfill_20260413 (
  meeting_id,
  original_started_at,
  original_created_at
)
SELECT
  id,
  started_at,
  created_at
FROM public.meetings
WHERE started_at IS NOT NULL
  AND created_at IS NOT NULL
  AND started_at <> created_at
ON CONFLICT (meeting_id) DO NOTHING;

UPDATE public.meetings AS m
SET started_at = b.original_started_at - INTERVAL '9 hours'
FROM public._meeting_started_at_backfill_20260413 AS b
WHERE m.id = b.meeting_id
  AND m.started_at = b.original_started_at;


-- ============================================================
-- source: 20260419100000_expense_types.sql
-- ============================================================
-- 지출 유형 테이블 (강사비/외주비/운영비 등, 사용자 정의)
CREATE TABLE expense_types (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL UNIQUE,
  sort_order INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 기본 유형 삽입
INSERT INTO expense_types (name, sort_order) VALUES
  ('강사비', 1),
  ('외주비', 2),
  ('운영비', 3);

-- RLS
ALTER TABLE expense_types ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated users can read expense_types"
  ON expense_types FOR SELECT TO authenticated USING (true);
CREATE POLICY "Authenticated users can insert expense_types"
  ON expense_types FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "Authenticated users can update expense_types"
  ON expense_types FOR UPDATE TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "Authenticated users can delete expense_types"
  ON expense_types FOR DELETE TO authenticated USING (true);


-- ============================================================
-- source: 20260419110000_expenses.sql
-- ============================================================
-- 지출(매입) 테이블
create table if not exists public.expenses (
  id uuid primary key default gen_random_uuid(),
  project_id uuid references public.projects(id) on delete set null,
  type_id uuid references public.expense_types(id) on delete set null,

  title text not null,
  vendor_name text,                                  -- 지출처/공급자명 (강사명/업체명)

  total_amount integer not null,                     -- 지출총액 (부가세 포함)
  supply_amount integer not null,                    -- 공급가액
  vat_amount integer not null default 0,             -- 부가세
  vat_included boolean not null default true,

  expense_date date,                                 -- 지출 발생일
  expected_payment_date date,                        -- 지급 예정일

  is_paid boolean not null default false,            -- 지급 완료
  paid_date date,                                    -- 실지급일

  purchase_tax_invoice_received boolean not null default false,      -- 매입세금계산서 수취 완료
  purchase_tax_invoice_date date,                                    -- 수취일
  purchase_tax_invoice_not_required boolean not null default false,  -- 수취 불필요

  memo text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_expenses_project_id on public.expenses(project_id);
create index if not exists idx_expenses_type_id on public.expenses(type_id);
create index if not exists idx_expenses_expense_date on public.expenses(expense_date);

-- updated_at 트리거
create trigger set_expenses_updated_at
  before update on public.expenses
  for each row
  execute function update_updated_at();

-- RLS
alter table public.expenses enable row level security;

create policy "Authenticated users can read expenses"
  on public.expenses for select
  to authenticated
  using (true);

create policy "Authenticated users can insert expenses"
  on public.expenses for insert
  to authenticated
  with check (true);

create policy "Authenticated users can update expenses"
  on public.expenses for update
  to authenticated
  using (true)
  with check (true);

create policy "Authenticated users can delete expenses"
  on public.expenses for delete
  to authenticated
  using (true);

-- Service role (외부 API 연동용) full access
create policy "Service role full access on expenses"
  on public.expenses for all
  to service_role
  using (true)
  with check (true);


-- ============================================================
-- source: 20260421100000_tasks_add_start_date.sql
-- ============================================================
-- 할일에 기간형 TODO 지원을 위한 start_date 컬럼 추가
-- 주간 타임라인 뷰에서 start_date ~ due_date 구간을 Timeline Bar로 표시
-- NULL이면 마감일 하루짜리 TODO로 처리 (기존 데이터 backfill 불필요)

ALTER TABLE tasks ADD COLUMN IF NOT EXISTS start_date date;

CREATE INDEX IF NOT EXISTS idx_tasks_date_range ON tasks(start_date, due_date);


-- ============================================================
-- source: 20260421110000_tasks_time_tracking.sql
-- ============================================================
-- 할일 소요 시간·완료 시각 추적용 컬럼 추가
-- 집중 모드에서 시작/완료 시점과 예상 소요시간(분)을 저장

ALTER TABLE tasks
  ADD COLUMN IF NOT EXISTS estimated_minutes int,
  ADD COLUMN IF NOT EXISTS actual_minutes int,
  ADD COLUMN IF NOT EXISTS started_at timestamptz,
  ADD COLUMN IF NOT EXISTS completed_at timestamptz;

CREATE INDEX IF NOT EXISTS idx_tasks_started_at
  ON tasks(started_at)
  WHERE started_at IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_tasks_due_date_status
  ON tasks(due_date, status)
  WHERE status NOT IN ('완료', '취소');

-- 기존 완료/취소건의 completed_at을 updated_at으로 백필
UPDATE tasks
SET completed_at = updated_at
WHERE status IN ('완료', '취소')
  AND completed_at IS NULL;


-- ============================================================
-- source: 20260421110100_employee_focus.sql
-- ============================================================
-- 직원별 현재 집중 중 할일 참조. 다중 탭에서 "단일 집중 모드" 서버 보장.
-- 할일 삭제 시 focused_task_id는 NULL로 자동 설정

ALTER TABLE employees
  ADD COLUMN IF NOT EXISTS focused_task_id uuid
  REFERENCES tasks(id) ON DELETE SET NULL;


-- ============================================================
-- source: 20260422100000_tasks_slack_thread_ts.sql
-- ============================================================
-- 할일 Slack 알림의 스레드 루트 ts 저장용 컬럼
-- 신규 등록(또는 백로그에서 처음 공개 상태로 전환)될 때 채널에 올린 메시지 ts 를 기록해두고,
-- 이후 상태 변경 이벤트는 이 스레드에 댓글로 누적한다.

ALTER TABLE tasks ADD COLUMN IF NOT EXISTS slack_thread_ts text;


-- ============================================================
-- source: 20260422120000_expenses_approval_flow.sql
-- ============================================================
-- 지출 결의·지급 플로우 확장
-- 회의(2026-04-22) 결정 사항 반영: 상태 전이, 지출처 FK, 세금 자동계산, Slack 스레드 기록, 상태 이력

-- 상태 컬럼: 기존 is_paid(boolean) 은 읽기 리포트 호환을 위해 유지하고 status 로 상태 흐름을 별도 관리
ALTER TABLE public.expenses
  ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft', 'requested', 'approved', 'rejected', 'scheduled', 'paid', 'cancelled'));

-- 지출처를 customers 와 연결 (기존 vendor_name 텍스트는 하위 호환으로 유지)
ALTER TABLE public.expenses
  ADD COLUMN IF NOT EXISTS vendor_id uuid REFERENCES public.customers(id) ON DELETE SET NULL;

-- 세금/원천징수 계산 필드
ALTER TABLE public.expenses
  ADD COLUMN IF NOT EXISTS tax_category text
    CHECK (tax_category IN ('personal_withholding', 'business_vat', 'corporate_vat', 'none')),
  ADD COLUMN IF NOT EXISTS withholding_rate numeric(5,4),
  ADD COLUMN IF NOT EXISTS withholding_amount integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS net_payment_amount integer
    GENERATED ALWAYS AS (total_amount - COALESCE(withholding_amount, 0)) STORED;

-- 결의/승인/반려/취소 메타
ALTER TABLE public.expenses
  ADD COLUMN IF NOT EXISTS requested_by uuid REFERENCES public.employees(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS requested_at timestamptz,
  ADD COLUMN IF NOT EXISTS approver_id uuid REFERENCES public.employees(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS approved_at timestamptz,
  ADD COLUMN IF NOT EXISTS rejected_reason text,
  ADD COLUMN IF NOT EXISTS cancelled_at timestamptz,
  ADD COLUMN IF NOT EXISTS cancelled_reason text;

-- Slack 스레드 누적용 루트 메시지 ts (tasks.slack_thread_ts 패턴 재사용)
ALTER TABLE public.expenses
  ADD COLUMN IF NOT EXISTS slack_thread_ts text;

CREATE INDEX IF NOT EXISTS idx_expenses_status ON public.expenses(status);
CREATE INDEX IF NOT EXISTS idx_expenses_vendor_id ON public.expenses(vendor_id);
CREATE INDEX IF NOT EXISTS idx_expenses_expected_payment_date ON public.expenses(expected_payment_date);

-- 기존 데이터 백필: is_paid=true 면 paid, 그 외 draft
UPDATE public.expenses
SET status = CASE WHEN is_paid THEN 'paid' ELSE 'draft' END
WHERE status = 'draft';

-- 상태 전이 감사 로그 테이블
CREATE TABLE IF NOT EXISTS public.expense_status_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  expense_id uuid NOT NULL REFERENCES public.expenses(id) ON DELETE CASCADE,
  from_status text,
  to_status text NOT NULL,
  actor_id uuid REFERENCES public.employees(id) ON DELETE SET NULL,
  actor_name text,
  reason text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_expense_status_history_expense_id
  ON public.expense_status_history(expense_id, created_at DESC);

ALTER TABLE public.expense_status_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can read expense_status_history"
  ON public.expense_status_history FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Authenticated users can insert expense_status_history"
  ON public.expense_status_history FOR INSERT
  TO authenticated
  WITH CHECK (true);

CREATE POLICY "Service role full access on expense_status_history"
  ON public.expense_status_history FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);


-- ============================================================
-- source: 20260422130000_customers_vendor_fields.sql
-- ============================================================
-- 고객관리에 지출 대상(벤더) 필드 통합
-- 회의(2026-04-22) 결정: 강사·외주 업체를 고객관리에 1회 등록하면 이후 지출 등록 시 자동 호출.
-- 민감 증빙(신분증/사업자등록증/통장사본)은 Google Drive 재사용 (business-cards/meetings 기존 패턴).
-- Phase 1 에서는 컬럼만 확보, 실제 업로드 UI 는 Phase 2 에서 붙인다.

ALTER TABLE public.customers
  ADD COLUMN IF NOT EXISTS tax_category text
    CHECK (tax_category IN ('personal_withholding', 'business_vat', 'corporate_vat', 'none')),
  ADD COLUMN IF NOT EXISTS default_withholding_rate numeric(5,4),
  ADD COLUMN IF NOT EXISTS bank_name text,
  ADD COLUMN IF NOT EXISTS account_number text,
  ADD COLUMN IF NOT EXISTS account_holder text,
  ADD COLUMN IF NOT EXISTS id_card_drive_file_id text,
  ADD COLUMN IF NOT EXISTS business_license_drive_file_id text,
  ADD COLUMN IF NOT EXISTS bankbook_copy_drive_file_id text,
  ADD COLUMN IF NOT EXISTS is_vendor boolean
    GENERATED ALWAYS AS (tax_category IS NOT NULL) STORED;

CREATE INDEX IF NOT EXISTS idx_customers_is_vendor ON public.customers(is_vendor) WHERE is_vendor = true;


-- ============================================================
-- source: 20260422140000_sms_tables.sql
-- ============================================================
-- SMS 리마인더 스키마 자리 (Phase 1: 테이블만, Phase 2: 실제 발송 연동)
-- 회의(2026-04-22): 입금 전 안내·입금 완료 통지 자동 발송. 공급사(알리고/CoolSMS/카카오 알림톡)는 Phase 2 진입 시 결정.

CREATE TABLE IF NOT EXISTS public.sms_templates (
  code text PRIMARY KEY,
  body text NOT NULL,
  vars jsonb NOT NULL DEFAULT '[]'::jsonb,
  description text,
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.sms_templates ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can manage sms_templates"
  ON public.sms_templates FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);

CREATE POLICY "Service role full access on sms_templates"
  ON public.sms_templates FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

CREATE TRIGGER sms_templates_updated_at
  BEFORE UPDATE ON public.sms_templates
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at();


CREATE TABLE IF NOT EXISTS public.sms_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  expense_id uuid REFERENCES public.expenses(id) ON DELETE SET NULL,
  customer_id uuid REFERENCES public.customers(id) ON DELETE SET NULL,
  template_code text REFERENCES public.sms_templates(code) ON DELETE SET NULL,
  to_phone text NOT NULL,
  body text NOT NULL,
  status text NOT NULL DEFAULT 'queued'
    CHECK (status IN ('queued', 'sent', 'failed')),
  provider text,
  provider_msg_id text,
  error text,
  sent_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_sms_logs_expense_id ON public.sms_logs(expense_id);
CREATE INDEX IF NOT EXISTS idx_sms_logs_customer_id ON public.sms_logs(customer_id);
CREATE INDEX IF NOT EXISTS idx_sms_logs_created_at ON public.sms_logs(created_at DESC);

ALTER TABLE public.sms_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can read sms_logs"
  ON public.sms_logs FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Authenticated users can insert sms_logs"
  ON public.sms_logs FOR INSERT
  TO authenticated
  WITH CHECK (true);

CREATE POLICY "Service role full access on sms_logs"
  ON public.sms_logs FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);


-- ============================================================
-- source: 20260422150000_project_note_images_bucket.sql
-- ============================================================
-- 프로젝트 메모에 Notion 형태의 텍스트+이미지 저장용 버킷
-- 이미지는 Supabase Storage 에 저장하고 메모 content 에는 마크다운 이미지 링크를 삽입한다.

insert into storage.buckets (id, name, public)
values ('project-note-images', 'project-note-images', true)
on conflict (id) do update set public = excluded.public;

drop policy if exists "Project note images are readable by anyone"
  on storage.objects;
drop policy if exists "Authenticated users can upload project note images"
  on storage.objects;
drop policy if exists "Authenticated users can update project note images"
  on storage.objects;
drop policy if exists "Authenticated users can delete project note images"
  on storage.objects;

create policy "Project note images are readable by anyone"
  on storage.objects for select
  using (bucket_id = 'project-note-images');

create policy "Authenticated users can upload project note images"
  on storage.objects for insert
  to authenticated
  with check (bucket_id = 'project-note-images');

create policy "Authenticated users can update project note images"
  on storage.objects for update
  to authenticated
  using (bucket_id = 'project-note-images')
  with check (bucket_id = 'project-note-images');

create policy "Authenticated users can delete project note images"
  on storage.objects for delete
  to authenticated
  using (bucket_id = 'project-note-images');


-- ============================================================
-- source: 20260422160000_customers_classification_and_drive.sql
-- ============================================================
-- 고객관리 개편
-- 1) customer_type 재정의: ('회사','개인','NOT NULL DEFAULT 회사') → ('개인','개인사업자','법인' 또는 NULL, 기본 NULL)
-- 2) 주민등록번호(resident_number)와 고객 전용 Google Drive 폴더(drive_folder_id) 추가
-- 3) 이전 마이그레이션(20260422130000)에서 Phase 1 임시로 둔 개별 drive_file_id 3종 제거
--    - 이제는 drive_folder_id 아래에서 DriveFileBrowser 로 관리

-- (1) customer_type 제약 완화 + 데이터 매핑
ALTER TABLE public.customers
  ALTER COLUMN customer_type DROP DEFAULT;

ALTER TABLE public.customers
  ALTER COLUMN customer_type DROP NOT NULL;

ALTER TABLE public.customers
  DROP CONSTRAINT IF EXISTS customers_customer_type_check;

-- 기존 데이터 매핑: '개인'은 유지, '회사'는 분류 모호 → NULL 처리(사용자가 재분류)
UPDATE public.customers
SET customer_type = NULL
WHERE customer_type = '회사';

ALTER TABLE public.customers
  ADD CONSTRAINT customers_customer_type_check
  CHECK (customer_type IS NULL OR customer_type IN ('개인', '개인사업자', '법인'));

-- (2) 주민등록번호·Drive 폴더 컬럼 추가
ALTER TABLE public.customers
  ADD COLUMN IF NOT EXISTS resident_number text,
  ADD COLUMN IF NOT EXISTS drive_folder_id text;

-- (3) is_vendor 생성 컬럼은 drive_file_id 3종과 무관하게 재생성 되지 않지만,
--     컬럼 drop 전 generated column 의존성 확인이 필요 없도록 먼저 drop
ALTER TABLE public.customers
  DROP COLUMN IF EXISTS id_card_drive_file_id,
  DROP COLUMN IF EXISTS business_license_drive_file_id,
  DROP COLUMN IF EXISTS bankbook_copy_drive_file_id;


-- ============================================================
-- source: 20260422170000_customer_notes.sql
-- ============================================================
-- 고객관리 메모 — 프로젝트 메모(20260309113000_project_notes.sql) 동일 구조 복제
-- 텍스트 + 이미지(Supabase Storage)를 함께 저장하는 Notion 풍 메모

create table if not exists customer_notes (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references customers(id) on delete cascade,
  title text,
  content text,
  link_url text,
  author_employee_id uuid references employees(id) on delete set null,
  author_name text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (
    coalesce(
      nullif(btrim(title), ''),
      nullif(btrim(content), ''),
      nullif(btrim(link_url), '')
    ) is not null
  )
);

create index if not exists idx_customer_notes_customer_id_created_at
  on customer_notes (customer_id, created_at desc);

alter table customer_notes enable row level security;

create policy "Authenticated users can select customer notes"
  on customer_notes for select
  to authenticated
  using (true);

create policy "Authenticated users can insert customer notes"
  on customer_notes for insert
  to authenticated
  with check (true);

create policy "Authenticated users can update customer notes"
  on customer_notes for update
  to authenticated
  using (true);

create policy "Authenticated users can delete customer notes"
  on customer_notes for delete
  to authenticated
  using (true);

drop trigger if exists customer_notes_updated_at on customer_notes;

create trigger customer_notes_updated_at
  before update on customer_notes
  for each row
  execute function update_updated_at();

-- 고객 메모 이미지 저장용 Storage 버킷 (project-note-images 패턴 재사용)
insert into storage.buckets (id, name, public)
values ('customer-note-images', 'customer-note-images', true)
on conflict (id) do update set public = excluded.public;

drop policy if exists "Customer note images are readable by anyone"
  on storage.objects;
drop policy if exists "Authenticated users can upload customer note images"
  on storage.objects;
drop policy if exists "Authenticated users can update customer note images"
  on storage.objects;
drop policy if exists "Authenticated users can delete customer note images"
  on storage.objects;

create policy "Customer note images are readable by anyone"
  on storage.objects for select
  using (bucket_id = 'customer-note-images');

create policy "Authenticated users can upload customer note images"
  on storage.objects for insert
  to authenticated
  with check (bucket_id = 'customer-note-images');

create policy "Authenticated users can update customer note images"
  on storage.objects for update
  to authenticated
  using (bucket_id = 'customer-note-images')
  with check (bucket_id = 'customer-note-images');

create policy "Authenticated users can delete customer note images"
  on storage.objects for delete
  to authenticated
  using (bucket_id = 'customer-note-images');


-- ============================================================
-- source: 20260422180000_revenues_realtime.sql
-- ============================================================
-- 매출 등록 시 display 페이지에서 실시간 알림을 받기 위해
-- revenues 테이블을 supabase_realtime publication에 추가한다 (멱등).
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'revenues'
  ) then
    alter publication supabase_realtime add table public.revenues;
  end if;
end $$;


-- ============================================================
-- source: 20260423100000_quotations_corporate_defaults.sql
-- ============================================================
-- 견적서 공급자(우리 회사) 기본값은 빈 값으로 둡니다.
-- 실제 회사 정보는 견적 등록 화면에서 입력하거나 src/lib/quotation-constants.ts 에서 기본값을 바꿔 사용하세요.

ALTER TABLE quotations
  ALTER COLUMN supplier_name SET DEFAULT '',
  ALTER COLUMN supplier_business_number SET DEFAULT '',
  ALTER COLUMN bank_account SET DEFAULT '';


-- ============================================================
-- source: 20260424100000_deposits_realtime.sql
-- ============================================================
-- 입금 등록 시 전광판(display)에서 실시간 알림 팝업을 띄우기 위해
-- deposits 테이블을 supabase_realtime publication에 추가한다 (멱등).
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'deposits'
  ) then
    alter publication supabase_realtime add table public.deposits;
  end if;
end $$;


-- ============================================================
-- source: 20260508130000_slack_pending_actions.sql
-- ============================================================
-- Slack 멘션 에이전트의 destructive 작업 확인 대기열
-- @윤비서 멘션 → propose_destructive_action 도구 호출 시 row 생성
-- 사용자가 ✅ 반응 누르면 confirmation_ts 기준으로 매칭하여 실행

create table if not exists public.slack_pending_actions (
  id uuid primary key default gen_random_uuid(),
  slack_user_id text not null,
  user_auth_uid uuid not null,
  channel text not null,
  thread_ts text not null,
  confirmation_ts text not null,
  tool_name text not null,
  tool_input jsonb not null,
  summary text not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '15 minutes'),
  executed_at timestamptz,
  cancelled_at timestamptz
);

create index if not exists slack_pending_actions_confirmation_ts_idx
  on public.slack_pending_actions (confirmation_ts);

create index if not exists slack_pending_actions_expires_at_idx
  on public.slack_pending_actions (expires_at)
  where executed_at is null and cancelled_at is null;

alter table public.slack_pending_actions enable row level security;

-- service_role 전용. Slack 핸들러는 admin client 사용.
create policy "service_role manages slack_pending_actions"
  on public.slack_pending_actions
  for all
  to service_role
  using (true)
  with check (true);


-- ============================================================
-- source: 20260509100000_workspace_realtime.sql
-- ============================================================
-- 워크스페이스 화면에서 실시간 협업 갱신을 위해
-- tasks, schedules, schedule_attendees, project_notes 테이블을
-- supabase_realtime publication에 추가한다 (멱등).
do $$
declare
  t text;
begin
  foreach t in array array['tasks', 'schedules', 'schedule_attendees', 'project_notes']
  loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;


-- ============================================================
-- source: 20260509110000_chat_usage_logs_source.sql
-- ============================================================
-- chat_usage_logs에 호출 출처 구분 컬럼 추가
-- 'chat' = 기존 윤대리 채팅, 'slack' = Slack @윤비서 멘션 에이전트

alter table public.chat_usage_logs
  add column if not exists source text not null default 'chat';

create index if not exists idx_chat_usage_logs_source
  on public.chat_usage_logs (source);


-- ============================================================
-- source: 20260513100000_weekly_meetings.sql
-- ============================================================
create table if not exists weekly_meetings (
  id uuid primary key default gen_random_uuid(),
  week_start_date date not null,
  progress_this_week text not null check (char_length(btrim(progress_this_week)) > 0),
  plans_next_week text not null check (char_length(btrim(plans_next_week)) > 0),
  blockers text not null default '',
  author_employee_id uuid references employees(id) on delete set null,
  author_name text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists ux_weekly_meetings_week_author
  on weekly_meetings (week_start_date, author_employee_id)
  where author_employee_id is not null;

create index if not exists idx_weekly_meetings_week_start_date
  on weekly_meetings (week_start_date desc);

alter table weekly_meetings enable row level security;

create policy "Authenticated users can select weekly_meetings"
  on weekly_meetings for select
  to authenticated
  using (true);

create policy "Authenticated users can insert weekly_meetings"
  on weekly_meetings for insert
  to authenticated
  with check (true);

create policy "Authenticated users can update weekly_meetings"
  on weekly_meetings for update
  to authenticated
  using (true);

create policy "Authenticated users can delete weekly_meetings"
  on weekly_meetings for delete
  to authenticated
  using (true);

drop trigger if exists weekly_meetings_updated_at on weekly_meetings;

create trigger weekly_meetings_updated_at
  before update on weekly_meetings
  for each row
  execute function update_updated_at();


-- ============================================================
-- source: 20260514100000_weekly_meeting_comments.sql
-- ============================================================
create table if not exists weekly_meeting_comments (
  id uuid primary key default gen_random_uuid(),
  weekly_meeting_id uuid not null references weekly_meetings(id) on delete cascade,
  author_employee_id uuid references employees(id) on delete set null,
  author_name text not null,
  content text not null check (char_length(btrim(content)) > 0),
  created_at timestamptz not null default now()
);

create index if not exists idx_weekly_meeting_comments_meeting_created
  on weekly_meeting_comments (weekly_meeting_id, created_at asc);

alter table weekly_meeting_comments enable row level security;

create policy "Authenticated users can select weekly_meeting_comments"
  on weekly_meeting_comments for select
  to authenticated
  using (true);

create policy "Authenticated users can insert weekly_meeting_comments"
  on weekly_meeting_comments for insert
  to authenticated
  with check (true);

create policy "Authenticated users can update weekly_meeting_comments"
  on weekly_meeting_comments for update
  to authenticated
  using (true);

create policy "Authenticated users can delete weekly_meeting_comments"
  on weekly_meeting_comments for delete
  to authenticated
  using (true);


-- ============================================================
-- source: 20260514110000_notes.sql
-- ============================================================
-- 독립적인 메모 관리 테이블
-- 프로젝트나 고객에 선택적으로 연결할 수 있음

CREATE TABLE notes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title TEXT,
  content TEXT,
  link_url TEXT,
  project_id UUID REFERENCES projects(id) ON DELETE SET NULL,
  customer_id UUID REFERENCES customers(id) ON DELETE SET NULL,
  author_employee_id UUID REFERENCES employees(id) ON DELETE SET NULL,
  author_name TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- updated_at 자동 갱신 트리거
CREATE TRIGGER set_notes_updated_at
  BEFORE UPDATE ON notes
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- 인덱스
CREATE INDEX idx_notes_project_id ON notes(project_id) WHERE project_id IS NOT NULL;
CREATE INDEX idx_notes_customer_id ON notes(customer_id) WHERE customer_id IS NOT NULL;
CREATE INDEX idx_notes_author_employee_id ON notes(author_employee_id) WHERE author_employee_id IS NOT NULL;
CREATE INDEX idx_notes_created_at ON notes(created_at DESC);

-- 검색을 위한 GIN 인덱스 (제목 + 내용)
CREATE INDEX idx_notes_search ON notes USING GIN (to_tsvector('simple', coalesce(title, '') || ' ' || coalesce(content, '')));

-- RLS 활성화
ALTER TABLE notes ENABLE ROW LEVEL SECURITY;

-- RLS 정책: 인증된 사용자만 접근
CREATE POLICY "notes_select" ON notes FOR SELECT TO authenticated USING (true);
CREATE POLICY "notes_insert" ON notes FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "notes_update" ON notes FOR UPDATE TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "notes_delete" ON notes FOR DELETE TO authenticated USING (true);

-- 이미지 저장을 위한 Storage 버킷
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'note-images',
  'note-images',
  true,
  10485760,
  ARRAY['image/jpeg', 'image/png', 'image/gif', 'image/webp']
) ON CONFLICT (id) DO NOTHING;

-- Storage 정책
CREATE POLICY "note_images_select" ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'note-images');

CREATE POLICY "note_images_insert" ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'note-images');

CREATE POLICY "note_images_update" ON storage.objects FOR UPDATE TO authenticated
  USING (bucket_id = 'note-images');

CREATE POLICY "note_images_delete" ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'note-images');


-- ============================================================
-- source: 20260514120000_corporate_cards.sql
-- ============================================================
-- 법인카드 마스터 테이블
-- SMS에서 추출한 카드번호 끝 4자리(last4)로 카드와 사용자(보유 직원)를 매핑한다.

create table public.corporate_cards (
  id uuid primary key default gen_random_uuid(),
  alias text not null,
  last4 text not null,
  holder_employee_id uuid references public.employees(id) on delete set null,
  issuer text,
  is_active boolean not null default true,
  memo text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 활성 카드 중에서는 last4가 유일해야 한다 (SMS 매칭 키)
create unique index uq_corporate_cards_active_last4
  on public.corporate_cards(last4)
  where is_active = true;

create index idx_corporate_cards_holder on public.corporate_cards(holder_employee_id);

create trigger set_corporate_cards_updated_at
  before update on public.corporate_cards
  for each row
  execute function update_updated_at();

alter table public.corporate_cards enable row level security;

create policy "Authenticated users can read corporate_cards"
  on public.corporate_cards for select
  to authenticated
  using (true);

create policy "Authenticated users can insert corporate_cards"
  on public.corporate_cards for insert
  to authenticated
  with check (true);

create policy "Authenticated users can update corporate_cards"
  on public.corporate_cards for update
  to authenticated
  using (true)
  with check (true);

create policy "Authenticated users can delete corporate_cards"
  on public.corporate_cards for delete
  to authenticated
  using (true);

create policy "Service role full access on corporate_cards"
  on public.corporate_cards for all
  to service_role
  using (true)
  with check (true);


-- ============================================================
-- source: 20260514120100_card_transactions.sql
-- ============================================================
-- 법인카드 거래 내역
-- Tasker가 보낸 SMS를 파싱해 즉시 row를 만들고,
-- 사용자가 영수증·적요를 채워 "지출로 확정"하면 expense_id로 연결한다.

create table public.card_transactions (
  id uuid primary key default gen_random_uuid(),

  card_id uuid references public.corporate_cards(id) on delete set null,
  card_last4 text,                                  -- 매칭 실패 시에도 보존

  amount integer not null,                          -- 결제 금액 (원)
  merchant text,                                    -- 가맹점명
  approved_at timestamptz not null,                 -- 승인 시각

  raw_text text not null,                           -- 원본 SMS 전문
  parse_status text not null default 'parsed'
    check (parse_status in ('parsed','partial','failed')),

  category text,                                    -- 사용자 분류
  description text,                                 -- 적요 (예: "6인 식사")

  receipt_url text,                                 -- Storage public URL
  receipt_required boolean not null default false,

  expense_id uuid references public.expenses(id) on delete set null,
  status text not null default 'pending'
    check (status in ('pending','confirmed','ignored')),

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index idx_card_tx_approved_at on public.card_transactions(approved_at desc);
create index idx_card_tx_card_id on public.card_transactions(card_id);
create index idx_card_tx_status on public.card_transactions(status);
create index idx_card_tx_expense_id on public.card_transactions(expense_id)
  where expense_id is not null;

create trigger set_card_transactions_updated_at
  before update on public.card_transactions
  for each row
  execute function update_updated_at();

alter table public.card_transactions enable row level security;

create policy "Authenticated users can read card_transactions"
  on public.card_transactions for select
  to authenticated
  using (true);

create policy "Authenticated users can insert card_transactions"
  on public.card_transactions for insert
  to authenticated
  with check (true);

create policy "Authenticated users can update card_transactions"
  on public.card_transactions for update
  to authenticated
  using (true)
  with check (true);

create policy "Authenticated users can delete card_transactions"
  on public.card_transactions for delete
  to authenticated
  using (true);

create policy "Service role full access on card_transactions"
  on public.card_transactions for all
  to service_role
  using (true)
  with check (true);


-- ============================================================
-- source: 20260514120200_recurring_expenses.sql
-- ============================================================
-- 반복 지출 템플릿 (임대료, 차량 렌트료, 관리비 등)
-- cron이 매월 day_of_month에 맞춰 expenses row를 자동 생성한다.

create table public.recurring_expenses (
  id uuid primary key default gen_random_uuid(),

  title text not null,
  type_id uuid references public.expense_types(id) on delete set null,
  vendor_name text,
  vendor_id uuid references public.customers(id) on delete set null,

  amount integer not null,                          -- 총액 (vat 포함 여부는 vat_included로)
  vat_included boolean not null default true,

  day_of_month smallint not null check (day_of_month between 1 and 28),

  start_date date not null,
  end_date date,

  last_generated_month text,                        -- 'YYYY-MM' 마지막 생성 월 (중복 방지)

  is_active boolean not null default true,
  memo text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index idx_recurring_expenses_active
  on public.recurring_expenses(is_active, day_of_month)
  where is_active = true;
create index idx_recurring_expenses_type on public.recurring_expenses(type_id);

create trigger set_recurring_expenses_updated_at
  before update on public.recurring_expenses
  for each row
  execute function update_updated_at();

alter table public.recurring_expenses enable row level security;

create policy "Authenticated users can read recurring_expenses"
  on public.recurring_expenses for select
  to authenticated
  using (true);

create policy "Authenticated users can insert recurring_expenses"
  on public.recurring_expenses for insert
  to authenticated
  with check (true);

create policy "Authenticated users can update recurring_expenses"
  on public.recurring_expenses for update
  to authenticated
  using (true)
  with check (true);

create policy "Authenticated users can delete recurring_expenses"
  on public.recurring_expenses for delete
  to authenticated
  using (true);

create policy "Service role full access on recurring_expenses"
  on public.recurring_expenses for all
  to service_role
  using (true)
  with check (true);


-- ============================================================
-- source: 20260514120300_expenses_card_link.sql
-- ============================================================
-- expenses에 카드 거래/반복 지출 연결과 영수증 컬럼 추가
-- 영수증 이미지(또는 PDF)는 Storage 'expense-receipts' 버킷에 보관한다.

alter table public.expenses
  add column if not exists source text not null default 'manual'
    check (source in ('manual','card','recurring')),
  add column if not exists card_transaction_id uuid
    references public.card_transactions(id) on delete set null,
  add column if not exists recurring_expense_id uuid
    references public.recurring_expenses(id) on delete set null,
  add column if not exists receipt_url text;

create index if not exists idx_expenses_source on public.expenses(source);
create index if not exists idx_expenses_card_tx on public.expenses(card_transaction_id)
  where card_transaction_id is not null;
create index if not exists idx_expenses_recurring on public.expenses(recurring_expense_id)
  where recurring_expense_id is not null;

-- 영수증 Storage 버킷
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'expense-receipts',
  'expense-receipts',
  true,
  10485760,
  array['image/jpeg','image/png','image/gif','image/webp','application/pdf']
) on conflict (id) do nothing;

create policy "expense_receipts_select" on storage.objects for select to authenticated
  using (bucket_id = 'expense-receipts');

create policy "expense_receipts_insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'expense-receipts');

create policy "expense_receipts_update" on storage.objects for update to authenticated
  using (bucket_id = 'expense-receipts');

create policy "expense_receipts_delete" on storage.objects for delete to authenticated
  using (bucket_id = 'expense-receipts');


-- ============================================================
-- source: 20260514130000_corporate_cards_alias_optional.sql
-- ============================================================
-- 법인카드 별칭(alias)을 선택 입력값으로 변경
-- (모든 직원에게 카드를 발급해 last4만으로 충분히 식별 가능한 케이스가 많아 NOT NULL 해제)

alter table public.corporate_cards
  alter column alias drop not null;


-- ============================================================
-- source: 20260514140000_card_transactions_currency.sql
-- ============================================================
-- 외화 카드 결제 지원
-- USD/EUR 등 비KRW 결제 시 원본 통화·금액을 보존한다.
-- amount(KRW 정수) 컬럼은 외화 결제일 때 0으로 두고, foreign_amount/currency를 사용한다.

alter table public.card_transactions
  add column currency text not null default 'KRW',
  add column foreign_amount numeric(14, 2);


-- ============================================================
-- source: 20260514150000_expense_types_account_code.sql
-- ============================================================
-- 지출 유형 확장: 세무 신고용 계정과목 + 부가세 매입세액 공제 여부
-- 기존 강사비/외주비/운영비는 그대로 유지하고 표준 계정과목을 추가한다.

alter table public.expense_types
  add column if not exists account_code text,
  add column if not exists is_vat_deductible boolean not null default true;

-- 표준 계정과목 시드 (이름 중복 시 skip)
insert into public.expense_types (name, sort_order, account_code, is_vat_deductible) values
  ('지급수수료',        10, 'fee',              true),
  ('복리후생비',        20, 'welfare',          true),
  ('회의비',            21, 'meeting',          true),
  ('교육훈련비',        22, 'training',         true),
  ('임차료',            30, 'rent_office',      true),
  ('수도광열비',        31, 'utility',          true),
  ('통신비',            32, 'comm',             true),
  ('비품임차료',        33, 'rent_equipment',   true),  -- 정수기, 복합기 등 설비 렌탈
  ('소프트웨어구독료',  34, 'software',         true),  -- SaaS 구독
  ('광고선전비',        40, 'ad',               true),
  ('소모품비',          41, 'supplies',         true),
  ('도서인쇄비',        42, 'print',            true),
  ('여비교통비',        50, 'transport',        true),
  ('차량유지비',        51, 'car_maint',        true),  -- 주유·톨게이트·정비
  ('차량렌트료',        52, 'car_rent',         false), -- 비영업용 소형승용차 렌트는 공제 불가
  ('접대비',            60, 'entertainment',    false), -- 기업업무추진비
  ('보험료',            70, 'insurance',        true),
  ('세금과공과',        71, 'tax_public',       true),
  ('잡비',              99, 'misc',             true)
on conflict (name) do nothing;

-- 기존 항목 account_code/공제여부 채움 (이미 있는 강사비/외주비/운영비)
update public.expense_types set account_code = 'lecture' where name = '강사비' and account_code is null;
update public.expense_types set account_code = 'outsourcing' where name = '외주비' and account_code is null;
update public.expense_types set account_code = 'operating' where name = '운영비' and account_code is null;


-- ============================================================
-- source: 20260515000000_card_transactions_drop_category.sql
-- ============================================================
-- card_transactions.category 제거
-- 사용자 자유 입력 카테고리는 expense_types(계정과목)로 대체되어 의미 중복.
-- 적요(description)는 계속 유지.

alter table public.card_transactions
  drop column if exists category;


-- ============================================================
-- source: 20260515000100_card_transactions_type_id.sql
-- ============================================================
-- 카드거래에 예정 지출유형 컬럼 추가
-- 일괄 분류 + 일괄 확정 워크플로우를 위해 카드거래에 type_id를 먼저 채울 수 있도록 한다.
-- 확정 시 expense에 동일 type_id가 복사되어 들어간다.

alter table public.card_transactions
  add column type_id uuid references public.expense_types(id) on delete set null;

create index if not exists idx_card_tx_type_id on public.card_transactions(type_id)
  where type_id is not null;


-- ============================================================
-- source: 20260515000200_expenses_purchase_payment_rename.sql
-- ============================================================
-- 지출(expense) → 매입 체계 단순화
-- 매입일(purchase_date) + 지급일(payment_date) 2개 컬럼으로 정리한다.
-- payment_date IS NOT NULL 이면 지급완료로 본다 (status='paid' 와 동치 운용).
-- 신용카드 도입 시 월별 지급일 분리 필요해지면 그 때 expected_payment_date 류 컬럼을 다시 추가한다.

-- 기존 인덱스 제거 (drop/rename 대상 컬럼 의존)
DROP INDEX IF EXISTS public.idx_expenses_expense_date;
DROP INDEX IF EXISTS public.idx_expenses_expected_payment_date;

-- 컬럼 이름 변경
ALTER TABLE public.expenses RENAME COLUMN expense_date TO purchase_date;
ALTER TABLE public.expenses RENAME COLUMN paid_date TO payment_date;

-- 백필: status='paid' 인데 payment_date NULL 인 행은 expected_payment_date 또는 purchase_date 로 채움
UPDATE public.expenses
   SET payment_date = COALESCE(payment_date, expected_payment_date, purchase_date)
 WHERE status = 'paid' AND payment_date IS NULL;

-- 컬럼 제거
ALTER TABLE public.expenses DROP COLUMN IF EXISTS expected_payment_date;
ALTER TABLE public.expenses DROP COLUMN IF EXISTS is_paid;

-- 인덱스 재생성
CREATE INDEX IF NOT EXISTS idx_expenses_purchase_date ON public.expenses(purchase_date);
CREATE INDEX IF NOT EXISTS idx_expenses_payment_date ON public.expenses(payment_date);


-- ============================================================
-- source: 20260518100000_employees_is_finance.sql
-- ============================================================
-- 재무팀 권한 컬럼 추가
-- 매입확정 등 재무 워크플로우 접근 권한. 관리자(employee_type='관리자')와 직교적으로 동작한다.
-- 클라이언트에서 (employee_type='관리자' OR is_finance=true) 로 판단한다.

alter table public.employees
  add column if not exists is_finance boolean not null default false;


-- ============================================================
-- source: 20260519100000_card_expenses_auto_paid.sql
-- ============================================================
-- 법인 체크카드 매입은 카드 확정 시 이미 지출된 건으로 보고 지급완료 상태로 정리한다.

INSERT INTO public.expense_status_history (
  expense_id,
  from_status,
  to_status,
  actor_id,
  actor_name,
  reason
)
SELECT
  id,
  status,
  'paid',
  NULL,
  NULL,
  '법인카드 매입확정 자동 지급완료 백필'
FROM public.expenses
WHERE (source = 'card' OR card_transaction_id IS NOT NULL)
  AND status NOT IN ('paid', 'cancelled');

UPDATE public.expenses
   SET status = 'paid',
       payment_date = COALESCE(payment_date, purchase_date, created_at::date),
       updated_at = now()
 WHERE (source = 'card' OR card_transaction_id IS NOT NULL)
   AND status NOT IN ('paid', 'cancelled');

UPDATE public.expenses
   SET purchase_tax_invoice_not_required = true,
       purchase_tax_invoice_received = false,
       purchase_tax_invoice_date = NULL,
       updated_at = now()
 WHERE (source = 'card' OR card_transaction_id IS NOT NULL)
   AND purchase_tax_invoice_received = false
   AND purchase_tax_invoice_not_required = false;


-- ============================================================
-- source: 20260520011520_secure_meeting_started_at_backfill.sql
-- ============================================================
-- Keep the one-off meeting timestamp backfill backup out of the public API.
-- No policies are added intentionally: app users do not need this recovery table.
ALTER TABLE IF EXISTS public._meeting_started_at_backfill_20260413
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public._meeting_started_at_backfill_20260413 FROM anon;
REVOKE ALL ON TABLE public._meeting_started_at_backfill_20260413 FROM authenticated;


-- ============================================================
-- source: 20260520011615_deny_app_access_meeting_started_at_backfill.sql
-- ============================================================
-- Make the private-backup intent explicit so the advisor does not report
-- "RLS enabled with no policy" for this table.
CREATE POLICY "No app access to meeting started_at backfill backup"
  ON public._meeting_started_at_backfill_20260413
  FOR ALL
  TO anon, authenticated
  USING (false)
  WITH CHECK (false);


-- ============================================================
-- source: 20260528064636_notification_filters.sql
-- ============================================================
-- 알림 webhook 본문을 Slack SMS 채널로 forward 할지 결정하는 blocklist.
-- phrase 가 본문에 contains 되면 forward 차단 (Make 의 "does not contain AND ..." 와 동치).
-- 카드거래 row 자체는 항상 만들어진다 (이 필터는 Slack 전달에만 영향).

create table public.notification_filters (
  id uuid primary key default gen_random_uuid(),
  phrase text not null,
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index notification_filters_phrase_unique
  on public.notification_filters (lower(phrase));

alter table public.notification_filters enable row level security;

create policy "Authenticated users can read notification filters"
  on public.notification_filters for select
  to authenticated
  using (true);

create policy "Authenticated users can manage notification filters"
  on public.notification_filters for all
  to authenticated
  using (true)
  with check (true);

-- 기존 Make 워크플로우에서 사용하던 phrase seed
insert into public.notification_filters (phrase) values
  ('선물을 수락했습니다'),
  ('한진택배입니다'),
  ('(광고)'),
  ('[쿠팡이츠]'),
  ('마이쿠팡'),
  ('엄마'),
  ('민감한 알림 콘텐츠 숨김'),
  ('메시지'),
  ('스팸차단'),
  ('선거운동정보'),
  ('좋아요 표시함'),
  ('NH기업2521승인'),
  ('NH기업2541승인'),
  ('백그라운드에서')
on conflict do nothing;


