import SwiftUI

struct PlayerView: View {
    @Environment(PlayerService.self) private var player
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let episode = player.currentEpisode {
            VStack(spacing: 24) {
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
                .padding(.horizontal, 32)
                .padding(.top, 24)

                VStack(spacing: 6) {
                    Text(episode.podcastName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(episode.title)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                }
                .padding(.horizontal, 24)

                ProgressSlider()
                    .padding(.horizontal, 24)

                HStack(spacing: 36) {
                    Button {
                        player.skip(by: -10)
                    } label: {
                        Image(systemName: "gobackward.10")
                            .font(.system(size: 32))
                    }
                    .buttonStyle(.plain)

                    Button {
                        player.togglePlayPause()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 64))
                    }
                    .buttonStyle(.plain)

                    Button {
                        player.skip(by: 10)
                    } label: {
                        Image(systemName: "goforward.10")
                            .font(.system(size: 32))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 8)

                Menu {
                    ForEach(PlayerService.speedOptions, id: \.self) { rate in
                        Button {
                            player.rate = rate
                        } label: {
                            HStack {
                                Text(PlayerService.formatRate(rate))
                                if player.rate == rate {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "speedometer")
                        Text(PlayerService.formatRate(player.rate))
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                }

                Spacer()
            }
            .padding(.bottom, 24)
        }
    }
}

private struct ProgressSlider: View {
    @Environment(PlayerService.self) private var player
    @State private var draggedValue: Double?
    @State private var isDragging = false

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
                    isDragging = editing
                    if !editing, let dv = draggedValue, player.duration > 0 {
                        player.seek(to: dv * player.duration)
                        draggedValue = nil
                    }
                }
            )

            HStack {
                Text(PlayerService.formatTime(player.currentTime))
                Spacer()
                Text(PlayerService.formatTime(max(0, player.duration - player.currentTime)))
            }
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
    }
}
