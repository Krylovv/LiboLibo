# Шаг 2.3 (iOS) — Подписка через Adapty: клиентская сторона

**Статус:** план, реализация в следующей сессии.
**Зависит от:** [`step-2.3-premium-adapty.md`](step-2.3-premium-adapty.md) (бэкенд готов и задеплоен).
**Связанные сессии:** [`2026-04-25-24-adapty-entitlement-backend.md`](../sessions/2026-04-25-24-adapty-entitlement-backend.md), [`2026-04-25-25-ios-subscription-plan.md`](../sessions/2026-04-25-25-ios-subscription-plan.md).

## Задача

Добавить премиум-подписку в iOS-приложение «Либо-Либо». Без логина: идентификатор зрителя — `adapty_profile_id` (UUID), который Adapty SDK создаёт сам и переживает переустановку через App Store receipt. Бэкенд по этому id решает, отдавать ли `audio_url` для премиум-эпизодов.

## Решения

| Вопрос | Решение |
|---|---|
| Тип paywall | AdaptyUI (no-code, конфигурируется в дашборде Adapty) |
| Точки входа | (1) тап на премиум-эпизод → EpisodeDetail → кнопка «Слушать с премиумом», (2) кнопка «Оформить» в `ProfileView`, (3) welcome-paywall на старте |
| Welcome-paywall | Раз в 7 дней, пока нет активной подписки. Закрываемый. Дата хранится в `UserDefaults`. |
| Тап на премиум-эпизод | Ведёт на `EpisodeDetailView`, оттуда явная кнопка → paywall. Никакого автотриггера. |
| Скачанные премиум-эпизоды после истечения | Файлы остаются на диске. UI показывает замочек. Тап на Play → paywall. (При продлении — играют с диска, заново качать не нужно.) |
| `POST /v1/me/entitlement/refresh` | Триггеры: (a) после `Adapty.makePurchase` success, (b) после `Adapty.restorePurchases` success, (c) при cold start приложения. Никаких авто-refresh из фона. |
| Restore Purchases | Кнопка в `ProfileView` секция «Премиум» («Восстановить покупки»). Дублирует кнопку Restore внутри AdaptyUI paywall'а. |
| Метка «премиум» в `EpisodeRow` для подписчиков | Не показывается. Подписчику премиум-эпизод визуально равен обычному. Замочек — только когда `audioUrl == nil`. |

## Архитектура

### Новый сервис `AdaptyService`

`@Observable` класс на главном акторе. Composition root — `LiboLiboApp.swift`, добавляется к остальным `@State`-сервисам и прокидывается через `.environment(...)`.

**Публичное состояние:**
```swift
@Observable
final class AdaptyService {
    var profileId: UUID? // выдаёт Adapty SDK после activate
    var isPremium: Bool = false
    var expiresAt: Date? = nil
    var lastRefreshAt: Date? = nil
}
```

**Методы:**
- `activate() async` — `Adapty.activate(with: ADAPTY_PUBLIC_SDK_KEY)` + получение `profileId`.
- `refreshEntitlement() async` — `APIClient.refreshEntitlement()`, обновляет `isPremium`/`expiresAt`/`lastRefreshAt`. Состояние пишется в `UserDefaults` для сохранения между запусками.
- `restorePurchases() async throws -> RestoreOutcome` — `Adapty.restorePurchases()` → `refreshEntitlement()`. `RestoreOutcome = .restored | .nothingToRestore | .failed(Error)`.
- `presentPaywall(placementId:) async` — открывает AdaptyUI paywall. После success → `refreshEntitlement()` + `repository.reload()`.

**Источник истины для `isPremium`** — ответ бэка на `/v1/me/entitlement/refresh`. Adapty SDK на клиенте используется только для (1) идентификации (`profileId`), (2) проведения покупки/restore через StoreKit, (3) рендера paywall'а. Решение «есть ли у юзера премиум» — всегда от сервера.

### Расширение `APIClient`

```swift
init(
    baseURL: URL = APIClient.defaultBaseURL,
    session: URLSession = .shared,
    profileIdProvider: @escaping () -> UUID? = { nil }
)
```

В `get(...)` — если `profileIdProvider()` вернул UUID, добавляется заголовок `X-Adapty-Profile-Id: <uuid>` к запросу.

Новые методы:
```swift
func refreshEntitlement() async throws -> EntitlementDTO   // POST /me/entitlement/refresh
func fetchEntitlement() async throws -> EntitlementDTO     // GET /me/entitlement (опц., для дебага)
```

`EntitlementDTO`:
```swift
struct EntitlementDTO: Decodable {
    let isPremium: Bool
    let expiresAt: Date?
    let checkedAt: Date?
}
```

### Расширение `PodcastsRepository`

После каждого изменения `isPremium` (смена `false→true` или `true→false`) — `repository.reload()` (рефреш фида и эпизодов). Без этого UI продолжит видеть старые `audioUrl: null` или наоборот.

### `DownloadService` и `PlayerService`

Не меняются. Файлы премиум-эпизодов остаются на диске независимо от состояния подписки. Гейт воспроизведения — через `episode.audioUrl == nil` (уже работает).

## UI-изменения

### `LiboLiboApp.swift`

```swift
@State private var adapty = AdaptyService()
@State private var showsWelcomePaywall = false
```

В `.onAppear`:
1. `await adapty.activate()`
2. `await adapty.refreshEntitlement()`
3. Если `isPremium` изменился по сравнению с прошлым запуском — `repository.reload()`.
4. Если `!isPremium && lastWelcomeShown > 7 days ago` — `showsWelcomePaywall = true`.

