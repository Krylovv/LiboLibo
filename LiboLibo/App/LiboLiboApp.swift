import SwiftUI

@main
struct LiboLiboApp: App {
    @State private var repository = PodcastsRepository()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(repository)
        }
    }
}
