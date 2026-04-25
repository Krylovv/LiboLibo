import SwiftUI

struct EpisodeRow: View {
    let episode: Episode

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AsyncImage(url: episode.podcastArtworkUrl) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    Color.secondary.opacity(0.15)
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(episode.podcastName)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(episode.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text(episode.pubDate, style: .date)
                    if let dur = episode.duration {
                        Text("·")
                        Text(formatDuration(dur))
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

private func formatDuration(_ seconds: TimeInterval) -> String {
    let total = Int(seconds.rounded())
    let h = total / 3600
    let m = (total % 3600) / 60
    if h > 0 { return "\(h) ч \(m) мин" }
    return "\(m) мин"
}
