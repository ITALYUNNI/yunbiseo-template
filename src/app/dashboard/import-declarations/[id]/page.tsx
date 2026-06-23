"use client";

import Link from "next/link";
import { Download, FileText, PencilLine, Trash2 } from "lucide-react";
import { useCallback, useEffect, useState } from "react";
import { useParams, useRouter } from "next/navigation";
import { toast } from "sonner";

import {
  ErrorState,
  LoadingState,
  PageHeader,
  PageShell,
  SectionCard,
} from "@/components/page-shell";
import { Button } from "@/components/ui/button";
import type { ImportDeclaration } from "@/lib/types";

function formatDate(value: string) {
  return value.replace(/-/g, ".");
}

function formatFileSize(bytes: number) {
  if (bytes < 1024) return `${bytes}B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)}KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)}MB`;
}

export default function ImportDeclarationDetailPage() {
  const params = useParams();
  const router = useRouter();
  const id = params.id as string;

  const [item, setItem] = useState<ImportDeclaration | null>(null);
  const [loading, setLoading] = useState(true);
  const [deleting, setDeleting] = useState(false);

  const fetchItem = useCallback(async () => {
    setLoading(true);
    try {
      const response = await fetch(`/api/import-declarations/${id}`, { cache: "no-store" });
      const result = await response.json();

      if (!response.ok) throw new Error(result.error ?? "알 수 없는 오류");

      setItem(result as ImportDeclaration);
    } catch (err) {
      toast.error("수입면장을 불러오지 못했습니다.");
      setItem(null);
    } finally {
      setLoading(false);
    }
  }, [id]);

  useEffect(() => {
    void fetchItem();
  }, [fetchItem]);

  const handleDelete = async () => {
    if (!item || deleting) return;
    if (!confirm(`"${item.title}" 면장을 삭제하시겠습니까?`)) return;

    setDeleting(true);
    try {
      const response = await fetch(`/api/import-declarations/${id}`, { method: "DELETE" });
      const result = await response.json();

      if (!response.ok) throw new Error(result.error ?? "삭제 실패");

      toast.success("수입면장이 삭제되었습니다.");
      router.push("/dashboard/import-declarations");
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "삭제에 실패했습니다.");
    } finally {
      setDeleting(false);
    }
  };

  if (loading) {
    return (
      <PageShell>
        <LoadingState title="수입면장을 불러오는 중입니다." />
      </PageShell>
    );
  }

  if (!item) {
    return (
      <PageShell>
        <ErrorState onRetry={() => void fetchItem()} />
      </PageShell>
    );
  }

  return (
    <PageShell>
      <PageHeader
        breadcrumbs={[
          { label: "수입면장", href: "/dashboard/import-declarations" },
          { label: item.title },
        ]}
        title={item.title}
        actions={
          <div className="flex gap-2">
            <Button variant="outline" asChild>
              <Link href={`/dashboard/import-declarations/${id}/edit`}>
                <PencilLine className="h-4 w-4" />
                수정
              </Link>
            </Button>
            <Button
              variant="outline"
              className="text-destructive hover:text-destructive"
              onClick={() => void handleDelete()}
              disabled={deleting}
            >
              <Trash2 className="h-4 w-4" />
              {deleting ? "삭제 중..." : "삭제"}
            </Button>
          </div>
        }
      />

      <SectionCard title="기본 정보">
        <dl className="grid grid-cols-1 gap-x-8 gap-y-4 sm:grid-cols-2">
          <div>
            <dt className="text-xs font-medium text-muted-foreground">신고일</dt>
            <dd className="mt-1 text-sm font-medium">{formatDate(item.declaration_date)}</dd>
          </div>
          {item.declaration_number && (
            <div>
              <dt className="text-xs font-medium text-muted-foreground">신고번호</dt>
              <dd className="mt-1 text-sm">{item.declaration_number}</dd>
            </div>
          )}
          {item.memo && (
            <div className="sm:col-span-2">
              <dt className="text-xs font-medium text-muted-foreground">메모</dt>
              <dd className="mt-1 whitespace-pre-wrap text-sm leading-6">{item.memo}</dd>
            </div>
          )}
        </dl>
      </SectionCard>

      {item.file_url && item.file_name && (
        <SectionCard title="첨부 파일">
          <div className="flex items-center gap-3">
            <FileText className="h-5 w-5 shrink-0 text-muted-foreground" />
            <span className="min-w-0 flex-1 truncate text-sm">{item.file_name}</span>
            {item.file_size && (
              <span className="shrink-0 text-xs text-muted-foreground">
                {formatFileSize(item.file_size)}
              </span>
            )}
            <Button variant="outline" size="sm" asChild>
              <a href={item.file_url} download={item.file_name} target="_blank" rel="noreferrer">
                <Download className="h-4 w-4" />
                다운로드
              </a>
            </Button>
          </div>
        </SectionCard>
      )}
    </PageShell>
  );
}
