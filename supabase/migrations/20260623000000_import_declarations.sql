-- 수입면장 테이블
CREATE TABLE IF NOT EXISTS import_declarations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL,
  declaration_date date NOT NULL,
  declaration_number text,
  file_url text,
  file_name text,
  file_size bigint,
  memo text,
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE import_declarations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "authenticated users can manage import declarations"
  ON import_declarations FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);

-- 수입면장 Storage 버킷
INSERT INTO storage.buckets (id, name, public)
VALUES ('import-declarations', 'import-declarations', false)
ON CONFLICT (id) DO NOTHING;

CREATE POLICY "authenticated users can read import declaration files"
  ON storage.objects FOR SELECT
  TO authenticated
  USING (bucket_id = 'import-declarations');

CREATE POLICY "authenticated users can upload import declaration files"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (bucket_id = 'import-declarations');

CREATE POLICY "authenticated users can delete import declaration files"
  ON storage.objects FOR DELETE
  TO authenticated
  USING (bucket_id = 'import-declarations');

-- updated_at 자동 갱신 트리거
CREATE OR REPLACE FUNCTION update_import_declarations_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_import_declarations_updated_at
  BEFORE UPDATE ON import_declarations
  FOR EACH ROW EXECUTE FUNCTION update_import_declarations_updated_at();
