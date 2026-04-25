# Шаг 3 — Лента из Instagram

Спека на новую фичу: курируемая лента-зеркало Instagram-аккаунта Либо-Либо
внутри iOS-приложения с обогащением каждого поста CTA-кнопкой
(эпизод подкаста / подкаст / внешняя ссылка).

Связанные документы:
- [README.md](../../README.md)
- [step-02-backend.md](step-02-backend.md) — бэкенд, на который опираемся
- [api/prisma/schema.prisma](../../api/prisma/schema.prisma) — текущая БД

## 1. Цель

Дать пользователю приложения отдельную вкладку, в которой он видит «жизнь
студии» — посты-галереи и рилсы из Instagram Либо-Либо — и может одним
тапом провалиться в релевантный эпизод/подкаст или внешнюю ссылку,
если редакция эту привязку проставила.

Ключевая особенность: лента **не зеркалит Instagram автоматически**. Каждый
пост проходит ручную модерацию в веб-админке, и только подтверждённые
посты с проставленным CTA уходят в приложение.

## 2. Источник данных

Используем **официальный Instagram Graph API**. Скрейпинг запрещён
(против ToS, ломкий, репозиторий публичный).

Предусловия для интеграции (выполняются в Meta Business Suite / Facebook
Page Creator, к которому у владельца проекта есть доступ):

1. IG-аккаунт Либо-Либо переключён в Business или Creator.
2. IG-аккаунт привязан к Facebook Page студии.
3. Создано Facebook App (тип Business), добавлен продукт Instagram Graph API.
4. Получен **long-lived Page access token** (60 дней, продлевается
   автоматически до истечения через специальный endpoint).
5. Резолвится `ig-user-id` по `/{page-id}?fields=instagram_business_account`.

Используемые endpoint'ы:
- `GET /{ig-user-id}/media?fields=id,media_type,media_product_type,permalink,caption,timestamp&limit=30`
- `GET /{media-id}?fields=id,media_type,media_product_type,permalink,caption,timestamp,media_url,thumbnail_url,children{id,media_type,media_url,thumbnail_url}`

Различение типов:
- `IMAGE` → одиночная картинка.
- `CAROUSEL_ALBUM` → карусель: разворачиваем `children` (картинки и/или видео).
- `VIDEO` с `media_product_type=REELS` → рилс.
- `VIDEO` без REELS → обычный пост-видео (трактуем так же, как рилс).

Важная особенность: `media_url` для видео **истекает примерно через сутки**.
Поэтому видео нужно скачивать к себе сразу при первом обнаружении поста,
а не отдавать iOS прямую ссылку.

## 3. Архитектура

```
Instagram Graph API
        │
        │  cron, каждые 30 мин
        ▼
┌──────────────────────────┐
│ instagram/collector      │  пишет новые посты со статусом PENDING
└──────────────────────────┘
        │
        ▼  событие "новый пост"
┌──────────────────────────┐
│ instagram/media-         │  качает .jpg/.mp4 + thumbnail на Railway volume
│ downloader               │
└──────────────────────────┘
        │
        ▼  файлы доступны
┌──────────────────────────┐
│ admin/  (web UI)         │  модератор подтверждает + проставляет CTA
└──────────────────────────┘
        │
        ▼  status=PUBLISHED
┌──────────────────────────┐
│ /v1/feed/instagram       │  публичный REST для iOS
└──────────────────────────┘
        │
        ▼
┌──────────────────────────┐
│ iOS InstagramFeedView    │  вертикальная лента карточек с CTA
└──────────────────────────┘
```

## 4. Бэкенд (api/)

### 4.1. Модули

Все новые модули — внутри существующего api/src.

| Модуль | Назначение |
|---|---|
| `src/instagram/graph-client.ts` | Тонкий клиент Graph API (fetch + ретраи + парсинг ошибок). Чистая функция, легко тестируется. |
| `src/instagram/collector.ts` | Синк постов: тянет последние 30, апсертит в БД. Точка входа — `syncInstagramPosts()`. |
| `src/instagram/media-downloader.ts` | Скачивание медиа по `InstagramPost.id` в `MEDIA_DIR/{postId}/{order}.{ext}` + генерация thumbnail из видео через `ffmpeg`. |
| `src/instagram/refresh-cli.ts` | CLI-обёртка для Railway Cron, по аналогии с `transistor/refresh-cli.ts`. |
| `src/admin/server.ts` | Express-роутер, монтируется в `app.ts` под префиксом `/admin`. HTTP Basic Auth middleware. |
| `src/admin/views/*.ejs` | Шаблоны: список постов, карточка модерации. |
| `src/routes/feed-instagram.ts` | Публичный endpoint `GET /v1/feed/instagram`. |
| `src/routes/media.ts` | Раздача файлов из `MEDIA_DIR` через `express.static` с длинным Cache-Control. |

