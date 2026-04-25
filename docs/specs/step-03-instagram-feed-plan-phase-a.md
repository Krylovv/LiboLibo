# Шаг 3 — Фаза A: Backend infra (Instagram collector). План реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Бэкенд (api/) умеет тянуть посты Instagram-аккаунта Либо-Либо через Graph API и складывать их в Postgres со статусом `PENDING`. Никаких файлов, админки и публичного API — это последующие фазы.

**Architecture:** Новый модуль `src/instagram/` рядом с существующим `src/transistor/`. Чистый Graph API клиент + collector с upsert по `ig_media_id`. CLI-обёртка под Railway Cron Service по аналогии с `transistor/refresh-cli.ts`. Прямой fetch (никаких SDK), всё в TypeScript ESM, тесты — vitest.

**Tech Stack:** Node.js 22, TypeScript ESM, Express, Prisma, Postgres, vitest. Доступ к Instagram через **Instagram Graph API** (long-lived Page access token).

**Спека:** [step-03-instagram-feed.md](step-03-instagram-feed.md)

---

## Файловая карта

| Файл | Что это | Статус |
|---|---|---|
| `api/prisma/schema.prisma` | + модели `InstagramPost`, `InstagramMedia`, enums `IgPostType/IgStatus/IgCtaType/IgMediaKind`, обратные отношения на `Episode`/`Podcast` | modify |
| `api/instagram.env.example` | Шаблон env (`META_ACCESS_TOKEN`, `META_IG_USER_ID`) | create |
| `api/src/instagram/config.ts` | `isConfigured()`, чтение env-переменных | create |
| `api/src/instagram/graph-client.ts` | Чистый клиент Graph API: `listRecentMedia()`, `fetchMediaDetails()` | create |
| `api/src/instagram/collector.ts` | `syncInstagramPosts()` — upsert постов по `igMediaId` | create |
| `api/src/instagram/refresh-cli.ts` | CLI для `npm run refresh:instagram` | create |
| `api/test/instagram-graph-client.test.ts` | Юнит-тесты графклиента (мокаем `fetch`) | create |
| `api/test/instagram-collector.test.ts` | Юнит-тесты на чистую функцию `normalizeMedia` | create |
| `api/package.json` | + npm script `refresh:instagram` | modify |
| `api/README.md` | + инструкция по локальному запуску collector'а | modify |

---

## Task 1: Подготовка env-конфига

**Files:**
- Create: `api/instagram.env.example`
- Create: `api/src/instagram/config.ts`

- [ ] **Step 1.1:** Создать `api/instagram.env.example` с шаблоном env-переменных.

```bash
# Instagram Graph API integration.
# Получить токен:
#   1. В Meta Business Suite → подключить IG Либо-Либо как Business/Creator аккаунт.
#   2. Привязать к Facebook Page студии.
#   3. В Facebook for Developers создать App (тип Business), добавить Instagram Graph API.
#   4. Сгенерировать long-lived Page access token (60 дней; продлевается автоматически).
#   5. Резолвить ig-user-id: GET /{page-id}?fields=instagram_business_account
META_ACCESS_TOKEN=
META_IG_USER_ID=
```

- [ ] **Step 1.2:** Создать `api/src/instagram/config.ts`.

```typescript
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
```

- [ ] **Step 1.3:** Коммит.

```bash
git add api/instagram.env.example api/src/instagram/config.ts
git commit -m "Step 3.A1: instagram env scaffold"
```

---

## Task 2: Prisma-миграция (модели Instagram)

**Files:**
- Modify: `api/prisma/schema.prisma`

- [ ] **Step 2.1:** Открыть `api/prisma/schema.prisma`. В конец файла (после `Device`) добавить блок:

