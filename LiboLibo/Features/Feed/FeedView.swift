import SwiftUI

struct FeedView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Скоро здесь будет фид",
                systemImage: "antenna.radiowaves.left.and.right",
                description: Text("На фазе 1.1 тут появятся выпуски подкастов Либо-Либо.")
            )
            .navigationTitle("Фид")
        }
    }
}

#Preview {
    FeedView()
}
