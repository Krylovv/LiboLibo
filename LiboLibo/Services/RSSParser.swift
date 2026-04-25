import Foundation

/// Минимальный парсер подкаст-RSS.
/// Возвращает channel description и список выпусков.
enum RSSParser {
    static func parse(data: Data, podcast: Podcast) -> (channel: PodcastChannelInfo, episodes: [Episode]) {
        let delegate = RSSParserDelegate(podcast: podcast)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return (
            channel: PodcastChannelInfo(description: delegate.channelDescription),
            episodes: delegate.episodes
        )
    }
}

private final class RSSParserDelegate: NSObject, XMLParserDelegate {
    let podcast: Podcast
    var episodes: [Episode] = []
    var channelDescription = ""

    private var currentElement = ""
    private var currentTitle = ""
    private var currentDescription = ""
    private var currentPubDate = ""
    private var currentDuration = ""
    private var currentGUID = ""
    private var currentAudioUrl: URL?
    private var inItem = false
    private var inChannel = false
    private var channelLevelDescriptionBuffer = ""

    init(podcast: Podcast) {
        self.podcast = podcast
    }

    func parser(_ parser: XMLParser,
                didStartElement element: String,
                namespaceURI: String?,
                qualifiedName: String?,
                attributes: [String: String]) {
        currentElement = element
        if element == "channel" {
            inChannel = true
        }
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
        if inItem {
            switch currentElement {
            case "title":             currentTitle += string
            case "description":       currentDescription += string
            case "itunes:summary":    if currentDescription.isEmpty { currentDescription += string }
            case "pubDate":           currentPubDate += string
            case "itunes:duration":   currentDuration += string
            case "guid":              currentGUID += string
            default: break
            }
            return
        }
        if inChannel {
            // Channel-level description (or itunes:summary) до первого <item>.
            switch currentElement {
            case "description", "itunes:summary":
                channelLevelDescriptionBuffer += string
            default:
                break
            }
        }
    }

    func parser(_ parser: XMLParser,
                didEndElement element: String,
                namespaceURI: String?,
                qualifiedName: String?) {
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
                summary: stripHTML(currentDescription).trimmingCharacters(in: .whitespacesAndNewlines),
                pubDate: date,
                duration: dur,
                audioUrl: audio
            ))
            return
        }

        if element == "channel" {
            // Финализируем channel description в момент закрытия канала.
            channelDescription = stripHTML(channelLevelDescriptionBuffer).trimmingCharacters(in: .whitespacesAndNewlines)
            inChannel = false
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

/// Грубый, но достаточный для подкаст-RSS strip HTML-тегов и сущностей.
private func stripHTML(_ string: String) -> String {
    var result = string
    // Заменим <br>, <br/>, <p>, </p> на пробелы / переводы строк.
    result = result.replacingOccurrences(of: "<br[^>]*>", with: "\n", options: .regularExpression)
    result = result.replacingOccurrences(of: "</p>", with: "\n\n")
    // Снесём остальные теги.
    result = result.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    // Базовые HTML-сущности.
    let entities: [String: String] = [
        "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
        "&#39;": "'", "&apos;": "'", "&nbsp;": " ",
        "&mdash;": "—", "&ndash;": "–", "&hellip;": "…",
        "&laquo;": "«", "&raquo;": "»",
    ]
    for (k, v) in entities {
        result = result.replacingOccurrences(of: k, with: v)
    }
    // Сожмём множественные переводы строк / пробелы.
    result = result.replacingOccurrences(of: "[\n]{3,}", with: "\n\n", options: .regularExpression)
    return result
}

// MARK: - Sentence helpers

extension String {
    /// Удаляет URL-ы (http/https/www.) и схлопывает оставшиеся пробелы.
    /// URL не должны попадать в превью — точки в URL ломают разбиение на предложения.
    var withoutURLs: String {
        var s = self
        s = s.replacingOccurrences(
            of: #"\bhttps?://[^\s,;<>«»"']+"#,
            with: "",
            options: .regularExpression
        )
        s = s.replacingOccurrences(
            of: #"\bwww\.[^\s,;<>«»"']+"#,
            with: "",
            options: .regularExpression
        )
        // Чистим хвостовые «:» / «—» / повторные пробелы, оставшиеся от вырезанного URL.
        s = s.replacingOccurrences(of: #"[:\-–—]\s*$"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Возвращает первое предложение строки. Если в нём меньше 2 слов — берём первые два.
    /// Перед извлечением URL-ы вырезаются.
    func firstSentences(maxCount: Int = 2) -> String {
        let cleaned = self.withoutURLs
        guard !cleaned.isEmpty else { return "" }

        var sentences: [String] = []
        var buffer = ""
        for char in cleaned {
            buffer.append(char)
            if ".!?".contains(char) {
                let s = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                // Игнорируем «предложения» из 1–2 символов («.», «А.»), это аббревиатуры или мусор.
                if s.count > 2 { sentences.append(s) }
                buffer = ""
                if sentences.count >= maxCount { break }
            }
        }
        let leftover = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !leftover.isEmpty && sentences.count < maxCount {
            sentences.append(leftover)
        }
        if sentences.isEmpty { return cleaned }

        // Если первое предложение короче 2 слов — добавляем второе (правило Ильи).
        let first = sentences[0]
        let firstWords = first.split { $0.isWhitespace }.count
        if firstWords < 2, sentences.count >= 2 {
            return sentences.prefix(2).joined(separator: " ")
        }
        return first
    }
}
