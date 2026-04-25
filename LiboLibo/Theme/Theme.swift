import SwiftUI

/// Дизайн-токены приложения Либо-Либо.
/// Шрифты — системные San Francisco через `Font.subheadline / .headline / ...` с встроенным
/// Dynamic Type. Никаких кастомных шрифтов: следуем Apple HIG.
enum Theme {
    /// Брендовый красный со страницы libolibo.me — #FF3D3D.
    /// Используется как акцент навигации (выбранный таб, NavigationLink, кнопки действия,
    /// прогресс плеера, активные индикаторы).
    static let red = Color(red: 1.0, green: 61.0/255.0, blue: 61.0/255.0)
}

extension Color {
    /// `Color.liboRed` — брендовый красный.
    static let liboRed = Theme.red
}

extension ShapeStyle where Self == Color {
    /// Сахар для `.foregroundStyle(.liboRed)`, `.tint(.liboRed)`.
    static var liboRed: Color { Theme.red }
}