### 4.2. Prisma-схема (расширение)

В соответствии со стилем существующей схемы: `snake_case` в БД, `camelCase` в коде.

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

`Episode` и `Podcast` получают обратные отношения `instagramPosts InstagramPost[]`.

### 4.3. Collector — поведение

Запуск: Railway Cron каждые 30 минут (отдельный cron-job в `railway.json`,
по аналогии с существующим transistor refresh).

Алгоритм:
1. Получить токен и ig-user-id из env.
2. Запросить последние 30 медиа.
3. Для каждого медиа из ответа:
   - Если `igMediaId` уже в БД — обновить `caption`, `igPermalink`, `updatedAt`. Не трогать `status`, `cta*`.
   - Если новый — создать запись `status=PENDING`. **`InstagramMedia`-записи на этом этапе НЕ создаются** — они появятся уже в downloader'е (Фаза B) вместе с реально скачанным файлом. Это снимает проблему истекающих `media_url` между этапами.
4. После транзакции downloader (Фаза B) сам подхватит посты, у которых ещё нет `InstagramMedia`.

Идемпотентность: коллектор можно запускать сколько угодно раз без побочных эффектов.

Удалённый в IG пост: коллектор это обнаруживает только если пост вышел за окно последних 30. Намеренно ничего не делаем — на MVP не критично, обработать можно вручную через админку (статус HIDDEN).

### 4.4. Media-downloader — поведение

Запускается отдельным шагом после коллектора (или из админки на случай повторной попытки).
Поведение:
1. Найти все `InstagramPost`-ы, у которых ещё нет связанных `InstagramMedia` записей.
2. Для каждого такого поста заново запросить у Graph API свежие `media_url` (для каруселей — `children{...}`). Это даёт нам не-истёкшие URL.
3. Скачать каждый файл в `MEDIA_DIR/{postId}/{order}.{jpg|mp4}`.
4. Для видео: через `ffmpeg` сгенерировать thumbnail (первый кадр) в `MEDIA_DIR/{postId}/{order}.thumb.jpg`. Извлечь `width`, `height`, `durationSec` из `ffprobe`.
5. Для картинок: получить `width/height` из самих файлов (например, через `image-size`).
6. Создать `InstagramMedia`-записи в одной транзакции с заполненными `filePath`.

`ffmpeg` ставится в Dockerfile (`apt-get install -y ffmpeg`).

`MEDIA_DIR` — env, по умолчанию `/data/media` (Railway volume). Локально в docker-compose — bind-mount.

### 4.5. Веб-админка `/admin`

Server-rendered HTML, EJS-шаблоны. **SPA не нужен.**

Защита: HTTP Basic Auth middleware. Креды в env: `ADMIN_USER`, `ADMIN_PASSWORD`. Single-user сценарий — этого достаточно на старте; полноценный auth откладываем.

Страницы:

- `GET /admin` → редирект на `/admin/posts?status=pending`.
- `GET /admin/posts?status=&page=` → список карточек: миниатюра первого медиа, обрезанный caption, дата, текущий статус и CTA (если есть). Фильтр по статусу: pending / published / hidden / all.
- `GET /admin/posts/:id` → карточка модерации:
  - Превью всех медиа (для каруселей — горизонтальная прокрутка; для видео — `<video controls>`).
  - Caption (read-only) + ссылка на оригинал в IG.
  - Форма CTA: radio (none / episode / podcast / link).
    - episode → `<select>` с поиском по локальным эпизодам (server-side фильтр по подстроке title; на MVP — простой `<select>` с группировкой по подкастам).
    - podcast → `<select>` с подкастами.
    - link → два поля: URL + label.
  - Кнопки: «Опубликовать», «Скрыть», «Сохранить черновик», «Перекачать медиа» (на случай битых файлов).
