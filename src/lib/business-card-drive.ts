import { deleteFile, uploadFile } from "@/lib/google-drive";

export const BUSINESS_CARD_DRIVE_FOLDER_ID = "1haJYnjRhJHTHfUrrqypFuQO5BuO-kqMO";

function toBuffer(base64Data: string) {
  return Buffer.from(base64Data, "base64");
}

export async function uploadBusinessCardImage(params: {
  fileName: string;
  mimeType: string;
  base64Data: string;
}) {
  return uploadFile(
    BUSINESS_CARD_DRIVE_FOLDER_ID,
    params.fileName,
    params.mimeType,
    toBuffer(params.base64Data)
  );
}

export async function deleteBusinessCardImage(fileId: string | null | undefined) {
  if (!fileId) {
    return;
  }

  await deleteFile(fileId);
}