В `.sheet(isPresented: $showsWelcomePaywall)` — `AdaptyPaywallView(placementId: "welcome")`.

### Новый `Features/Subscription/AdaptyPaywallView.swift`

`UIViewControllerRepresentable` обёртка над AdaptyUI paywall. Принимает `placementId: String`, колбэки `onPurchase`/`onRestore`/`onClose`. Используется и для welcome, и для triggers из EpisodeDetail, и для ProfileView.

### `EpisodeDetailView`

Для эпизода с `isPremium == true && audioUrl == nil`:
- Place кнопки Play занимает большая кнопка «Слушать с премиумом» (`.liboRed`, иконка `lock.fill`). 
- Тап → `.sheet` с `AdaptyPaywallView(placementId: "episode-trigger")`.
- Описание эпизода показывается полностью.

### `ProfileView`

Новая секция сверху списка, выше «Подписки»:

**Если `adapty.isPremium == true`:**
- Заголовок: «Премиум активен»
- Подзаголовок: «до 25 апреля 2027» (формат `expiresAt`)
- Кнопка-ссылка: «Управлять подпиской» → `https://apps.apple.com/account/subscriptions`

**Если `false`:**
- Заголовок: «Премиум-подписка»
- Подзаголовок: «Бонусные и эксклюзивные выпуски»
- Кнопка `.borderedProminent`: «Оформить» → `.sheet` с `AdaptyPaywallView(placementId: "profile-cta")`
- Кнопка `.bordered`/text: «Восстановить покупки» → `adapty.restorePurchases()` + alert по результату

### `EpisodeRow`

Без изменений. Замочек уже работает по `audioUrl == nil`.

## Edge cases

| Сценарий | Поведение |
|---|---|
| Adapty SDK не активировался (сеть, ключ) | `profileId == nil`, заголовок не отправляется, viewer на бэке анонимный, премиум-эпизоды с замочком. UI остальное работает. На следующем старте — повтор. |
| `/refresh` вернул 503 | iOS оставляет последний известный `isPremium` (или `false`, если первый запуск). Не блокирующе. |
| Сетевая ошибка на cold-start refresh | Используем закэшированные `isPremium`/`expiresAt` из `UserDefaults`. Бэк гейтит `audio_url` независимо, поэтому никакого security-риска. |
| Sandbox-подписка истекла | На следующем `refresh` → `isPremium: false` → UI обновляется → файлы скачанных эпизодов остаются на диске, но Play недоступен (замочек). |
| Юзер переустановил приложение | `profileId` Adapty SDK восстановит через App Store receipt. Восстановление подписки — через кнопку «Восстановить покупки» в `ProfileView`. |
| Юзер продлил подписку через App Store вне приложения | Узнаем при следующем cold start, когда iOS дёрнет `refresh`. Webhook от Adapty в этой фазе не подключён. |

## Безопасность

- `ADAPTY_PUBLIC_SDK_KEY` — в xcconfig'е, который НЕ чекинится в репо. Доступ через `Info.plist` → `Bundle.main.object(forInfoDictionaryKey:)`.
- `profileId` хранится Adapty SDK в Keychain, мы сами никаких секретов не пишем.
- iOS не отправляет на бэк собственное мнение об `isPremium` — только `profileId`.
- Локальный `isPremium` на iOS влияет только на UI; бэк независимо гейтит `audio_url`. Поэтому подделка локального состояния (jailbreak и т.д.) не даёт доступ к контенту.

## Шаги имплементации

1. **SPM-зависимости:** `Adapty` + `AdaptyUI` (одна репа `adapty-iOS`).
2. **`xcconfig`** для `ADAPTY_PUBLIC_SDK_KEY`. Файл — в `.gitignore`. Шаблон — в `LiboLibo/Resources/Config.example.xcconfig` (без значения).
3. **`Services/AdaptyService.swift`** — `@Observable`, описанный выше.
4. **`APIClient`** — рефакторинг конструктора, заголовок, новые методы `refreshEntitlement`/`fetchEntitlement`.
5. **`Features/Subscription/AdaptyPaywallView.swift`** — `UIViewControllerRepresentable` обёртка.
6. **`LiboLiboApp.swift`** — wiring `AdaptyService`, welcome-paywall sheet, проверка `welcomePaywallLastShownAt`.
7. **`EpisodeDetailView`** — кнопка «Слушать с премиумом» + paywall sheet.
8. **`ProfileView`** — секция «Премиум» + Restore + alert'ы.
9. **Sandbox-проверка:** купить → `audio_url` приходит → Play играет → подписка истекает → замочки возвращаются → restore на свежей установке.
10. **Ритуал завершения:** `xcodebuild` → install → commit → push (по `CLAUDE.md`).

## Что нужно от пользователя

1. **Adapty Public SDK Key** (есть в `subs.env` по логу сессии 24).
2. **`placementId`** для paywall'а после создания paywall в Adapty Dashboard. Один или два (welcome + triggers могут быть одним placement'ом).
3. **Продукт в App Store Connect** — Subscription Group + хотя бы один tier.
4. **Sandbox-тестер** в App Store Connect.

## Открытые вопросы (после реализации)

- Текст на welcome-paywall'е и paywall'е из EpisodeDetail — пишется в Adapty Dashboard, не в коде. Согласовать копирайт перед запуском.
- Имя продукта/подписки и цена — решение бизнеса.
- Webhook от Adapty (`subscription_renewed`, `expired`) — пока не подключаем (см. бэкенд-спеку). Если конверсия и retention покажут, что 7-дневное «протухание» статуса между cold-start refresh'ами вредит UX — добавим в фазу 2.3.1.
