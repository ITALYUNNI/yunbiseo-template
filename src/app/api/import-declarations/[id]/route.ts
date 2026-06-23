import { NextRequest, NextResponse } from "next/server";

import { createAdminClient } from "@/lib/supabase/admin";
import { createRouteAuthErrorResponse, requireRouteUser } from "@/lib/route-auth";
import { logInfo } from "@/lib/logger";
import type { ImportDeclaration } from "@/lib/types";

export async function GET(
  _request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  try {
    const { supabase, user, authUnavailable } = await requireRouteUser();
    if (!user) return createRouteAuthErrorResponse(authUnavailable);

    const { id } = await params;

    const { data, error } = await supabase
      .from("import_declarations")
      .select("*")
      .eq("id", id)
      .single();

    if (error) {
      return NextResponse.json(
        { error: error.code === "PGRST116" ? "존재하지 않는 수입면장입니다." : error.message },
        { status: error.code === "PGRST116" ? 404 : 400 }
      );
    }

    return NextResponse.json(data as ImportDeclaration);
  } catch (error) {
    return NextResponse.json(
      { error: error instanceof Error ? error.message : "Unknown server error" },
      { status: 500 }
    );
  }
}

export async function PUT(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  try {
    const { supabase, user, authUnavailable } = await requireRouteUser();
    if (!user) return createRouteAuthErrorResponse(authUnavailable);

    const { id } = await params;
    const body = await request.json();

    const update: Record<string, unknown> = {};

    if (typeof body.title === "string" && body.title.trim()) {
      update.title = body.title.trim();
    }
    if (
      typeof body.declaration_date === "string" &&
      /^\d{4}-\d{2}-\d{2}$/.test(body.declaration_date)
    ) {
      update.declaration_date = body.declaration_date;
    }
    if ("declaration_number" in body) {
      update.declaration_number =
        typeof body.declaration_number === "string" && body.declaration_number.trim()
          ? body.declaration_number.trim()
          : null;
    }
    if ("file_url" in body) {
      update.file_url = body.file_url ?? null;
    }
    if ("file_name" in body) {
      update.file_name = body.file_name ?? null;
    }
    if ("file_size" in body) {
      update.file_size = body.file_size ?? null;
    }
    if ("memo" in body) {
      update.memo =
        typeof body.memo === "string" && body.memo.trim() ? body.memo.trim() : null;
    }

    const { data, error } = await supabase
      .from("import_declarations")
      .update(update)
      .eq("id", id)
      .select("*")
      .single();

    if (error) return NextResponse.json({ error: error.message }, { status: 400 });

    logInfo("UPDATE_IMPORT_DECLARATION", `수입면장 수정: ${id}`, {
      resource: "import_declaration",
      resource_id: id,
    });

    return NextResponse.json(data as ImportDeclaration);
  } catch (error) {
    return NextResponse.json(
      { error: error instanceof Error ? error.message : "Unknown server error" },
      { status: 500 }
    );
  }
}

export async function DELETE(
  _request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  try {
    const { supabase, user, authUnavailable } = await requireRouteUser();
    if (!user) return createRouteAuthErrorResponse(authUnavailable);

    const { id } = await params;

    // 파일 URL 먼저 조회해서 Storage에서도 삭제
    const { data: existing } = await supabase
      .from("import_declarations")
      .select("file_url, title")
      .eq("id", id)
      .single();

    const { error } = await supabase
      .from("import_declarations")
      .delete()
      .eq("id", id);

    if (error) return NextResponse.json({ error: error.message }, { status: 400 });

    // Storage 파일 삭제 (file_url에서 경로 추출)
    if (existing?.file_url) {
      try {
        const adminClient = createAdminClient();
        const url = new URL(existing.file_url);
        const pathParts = url.pathname.split("/import-declarations/");
        if (pathParts.length > 1) {
          await adminClient.storage
            .from("import-declarations")
            .remove([decodeURIComponent(pathParts[1])]);
        }
      } catch {
        // Storage 삭제 실패는 무시 (DB 삭제는 성공)
      }
    }

    logInfo("DELETE_IMPORT_DECLARATION", `수입면장 삭제: ${existing?.title ?? id}`, {
      resource: "import_declaration",
      resource_id: id,
    });

    return NextResponse.json({ success: true });
  } catch (error) {
    return NextResponse.json(
      { error: error instanceof Error ? error.message : "Unknown server error" },
      { status: 500 }
    );
  }
}
