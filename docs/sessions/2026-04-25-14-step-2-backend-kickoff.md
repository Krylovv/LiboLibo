# 2026-04-25 — Шаг 2: стартовая сессия по бэкенду (сессия 8)

**Контекст:** Шаг 1 (iOS-каркас) закрыт — приложение тянет 44 RSS-фида Либо-Либо напрямую с Transistor, играет, помнит подписки и историю локально (см. [сессия 7](2026-04-25-07-step-1.4.md), [спека шага 1](../specs/step-01-ios-skeleton.md)). Теперь стартует параллельный трек — бэкенд Самата. На этой сессии договорились о стеке, инфраструктуре, объёме фазы 2.0.

**Участники:** Самат Галимов (backend), Claude.

## Что решили

### Стек бэкенда

| Слой | Выбор | Почему |
|---|---|---|
| Runtime | Node.js 22 + TypeScript | Стандарт; TS обязателен для Prisma |
| HTTP-фреймворк | Express | Зрелый, простой, всем знаком |
| ORM | Prisma | Запрошен явно; типы и миграции из коробки |
| БД | Postgres (Railway plugin) | Нативная интеграция, `DATABASE_URL` подставляется reference-переменной |
| Cron | Railway Cron Service | Отдельный сервис из того же Dockerfile, запускает CLI |
| Парсер RSS | fast-xml-parser | Самый адекватный pure-JS парсер |
| Тесты | vitest | По запросу |
| Логи | console.\* | На фазе 2.0 хватит; pino/Sentry — позже |
| Локалка | Docker Compose (Postgres + API) | Запуск в одну команду |

Зависимости рантайма: `express`, `@prisma/client`, `fast-xml-parser`. Dev: `typescript`, `tsx`, `prisma`, `vitest`, `@types/express`, `@types/node`. Больше ничего.

### Что бэкенд делает на фазе 2.0 (RAW)

Заменить 44 параллельных запроса с iOS к Transistor на один-два запроса к нашему API. Поведение приложения снаружи не меняется. Всё про премиум, push, оплаты, аккаунты, синк подписок — на следующих фазах.

Полный план фазы — в [`docs/specs/step-02-backend.md`](../specs/step-02-backend.md). Контракт API — в [`docs/specs/api/openapi.yaml`](../specs/api/openapi.yaml).

### Источник правды по контенту

Transistor остаётся источником правды, аудио продолжает раздавать он. Свой CDN не делаем. Бэкенд — про метаданные и контроль доступа.

### Premium на стороне Transistor

Премиум — на уровне эпизода. Чтобы наш бэкенд видел приватные эпизоды, нужен мастер-subscriber-token Transistor. Самат предоставит позже — до этого момента закладываем модель `is_premium` и поле в API, но реальное наполнение — отдельной маленькой подфазой 2.0.1, под фича-флагом.

### Аутентификация

На фазе 2.0 — анонимный `device_id` (UUID, выдаёт сервер при первой регистрации устройства). iOS хранит в Keychain. Полноценный логин (Sign in with Apple + email) — позже, вместе с оплатой картами.

### Что отложено

- Sign in with Apple, аккаунты, синк подписок и истории между устройствами.
- Push-уведомления (APNs).
- Apple IAP и интеграция с CloudPayments.
- Voice commentary (фича приложения, к бэкенду не относится).
- Аналитика прослушиваний — будет нужна, но не сейчас.
- Миграция пользователей из текущего Telegram-приложения — пока не думаем.
- Rate limiting — забиваем до первого инцидента.

## Конвенция по документации

В корень репо положили [`CLAUDE.md`](../../CLAUDE.md) — он фиксирует правило: каждая сессия завершается логом в `docs/sessions/`, спеки — в `docs/specs/`. AI-ассистенты подхватывают это автоматически; контрибьюторам тоже видно.

## Открытые вопросы

- Точный механизм премиум-фидов на стороне Transistor (один мастер-токен на студию или per-show) — выяснится после получения токена.
- Стратегия публикации в App Store, Apple Developer-аккаунт — на горизонте.

## Поправка по ходу сессии: платформа

