import SwiftUI

struct RootView: View {
    @Environment(PlayerService.self) private var player
    @State private var showFullPlayer = false

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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if player.currentEpisode != nil {
                MiniPlayerView()
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        showFullPlayer = true
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: player.currentEpisode?.id)
        .sheet(isPresented: $showFullPlayer) {
            PlayerView()
                .presentationDragIndicator(.visible)
        }
    }
}

#Preview {
    RootView()
        .environment(PodcastsRepository())
        .environment(PlayerService())
}