```prisma
model InstagramPost {
  id            String     @id @default(uuid()) @db.Uuid
  igMediaId     String     @unique @map("ig_media_id")
  igPermalink   String     @map("ig_permalink")
  type          IgPostType
  caption       String?
  igCreatedAt   DateTime   @map("ig_created_at")
  status        IgStatus   @default(PENDING)
  publishedAt   DateTime?  @map("published_at")
  ctaType       IgCtaType? @map("cta_type")
  ctaEpisodeId  String?    @map("cta_episode_id")
  ctaEpisode    Episode?   @relation(fields: [ctaEpisodeId], references: [id], onDelete: SetNull)
  ctaPodcastId  BigInt?    @map("cta_podcast_id")
  ctaPodcast    Podcast?   @relation(fields: [ctaPodcastId], references: [id], onDelete: SetNull)
  ctaUrl        String?    @map("cta_url")
  ctaLabel      String?    @map("cta_label")
  createdAt     DateTime   @default(now()) @map("created_at")
  updatedAt     DateTime   @updatedAt @map("updated_at")

  media         InstagramMedia[]

  @@index([status, publishedAt(sort: Desc)])
  @@map("instagram_posts")
}

model InstagramMedia {
  id             String        @id @default(uuid()) @db.Uuid
  postId         String        @map("post_id") @db.Uuid
  post           InstagramPost @relation(fields: [postId], references: [id], onDelete: Cascade)
  order          Int
  kind           IgMediaKind
  filePath       String        @map("file_path")
  thumbnailPath  String?       @map("thumbnail_path")
  width          Int
  height         Int
  durationSec    Int?          @map("duration_sec")

  @@unique([postId, order])
  @@map("instagram_media")
}

enum IgPostType  { IMAGE CAROUSEL VIDEO }
enum IgStatus    { PENDING PUBLISHED HIDDEN }
enum IgCtaType   { EPISODE PODCAST LINK }
enum IgMediaKind { IMAGE VIDEO }
```

- [ ] **Step 2.2:** В существующих моделях `Episode` и `Podcast` добавить обратные отношения. Найти модель `Episode` (после поля `updatedAt`) и добавить строку:

```prisma
  instagramPosts InstagramPost[]
```

То же для модели `Podcast` (после `feedFetch FeedFetch?`):

```prisma
  instagramPosts InstagramPost[]
```

- [ ] **Step 2.3:** Запустить миграцию локально (поднимает Postgres из docker-compose, если ещё не запущен).

```bash
cd api && npm run prisma:migrate -- --name add-instagram-models
```

Expected: новая миграция в `api/prisma/migrations/<timestamp>_add_instagram_models/migration.sql`, таблицы `instagram_posts`, `instagram_media` и enum-типы созданы. Команда `npx prisma generate` отрабатывает без ошибок.

- [ ] **Step 2.4:** Запустить vitest, чтобы убедиться что существующие тесты не сломались.

```bash
cd api && npm test
```

Expected: `parser.test.ts` зелёный.

- [ ] **Step 2.5:** Коммит.

```bash
git add api/prisma/schema.prisma api/prisma/migrations/
git commit -m "Step 3.A2: Prisma models for Instagram posts and media"
```

---

## Task 3: Graph API клиент (TDD)

**Files:**
- Create: `api/src/instagram/graph-client.ts`
- Test: `api/test/instagram-graph-client.test.ts`

Чистый клиент: один файл, две функции, без работы с БД, без зависимости от env (конфиг приходит параметром, чтобы тесты не возились с `process.env`).

- [ ] **Step 3.1: Написать падающий тест на `listRecentMedia`.**

Создать `api/test/instagram-graph-client.test.ts`:

