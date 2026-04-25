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
    fetchSpy.mockResolvedValue(
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
