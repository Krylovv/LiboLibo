import SwiftUI

@main
struct LiboLiboApp: App {
    @State private var repository = PodcastsRepository()
    @State private var subscriptions = SubscriptionsService()
    @State private var history = HistoryService()
    @State private var player = PlayerService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(repository)
                .environment(subscriptions)
                .environment(history)
                .environment(player)
                .tint(.liboRed)
                .onAppear {
                    // Связываем плеер и историю.
                    player.onPlay = { [weak history] episode in
                        history?.record(episode)
                    }
                }
        }
    }
}
