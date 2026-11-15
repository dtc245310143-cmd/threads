import Foundation
import AVFoundation

enum StudioError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

struct Capture: Codable, Identifiable {
    var id = UUID()
    var text: String
    var asset: String
}

struct ThreadComment: Codable, Identifiable {
    var id: String
    var code: String = ""
    var author: String
    var text: String
    var likes: Int = 0
    var replies: Int = 0
    var authorLiked: Bool = false
    var authorReplied: Bool = false
    var captures: [Capture] = []
    var sounds: [String] = []
    var effectOverride: Bool? = nil
}

struct PostPhoto: Codable, Identifiable {
    var id = UUID()
    var asset: String
    var seconds: Double = 8
    var text: String = ""
}

struct Project: Codable {
    var sourceURL = ""
    var author = "tacgia"
    var text = "Một câu chuyện hay bắt đầu từ những điều rất nhỏ."
    var comments: [ThreadComment] = []
    var captures: [Capture] = []
    var capturedText = ""
    var photos: [PostPhoto] = []
    var commentCount = 5
    var prioritizeAuthor = true
    var onlyAuthorInteraction = false
    var includeAuthor = true
    var sortByLikes = false
    var hideNames = false
    var openPhotos = true
    var readPhotos = true
    var readAloud = true
    var voiceID = ""
    var voiceEngine = "desktop"
    var speed = 0.95
    var sentencePause = 0.45
    var paragraphPause = 0.7
    var normalizeWords = true
    var speechRules = "kh=không\nko=không\nk=không\nđc=được\ndc=được\nvs=với\nmn=mọi người\nny=người yêu\nnyc=người yêu cũ\nib=nhắn tin\nrep=trả lời\nbth=bình thường\nj=gì\nz=vậy"
    var soundsEnabled = true
    var effectMode = "random"
    var effectEvery = 3
    var effectProbability = 0.35
    var soundCount = 1
    var soundVolume = 0.65
    var sounds: [String] = []
    var backgroundEnabled = true
    var blurBackground = true
    var auxiliaryEnabled = true
    var musicEnabled = true
    var backgrounds: [String] = []
    var auxiliaryVideos: [String] = []
    var music: [String] = []
    var assetNames: [String:String] = [:]
    var musicVolume = 0.12
    var cardX = 0.5
    var cardY = 0.28
    var cardScale = 0.92
    var auxiliaryX = 0.5
    var auxiliaryY = 0.76
    var auxiliaryScale = 0.92
    var auxiliaryBelowCard = true
    var outroEnabled = false
    var channelName = ""
    var channelLogo = ""
    var outroText = "Nếu thấy video thú vị, hãy theo dõi kênh để xem thêm nhé!"

    func selectedComments() -> [ThreadComment] {
        Array(comments.filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            (includeAuthor || $0.author.lowercased() != author.lowercased()) &&
            (!onlyAuthorInteraction || $0.authorLiked || $0.authorReplied)
        }.sorted { a,b in
            let ax = a.authorLiked || a.authorReplied, bx = b.authorLiked || b.authorReplied
            if prioritizeAuthor && ax != bx { return ax }
            let av = a.likes + (sortByLikes ? 0 : a.replies), bv = b.likes + (sortByLikes ? 0 : b.replies)
            return av == bv ? a.id < b.id : av > bv
        }.prefix(commentCount))
    }

    func validate() throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !photos.isEmpty else {
            throw StudioError.message("Chưa có nội dung bài viết hoặc ảnh.")
        }
        guard text.count <= 16000, comments.count <= 500, photos.count <= 20,
              (0...100).contains(commentCount), (0.5...2).contains(speed),
              (0...5).contains(soundCount), (0...1).contains(soundVolume), (0...1).contains(musicVolume),
              (0...2).contains(sentencePause), (0...3).contains(paragraphPause),
              ["desktop","ios"].contains(voiceEngine), ["every","fixed","random"].contains(effectMode),
              (1...20).contains(effectEvery), (0...1).contains(effectProbability),
              photos.allSatisfy({ (2...120).contains($0.seconds) }),
              [cardX,cardY,auxiliaryX,auxiliaryY].allSatisfy({ $0.isFinite && (0...1).contains($0) }),
              [cardScale,auxiliaryScale].allSatisfy({ $0.isFinite && (0.3...1).contains($0) }) else {
            throw StudioError.message("Có tùy chỉnh vượt giới hạn. Kiểm tra tốc độ, âm lượng, số lượng và thời gian ảnh.")
        }
        _ = try SpeechText.rules(speechRules)
    }

    static func decodeSaved(_ data: Data) throws -> Project {
        guard data.count <= 8_000_000,
              let saved = try JSONSerialization.jsonObject(with: data) as? [String:Any],
              var merged = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Project())) as? [String:Any] else {
            throw StudioError.message("Bản nháp không hợp lệ.")
        }
        merged.merge(saved) { _,old in old }
        return try JSONDecoder().decode(Project.self,from: JSONSerialization.data(withJSONObject: merged))
    }
}

