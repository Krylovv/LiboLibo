import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            FeedView()
                .tabItem {
                    Label("Фид", systemImage: "list.dash")
                }

            PodcastsView()
                .tabItem {
                    Label("Подкасты", systemImage: "rectangle.grid.2x2")
                }

            ProfileView()
                .tabItem {
                    Label("Моё", systemImage: "person.crop.circle")
                }
        }
    }
}

#Preview {
    RootView()
}