```typescript
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { listRecentMedia, fetchMediaDetails } from "../src/instagram/graph-client.js";

const CONFIG = { accessToken: "TEST_TOKEN", igUserId: "17841400000000000" };

describe("listRecentMedia", () => {
  let fetchSpy: ReturnType<typeof vi.spyOn>;

  beforeEach(() => {
    fetchSpy = vi.spyOn(globalThis, "fetch");
  });
  afterEach(() => {
    fetchSpy.mockRestore();
  });

  it("формирует правильный URL и парсит ответ", async () => {
    fetchSpy.mockResolvedValueOnce(
      new Response(
        JSON.stringify({
          data: [
            {
              id: "111",
              media_type: "IMAGE",
              media_product_type: "FEED",
              permalink: "https://www.instagram.com/p/abc/",
              caption: "Hello",
              timestamp: "2026-04-25T10:00:00+0000",
            },
            {
              id: "222",
              media_type: "VIDEO",
              media_product_type: "REELS",
              permalink: "https://www.instagram.com/reel/xyz/",
              caption: null,
              timestamp: "2026-04-24T08:00:00+0000",
            },
          ],
        }),
        { status: 200 },
      ),
    );

    const items = await listRecentMedia(CONFIG, 30);

    expect(fetchSpy).toHaveBeenCalledOnce();
    const calledUrl = new URL((fetchSpy.mock.calls[0]![0] as URL | string).toString());
    expect(calledUrl.host).toBe("graph.facebook.com");
    expect(calledUrl.pathname).toBe(`/v21.0/${CONFIG.igUserId}/media`);
    expect(calledUrl.searchParams.get("limit")).toBe("30");
    expect(calledUrl.searchParams.get("access_token")).toBe(CONFIG.accessToken);
    expect(calledUrl.searchParams.get("fields")).toContain("media_type");

    expect(items).toHaveLength(2);
    expect(items[0]).toMatchObject({
      id: "111",
      mediaType: "IMAGE",
      mediaProductType: "FEED",
      caption: "Hello",
    });
    expect(items[0]!.timestamp.toISOString()).toBe("2026-04-25T10:00:00.000Z");
    expect(items[1]!.caption).toBeNull();
  });

  it("кидает ошибку без токена в сообщении на не-2xx ответе", async () => {
    fetchSpy.mockResolvedValueOnce(
      new Response(JSON.stringify({ error: { message: "Invalid OAuth", code: 190 } }), {
        status: 400,
      }),
    );

    await expect(listRecentMedia(CONFIG, 30)).rejects.toThrow(/Graph API .* 400/);
    await expect(listRecentMedia(CONFIG, 30)).rejects.not.toThrow(/TEST_TOKEN/);
  });
});

describe("fetchMediaDetails", () => {
  let fetchSpy: ReturnType<typeof vi.spyOn>;

  beforeEach(() => {
    fetchSpy = vi.spyOn(globalThis, "fetch");
  });
  afterEach(() => {
    fetchSpy.mockRestore();
  });

  it("отдаёт media_url и thumbnail_url для одиночного поста", async () => {
    fetchSpy.mockResolvedValueOnce(
      new Response(
        JSON.stringify({
          id: "111",
          media_type: "VIDEO",
          media_product_type: "REELS",
          permalink: "https://www.instagram.com/reel/xyz/",
          caption: "reel",
          timestamp: "2026-04-24T08:00:00+0000",
          media_url: "https://video.cdninstagram.com/video.mp4",
          thumbnail_url: "https://video.cdninstagram.com/thumb.jpg",
        }),
        { status: 200 },
      ),
    );

    const detail = await fetchMediaDetails(CONFIG, "111");

    expect(detail.mediaUrl).toBe("https://video.cdninstagram.com/video.mp4");
    expect(detail.thumbnailUrl).toBe("https://video.cdninstagram.com/thumb.jpg");
    expect(detail.children).toEqual([]);
  });

  it("разворачивает children для CAROUSEL_ALBUM", async () => {
    fetchSpy.mockResolvedValueOnce(
      new Response(
        JSON.stringify({
          id: "333",
          media_type: "CAROUSEL_ALBUM",
          media_product_type: "FEED",
          permalink: "https://www.instagram.com/p/qqq/",
          caption: "carousel",
          timestamp: "2026-04-23T10:00:00+0000",
          children: {
            data: [
              { id: "c1", media_type: "IMAGE", media_url: "https://x/1.jpg" },
              { id: "c2", media_type: "VIDEO", media_url: "https://x/2.mp4", thumbnail_url: "https://x/2t.jpg" },
            ],
          },
        }),
        { status: 200 },
      ),
    );

    const detail = await fetchMediaDetails(CONFIG, "333");

    expect(detail.children).toHaveLength(2);
    expect(detail.children[0]).toMatchObject({ id: "c1", mediaType: "IMAGE", mediaUrl: "https://x/1.jpg" });
    expect(detail.children[1]).toMatchObject({ id: "c2", mediaType: "VIDEO", thumbnailUrl: "https://x/2t.jpg" });
  });
});
```

