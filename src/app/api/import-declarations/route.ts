import { NextRequest, NextResponse } from "next/server";

import { createRouteAuthErrorResponse, requireRouteUser } from "@/lib/route-auth";
import { logInfo } from "@/lib/logger";
import type { ImportDeclaration } from "@/lib/types";

export async function GET() {
  try {
    const { supabase, user, authUnavailable } = await requireRouteUser();
    if (!user) return createRouteAuthErrorResponse(authUnavailable);

    const { data, error } = await supabase
      .from("import_declarations")
      .select("*")
      .order("declaration_date", { ascending: false })
      .order("created_at", { ascending: false });

    if (error) return NextResponse.json({ error: error.message }, { status: 400 });

    return NextResponse.json((data ?? []) as ImportDeclaration[]);
  } catch (error) {
    return NextResponse.json(
      { error: error instanceof Error ? error.message : "Unknown server error" },
      { status: 500 }
    );
  }
}

export async function POST(request: NextRequest) {
  try {
    const { supabase, user, authUnavailable } = await requireRouteUser();
    if (!user) return createRouteAuthErrorResponse(authUnavailable);

    const body = await request.json();

    const title = typeof body.title === "string" ? body.title.trim() : "";
    if (!title) {
      return NextResponse.json({ error: "제목을 입력해 주세요." }, { status: 400 });
    }

    const declarationDate =
      typeof body.declaration_date === "string" ? body.declaration_date.trim() : "";
    if (!declarationDate || !/^\d{4}-\d{2}-\d{2}$/.test(declarationDate)) {
      return NextResponse.json({ error: "신고일을 올바르게 입력해 주세요." }, { status: 400 });
    }

    const payload = {
      title,
      declaration_date: declarationDate,
      declaration_number:
        typeof body.declaration_number === "string" && body.declaration_number.trim()
          ? body.declaration_number.trim()
          : null,
      file_url: typeof body.file_url === "string" && body.file_url ? body.file_url : null,
      file_name: typeof body.file_name === "string" && body.file_name ? body.file_name : null,
      file_size:
        typeof body.file_size === "number" && body.file_size > 0 ? body.file_size : null,
      memo: typeof body.memo === "string" && body.memo.trim() ? body.memo.trim() : null,
      created_by: user.id,
    };

    const { data, error } = await supabase
      .from("import_declarations")
      .insert(payload)
      .select("*")
      .single();

    if (error) return NextResponse.json({ error: error.message }, { status: 400 });

    logInfo("CREATE_IMPORT_DECLARATION", `수입면장 등록: ${title}`, {
      resource: "import_declaration",
      resource_id: data.id,
      details: { declaration_date: declarationDate },
    });

    return NextResponse.json(data as ImportDeclaration, { status: 201 });
  } catch (error) {
    return NextResponse.json(
      { error: error instanceof Error ? error.message : "Unknown server error" },
      { status: 500 }
    );
  }
}
