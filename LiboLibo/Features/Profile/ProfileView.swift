import SwiftUI

struct ProfileView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Профиль появится скоро",
                systemImage: "person.crop.circle",
                description: Text("На фазе 1.8 тут будут подписки и история прослушиваний.")
            )
            .navigationTitle("Моё")
        }
    }
}

#Preview {
    ProfileView()
}
