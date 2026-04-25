import SwiftUI

struct FeedView: View {
    @Environment(PodcastsRepository.self) private var repository
    @Environment(PlayerService.self) private var player

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Фид")
                .refreshable {
                    await repository.loadAllEpisodes()
                }
                .task {
                    if repository.allEpisodes.isEmpty {
                        await repository.loadAllEpisodes()
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if repository.isLoading && repository.allEpisodes.isEmpty {
            ProgressView("Загружаем выпуски…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if repository.allEpisodes.isEmpty {
            ContentUnavailableView(
                "Нет выпусков",
                systemImage: "antenna.radiowaves.left.and.right",
                description: Text(repository.loadError ?? "Потяните вниз, чтобы обновить.")
            )
        } else {
            List(repository.allEpisodes) { episode in
                Button {
                    player.play(episode)
                } label: {
                    EpisodeRow(episode: episode)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
        }
    }
}

#Preview {
    FeedView()
        .environment(PodcastsRepository())
        .environment(PlayerService())
}
