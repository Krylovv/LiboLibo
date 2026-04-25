# 2026-04-25 — Сессия 23. Step 3 Phase A: backend infra (Instagram collector)

## Контекст

Продолжение [сессии 19](2026-04-25-19-instagram-feed-spec.md), где была
написана спека и план реализации Фазы A для нового экрана «Лента из
Instagram». На этой сессии — реальная реализация Tasks 1–7 плана.

## Что сделали

### Получили production-токен Instagram Graph API

Прошли весь путь от создания Facebook App до long-lived Page-токена:

1. `LiboLibo inst Integration` (App ID `1005849215442183`).
2. Permissions: `instagram_basic`, `pages_show_list`, `pages_read_engagement`, `business_management`.
3. Long-lived Page-токен через двухшаговый обмен (`fb_exchange_token` → `/me/accounts`).
4. **`expires_at: 0`** (never expires) — подтверждено через `debug_token`.
5. Smoke-test на `/{ig-user-id}/media` показал реальные посты Либо-Либо
   (`@libolibostudio`, IG User ID `17841414860806820`).
6. Все секреты — в локальном `ig-token.txt` (gitignored) и `api/instagram.env`
   (тоже gitignored через `*.env`-правило).

### Реализация Phase A (7 коммитов на `main`)

| Коммит | Что | Тестов |
|---|---|---|
| `9e1a276` Step 3.A1 | env config (`instagram.env.example`, `config.ts`) | — |
| `fa27dff` Step 3.A2 | Prisma модели `InstagramPost` / `InstagramMedia` + enums | — |
| `5520eb4` Step 3.A3 | `graph-client.ts` (`listRecentMedia`, `fetchMediaDetails`) | 4 vitest |
| `cc05e0d` Step 3.A4-A5 | `collector.ts`: `normalizeForUpsert` + `syncInstagramPosts` | 4 vitest |
| `1aac22d` Step 3.A6 | `refresh-cli.ts` + npm-скрипт `refresh:instagram` | — |
| `9c62d9e` Step 3.A7 | Раздел про Instagram в `api/README.md` | — |

**Итого: 11 тестов зелёные** (3 parser + 4 graph-client + 4 collector).

### Smoke-тест локально (без БД)

Запуск `npm run refresh:instagram` с реальным токеном (но без локального
Postgres) показал, что:

- CLI стартует, конфиг читается ✓
- `listRecentMedia()` действительно ходит в Graph API и возвращает посты ✓
- `normalizeForUpsert()` отрабатывает на реальных summaries ✓
- Падает только на `prisma.upsert` (БД нет — это ожидаемо локально без Docker).

Production-путь полностью рабочий.

## Production-прогон (добавлено в конце сессии)

После того как Илья дал доступ к Railway-проекту `welcoming-happiness`:

- Через `railway link --project welcoming-happiness --service LiboLibo` залинковали репо.
- `railway variables --set META_ACCESS_TOKEN=... --set META_IG_USER_ID=17841414860806820`.
- `railway add --service cron-refresh-instagram --repo Krasilshchik3000/LiboLibo --variables ...` создал второй cron-сервис рядом с существующим `cron-refresh` (тот тянет Transistor).
- Илья в UI проставил `Root Directory=api`, `Custom Start Command=npm run refresh:instagram`, `Cron Schedule=*/30 * * * *`.
- Первый запуск отработал `{ "total": 30, "inserted": 30, "updated": 0, "skipped": 0, "apiEnabled": true }`.
- Через `railway connect Postgres` подтвердили: 30 строк со `status=PENDING`, типы 14 VIDEO + 15 CAROUSEL + 1 IMAGE, первые три записи — реальные посты Либо/Либо.

**Phase A полностью развёрнута на проде. Cron каждые 30 минут будет тянуть свежие посты.**

## Открытые наблюдения по ходу

- В рабочем дереве остались чужие изменения с design/podcast-header-variants
  (PodcastHeaderMockupsView) и chore/prisma-6 (bump prisma 5→6, PR #15).
  Я их не трогал.
- Между моими коммитами кто-то (вероятно IDE/Xcode) параллельно переключал
  ветки. Пара коммитов случайно ушла на `design/podcast-header-variants` и
  `analytics`; пере-cherry-pick'ал на `main`. Чтобы не мешать локальной
  работе пользователя при production-smoke, создал отдельный worktree
  `/tmp/libolibo-main`, удалил его в конце.

## Что НЕ доделано (для следующей сессии)

(Историческое: на момент написания основной части сессии Task 8
оставался открытым. К концу сессии Task 8 закрыт — см. секцию
«Production-прогон» выше. Список ниже сохраняю как фактический
референс по шагам, чтобы воспроизвести в случае пересоздания проекта.)

**Task 8 — Railway-конфигурация.** Сделать может только владелец проекта вручную:

1. На сервисе `api` в Railway → Variables добавить:
   - `META_ACCESS_TOKEN` = значение `PAGE_ACCESS_TOKEN` из `ig-token.txt`.
   - `META_IG_USER_ID` = `17841414860806820`.
2. Дождаться, пока pre-deploy `prisma db push` применит новую схему
   (таблицы `instagram_posts`, `instagram_media` появятся в Postgres).
3. Создать второй сервис в проекте: New → GitHub Repo → этот же.
   - Root Directory: `api`.
   - Settings → Deploy → Start Command: `npm run refresh:instagram`.
   - Settings → Deploy → Cron Schedule: `*/30 * * * *`.
   - Variables: `DATABASE_URL` = `${{Postgres.DATABASE_URL}}` (reference),
     `META_ACCESS_TOKEN` и `META_IG_USER_ID` (тоже reference из `api`-сервиса).
4. Проверить логи Cron Service — первый запуск должен напечатать
   `{"apiEnabled": true, "inserted": ~30, ...}`.
5. Проверить через `railway connect postgres` или data-explorer:
   `SELECT count(*) FROM instagram_posts WHERE status='PENDING';` →
   должно быть ~30.

После этого Phase A считается законченной — посты Либо-Либо начнут
автоматически появляться в БД каждые 30 минут.

## Открытые вопросы / наблюдения

- В рабочем дереве остались чужие изменения (design experiment
  `PodcastHeaderMockupsView` + bump prisma 5→6). Я их не трогал.
  При коммите Step 3.A6 пришлось временно откатывать `package.json` до HEAD,
  применять только мою строку `refresh:instagram`, коммитить, и потом
  возвращать пользовательский bump в working tree.
- Между моими коммитами кто-то параллельно переключал ветки (вероятно,
  IDE / Xcode). Пара коммитов случайно ушла на сторонние ветки
  (`design/podcast-header-variants`, `analytics`) и была перенесена на
  `main` через cherry-pick.

## ТЗ на следующую сессию

После выполнения Task 8 (или сразу — параллельно):

**Phase B — media pipeline.** Отдельный план реализации:
- `src/instagram/media-downloader.ts`: тянет media_url + thumbnails
  на Railway volume.
- `ffmpeg` в Dockerfile (для thumbnails из видео).
- `routes/media.ts`: статик-раздача из `MEDIA_DIR`.
- Интеграция: после каждого `syncInstagramPosts` (или отдельным cron)
  запускать downloader.

После Phase B → Phase C (admin + public API) → Phase D (iOS).
