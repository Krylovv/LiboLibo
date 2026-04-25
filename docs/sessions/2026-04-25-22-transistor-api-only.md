# 2026-04-25-22 — Только Transistor API, без RSS

## Контекст

После предыдущей сессии (bonus → premium через RSS-парсер) выяснилось, что
в БД задвоено ~2271 эпизода: одна копия из публичного RSS (id = `<guid>`),
вторая — из Transistor API (id = `mediaUrl` через fallback, потому что
`ep.guid` API не возвращает). У ~2242 пар `is_premium` расходился, что
делало гейтинг бессмысленным.

Решение: полностью отказаться от RSS как источника данных и тянуть всё
из Transistor API.

## Что сделали

1. `api/src/transistor/api.ts`:
   - `TransistorShow` теперь содержит `description` и `imageUrl`.
   - `listAllShowsByFeedUrl()` возвращает `Map<string, TransistorShow>`
     (было: `Map<string, string>`), чтобы channel-метаданные брать тем
     же запросом.

2. `api/src/transistor/refresh.ts` — переписан с нуля:
   - Один источник: Transistor API.
   - `episode.id` = Transistor episode id (например, `"3187703"`).
   - `is_premium = (attributes.type === "bonus")`.
   - Channel description и `artwork_url` обновляются из show'а.
   - `lastEpisodeDate` и `hasPremium` пересчитываются по эпизодам.
   - `FeedFetch` остался как success/error журнал (etag/lastModified
     теперь всегда null).

3. Удалены `api/src/transistor/parser.ts` и `api/test/parser.test.ts` —
   RSS-парсер больше не нужен.

4. Обновили `TRANSISTOR_API_KEY` в Railway (`LiboLibo` и `cron-refresh`)
   — старый ключ возвращал HTTP 401.

## Что в проде

- `TRUNCATE episodes; DELETE FROM feed_fetches;`
- `npm run refresh` локально с прод-DB → 2753 эпизода, 297 premium,
  44 подкаста, 22 с premium-контентом, **0 дубликатов**.

## Открытые вопросы / следующий шаг

- Refresh идёт последовательно по подкастам. Раньше был параллелизм
  `CONCURRENCY=8`. Внутри Railway-VPC (через `postgres.railway.internal`)
  это не критично, но при большом росте количества эпизодов стоит вернуть.
- В Transistor-аккаунте 56 shows, в БД 44 — 12 shows из API не заведены
  в каталог приложения (Любить нельзя воспитывать, Братислава, и т.д.).
  Это вопрос seed'а, не refresh'а.
- Если в подкасте «Два по цене одного» бонусный эпизод по политике
  должен быть подписочным, но в Transistor он `type=full` — нужен
  другой механизм (private show в Transistor или ручной override
  в БД).