Сначала закладывались на Vercel (serverless functions + Vercel Cron + Neon через marketplace). По ходу решили переехать на **Railway** — всегда-он Express проще, cron ставится отдельным сервисом из того же Dockerfile. Удалили `vercel.json`, `api/api/index.ts`, `routes/cron.ts`, переменную `CRON_SECRET`. Добавили `api/railway.json`. Всё остальное (стек, схема, эндпоинты, OpenAPI) — без изменений.

## Поправка по ходу сессии: премиум-эпизоды и секреты

Сначала премиум хотели включать отдельной подфазой 2.0.1, после получения «мастер-subscriber-token». По ходу решили реализовать сразу:

- В `.gitignore` усилили правило: `*.env` (плюс исключение `*.env.example`). Теперь `transistor.env` гарантированно не попадёт в коммит. Проверено `git check-ignore`.
- Добавлен файл `api/transistor.env.example` — шаблон с пустым `TRANSISTOR_API_KEY`. Реальный `transistor.env` Самат положит вручную; в сессии его содержимое не светится.
- `api/docker-compose.yml` подсасывает `transistor.env` через `env_file` с `required: false` — без файла всё работает, просто без премиум-эпизодов.
- В Postgres-схеме у `Podcast` появилось поле `transistor_show_id` — кэш show-id Transistor, резолвится один раз по `feed_url`.
- Новый клиент `src/transistor/api.ts` — тонкая обёртка над REST API Transistor, авторизация заголовком `x-api-key`, ключ берётся из `process.env`, нигде не логируется.
- `src/transistor/refresh.ts` теперь делает два прохода: публичный RSS (источник правды по «что считать публичным») + Transistor API (даёт всё включая subscriber-only). Эпизоды, которых нет в публичном RSS, помечаются `is_premium = true`.
- `src/lib/serialize.ts` получил `ViewerContext.hasPremiumEntitlement`. На фазе 2.0 он всегда `false` → метаданные премиум-эпизодов отдаются всем (тизер), но `audio_url` для них `null`. Когда на 2.3 появится Apple IAP, флаг будет приходить из проверки entitlements.

## Поправка по ходу сессии: pull последних изменений Ильи

К моменту завершения каркаса бэкенда на main прилетели сессии Ильи 1.5–1.10 (коммиты `b6f48b8..ea8916f`). Сделал `git pull --ff-only`, конфликтов не было. Из релевантного для бэкенда:

- В `Podcast` (Swift-модель) появились два новых поля: `description` (channel-level описание из RSS) и `lastEpisodeDate` (дата последнего выпуска — клиент по ней делит подкасты на «выходят сейчас / недавно / давно не выходят»).
- Скрипт `scripts/refresh-podcast-metadata.py` обогащает `docs/specs/podcasts-feeds.json` и `LiboLibo/Resources/podcasts.json` этими полями. Запускается раз в сутки/неделю.
- iOS-парсер `RSSParser.swift` теперь возвращает не только эпизоды, но и `PodcastChannelInfo.description`.

Чтобы бэкенд закрыл эту функциональность за клиента (после переключения iOS на API скрипт `refresh-podcast-metadata.py` станет ненужным), сделал:

1. В Prisma-схему `Podcast` добавил `lastEpisodeDate` (`last_episode_date` в БД).
2. Парсер `transistor/parser.ts` теперь возвращает `ParsedFeed = { channel: { description }, episodes }`. Channel-level description стрипает HTML — зеркально iOS-парсеру и Python-скрипту.
3. Воркер `transistor/refresh.ts` в новой функции `refreshPodcastMetadata`:
   - сохраняет `description` из RSS в `Podcast.description`, если RSS дал непустую (на 304 не затирает старое значение);
   - пересчитывает `lastEpisodeDate = max(pubDate)` по эпизодам подкаста;
   - выставляет `hasPremium = true`, если найден хоть один премиум-эпизод.
4. `serialize.ts` отдаёт `last_episode_date` в `PodcastDTO` (ISO-строка).
5. `seed.ts` забирает `lastEpisodeDate` из бандла при первичной инициализации — чтобы на холодном старте до первого refresh уже было что отдать.
6. OpenAPI-схема `Podcast` пополнилась полем `last_episode_date` (`format: date-time`, nullable).
7. Тест парсера расширен на проверку channel description.