enum EffectSchedule {
    static func shouldPlay(_ project: Project,index: Int,override: Bool?,draw: () -> Double = { Double.random(in: 0..<1) }) -> Bool {
        guard project.soundsEnabled,project.soundCount > 0 else { return false }
        if let override { return override }
        switch project.effectMode {
        case "every":return true
        case "fixed":return (index+1)%max(1,project.effectEvery) == 0
        default:return draw() < project.effectProbability
        }
    }
}

enum SpeechText {
    static func rules(_ raw: String) throws -> [(String,String)] {
        guard raw.count <= 8000 else { throw StudioError.message("Bảng cách đọc tối đa 8.000 ký tự.") }
        return try raw.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.map {
            let parts = $0.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
                throw StudioError.message("Cách đọc phải có dạng từ viết tắt=cách đọc.")
            }
            return (parts[0],parts[1])
        }.sorted { $0.0.count > $1.0.count }
    }

    static func spoken(_ text: String, project: Project) throws -> String {
        guard project.normalizeWords else { return text }
        let protected = try NSRegularExpression(pattern: #"https?://\S+|www\.\S+|[\w.+-]+@[\w.-]+\.\w+|@[\w.]+"#, options: .caseInsensitive)
        var value = text
        var saved: [String] = []
        for match in protected.matches(in: text, range: NSRange(text.startIndex...,in: text)).reversed() {
            guard let range = Range(match.range,in: value) else { continue }
            saved.append(String(value[range])); value.replaceSubrange(range,with: "\u{E000}\(saved.count-1)\u{E001}")
        }
        for (key,replacement) in try rules(project.speechRules) {
            let pattern = #"(?<!\w)"# + NSRegularExpression.escapedPattern(for: key) + #"(?!\w)"#
            let regex = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
            value = regex.stringByReplacingMatches(in: value, range: NSRange(value.startIndex...,in: value), withTemplate: NSRegularExpression.escapedTemplate(for: replacement))
        }
        for (pattern,replacement) in [(#"[:=;][-^']?\)+|[😂🤣😆]+"#," ha ha "),(#":[-']?\(+"#," buồn ")] {
            value = value.replacingOccurrences(of: pattern,with: replacement,options: .regularExpression)
        }
        for (index,original) in saved.enumerated() { value = value.replacingOccurrences(of: "\u{E000}\(index)\u{E001}",with: original) }
        return value
    }

    static func sentences(_ text: String, project: Project) -> [(String,Double)] {
        var result: [(String,Double)] = []
        for paragraph in text.components(separatedBy: .newlines) {
            let before = result.count
            paragraph.enumerateSubstrings(in: paragraph.startIndex...,options: .bySentences) { sentence,_,_,_ in
                let value = (sentence ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if value.unicodeScalars.contains(where: CharacterSet.alphanumerics.contains) { result.append((value,project.sentencePause)) }
            }
            if result.count > before { result[result.count-1].1 = project.paragraphPause }
        }
        if !result.isEmpty { result[result.count-1].1 = 0 }
        return result
    }

    static func pages(_ text: String, limit: Int = 220) -> [String] {
        var pages: [String] = [], current = ""
        // Split an exceptionally long token too; no displayed or spoken suffix is discarded.
        for character in text {
            current.append(character)
            if current.count >= limit && (character.isWhitespace || current.count >= limit+40) {
                pages.append(current);current = ""
            }
        }
        if !current.isEmpty { pages.append(current) }
        return pages.isEmpty ? [""] : pages
    }
}

func mediaDuration(_ url: URL) async throws -> Double {
    let duration = try await AVURLAsset(url: url).load(.duration).seconds
    guard duration.isFinite && duration > 0 && duration <= 1800 else {
        throw StudioError.message("Media rỗng hoặc dài quá 30 phút: \(url.lastPathComponent)")
    }
    return duration
}

func audioDuration(_ url: URL) async throws -> Double {
    let asset = AVURLAsset(url: url)
    guard let track = try await asset.loadTracks(withMediaType: .audio).first else { throw StudioError.message("Tệp không có tiếng: \(url.lastPathComponent)") }
    let duration = try await track.load(.timeRange).duration.seconds
    guard duration.isFinite && duration > 0 && duration <= 1800 else { throw StudioError.message("Đoạn âm thanh rỗng hoặc dài quá 30 phút.") }
    return duration
}
