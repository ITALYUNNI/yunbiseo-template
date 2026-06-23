"use client";

import Link from "next/link";
import { FileText, Plus, Search } from "lucide-react";
import { useCallback, useEffect, useMemo, useState } from "react";
import { toast } from "sonner";

import {
  EmptyState,
  ErrorState,
  LoadingState,
  PageHeader,
  PageShell,
  PageToolbar,
  StatCard,
  StatsGrid,
} from "@/components/page-shell";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import type { ImportDeclaration } from "@/lib/types";

function formatDate(value: string) {
  return value.replace(/-/g, ".");
}

function formatFileSize(bytes: number) {
  if (bytes < 1024) return `${bytes}B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)}KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)}MB`;
}

export default function ImportDeclarationsPage() {
  const [items, setItems] = useState<ImportDeclaration[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);
  const [search, setSearch] = useState("");

  const fetchItems = useCallback(async () => {
    setLoading(true);
    setError(false);

    try {
      const response = await fetch("/api/import-declarations", { cache: "no-store" });
      const result = await response.json();

      if (!response.ok) throw new Error(result.error ?? "알 수 없는 오류");

      setItems(Array.isArray(result) ? (result as ImportDeclaration[]) : []);
    } catch (err) {
      console.error("수입면장 목록 조회 실패:", err instanceof Error ? err.message : String(err));
      toast.error("수입면장 목록을 불러오지 못했습니다.");
      setError(true);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void fetchItems();
  }, [fetchItems]);

  const filtered = useMemo(() => {
    const keyword = search.trim().toLowerCase();
    if (!keyword) return items;
    return items.filter(
      (item) =>
        item.title.toLowerCase().includes(keyword) ||
        item.declaration_number?.toLowerCase().includes(keyword) ||
        item.memo?.toLowerCase().includes(keyword)
    );
  }, [items, search]);

  const latestDate = items[0]?.declaration_date;

  return (
    <PageShell>
      <PageHeader
        title="수입면장"
        description="수입신고 면장 파일을 신고일 기준으로 관리합니다."
        actions={
          <Button asChild>
            <Link href="/dashboard/import-declarations/new">
              <Plus className="h-4 w-4" />
              면장 등록
            </Link>
          </Button>
        }
      />

      <StatsGrid columns={2}>
        <StatCard
          label="등록 면장"
          value={`${items.length}건`}
          description="현재 등록된 수입면장 수"
          icon={FileText}
        />
        <StatCard
          label="최신 신고일"
          value={latestDate ? formatDate(latestDate) : "-"}
          description="가장 최근 신고일 기준"
          icon={FileText}
          tone={items.length > 0 ? "info" : "default"}
        />
      </StatsGrid>

      <PageToolbar>
        <div className="relative max-w-md">
          <Search className="pointer-events-none absolute left-3.5 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
          <Input
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="제목, 신고번호, 메모로 검색"
            className="pl-10"
          />
        </div>
      </PageToolbar>

      {loading ? (
        <LoadingState title="수입면장을 불러오는 중입니다." description="등록된 면장 목록을 정리하고 있습니다." />
      ) : error ? (
        <ErrorState onRetry={() => void fetchItems()} />
      ) : filtered.length === 0 ? (
        <EmptyState
          title={search ? "검색 결과가 없습니다." : "등록된 수입면장이 없습니다."}
          description={search ? "다른 검색어로 다시 확인해 주세요." : "첫 면장을 등록해 수입신고 내역을 관리하세요."}
          action={
            !search ? (
              <Button asChild>
                <Link href="/dashboard/import-declarations/new">
                  <Plus className="h-4 w-4" />
                  면장 등록
                </Link>
              </Button>
            ) : undefined
          }
        />
      ) : (
        <div className="space-y-3">
          {filtered.map((item) => (
            <Link
              key={item.id}
              href={`/dashboard/import-declarations/${item.id}`}
              className="block rounded-[1.5rem] border border-border/70 bg-card/85 p-5 shadow-sm transition-colors hover:bg-muted/35"
            >
              <div className="flex items-start justify-between gap-4">
                <div className="min-w-0 space-y-1">
                  <h2 className="text-base font-semibold tracking-tight text-foreground">{item.title}</h2>
                  {item.declaration_number && (
                    <p className="text-sm text-muted-foreground">신고번호: {item.declaration_number}</p>
                  )}
                  {item.memo && (
                    <p className="line-clamp-2 text-sm text-muted-foreground">{item.memo}</p>
                  )}
                </div>
                <div className="shrink-0 text-right">
                  <p className="text-sm font-medium text-foreground">{formatDate(item.declaration_date)}</p>
                  <p className="mt-0.5 text-xs text-muted-foreground">신고일</p>
                </div>
              </div>
              {item.file_name && (
                <div className="mt-3 flex items-center gap-2 text-xs text-muted-foreground">
                  <FileText className="h-3.5 w-3.5 shrink-0" />
                  <span className="truncate">{item.file_name}</span>
                  {item.file_size && (
                    <span className="shrink-0">({formatFileSize(item.file_size)})</span>
                  )}
                </div>
              )}
            </Link>
          ))}
        </div>
      )}
    </PageShell>
  );
}
