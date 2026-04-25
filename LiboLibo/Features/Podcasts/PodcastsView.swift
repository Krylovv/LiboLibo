import SwiftUI

struct PodcastsView: View {
    @Environment(PodcastsRepository.self) private var repository

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(repository.podcasts) { podcast in
                        NavigationLink(value: podcast) {
                            PodcastTile(podcast: podcast)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle("Подкасты")
            .navigationDestination(for: Podcast.self) { podcast in
                PodcastDetailView(podcast: podcast)
            }
        }
    }
}

private struct PodcastTile: View {
    let podcast: Podcast

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: podcast.artworkUrl) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    Color.secondary.opacity(0.15)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(podcast.name)
                .font(.subheadline)
                .lineLimit(2)
                .foregroundStyle(.primary)
        }
    }
}

#Preview {
    PodcastsView()
        .environment(PodcastsRepository())
}
