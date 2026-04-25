import SwiftUI

struct PodcastsView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Подкасты появятся скоро",
                systemImage: "rectangle.grid.2x2",
                description: Text("На фазе 1.6 тут будет сетка из 44 подкастов студии Либо-Либо.")
            )
            .navigationTitle("Подкасты")
        }
    }
}

#Preview {
    PodcastsView()
}
