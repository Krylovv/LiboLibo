# 2026-04-25-25 — План iOS-стороны премиум-подписки (фаза 2.3 iOS)

## Контекст

Бэкенд для премиум-подписки задеплоен (см. сессию [`2026-04-25-24-adapty-entitlement-backend.md`](2026-04-25-24-adapty-entitlement-backend.md)): таблица `entitlements`, ручки `/v1/me/entitlement[/refresh]`, middleware `resolveViewer` гейтит `audio_url` для премиум-эпизодов, `ADAPTY_SECRET_KEY` стоит в Railway Variables.

В iOS-коде уже:
- `Episode.audioUrl: URL?` опциональный, гейт по `audio_url == nil`.
- `EpisodeRow` рисует замочек при `audioUrl == nil`.
- `Episode.isPremium` приходит из API.

Не хватает: Adapty SDK, paywall, кнопок Restore / «Слушать с премиумом», заголовка `X-Adapty-Profile-Id` в `APIClient`, секции «Премиум» в `ProfileView`, welcome-paywall'а на старте.

## Что сделали в этой сессии

Чисто планировочная сессия, без кода. Через брейншторминг (skill `superpowers:brainstorming`) приняли решения по UX и архитектуре, оформили дизайн-спеку.

### Принятые решения

| Вопрос | Решение |
|---|---|
| Тип paywall | **AdaptyUI** (no-code, конфиг в дашборде Adapty) |
| Точки входа | реактивно (тап на премиум → детали → кнопка) + кнопка в «Моё» + welcome-paywall |
| Welcome-paywall | раз в 7 дней, пока нет подписки, закрываемый |
| Тап на премиум-эпизод | EpisodeDetailView → явная кнопка «Слушать с премиумом» → paywall (никакого автотриггера) |
| Скачанные премиум-эпизоды после истечения | файлы остаются на диске, гейт через `audioUrl == nil` (замочек, Play недоступен; при продлении — играют с диска) |
| Когда iOS дёргает `/refresh` | после purchase + после restore + при cold start (никаких авто-refresh из фона) |
| Restore Purchases | кнопка в `ProfileView` секции «Премиум» (плюс стандартная Restore внутри AdaptyUI paywall'а) |

### Артефакты

- **Спека:** [`docs/specs/step-2.3-premium-adapty-ios.md`](../specs/step-2.3-premium-adapty-ios.md) — архитектура `AdaptyService`, расширение `APIClient`, изменения в `LiboLiboApp` / `EpisodeDetailView` / `ProfileView`, edge cases, безопасность, шаги имплементации.

## Что НЕ делали

- Никакого iOS-кода. SPM, `AdaptyService.swift`, paywall view — всё в следующей сессии.
- Не подключали Adapty Dashboard (paywall, продукты, placement'ы) — это шаги пользователя в дашборде, не в коде.

## Что нужно от пользователя для следующей сессии

1. **Adapty Public SDK Key** (есть в `subs.env` по логу сессии 24). Нужно класть в xcconfig (в `.gitignore`) и подтягивать через `Info.plist`.
2. **`placementId`** для paywall'а в Adapty Dashboard. Один или два — welcome + episode-trigger могут быть одним.
3. **Продукт в App Store Connect** — Subscription Group + tier (например, месячная). Adapty Dashboard связывается с ним через bundle id.
4. **Sandbox-тестер** в App Store Connect.

## Следующая сессия

Реализация по спеке `step-2.3-premium-adapty-ios.md`, шаги 1–10. Pre-flight: пользователь подтверждает, что ключ + продукт + placement в дашборде есть. Дальше — SPM, `AdaptyService`, заголовок в `APIClient`, paywall view, UI, sandbox-проверка, ритуал build/install/commit/push.
