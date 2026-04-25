// Thin client for the Instagram Graph API.
// Docs: https://developers.facebook.com/docs/instagram-api/
// Auth: long-lived Page access token, passed in `access_token` query param.
// The token is NEVER included in error messages or logs (defense in depth).

import type { InstagramConfig } from "./config.js";

const BASE = "https://graph.facebook.com/v21.0";

const LIST_FIELDS = ["id", "media_type", "media_product_type", "permalink", "caption", "timestamp"].join(",");
const DETAIL_FIELDS = [
  "id",
  "media_type",
  "media_product_type",
  "permalink",
  "caption",
  "timestamp",
  "media_url",
  "thumbnail_url",
  "children{id,media_type,media_url,thumbnail_url}",
].join(",");

export type IgRawMediaType = "IMAGE" | "VIDEO" | "CAROUSEL_ALBUM";
export type IgRawProductType = "FEED" | "REELS" | "STORY" | "AD";

export interface IgMediaSummary {
  id: string;
  mediaType: IgRawMediaType;
  mediaProductType: IgRawProductType;
  permalink: string;
  caption: string | null;
  timestamp: Date;
}

export interface IgChildMedia {
  id: string;
  mediaType: "IMAGE" | "VIDEO";
  mediaUrl: string | null;
  thumbnailUrl: string | null;
}

export interface IgMediaDetails extends IgMediaSummary {
  mediaUrl: string | null;
  thumbnailUrl: string | null;
  children: IgChildMedia[];
}

interface RawMedia {
  id: string;
  media_type: string;
  media_product_type?: string;
  permalink: string;
  caption?: string | null;
  timestamp: string;
  media_url?: string | null;
  thumbnail_url?: string | null;
  children?: { data: RawChild[] };
}

interface RawChild {
  id: string;
  media_type: string;
  media_url?: string | null;
  thumbnail_url?: string | null;
}

async function getJSON<T>(url: URL, path: string): Promise<T> {
  const resp = await fetch(url);
  if (!resp.ok) {
    // `path` deliberately does not include the access_token query param.
    throw new Error(`Graph API ${path} → HTTP ${resp.status}`);
  }
  return (await resp.json()) as T;
}

export async function listRecentMedia(
  config: InstagramConfig,
  limit: number,
): Promise<IgMediaSummary[]> {
  const path = `/${config.igUserId}/media`;
  const url = new URL(BASE + path);
  url.searchParams.set("fields", LIST_FIELDS);
  url.searchParams.set("limit", String(limit));
  url.searchParams.set("access_token", config.accessToken);

  const json = await getJSON<{ data: RawMedia[] }>(url, path);
  return (json.data ?? []).map(parseSummary);
}

export async function fetchMediaDetails(
  config: InstagramConfig,
  mediaId: string,
): Promise<IgMediaDetails> {
  const path = `/${mediaId}`;
  const url = new URL(BASE + path);
  url.searchParams.set("fields", DETAIL_FIELDS);
  url.searchParams.set("access_token", config.accessToken);

  const raw = await getJSON<RawMedia>(url, path);
  const summary = parseSummary(raw);
  return {
    ...summary,
    mediaUrl: raw.media_url ?? null,
    thumbnailUrl: raw.thumbnail_url ?? null,
    children: (raw.children?.data ?? []).map(parseChild),
  };
}

function parseSummary(raw: RawMedia): IgMediaSummary {
  return {
    id: raw.id,
    mediaType: normalizeMediaType(raw.media_type),
    mediaProductType: normalizeProductType(raw.media_product_type),
    permalink: raw.permalink,
    caption: raw.caption ?? null,
    timestamp: new Date(raw.timestamp),
  };
}

function parseChild(raw: RawChild): IgChildMedia {
  const t = normalizeMediaType(raw.media_type);
  // Carousels can technically only contain IMAGE or VIDEO, never nested albums.
  if (t === "CAROUSEL_ALBUM") {
    throw new Error(`Unexpected nested CAROUSEL_ALBUM in carousel children: ${raw.id}`);
  }
  return {
    id: raw.id,
    mediaType: t,
    mediaUrl: raw.media_url ?? null,
    thumbnailUrl: raw.thumbnail_url ?? null,
  };
}

function normalizeMediaType(raw: string): IgRawMediaType {
  if (raw === "IMAGE" || raw === "VIDEO" || raw === "CAROUSEL_ALBUM") return raw;
  throw new Error(`Unknown media_type from Graph API: ${raw}`);
}

function normalizeProductType(raw: string | undefined): IgRawProductType {
  if (raw === "FEED" || raw === "REELS" || raw === "STORY" || raw === "AD") return raw;
  // Default to FEED if Meta sends something we don't recognize. Don't throw —
  // that would block sync of an otherwise valid post.
  return "FEED";
}
