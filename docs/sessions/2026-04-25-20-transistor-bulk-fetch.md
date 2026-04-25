# 2026-04-25-20 — Transistor refresh: bulk-выкачка вместо per-podcast

## Контекст

Пользователь: «есть ли бонусные эпизоды (exclusive) в API? например, в подкасте «запуск завтра» эпизод «как оставаться на связи в россии»». Эпизод не нашёлся в проде.

## Диагностика

- В Transistor этот эпизод существует: show `48202` (Запуск завтра), episode `3156403`, `type: bonus`, `status: published`, опубликован 2026-04-09.
- Локальный `TRANSISTOR_API_KEY` видит и show, и эпизод.
- На Railway переменная `TRANSISTOR_API_KEY` задана и у `LiboLibo` (web), и у `cron-refresh`.
- В логах `cron-refresh` — 35 ошибок `Transistor API … → HTTP 429` из ~44 подкастов.

Корневая причина: `refreshAllFeeds` гнал 8 параллельных воркеров, каждый делал `findShowIdByFeedUrl` (ходит по `/v1/shows`) и `listAllEpisodes(showId)` (ходит по `/v1/episodes?show_id=…`). Transistor резал по rate-limit, `transistorShowId` не сохранялся, премиум не подтягивался. Каждый следующий cron повторял ту же ошибку.

## Что сделали

`api/src/transistor/api.ts`:

- `getJSON`: ретраи на 429 с уважением `Retry-After` и экспонентой как fallback.
- `findShowIdByFeedUrl` → `listAllShowsByFeedUrl()`: отдаёт `Map<feedUrl, showId>` за 1–2 страницы.
- `listAllEpisodes(showId)` → `listAllEpisodesByShowId()`: один paginated пробег `/v1/episodes` без `show_id`, эпизоды раскладываются по `relationships.show.data.id`. Для всего аккаунта (~3088 эпизодов) это ~62 запроса вместо ~220 по подкастам.

`api/src/transistor/refresh.ts`:

- `refreshAllFeeds` один раз тянет shows + episodes из Transistor, передаёт в воркеры.
- `syncPremiumViaAPI` → `syncPremiumFromBulk`: показ резолвится через bulk-map (или из закэшированного `transistorShowId`), эпизоды берутся из готового `Map<showId, episodes[]>` — никаких per-podcast запросов в Transistor.
- При первом обнаружении `showId` он сохраняется в `Podcast.transistorShowId` (как и раньше).

## Ожидаемое поведение

- За один прогон: 1×`/shows` (1–2 стр.) + 1×`/episodes` (все стр.). На порядок меньше запросов, никаких 429.
- Даже если bulk-вызов упадёт целиком — public RSS-часть прогоняется как раньше.
- При следующем cron, после деплоя, бонусный эпизод «Как оставаться на связи в России?» появится в `GET /v1/podcasts/1488945593/episodes` с `is_premium: true` и `audio_url: null` (фаза 2.0, без IAP).

## Открытые вопросы

- Имеет смысл добавить тест на новые api-функции (вызов мокнутого fetch с 429-then-200), но сейчас не критично.
- На /shows и /episodes тоже стоит прикрутить кэш по дню/часу, если нагрузка на cron вырастет.