- [ ] **Step 3.2: Запустить тест и убедиться, что он падает.**

```bash
cd api && npm test -- instagram-graph-client
```

Expected: FAIL — модуль `../src/instagram/graph-client.js` не существует.

- [ ] **Step 3.3: Написать минимальную реализацию `graph-client.ts`.**

Создать `api/src/instagram/graph-client.ts`:

```typescript
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
```

- [ ] **Step 3.4: Запустить тесты и убедиться, что они зелёные.**

```bash
cd api && npm test -- instagram-graph-client
```

Expected: PASS, оба describe-блока зелёные.

- [ ] **Step 3.5: Коммит.**

```bash
git add api/src/instagram/graph-client.ts api/test/instagram-graph-client.test.ts
git commit -m "Step 3.A3: Instagram Graph API client"
```

---

## Task 4: Чистая функция нормализации поста (TDD)

Перед тем как трогать prisma, отделим преобразование "ответ Graph API → данные для upsert" в чистую функцию. Так её можно тестировать без БД.

**Files:**
- Create: `api/src/instagram/collector.ts` (только `normalizeForUpsert` на этом шаге)
- Test: `api/test/instagram-collector.test.ts`

- [ ] **Step 4.1: Написать тест на нормализацию.**

Создать `api/test/instagram-collector.test.ts`:

```typescript
import { describe, it, expect } from "vitest";
import { normalizeForUpsert } from "../src/instagram/collector.js";
import type { IgMediaSummary } from "../src/instagram/graph-client.js";

const baseSummary = (over: Partial<IgMediaSummary> = {}): IgMediaSummary => ({
  id: "111",
  mediaType: "IMAGE",
  mediaProductType: "FEED",
  permalink: "https://www.instagram.com/p/abc/",
  caption: "Hello",
  timestamp: new Date("2026-04-25T10:00:00Z"),
  ...over,
});

describe("normalizeForUpsert", () => {
  it("маппит IMAGE → type=IMAGE", () => {
    const p = normalizeForUpsert(baseSummary({ mediaType: "IMAGE" }));
    expect(p.type).toBe("IMAGE");
    expect(p.igMediaId).toBe("111");
    expect(p.caption).toBe("Hello");
    expect(p.igPermalink).toBe("https://www.instagram.com/p/abc/");
    expect(p.igCreatedAt.toISOString()).toBe("2026-04-25T10:00:00.000Z");
  });

  it("маппит CAROUSEL_ALBUM → type=CAROUSEL", () => {
    const p = normalizeForUpsert(baseSummary({ mediaType: "CAROUSEL_ALBUM" }));
    expect(p.type).toBe("CAROUSEL");
  });

  it("маппит VIDEO (как FEED, так и REELS) → type=VIDEO", () => {
    expect(normalizeForUpsert(baseSummary({ mediaType: "VIDEO", mediaProductType: "FEED" })).type).toBe("VIDEO");
    expect(normalizeForUpsert(baseSummary({ mediaType: "VIDEO", mediaProductType: "REELS" })).type).toBe("VIDEO");
  });

  it("сохраняет caption=null", () => {
    const p = normalizeForUpsert(baseSummary({ caption: null }));
    expect(p.caption).toBeNull();
  });
});
```

