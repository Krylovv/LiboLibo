// Reads Instagram Graph API config from process.env. Mirrors the pattern in
// src/transistor/api.ts: tokens are NEVER logged or echoed; the integration
// is fully optional (`isConfigured() === false` → collector becomes a no-op).

export interface InstagramConfig {
  accessToken: string;
  igUserId: string;
}

export function isConfigured(): boolean {
  return (
    typeof process.env.META_ACCESS_TOKEN === "string" &&
    process.env.META_ACCESS_TOKEN.length > 0 &&
    typeof process.env.META_IG_USER_ID === "string" &&
    process.env.META_IG_USER_ID.length > 0
  );
}

export function readConfig(): InstagramConfig {
  const accessToken = process.env.META_ACCESS_TOKEN;
  const igUserId = process.env.META_IG_USER_ID;
  if (!accessToken) throw new Error("META_ACCESS_TOKEN is not set");
  if (!igUserId) throw new Error("META_IG_USER_ID is not set");
  return { accessToken, igUserId };
}
