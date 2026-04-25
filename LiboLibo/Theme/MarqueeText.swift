import SwiftUI

/// Бегущая строка. Если текст помещается в контейнер — рендерится как обычно
/// без анимации. Если шире — плавно едет влево по бесконечному циклу с
/// дублированием контента, так что в кадре никогда не образуется «пустота»
/// между концом и началом.
///
/// Принимает готовый `Text`, чтобы вызывающий мог задать шрифт / вес / цвет
/// в одном месте и не было дублирующих параметров.
struct MarqueeText: View {
    let content: Text
    var spacing: CGFloat = 40
    /// Скорость прокрутки в точках в секунду.
    var velocity: CGFloat = 30

    @State private var textWidth: CGFloat = 0
    @State private var phase: CGFloat = 0

    var body: some View {
        // Невидимая копия в одну строку задаёт высоту блока — внешняя ширина
        // приходит от контейнера (через `.frame(maxWidth: .infinity)` сверху).
        content
            .lineLimit(1)
            .opacity(0)
            .overlay(GeometryReader { geo in
                let needsScroll = textWidth > geo.size.width + 0.5
                HStack(spacing: spacing) {
                    content
                        .fixedSize(horizontal: true, vertical: false)
                        .background(measureWidth)
                    if needsScroll {
                        content.fixedSize(horizontal: true, vertical: false)
                    }
                }
                .offset(x: needsScroll ? phase : 0)
                .frame(width: geo.size.width, alignment: .leading)
                .clipped()
                .onAppear {
                    if needsScroll { startAnimation() }
                }
                .onChange(of: needsScroll) { _, scroll in
                    if scroll { startAnimation() } else { phase = 0 }
                }
                .onChange(of: textWidth) { _, _ in
                    if textWidth > geo.size.width + 0.5 { startAnimation() }
                }
            })
    }

    private var measureWidth: some View {
        GeometryReader { textGeo in
            Color.clear
                .onAppear { textWidth = textGeo.size.width }
                .onChange(of: textGeo.size.width) { _, w in textWidth = w }
        }
    }

    private func startAnimation() {
        let distance = textWidth + spacing
        guard distance > 0 else { return }
        phase = 0
        let duration = Double(distance) / Double(velocity)
        withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
            phase = -distance
        }
    }
}
