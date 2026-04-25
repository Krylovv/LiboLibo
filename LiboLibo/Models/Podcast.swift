import Foundation

struct Podcast: Identifiable, Hashable, Codable, Sendable {
    let id: Int
    let name: String
    let artist: String
    let feedUrl: URL
    let artworkUrl: URL?
    /// Канальное описание из RSS (обогащается скриптом scripts/refresh-podcast-metadata.py).
    let description: String?
    /// Дата самого свежего выпуска. По ней приложение делит подкасты на
    /// «выходят сейчас / недавно / давно не выходят».
    let lastEpisodeDate: Date?
}

/// Подробности, вытащенные из самого RSS-канала. Используется PodcastDetailView
/// для отрисовки полного описания, когда оно нужно «свежее».
struct PodcastChannelInfo: Sendable {
    let description: String
}
