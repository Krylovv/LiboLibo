import SwiftUI

@main
struct LiboLiboApp: App {
    @State private var repository = PodcastsRepository()
    @State private var subscriptions = SubscriptionsService()
    @State private var history = HistoryService()
    @State private var downloads = DownloadService()
    @State private var player = PlayerService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(repository)
                .environment(subscriptions)
                .environment(history)
                .environment(downloads)
                .environment(player)
                .tint(.liboRed)
                .onAppear {
                    // История прослушиваний.
                    player.onPlay = { [weak history] episode in
                        history?.record(episode)
                    }
                    // Если выпуск скачан — играть с диска.
                    player.localUrlResolver = { episode in
                        DownloadService.localUrl(for: episode)
                    }
                }
        }
    }
}
