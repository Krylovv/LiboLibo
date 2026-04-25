import Foundation
import Observation

/// Сервис оффлайн-загрузки. Один эпизод = один .mp3 в Documents/Downloads/.
/// Также ведёт `items` — список скачанных выпусков с метаданными, чтобы
/// «Моё» могла показать секцию «Скачано» и без обращения к сети.
@MainActor
@Observable
final class DownloadService {
    enum Status: Equatable, Sendable {
        case notDownloaded
        case downloading
        case downloaded
    }

    struct Item: Codable, Identifiable, Hashable, Sendable {
        var id: String              // episode.id
        var title: String
        var podcastId: Int
        var podcastName: String
        var podcastArtworkUrl: URL?
        var audioUrl: URL
        var pubDate: Date
        var duration: TimeInterval?
        var summary: String
        var downloadedAt: Date

        var asEpisode: Episode {
            Episode(
                id: id,
                podcastId: podcastId,
                podcastName: podcastName,
                podcastArtworkUrl: podcastArtworkUrl,
                title: title,
                summary: summary,
                pubDate: pubDate,
                duration: duration,
                audioUrl: audioUrl
            )
        }
    }

    private(set) var statuses: [String: Status] = [:]
    /// Скачанные выпуски, свежие сверху.
    private(set) var items: [Item] = []

    private static let itemsKey = "libolibo.downloadedItems"

    init() {
        loadItems()
        rebuildStatuses()
    }

    func status(for episode: Episode) -> Status {
        statuses[episode.id] ?? .notDownloaded
    }

    /// Локальный URL для воспроизведения с диска. Используется PlayerService.
    nonisolated static func localUrl(for episode: Episode) -> URL? {
        let url = downloadsDirectory()
            .appendingPathComponent(fileKey(episode.id))
            .appendingPathExtension(extensionFor(episode))
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func download(_ episode: Episode) {
        guard statuses[episode.id] != .downloading,
              statuses[episode.id] != .downloaded else { return }
        statuses[episode.id] = .downloading
        Task { [weak self] in
            await self?.performDownload(episode)
        }
    }

    func deleteDownload(_ episode: Episode) {
        let url = Self.downloadsDirectory()
            .appendingPathComponent(Self.fileKey(episode.id))
            .appendingPathExtension(Self.extensionFor(episode))
        try? FileManager.default.removeItem(at: url)
        statuses[episode.id] = .notDownloaded
        items.removeAll { $0.id == episode.id }
        saveItems()
    }

    func toggle(_ episode: Episode) {
        switch status(for: episode) {
        case .notDownloaded: download(episode)
        case .downloaded:    deleteDownload(episode)
        case .downloading:   break
        }
    }

    // MARK: - Internals

    private func performDownload(_ episode: Episode) async {
        let dir = Self.downloadsDirectory()
        let dest = dir.appendingPathComponent(Self.fileKey(episode.id))
            .appendingPathExtension(Self.extensionFor(episode))
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let (tempURL, _) = try await URLSession.shared.download(from: episode.audioUrl)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tempURL, to: dest)
            statuses[episode.id] = .downloaded

            let item = Item(
                id: episode.id,
                title: episode.title,
                podcastId: episode.podcastId,
                podcastName: episode.podcastName,
                podcastArtworkUrl: episode.podcastArtworkUrl,
                audioUrl: episode.audioUrl,
                pubDate: episode.pubDate,
                duration: episode.duration,
                summary: episode.summary,
                downloadedAt: Date()
            )
            items.removeAll { $0.id == item.id }
            items.insert(item, at: 0)
            saveItems()
        } catch {
            statuses[episode.id] = .notDownloaded
        }
    }

    private func loadItems() {
        if let data = UserDefaults.standard.data(forKey: Self.itemsKey),
           let decoded = try? JSONDecoder().decode([Item].self, from: data) {
            items = decoded
        }
    }

    private func saveItems() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: Self.itemsKey)
        }
    }

    /// Восстанавливает statuses[] из items[] и из реальных файлов на диске.
    /// Если файл удалили извне — снимаем статус .downloaded.
    private func rebuildStatuses() {
        var newStatuses: [String: Status] = [:]
        var prunedItems: [Item] = []
        for item in items {
            let url = Self.downloadsDirectory()
                .appendingPathComponent(Self.fileKey(item.id))
                .appendingPathExtension(Self.extensionFor(item.asEpisode))
            if FileManager.default.fileExists(atPath: url.path) {
                newStatuses[item.id] = .downloaded
                prunedItems.append(item)
            }
        }
        statuses = newStatuses
        if prunedItems.count != items.count {
            items = prunedItems
            saveItems()
        }
    }

    nonisolated private static func downloadsDirectory() -> URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Downloads")
    }

    nonisolated private static func fileKey(_ episodeId: String) -> String {
        var hex = ""
        for byte in episodeId.utf8 { hex += String(format: "%02x", byte) }
        return String(hex.prefix(40))
    }

    nonisolated private static func extensionFor(_ episode: Episode) -> String {
        let ext = episode.audioUrl.pathExtension
        return ext.isEmpty ? "mp3" : ext
    }
}
