import SwiftUI

@main
struct LiboLiboApp: App {
    @State private var repository = PodcastsRepository()
    @State private var player = PlayerService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(repository)
                .environment(player)
        }
    }
}
