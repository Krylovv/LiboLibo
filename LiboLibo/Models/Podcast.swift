import Foundation

struct Podcast: Identifiable, Hashable, Codable, Sendable {
    let id: Int
    let name: String
    let artist: String
    let feedUrl: URL
    let artworkUrl: URL?
}

/// Подробности, вытащенные из самого RSS-канала (description, link и т.п.).
/// Загружаются по требованию в PodcastDetailView.
struct PodcastChannelInfo: Sendable {
    let description: String
}