- [ ] **Step 4.2: Запустить тест и убедиться, что он падает.**

```bash
cd api && npm test -- instagram-collector
```

Expected: FAIL — модуль `../src/instagram/collector.js` не существует.

- [ ] **Step 4.3: Создать `api/src/instagram/collector.ts` с функцией `normalizeForUpsert`.**

```typescript
// Instagram post collector. Pulls the latest media via Graph API and upserts
// rows into the `instagram_posts` table by `igMediaId`. NO media files are
// downloaded here — that's Phase B (media-downloader). Idempotent: safe to
// run repeatedly, only `caption` and `igPermalink` get refreshed for known posts.

import type { IgMediaSummary } from "./graph-client.js";

export type IgPostType = "IMAGE" | "CAROUSEL" | "VIDEO";

export interface UpsertablePost {
  igMediaId: string;
  igPermalink: string;
  type: IgPostType;
  caption: string | null;
  igCreatedAt: Date;
}

export function normalizeForUpsert(summary: IgMediaSummary): UpsertablePost {
  return {
    igMediaId: summary.id,
    igPermalink: summary.permalink,
    type: mapType(summary.mediaType),
    caption: summary.caption,
    igCreatedAt: summary.timestamp,
  };
}

function mapType(t: IgMediaSummary["mediaType"]): IgPostType {
  switch (t) {
    case "IMAGE":
      return "IMAGE";
    case "CAROUSEL_ALBUM":
      return "CAROUSEL";
    case "VIDEO":
      return "VIDEO";
  }
}
```

- [ ] **Step 4.4: Запустить тесты — должны позеленеть.**

```bash
cd api && npm test -- instagram-collector
```

Expected: PASS, 4 теста.

- [ ] **Step 4.5: Коммит.**

```bash
git add api/src/instagram/collector.ts api/test/instagram-collector.test.ts
git commit -m "Step 3.A4: post normalization helper"
```

---

## Task 5: Точка входа `syncInstagramPosts`

В `collector.ts` добавляем основную функцию, которая использует graph-client и пишет в Prisma. Юнит-тестов на неё не делаем (это I/O-функция, цена тестов на mock prisma не оправдана; верификация — Task 7 ручной smoke).

**Files:**
- Modify: `api/src/instagram/collector.ts`

- [ ] **Step 5.1:** Дописать в `api/src/instagram/collector.ts` после функции `mapType` (импорты добавить в шапку):

```typescript
// --- Импорты, добавить в верх файла --------------------------------------
// import { prisma } from "../db.js";
// import { isConfigured, readConfig } from "./config.js";
// import { listRecentMedia } from "./graph-client.js";

const BATCH_LIMIT = 30;

export interface SyncSummary {
  total: number;
  inserted: number;
  updated: number;
  skipped: number;
  apiEnabled: boolean;
}

export async function syncInstagramPosts(): Promise<SyncSummary> {
  if (!isConfigured()) {
    return { total: 0, inserted: 0, updated: 0, skipped: 0, apiEnabled: false };
  }

  const config = readConfig();
  const summaries = await listRecentMedia(config, BATCH_LIMIT);

  let inserted = 0;
  let updated = 0;

  for (const summary of summaries) {
    const upsertable = normalizeForUpsert(summary);

    const result = await prisma.instagramPost.upsert({
      where: { igMediaId: upsertable.igMediaId },
      create: {
        igMediaId: upsertable.igMediaId,
        igPermalink: upsertable.igPermalink,
        type: upsertable.type,
        caption: upsertable.caption,
        igCreatedAt: upsertable.igCreatedAt,
      },
      update: {
        igPermalink: upsertable.igPermalink,
        caption: upsertable.caption,
      },
      select: { createdAt: true, updatedAt: true },
    });

    // Heuristic: createdAt === updatedAt (within 1ms) means we just inserted.
    if (Math.abs(result.createdAt.getTime() - result.updatedAt.getTime()) < 1) {
      inserted += 1;
    } else {
      updated += 1;
    }
  }

  return {
    total: summaries.length,
    inserted,
    updated,
    skipped: summaries.length - inserted - updated,
    apiEnabled: true,
  };
}
```

