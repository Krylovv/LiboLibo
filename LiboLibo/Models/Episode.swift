import Foundation

struct Episode: Identifiable, Hashable, Sendable {
    let id: String
    let podcastId: Int
    let podcastName: String
    let podcastArtworkUrl: URL?
    let title: String
    let summary: String
    let pubDate: Date
    let duration: TimeInterval?
    let audioUrl: URL
}