- `POST /admin/posts/:id` → обработка формы. Валидация: при `status=PUBLISHED` обязателен один из CTA либо явный «без CTA» (опция none).

Стиль — минимальный CSS, читабельный с десктопа. Мобильная адаптация не приоритет (модерация с десктопа).

### 4.6. Публичный API

```
GET /v1/feed/instagram?cursor=<base64-cursor>&limit=20
```

- Возвращает только посты со `status=PUBLISHED`, отсортированные по `publishedAt DESC`.
- `cursor` кодирует `(publishedAt, id)` последнего элемента предыдущей страницы.
- `limit` — 1..50, по умолчанию 20.

Формат ответа:

```json
{
  "items": [
    {
      "id": "uuid",
      "type": "image|carousel|video",
      "permalink": "https://www.instagram.com/p/...",
      "caption": "...",
      "publishedAt": "2026-04-25T10:00:00Z",
      "media": [
        { "kind": "image", "url": "https://api.../media/<postId>/0.jpg", "width": 1080, "height": 1350 },
        { "kind": "video", "url": "https://api.../media/<postId>/1.mp4", "thumbnailUrl": "https://api.../media/<postId>/1.thumb.jpg", "width": 1080, "height": 1920, "durationSec": 23 }
      ],
      "cta": {
        "type": "episode|podcast|link",
        "label": "Слушать эпизод",
        "url": "https://www.libolibo.ru/...",
        "episode": { "id": "...", "title": "...", "podcastId": "..." },
        "podcast": { "id": "...", "name": "..." }
      }
    }
  ],
  "nextCursor": "<base64-cursor-or-null>"
}
```

Поля `episode`/`podcast` в `cta` присутствуют только если CTA соответствующего типа. Поле `cta` может быть `null` (если редакция явно опубликовала без CTA).

### 4.7. Раздача медиа

`GET /media/{postId}/{file}` → `express.static(MEDIA_DIR)` с
`Cache-Control: public, max-age=31536000, immutable`. Имена файлов
неизменяемы (post-id + order), поэтому agressive-кеш безопасен.

### 4.8. Безопасность

- IG-токен (`META_ACCESS_TOKEN`), `META_IG_USER_ID`, `ADMIN_USER`,
  `ADMIN_PASSWORD` — только Railway Variables. В репо — `transistor.env.example` дополняется аналогом `instagram.env.example`.
- Публичный API не отдаёт `pending`/`hidden` посты.
- Админка под HTTP Basic Auth, по HTTPS (Railway включает по умолчанию).

### 4.9. Тесты (vitest)

- `graph-client` — мокаем `fetch`, проверяем формирование URL, парсинг ошибок Meta.
- `collector` — с in-memory mock БД (или test Postgres из docker-compose): идемпотентность, апсерт по `igMediaId`, обработка карусели.
- `feed-instagram` route — фикстура из 5 постов, проверка курсорной пагинации и фильтра по статусу.
- Админка — happy-path E2E через supertest: POST с валидной формой меняет статус.

## 5. iOS

### 5.1. Структура

```
LiboLibo/
  Features/
    InstagramFeed/
      InstagramFeedView.swift
      InstagramPostCard.swift
      InstagramMediaPager.swift
      InstagramVideoPlayer.swift
  Models/
    InstagramPost.swift          // + InstagramMedia, InstagramCta enum
  Services/
    InstagramFeedService.swift   // @Observable, как PodcastsRepository
```

### 5.2. Tab-bar

В `RootView.SelectedTab` добавляется кейс `.instagram`. В `modernTabs` —
пятая вкладка:

```swift
Tab("Лента", systemImage: "square.grid.3x3", value: .instagram) {
    InstagramFeedView()
}
```

Имя «Лента» сознательно отличается от «Фид» — фид это лента эпизодов,
лента — соцсеть. Если возникнет двусмысленность в UX-тестировании,
переименуем в «Студия».

### 5.3. Карточка поста

- Сверху — медиа-зона:
  - `IMAGE` → `AsyncImage` с placeholder'ом (skeleton).
  - `CAROUSEL` → `TabView(selection:) .tabViewStyle(.page)` с индикатором страниц.
  - `VIDEO` → собственный обёртчик `InstagramVideoPlayer` поверх `AVPlayerLayer`/`VideoPlayer`. Автоплей при попадании в viewport (через `onAppear`/`onDisappear` на `.onScrollVisibilityChange` где доступно), mute по умолчанию, тап-toggle unmute, лупом.
  - Соотношение сторон — по `width/height` первого медиа, max 4:5 (как в IG).