Финальная шапка файла должна выглядеть так:

```typescript
import { prisma } from "../db.js";
import { isConfigured, readConfig } from "./config.js";
import { listRecentMedia, type IgMediaSummary } from "./graph-client.js";
```

- [ ] **Step 5.2:** Запустить tsc, чтобы убедиться что типы ок.

```bash
cd api && npx tsc -p tsconfig.json --noEmit
```

Expected: пусто (нет ошибок).

- [ ] **Step 5.3:** Запустить весь тест-сьют — старые тесты должны быть зелёными.

```bash
cd api && npm test
```

Expected: PASS.

- [ ] **Step 5.4: Коммит.**

```bash
git add api/src/instagram/collector.ts
git commit -m "Step 3.A5: syncInstagramPosts upserts via Prisma"
```

---

## Task 6: CLI и npm-скрипт для Railway Cron

**Files:**
- Create: `api/src/instagram/refresh-cli.ts`
- Modify: `api/package.json`

- [ ] **Step 6.1:** Создать `api/src/instagram/refresh-cli.ts`.

```typescript
// Standalone CLI: `npm run refresh:instagram`. Used by Railway Cron Service
// that runs every 30 minutes (configured separately in Railway UI as a cron
// service pointing at the same repo, command `npm run refresh:instagram`).
import { syncInstagramPosts } from "./collector.js";

(async () => {
  const summary = await syncInstagramPosts();
  console.log(JSON.stringify(summary, null, 2));
  process.exit(0);
})().catch((err) => {
  console.error(err);
  process.exit(1);
});
```

- [ ] **Step 6.2:** Открыть `api/package.json`, в `scripts` рядом с существующим `"refresh"` добавить:

```json
"refresh:instagram": "tsx src/instagram/refresh-cli.ts",
```

После правки `scripts` должен содержать строку:

```json
"refresh": "tsx src/transistor/refresh-cli.ts",
"refresh:instagram": "tsx src/instagram/refresh-cli.ts",
```

- [ ] **Step 6.3:** Скомпилировать, чтобы убедиться что нет ошибок.

```bash
cd api && npm run build
```

Expected: сборка без ошибок.

- [ ] **Step 6.4: Коммит.**

```bash
git add api/src/instagram/refresh-cli.ts api/package.json
git commit -m "Step 3.A6: refresh:instagram CLI"
```

---

## Task 7: Локальный smoke-test и документация

**Files:**
- Modify: `api/README.md`

- [ ] **Step 7.1:** Скопировать пример env и заполнить локально.

```bash
cd api
cp instagram.env.example instagram.env
# открыть instagram.env, вписать настоящие META_ACCESS_TOKEN и META_IG_USER_ID
```

- [ ] **Step 7.2:** Убедиться что `instagram.env` в `.gitignore`. Прочитать `api/.gitignore` и, если там нет паттерна `*.env` или явного `instagram.env`, добавить:

```
instagram.env
```

- [ ] **Step 7.3:** Запустить `docker-compose up -d` (если ещё не запущен), затем:

```bash
cd api
set -a && source instagram.env && source transistor.env && set +a
npm run refresh:instagram
```

Expected: на stdout — JSON вида `{"total": 30, "inserted": 30, "updated": 0, "skipped": 0, "apiEnabled": true}`. В Postgres появляются 30 строк в `instagram_posts` со статусом `PENDING`.

- [ ] **Step 7.4:** Проверить запросом:

```bash
docker compose -f api/docker-compose.yml exec postgres psql -U postgres -d libolibo -c "SELECT count(*), status FROM instagram_posts GROUP BY status;"
```

