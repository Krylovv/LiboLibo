import SwiftUI

struct PlayerView: View {
    @Environment(PlayerService.self) private var player
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let episode = player.currentEpisode {
            ZStack {
                // Размытый артворк как фон — даёт правильный амбиент-цвет
                // и контраст под белый/чёрный текст в зависимости от обложки.
                AsyncImage(url: episode.podcastArtworkUrl) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill().blur(radius: 80, opaque: true)
                    default:
                        Color.gray.opacity(0.1)
                    }
                }
                .ignoresSafeArea()

                // Лёгкое затемнение для читаемости текста на любой обложке.
                Color.black.opacity(0.25).ignoresSafeArea()

                VStack(spacing: 28) {
                    AsyncImage(url: episode.podcastArtworkUrl) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fill)
                        default:
                            Color.secondary.opacity(0.15)
                        }
                    }
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
                    .padding(.horizontal, 32)
                    .padding(.top, 24)

                    VStack(spacing: 8) {
                        Text(episode.podcastName)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1)
                        Text(episode.title)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                    }
                    .padding(.horizontal, 24)

                    ProgressSlider()
                        .padding(.horizontal, 24)

                    HStack(spacing: 44) {
                        ControlButton(systemImage: "gobackward.10", size: 32) {
                            player.skip(by: -10)
                        }

                        Button {
                            player.togglePlayPause()
                        } label: {
                            Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 72))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)

                        ControlButton(systemImage: "goforward.10", size: 32) {
                            player.skip(by: 10)
                        }
                    }
                    .padding(.top, 4)

                    HStack(spacing: 12) {
                        PillButton(
                            icon: "speedometer",
                            text: PlayerService.formatRate(player.rate),
                            isHighlighted: player.rate != 1.0
                        ) {
                            player.cycleSpeed()
                        }

                        PillButton(
                            icon: "moon.zzz",
                            text: player.sleepTimer.label,
                            isHighlighted: player.sleepTimer.isActive
                        ) {
                            player.cycleSleepTimer()
                        }
                    }

                    Spacer()
                }
                .padding(.bottom, 24)
            }
            .preferredColorScheme(.dark)
        }
    }
}

// MARK: - Components

private struct ControlButton: View {
    let systemImage: String
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size))
                .foregroundStyle(.white)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct PillButton: View {
    let icon: String
    let text: String
    let isHighlighted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(text)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(
                Capsule()
                    .fill(isHighlighted ? Color.liboRed.opacity(0.85) : Color.white.opacity(0.18))
            )
            .foregroundStyle(.white)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct ProgressSlider: View {
    @Environment(PlayerService.self) private var player
    @State private var draggedValue: Double?

    var body: some View {
        VStack(spacing: 6) {
            Slider(
                value: Binding(
                    get: {
                        if let dv = draggedValue { return dv }
                        return player.duration > 0 ? player.currentTime / player.duration : 0
                    },
                    set: { newValue in
                        draggedValue = newValue
                    }
                ),
                in: 0...1,
                onEditingChanged: { editing in
                    if !editing, let dv = draggedValue, player.duration > 0 {
                        player.seek(to: dv * player.duration)
                        draggedValue = nil
                    }
                }
            )
            .tint(.white)

            HStack {
                Text(PlayerService.formatTime(player.currentTime))
                Spacer()
                Text(PlayerService.formatTime(max(0, player.duration - player.currentTime)))
            }
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.7))
        }
    }
}
