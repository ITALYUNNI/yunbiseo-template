"use client";

import Link from "next/link";
import { ArrowLeft, Upload, X } from "lucide-react";
import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";

import { PageHeader, PageShell } from "@/components/page-shell";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";

interface UploadedFile {
  file_url: string;
  file_name: string;
  file_size: number;
}

export default function NewImportDeclarationPage() {
  const router = useRouter();
  const fileInputRef = useRef<HTMLInputElement>(null);

  const [title, setTitle] = useState("");
  const [declarationDate, setDeclarationDate] = useState("");
  const [declarationNumber, setDeclarationNumber] = useState("");
  const [memo, setMemo] = useState("");
  const [uploadedFile, setUploadedFile] = useState<UploadedFile | null>(null);
  const [uploading, setUploading] = useState(false);
  const [saving, setSaving] = useState(false);

  const handleFileChange = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    setUploading(true);
    try {
      const formData = new FormData();
      formData.append("file", file);

      const response = await fetch("/api/import-declarations/upload", {
        method: "POST",
        body: formData,
      });
      const result = await response.json();

      if (!response.ok) throw new Error(result.error ?? "업로드 실패");

      setUploadedFile({
        file_url: result.file_url,
        file_name: result.file_name,
        file_size: result.file_size,
      });
      toast.success("파일이 업로드되었습니다.");
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "파일 업로드에 실패했습니다.");
    } finally {
      setUploading(false);
      if (fileInputRef.current) fileInputRef.current.value = "";
    }
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    if (!title.trim()) {
      toast.error("제목을 입력해 주세요.");
      return;
    }
    if (!declarationDate) {
      toast.error("신고일을 입력해 주세요.");
      return;
    }

    setSaving(true);
    try {
      const response = await fetch("/api/import-declarations", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          title: title.trim(),
          declaration_date: declarationDate,
          declaration_number: declarationNumber.trim() || null,
          memo: memo.trim() || null,
          file_url: uploadedFile?.file_url ?? null,
          file_name: uploadedFile?.file_name ?? null,
          file_size: uploadedFile?.file_size ?? null,
        }),
      });
      const result = await response.json();

      if (!response.ok) throw new Error(result.error ?? "등록 실패");

      toast.success("수입면장이 등록되었습니다.");
      router.push(`/dashboard/import-declarations/${result.id}`);
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "등록에 실패했습니다.");
    } finally {
      setSaving(false);
    }
  };

  return (
    <PageShell>
      <PageHeader
        breadcrumbs={[
          { label: "수입면장", href: "/dashboard/import-declarations" },
          { label: "면장 등록" },
        ]}
        title="면장 등록"
        description="수입신고 면장 정보와 파일을 등록합니다."
        actions={
          <Button variant="outline" asChild>
            <Link href="/dashboard/import-declarations">
              <ArrowLeft className="h-4 w-4" />
              목록
            </Link>
          </Button>
        }
      />

      <form onSubmit={(e) => void handleSubmit(e)} className="space-y-6 max-w-2xl">
        <div className="rounded-[1.5rem] border border-border/70 bg-card/85 p-6 space-y-5">
          <div className="space-y-2">
            <Label htmlFor="title">
              제목 <span className="text-destructive">*</span>
            </Label>
            <Input
              id="title"
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              placeholder="예: 2026-06 버켄스탁 수입신고"
              required
            />
          </div>

          <div className="grid grid-cols-1 gap-5 sm:grid-cols-2">
            <div className="space-y-2">
              <Label htmlFor="declaration_date">
                신고일 <span className="text-destructive">*</span>
              </Label>
              <Input
                id="declaration_date"
                type="date"
                value={declarationDate}
                onChange={(e) => setDeclarationDate(e.target.value)}
                required
              />
            </div>

            <div className="space-y-2">
              <Label htmlFor="declaration_number">신고번호</Label>
              <Input
                id="declaration_number"
                value={declarationNumber}
                onChange={(e) => setDeclarationNumber(e.target.value)}
                placeholder="선택 입력"
              />
            </div>
          </div>

          <div className="space-y-2">
            <Label htmlFor="memo">메모</Label>
            <Textarea
              id="memo"
              value={memo}
              onChange={(e) => setMemo(e.target.value)}
              placeholder="참고 사항을 입력하세요."
              rows={3}
            />
          </div>

          <div className="space-y-2">
            <Label>면장 파일</Label>
            {uploadedFile ? (
              <div className="flex items-center gap-3 rounded-xl border border-border/70 bg-muted/30 px-4 py-3">
                <span className="min-w-0 flex-1 truncate text-sm">{uploadedFile.file_name}</span>
                <Button
                  type="button"
                  variant="ghost"
                  size="icon"
                  className="h-7 w-7 shrink-0"
                  onClick={() => setUploadedFile(null)}
                >
                  <X className="h-4 w-4" />
                </Button>
              </div>
            ) : (
              <div>
                <input
                  ref={fileInputRef}
                  type="file"
                  id="file"
                  className="hidden"
                  onChange={(e) => void handleFileChange(e)}
                  accept=".pdf,.xls,.xlsx,.hwp,.doc,.docx,.jpg,.jpeg,.png"
                />
                <Button
                  type="button"
                  variant="outline"
                  onClick={() => fileInputRef.current?.click()}
                  disabled={uploading}
                >
                  <Upload className="h-4 w-4" />
                  {uploading ? "업로드 중..." : "파일 선택"}
                </Button>
                <p className="mt-1.5 text-xs text-muted-foreground">
                  PDF, Excel, HWP, Word, 이미지 (최대 50MB)
                </p>
              </div>
            )}
          </div>
        </div>

        <div className="flex gap-3">
          <Button type="submit" disabled={saving || uploading}>
            {saving ? "등록 중..." : "면장 등록"}
          </Button>
          <Button type="button" variant="outline" onClick={() => router.back()}>
            취소
          </Button>
        </div>
      </form>
    </PageShell>
  );
}
