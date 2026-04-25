import Foundation

struct Podcast: Identifiable, Hashable, Codable, Sendable {
    let id: Int
    let name: String
    let artist: String
    let feedUrl: URL
    let artworkUrl: URL?
}
