# Spec: Шаг 1 — iOS-каркас приложения

**Статус:** в работе. Текущая фаза — 1.0.
**Базовое ТЗ:** [docs/sessions/2026-04-25-kickoff.md](../sessions/2026-04-25-kickoff.md). Поправки: [docs/sessions/2026-04-25-02-corrections.md](../sessions/2026-04-25-02-corrections.md).
**Owner:** Илья (направляет), Claude (кодит).

## Цель шага 1

Поднять iOS-каркас на SwiftUI: запускается в симуляторе, навигация работает, реальные подкасты Либо-Либо тянутся по RSS, плеер играет выпуск с базовыми контролами. «Сырой работающий MVP» (директива Егора).

## Декомпозиция на фазы

| Фаза | Что делаем | Definition of Done |
|---|---|---|
| **1.0** | Пустое приложение, три вкладки (Фид / Подкасты / Моё) | Запускается в симуляторе, тапы по таб-бару переключают экраны, на каждом — заглушка. |
| 1.1 | Моки на «Фиде» | Список из 5 фейковых выпусков. |
| 1.2 | Реальный RSS на «Фиде» | Настоящие выпуски одного подкаста. |
| 1.3 | Тап → плеер играет звук | Тап по выпуску запускает аудио. |
| 1.4 | Мини-плеер + контролы | Снизу мини-плеер, разворачивается, play/pause/±10s/скорость. |
| 1.5 | Background audio + lock screen | Свернул приложение — играет; на lock screen — контролы. |
| 1.6 | «Подкасты»: сетка | Видны все 44 подкаста с обложками. |
| 1.7 | Подписки локально | SwiftData; состояние подписки сохраняется. |
| 1.8 | «Моё»: подписки + история | Профиль показывает подписки и историю. |
| 1.9 | Polish | Liquid glass, dark mode, dynamic type. |

Каждая фаза — отдельный коммит и [session log](../sessions/).

## Стартовые параметры (зафиксированы)

- **Стек:** Swift 5.10+, SwiftUI, AVFoundation, SwiftData, URLSession.
- **Минимальный iOS:** 18.0 (для liquid glass и `@Observable`).
- **Bundle ID:** `me.libolibo.app`.
- **Display name:** «Либо-Либо».
- **Источник данных:** [`docs/specs/podcasts-feeds.json`](podcasts-feeds.json) — 44 фида студии libo/libo.
- **Шрифт:** временно — системный San Francisco. Финальный выбор (Gerbera vs OFL-альтернативы вроде Golos / Onest) обсуждается, см. [сессию 02](../sessions/2026-04-25-02-corrections.md). Переключение — в одной точке (`Theme.swift` появится на 1.1+).
- **Сборка проекта:** через [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`project.yml` в репо, `.xcodeproj` генерируется командой и в репо НЕ коммитится — diff'ы Xcode-проектов нечитаемы).

## Структура репозитория после шага 1.0

```
LiboLibo/
├── project.yml               # XcodeGen-описание проекта (источник правды)
├── LiboLibo/
│   ├── App/
│   │   ├── LiboLiboApp.swift # @main entry point
│   │   └── RootView.swift    # TabView с тремя вкладками
│   ├── Features/
│   │   ├── Feed/FeedView.swift
│   │   ├── Podcasts/PodcastsView.swift
│   │   └── Profile/ProfileView.swift
│   └── Resources/
│       ├── Assets.xcassets   # AppIcon (заглушка), AccentColor
│       └── Info.plist        # генерируется XcodeGen
└── (LiboLibo.xcodeproj — генерируется, не в git)
```

## Билд и запуск (для участников)

```bash
brew install xcodegen          # один раз
xcodegen generate              # создаёт LiboLibo.xcodeproj
open LiboLibo.xcodeproj        # → Xcode → Run (Cmd+R)
```

Альтернатива без UI:

```bash
xcodebuild -scheme LiboLibo -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' build
```

## Что НЕ делаем на фазе 1.0

- Никаких реальных данных — даже моков (моки придут на 1.1).
- Никакого плеера, AVFoundation не подключаем (1.3).
- Никакого SwiftData (1.7).
- Без иконки приложения — placeholder Apple.
- Без брендинга, без шрифта, без анимаций.

## DoD фазы 1.0

- [ ] `project.yml` описывает iOS-приложение, минимальный таргет iOS 18.
- [ ] `xcodegen generate` создаёт работоспособный `.xcodeproj` без ошибок.
- [ ] `xcodebuild ... build` успешно собирает для симулятора.
- [ ] При запуске приложение открывается, видна нижняя панель с тремя вкладками: «Фид», «Подкасты», «Моё». Тапы переключают вкладки. На каждой — `ContentUnavailableView` с подписью «здесь будет ...».
- [ ] Коммит запушен; на GitHub проверено, что секретов не утекло.
- [ ] Сессия задокументирована в `docs/sessions/2026-04-25-NN-step-1.0.md`.

---

## План действий (фаза 1.0)

Конкретные шаги, которые выполняю прямо сейчас:

1. **Проверить инструменты.** `xcodegen --version` и `xcodebuild -version`. Если xcodegen не установлен — `brew install xcodegen`. Если Xcode не стоит или только Command Line Tools — стоп, информирую Илью.
2. **Создать `project.yml`** в корне репо: имя `LiboLibo`, bundle id `me.libolibo.app`, display name «Либо-Либо», deployment target iOS 18, single-target SwiftUI app.
3. **Создать структуру директорий** под `LiboLibo/`: `App/`, `Features/{Feed,Podcasts,Profile}/`, `Resources/`.
4. **Написать минимальные Swift-файлы:**
   - `LiboLiboApp.swift` — `@main`, объявление сцены.
   - `RootView.swift` — `TabView` с тремя экранами и SF-иконками (`list.dash`, `rectangle.grid.2x2`, `person.crop.circle`).
   - `FeedView.swift`, `PodcastsView.swift`, `ProfileView.swift` — каждый с `NavigationStack` + `ContentUnavailableView` («здесь будет ...»).
5. **Создать минимальные `Assets.xcassets`** — пустой `AppIcon.appiconset` и дефолтный `AccentColor.colorset`.
6. **Сгенерировать проект** командой `xcodegen generate`.
7. **Собрать через xcodebuild** для симулятора. Если ошибки — фиксить, не идти дальше.
8. **Обновить `.gitignore`:** добавить `*.xcodeproj/` (генерируется).
9. **Обновить `README.md`** в корне — секция «Билд и запуск» с командами выше.
10. **Сканировать staging на секреты** перед коммитом.
11. **Закоммитить** одним коммитом (скаффолд + README + .gitignore + session log).
12. **Запушить.** Убедиться, что на GitHub все файлы на месте и `.xcodeproj` НЕ попал в push.
13. **Записать session log** `docs/sessions/2026-04-25-03-step-1.0.md`: что сделано, как запустить, скриншот при возможности, ссылка на коммит.

После выполнения этого плана: открываешь `LiboLibo.xcodeproj` в Xcode, нажимаешь Run, видишь пустое приложение с тремя вкладками. Дальше — фаза 1.1.