- Под медиа — caption, max 2 строки + «ещё», по тапу разворачивается.
- Под caption — кнопка-CTA (если `cta != null`):
  - episode → `liboRed`-стиль, label «Слушать: <title>».
  - podcast → outline-стиль, label «Подкаст: <name>».
  - link → нейтральный, label из `cta.label`.
- Внизу — мелкая ссылка-иконка «Открыть в Instagram» (`permalink`).

### 5.4. Навигация по CTA

- `episode` → push `EpisodeDetailView(episode:)`. Эпизод подгружается из `PodcastsRepository` по id; если его там ещё нет — вызывается single-fetch по id (новый метод на репозитории).
- `podcast` → push `PodcastDetailView(podcast:)` аналогично.
- `link` → системный `openURL`.

### 5.5. Сервис

`InstagramFeedService` — `@Observable`, в `App/LiboLiboApp.swift`
прокидывается в environment, как остальные сервисы:

```swift
@Observable
final class InstagramFeedService {
    var posts: [InstagramPost] = []
    var isLoading = false
    var loadError: String?
    private(set) var nextCursor: String?

    func loadFirstPage() async { ... }
    func loadMore() async { ... }
    func refresh() async { ... }
}
```

Использует существующий `APIClient` (он уже в untracked-изменениях рабочего дерева; если его публичная форма ещё не утверждена — InstagramFeedService может ходить через свой `URLSession` и потом мигрировать).

### 5.6. UX-детали

- Pull-to-refresh.
- Бесконечная пагинация: при показе предпоследней карточки — `loadMore()`.
- Empty state: иконка + «Здесь пока ничего нет».
- Error state: `ContentUnavailableView` с кнопкой «Повторить».
- Видеоплеер — один активный одновременно (звук/декод): при скролле
  предыдущий ставится на паузу, следующий начинает играть.

## 6. Декомпозиция на фазы

Один общий план реализации, разбитый на 4 фазы. Каждая фаза — отдельный
коммит-набор и отдельный «зелёный» билд/тесты.

| Фаза | Что входит | Артефакты |
|---|---|---|
| **A. Backend infra** | Prisma-миграция, IgPostType/IgStatus enums, graph-client, collector + cron, env-схема | Новая таблица в БД на Railway, cron работает, посты видны в БД через `psql` |
| **B. Media pipeline** | Media-downloader, ffmpeg в Dockerfile, статик-раздача `/media`, тесты на downloader | По `https://api/media/.../0.jpg` отдаётся файл |
| **C. Admin + public API** | EJS-шаблоны, Basic Auth, форма CTA, `/v1/feed/instagram` | Можно зайти на `/admin`, опубликовать пост, увидеть его в JSON `/v1/feed/instagram` |
| **D. iOS** | Модели, InstagramFeedService, View, карточка, видеоплеер, новая вкладка, навигация по CTA | На симуляторе видна вкладка «Лента» с карточками; CTA работают |

## 7. Открытые вопросы (на момент написания спеки)

- **Stories.** В скоупе — только feed (посты + рилсы). Stories Graph API даёт ограниченно и они быстро истекают; на MVP не делаем.
- **Лимиты API.** Meta даёт 200 запросов/час на пользователя. Раз в 30 мин по 1–2 запроса — в пределах, но если приложение начнёт активно гонять fetch для деталей — стоит ввести бюджет.
- **Время хранения видео.** Старые видео могут расти без ограничений. На MVP — без вычистки. Когда упрёмся в место на volume — добавить retention policy (например, удалять файлы постов со `status=HIDDEN` старше 90 дней).
- **Имя вкладки.** «Лента» vs «Студия» — решаем после прохода на пользователе.

## 8. Что прямо НЕ входит в этот шаг

- Stories.
- Автоматическое распознавание CTA (привязка по тексту caption).
- Полноценная админка с ролями/SSO.
- Push-уведомления о новых постах.
- Лайки/комментарии/шаринг внутри приложения.
- Скрейпинг или обходные пути на случай блокировки Graph API.
