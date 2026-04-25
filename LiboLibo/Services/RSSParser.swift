import Foundation

/// Минимальный парсер подкаст-RSS.
/// Достаёт title / description / pubDate / enclosure URL / itunes:duration / guid из каждого <item>.
enum RSSParser {
    static func parse(data: Data, podcast: Podcast) -> [Episode] {
        let delegate = RSSParserDelegate(podcast: podcast)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.episodes
    }
}

private final class RSSParserDelegate: NSObject, XMLParserDelegate {
    let podcast: Podcast
    var episodes: [Episode] = []

    private var currentElement = ""
    private var currentTitle = ""
    private var currentDescription = ""
    private var currentPubDate = ""
    private var currentDuration = ""
    private var currentGUID = ""
    private var currentAudioUrl: URL?
    private var inItem = false

    init(podcast: Podcast) {
        self.podcast = podcast
    }

    func parser(_ parser: XMLParser,
                didStartElement element: String,
                namespaceURI: String?,
                qualifiedName: String?,
                attributes: [String: String]) {
        currentElement = element
        if element == "item" {
            inItem = true
            currentTitle = ""
            currentDescription = ""
            currentPubDate = ""
            currentDuration = ""
            currentGUID = ""
            currentAudioUrl = nil
        }
        if inItem,
           element == "enclosure",
           let raw = attributes["url"],
           let url = URL(string: raw) {
            currentAudioUrl = url
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inItem else { return }
        switch currentElement {
        case "title": currentTitle += string
        case "description": currentDescription += string
        case "pubDate": currentPubDate += string
        case "itunes:duration": currentDuration += string
        case "guid": currentGUID += string
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
        if element == "item" {
            defer { inItem = false }
            guard let audio = currentAudioUrl else { return }

            let trimmedGUID = currentGUID.trimmingCharacters(in: .whitespacesAndNewlines)
            let id = trimmedGUID.isEmpty ? audio.absoluteString : trimmedGUID
            let date = parseRFC822(currentPubDate.trimmingCharacters(in: .whitespacesAndNewlines)) ?? Date(timeIntervalSince1970: 0)
            let dur = parseDuration(currentDuration.trimmingCharacters(in: .whitespacesAndNewlines))

            episodes.append(Episode(
                id: id,
                podcastId: podcast.id,
                podcastName: podcast.name,
                podcastArtworkUrl: podcast.artworkUrl,
                title: currentTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                summary: currentDescription.trimmingCharacters(in: .whitespacesAndNewlines),
                pubDate: date,
                duration: dur,
                audioUrl: audio
            ))
        }
    }
}

private let rfc822Formatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
    return f
}()

private func parseRFC822(_ string: String) -> Date? {
    rfc822Formatter.date(from: string)
}

private func parseDuration(_ string: String) -> TimeInterval? {
    if let n = Double(string) { return n }
    let parts = string.split(separator: ":").compactMap { Double($0) }
    switch parts.count {
    case 3: return parts[0] * 3600 + parts[1] * 60 + parts[2]
    case 2: return parts[0] * 60 + parts[1]
    case 1: return parts[0]
    default: return nil
    }
}
