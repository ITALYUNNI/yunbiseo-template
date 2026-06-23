import { NextRequest, NextResponse } from "next/server";

import { createAdminClient } from "@/lib/supabase/admin";
import { createRouteAuthErrorResponse, requireRouteUser } from "@/lib/route-auth";

const MAX_FILE_SIZE = 50 * 1024 * 1024; // 50MB

export async function POST(request: NextRequest) {
  try {
    const { user, authUnavailable } = await requireRouteUser();
    if (!user) return createRouteAuthErrorResponse(authUnavailable);

    const formData = await request.formData();
    const file = formData.get("file") as File | null;

    if (!file) {
      return NextResponse.json({ error: "파일을 선택해 주세요." }, { status: 400 });
    }

    if (file.size > MAX_FILE_SIZE) {
      return NextResponse.json({ error: "파일 크기는 50MB 이하여야 합니다." }, { status: 400 });
    }

    const ext = file.name.split(".").pop() ?? "";
    const timestamp = Date.now();
    const safeName = file.name.replace(/[^a-zA-Z0-9가-힣._-]/g, "_");
    const filePath = `${user.id}/${timestamp}_${safeName}`;

    const arrayBuffer = await file.arrayBuffer();
    const buffer = Buffer.from(arrayBuffer);

    const adminClient = createAdminClient();
    const { data, error } = await adminClient.storage
      .from("import-declarations")
      .upload(filePath, buffer, {
        contentType: file.type || "application/octet-stream",
        upsert: false,
      });

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 400 });
    }

    const { data: urlData } = adminClient.storage
      .from("import-declarations")
      .getPublicUrl(data.path);

    // 비공개 버킷이므로 signed URL 생성 (1년 유효)
    const { data: signedData, error: signedError } = await adminClient.storage
      .from("import-declarations")
      .createSignedUrl(data.path, 60 * 60 * 24 * 365);

    const fileUrl = signedError ? urlData.publicUrl : (signedData?.signedUrl ?? urlData.publicUrl);

    return NextResponse.json({
      file_url: fileUrl,
      file_name: file.name,
      file_size: file.size,
      path: data.path,
      ext,
    });
  } catch (error) {
    return NextResponse.json(
      { error: error instanceof Error ? error.message : "Unknown server error" },
      { status: 500 }
    );
  }
}
