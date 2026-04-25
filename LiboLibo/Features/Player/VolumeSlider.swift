import SwiftUI
import MediaPlayer

/// Системный регулятор громкости. На iOS — это `MPVolumeView`, обёрнутая в SwiftUI.
/// Apple не позволяет менять системную громкость программно мимо `MPVolumeView`,
/// поэтому используем её и не пытаемся рисовать кастом.
struct SystemVolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: .zero)
        view.showsRouteButton = false
        view.tintColor = .white
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}