Также переименовал лог этой сессии: `2026-04-25-08-step-2-backend-kickoff.md` → `2026-04-25-14-step-2-backend-kickoff.md`. Номер 08 занял Ильин лог 1.5; перенумеровал свой на следующий после его последнего (#13). Ссылка в `docs/specs/step-02-backend.md` обновлена.

## Локальная проверка (OrbStack)

Docker Desktop ставить не стали — поставили **OrbStack** (нативный Swift-app под macOS, drop-in совместимый с `docker`/`docker compose`, в разы быстрее на ноуте). `brew install --cask orbstack` → `docker compose up --build` → API на `localhost:3000`.

Получили `db: true`, отдельной командой засеяли 44 подкаста, прогнали refresh — публичные эпизоды + премиум через Transistor API, `audio_url: null` у премиум-эпизодов как и положено.

## Поправка по ходу: Alpine → Debian-slim в Dockerfile

Первая сборка контейнера с `node:22-alpine` упала: Prisma schema-engine не нашёл совместимую версию OpenSSL (Alpine 3 поставляется с OpenSSL 3, бандл Prisma ждёт 1.1.x). Известная проблема. Перешёл на `node:22-slim` (Debian) с явным `apt-get install openssl ca-certificates` — Prisma поднимается из коробки.

## Поправка по ходу: имя переменной в `transistor.env`

Файл `api/transistor.env` Самат создал, но содержимое имело вид `transistor-api-key=...` — POSIX-shell и docker `env_file` такое имя игнорируют (нужен `[A-Z_][A-Z0-9_]*`). Чинил через `sed -i 's/^transistor-api-key=/TRANSISTOR_API_KEY=/'` без чтения значения, плюс добавил trailing newline. Содержимое в сессии не светил.

## Развёртывание на Railway: всё через CLI + GraphQL, без дашборда

Самат авторизовался через `railway login` (browser session token) и положил рядом Project-scoped Personal Token (`railway-personal-token.env`) — он попадает под правило `*.env` в gitignore, ни в одном коммите не появится.

Через CLI и GraphQL сделал:

1. `railway add --database postgres` → плагин Postgres в проекте.
2. `serviceInstanceUpdate` через GraphQL: `rootDirectory: api`, `dockerfilePath: Dockerfile`, `startCommand: npx tsx src/server.ts`, `preDeployCommand: ["npx prisma db push --skip-generate"]`, `healthcheckPath: /v1/health`. Без этого Railway по умолчанию использует Railpack, который игнорирует наш Dockerfile.
3. `railway variable set --stdin TRANSISTOR_API_KEY` (значение перекидывал через stdin из локального файла, в логи не уезжает).
4. `railway variable set DATABASE_URL='${{Postgres.DATABASE_URL}}'` — reference на сервис плагина.
5. `railway domain --port 3000` — сгенерировался `https://libolibo-production.up.railway.app`.

Деплой собрался, healthcheck прошёл. На этой версии Dockerfile.CMD `npx tsx src/server.ts` запускает сервер в TypeScript напрямую через tsx — TS не компилируется в JS, всё держится на runtime-парсе. На Railway dev-зависимости (включая tsx) ставятся, потому что `npm ci` без `NODE_ENV=production` тянет всё.

Параллельно сделал тонкий cleanup-коммит: `tsconfig.json` → `rootDir: src`, `include: ["src/**/*"]`. Это не влияет на текущий Railway-флоу (он не запускает `npm run build`), но если в будущем кто-то запустит `npm run build`, JS попадёт в `dist/server.js` (не в `dist/src/server.js`).

## Сидинг и refresh на проде

Postgres у Railway доступен внутри контейнеров по `postgres.railway.internal:5432`, с локалки эта адресация не работает. У плагина есть `DATABASE_PUBLIC_URL` (TCP-proxy наружу) — взял его без эха через `railway variable list --service Postgres --kv | grep | cut`, подставил как `DATABASE_URL` локальному `npm run seed` и `npm run refresh`. БД на проде наполнилась 44 подкастами и 2420 эпизодами.

## cron-refresh — отдельный сервис из того же репо

Создал через `serviceCreate` GraphQL, тот же `repo: Krasilshchik3000/LiboLibo`, `branch: main`. Сконфигурировал:

- `rootDirectory: api`, `dockerfilePath: Dockerfile`
- `startCommand: npm run refresh` (= `tsx src/transistor/refresh-cli.ts`)
- `cronSchedule: */15 * * * *`
- `restartPolicyType: NEVER` (после завершения cron-задачи контейнер не перезапускается)
- те же `DATABASE_URL` (reference на Postgres) и `TRANSISTOR_API_KEY`

Первый деплой запустил через `serviceInstanceDeployV2` (CLI команда `redeploy` для нового сервиса не работает — нужен хотя бы один прошлый деплой). Затем форсировал немедленный run через `deploymentInstanceExecutionCreate(serviceInstanceId)` — прошёл успешно: `total: 44, ok: 1, notModified: 43, errors: 0, apiEnabled: true`. Дальше cron сам триггерит каждые 15 минут.

## Поправка по ходу: ревизия API-контракта от Ильи (commit `c1eea22`)

Параллельно Илья прошёлся по `openapi.yaml` против фактических iOS-моделей и нашёл расхождения по nullability:

- `Podcast.artist` был `nullable: true` в OpenAPI, но `String` (non-optional) в Swift. Добавил в `required`, описал контракт «бэкенд гарантирует строку, если в RSS пусто — `""`».
- `Episode.summary` — то же самое.
- `Episode.required` дополнен `podcast_name` и `summary` — формально отсутствовали в required.
- `Episode.audio_url` остался nullable (премиум без entitlement) — на iOS-стороне `audioUrl: URL?` + UI-тизер.

Также в спеке шага 2 явно зафиксировано, что после переключения iOS на API из клиента уйдут `RSSParser` и `PodcastsRepository.fetchFeed`, описание подкаста будет браться только из `/v1/podcasts/:id`. Подписки/история/поиск на 2.0 остаются клиентскими.

Подробно — в его сессии 15 [`docs/sessions/2026-04-25-15-api-spec-review.md`](2026-04-25-15-api-spec-review.md).

В ответ адаптировал `api/src/lib/serialize.ts`:
- `PodcastDTO.artist: string | null → string`, при сериализации `p.artist ?? ""`.
- `EpisodeDTO.summary: string | null → string`, при сериализации `e.summary ?? ""`.

Прод задеплоился автоматически после push. Проверил: на 44 подкастах и 200 эпизодах все `artist` и `summary` имеют тип `string`, ни одного `null`.

## Конфликт нумерации логов

Мой лог `2026-04-25-14-step-2-backend-kickoff.md` (этот файл) и Ильин `2026-04-25-14-step-1.11.md` оба используют номер #14. Ильин #15 ссылается на мой #14 как на «kickoff бэкенда». Решили оставить как есть: имена файлов уникальны, ссылки рабочие, перенумеровка ломала бы существующие ссылки в спеке и в его логе. На будущее — координируем номер заранее, либо договариваемся, что бэкенд и iOS используют разные диапазоны.

## Финальное состояние прода

| Что | Значение |
|---|---|
| Public domain | `https://libolibo-production.up.railway.app` |
| `LiboLibo` (web) | `Status: SUCCESS`, healthcheck `/v1/health` 200 |
| `cron-refresh` | `Status: SUCCESS`, расписание `*/15 * * * *`, `apiEnabled: true` |
| Postgres plugin | подключён через reference-переменную |
| `DATABASE_URL` | `${{Postgres.DATABASE_URL}}` на обоих сервисах |
| `TRANSISTOR_API_KEY` | стоит на обоих сервисах, в репо никогда не попадает |
| Каталог | 44 подкаста, 7 с `has_premium: true` |
| Эпизоды | 2420+ публичных, 22+ премиум-тизеров |
| Контракт типов | `artist` и `summary` всегда строки (никогда `null`) |

Шаг 2.0 закрыт. Дальше — переключение iOS на API (отдельная сессия Ильи) и подфазы 2.1+ (Sign in with Apple, синк подписок, push, IAP).

## Урок про polling Railway-деплоев

В нескольких местах писал многословные циклы вида `until s=$(railway service status ...); ... do echo "$(date) $s"; sleep 10; done` — печатают по строке каждые 10с, шумно. Заменил на тихий `until ...; do sleep 4; done` без эха тела. Деплои на Railway идут 10-30 секунд, постоянное логирование тиков избыточно.
