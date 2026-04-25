import SwiftUI

struct MiniPlayerView: View {
    @Environment(PlayerService.self) private var player

    var body: some View {
        if let episode = player.currentEpisode {
            HStack(spacing: 12) {
                AsyncImage(url: episode.podcastArtworkUrl) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    default:
                        Color.secondary.opacity(0.15)
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(episode.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    Text(episode.podcastName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)

                Button {
                    player.skip(by: -10)
                } label: {
                    Image(systemName: "gobackward.10")
                        .font(.title3)
                }
                .buttonStyle(.plain)

                Button {
                    player.togglePlayPause()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(.separator.opacity(0.3), lineWidth: 0.5)
            )
        }
    }
}