Expected: одна строка, status=`PENDING`, count = тому что в IG-аккаунте за последние 30 постов.

- [ ] **Step 7.5:** Запустить второй раз — проверить идемпотентность.

```bash
cd api && npm run refresh:instagram
```

Expected: `{"total": 30, "inserted": 0, "updated": 30, ...}` (либо `skipped`, если ничего не поменялось — детали зависят от точности маркера).

- [ ] **Step 7.6:** Дописать в `api/README.md` короткий блок про Instagram (после блока про transistor):

```markdown
## Instagram collector

Стягивает посты Instagram-аккаунта Либо-Либо через Graph API и складывает
в `instagram_posts` со статусом `PENDING`. На Railway работает отдельный
Cron Service, запускающий `npm run refresh:instagram` каждые 30 минут.

Локально:

1. Скопировать `instagram.env.example` → `instagram.env`, заполнить
   `META_ACCESS_TOKEN` (long-lived Page token) и `META_IG_USER_ID`.
2. `set -a && source instagram.env && set +a && npm run refresh:instagram`.

Файлы медиа на этом этапе НЕ скачиваются — это делает downloader (Фаза B).
```

- [ ] **Step 7.7: Коммит.**

```bash
git add api/README.md api/.gitignore
git commit -m "Step 3.A7: docs and gitignore for instagram collector"
```

---

## Task 8: Деплой и Cron Service на Railway

Не-кодовые шаги, выполняемые человеком в Railway UI. Не входят в TDD-цикл, но должны быть в плане для полноты.

- [ ] **Step 8.1:** Запушить ветку.

```bash
git push origin main
```

- [ ] **Step 8.2:** В Railway проекте `libolibo`:
  - В сервисе API установить переменные окружения `META_ACCESS_TOKEN`, `META_IG_USER_ID` (Variables → Add).
  - Дождаться, пока pre-deploy `prisma db push` применит новую схему (`instagram_posts`, `instagram_media` появятся в Postgres).

- [ ] **Step 8.3:** В Railway создать новый **Cron Service** в том же проекте:
  - Source: тот же GitHub repo, та же ветка `main`, root directory `api`.
  - Schedule: `*/30 * * * *` (каждые 30 минут).
  - Start command: `npm run refresh:instagram`.
  - Variables: те же `DATABASE_URL`, `META_ACCESS_TOKEN`, `META_IG_USER_ID` (можно через Reference Variables).

- [ ] **Step 8.4:** В Railway → Cron Service → Logs убедиться, что первый запуск прошёл и в логе виден JSON с `apiEnabled: true` и `inserted > 0`.

- [ ] **Step 8.5:** Через `railway connect postgres` (или Railway data-explorer) убедиться, что в `instagram_posts` появились строки.

---

## Self-review (по итогам написания плана)

- [x] **Spec coverage.** Спека раздел 4.1 (модули) → 4.3 (collector behavior) → 4.8 (security): все позиции, относящиеся к Фазе A, имеют соответствующую задачу. Раздел 4.2 (Prisma) — Task 2. Раздел 4.3 — Task 3+4+5. Раздел 4.4 (downloader) и 4.5 (admin) и 4.6 (public API) — НЕ входят в Фазу A, и это явно зафиксировано.
- [x] **Placeholder scan.** Нет «TBD/TODO», все код-блоки полные.
- [x] **Type consistency.** `IgPostType` определён как enum в `collector.ts` (строки `IMAGE`/`CAROUSEL`/`VIDEO`), совпадает с Prisma enum'ом. `IgMediaSummary.mediaType` остаётся "сырым" (`IMAGE`/`VIDEO`/`CAROUSEL_ALBUM`) — намеренно различает входной формат Meta и наш доменный enum.
- [x] **Идемпотентность** проверяется на Step 7.5.
- [x] **Тесты не зависят от БД** (нет mock prisma); БД-проверки — через ручной smoke (Task 7) и Railway logs (Task 8).
