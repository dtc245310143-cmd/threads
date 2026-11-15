import SwiftUI
import WebKit

struct ScanRecord: Codable {
    var id: String
    var code: String
    var author: String
    var text: String
    var likes: Int
    var replies: Int
    var authorLiked: Bool
    var authorReplied: Bool
    var images: [String]
    var comment: ThreadComment {
        ThreadComment(id: id,code: code,author: author,text: text,likes: likes,replies: replies,authorLiked: authorLiked,authorReplied: authorReplied)
    }
}
struct ScanResult: Codable { var root: ScanRecord;var comments: [ScanRecord] }

@MainActor final class ThreadScanner: NSObject,ObservableObject,WKNavigationDelegate {
    let webView: WKWebView
    @Published var status = "Đăng nhập Threads một lần trong cửa sổ này."
    @Published var busy = false
    @Published var loaded = false
    private var task: Task<Void,Never>?

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        if let path = Bundle.main.url(forResource: "ThreadsScan",withExtension: "js"), let code = try? String(contentsOf: path,encoding: .utf8) {
            config.userContentController.addUserScript(WKUserScript(source: code,injectionTime: .atDocumentStart,forMainFrameOnly: true))
        }
        webView = WKWebView(frame: .zero,configuration: config)
        super.init();webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
    }

    static func postURL(_ raw: String) throws -> URL {
        guard let parts = URLComponents(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),parts.scheme == "https",
              ["threads.com","www.threads.com","threads.net","www.threads.net"].contains(parts.host?.lowercased() ?? ""),
              parts.user == nil,parts.password == nil, parts.port == nil,
              parts.path.range(of: #"^/(?:@[^/]+/post/[A-Za-z0-9_-]+|share/[A-Za-z0-9_-]+)/?$"#,options: .regularExpression) != nil,
              let url = parts.url else { throw StudioError.message("Dán link HTTPS của bài Threads, không phải trang cá nhân.") }
        return url
    }

    func open(_ raw: String) throws {
        let url = try Self.postURL(raw)
        if webView.url != url { loaded = false;webView.load(URLRequest(url: url)) }
    }
    func login() { loaded = false;webView.load(URLRequest(url: URL(string: "https://www.threads.com/login")!)) }
    func stop() { task?.cancel();webView.stopLoading();busy = false;status = "Đã dừng quét." }
    func webView(_ webView: WKWebView,didFinish navigation: WKNavigation!) { loaded = true }
    func webView(_ webView: WKWebView,didFailProvisionalNavigation navigation: WKNavigation!,withError error: Error) { status = error.localizedDescription }

    func start(store: ProjectStore, finished: @escaping () -> Void) {
        guard !busy else { return };busy = true
        task = Task {
            defer { busy = false }
            do { let result = try await scan(project: store.project);store.project = result;store.save();finished() }
            catch is CancellationError { status = "Đã dừng quét." }
            catch { status = error.localizedDescription }
        }
    }

    private func javascript(_ script: String) async throws -> Any? { try await webView.evaluateJavaScript(script) }
    private func argument<T: Encodable>(_ value: T) throws -> String { String(decoding: try JSONEncoder().encode(value),as: UTF8.self) }

    private func scan(project: Project) async throws -> Project {
        for _ in 0..<40 { if loaded { break };try await Task.sleep(for: .milliseconds(500)) }
        guard loaded else { throw StudioError.message("Trang chưa tải xong. Kiểm tra mạng và bấm Quét lại.") }
        var latest: ScanResult?, previous = -1, unchanged = 0
        for turn in 0..<24 {
            try Task.checkCancellation()
            _ = try await javascript("window.ThreadsStudio?.expand()")
            try await Task.sleep(for: .milliseconds(turn == 0 ? 2000 : 1000))
            if let raw = try await javascript("JSON.stringify(window.ThreadsStudio?.result() ?? null)") as? String,raw != "null" {
                latest = try JSONDecoder().decode(ScanResult.self,from: Data(raw.utf8))
            }
            if let latest {
                status = "Đã lấy \(latest.comments.count) bình luận; đang tải thêm để xếp hạng…"
                unchanged = latest.comments.count == previous ? unchanged+1 : 0;previous = latest.comments.count
                if latest.comments.count >= min(500,max(30,project.commentCount*3)) || unchanged >= 4 || project.commentCount == 0 { break }
            } else if turn >= 4 {
                throw StudioError.message("Chưa lấy được bài. Hãy đăng nhập/xác minh trong trang phía dưới rồi bấm Quét lại. Bài có thể bị giới hạn hoặc đã xóa.")
            }
            _ = try await javascript("window.scrollBy(0,550)")
        }
        guard let result = latest else { throw StudioError.message("Không có dữ liệu bài viết. Hãy đăng nhập và thử lại.") }
        guard result.root.text.count <= 16000 else { throw StudioError.message("Bài viết quá 16.000 ký tự.") }
        var updated = project
        updated.author = result.root.author;updated.text = result.root.text;updated.capturedText = result.root.text
        updated.comments = result.comments.map(\.comment);updated.photos = [];updated.captures = []
        if let url = webView.url { updated.sourceURL = url.absoluteString }
        for (index,source) in result.root.images.enumerated() {
            try Task.checkCancellation();status = "Đang lấy ảnh gốc \(index+1)/\(result.root.images.count)…"
            updated.photos.append(PostPhoto(asset: try await downloadImage(source)))
        }
        status = "Đang chụp khung bài viết và bình luận…"
        var failed = 0
        do { updated.captures = try await capture(result.root) } catch is CancellationError { throw CancellationError() } catch { failed += 1 }
        let selected = Set(updated.selectedComments().map(\.id))
        for record in result.comments where selected.contains(record.id) {
            try Task.checkCancellation()
            do {
                let pages = try await capture(record)
                if let index = updated.comments.firstIndex(where: { $0.id == record.id }) { updated.comments[index].captures = pages }
            } catch is CancellationError { throw CancellationError() } catch { failed += 1 }
        }
        status = "Đã quét \(updated.photos.count) ảnh, \(updated.comments.count) bình luận."
        if failed > 0 { storeWarning = "\(failed) khung chưa chụp được; dùng thẻ dựng lại và vẫn đọc đủ chữ." }
        else { storeWarning = "" }
        return updated
    }
    @Published var storeWarning = ""

    private func capture(_ record: ScanRecord) async throws -> [Capture] {
        var captures: [Capture] = []
        for chunk in SpeechText.pages(record.text) {
            try Task.checkCancellation()
            let call = "window.ThreadsStudio?.prepare(\(try argument(record)),\(try argument(chunk)))"
            guard let box = try await javascript(call) as? [String:Double],let x = box["x"],let y = box["y"],let width = box["width"],let height = box["height"],width > 0,height > 0 else {
                throw StudioError.message("Không tìm được khung bài gốc.")
            }
            do {
                try await Task.sleep(for: .milliseconds(180))
                let config = WKSnapshotConfiguration()
                config.rect = CGRect(x: x,y: y,width: width,height: height).intersection(webView.bounds)
                let image = try await webView.takeSnapshot(configuration: config)
                guard let png = image.pngData() else { throw StudioError.message("Không chụp được khung bài.") }
                captures.append(Capture(text: chunk,asset: try ProjectStore.store(png,extension: "png")))
            } catch { _ = try? await javascript("window.ThreadsStudio?.cleanup()");throw error }
            _ = try? await javascript("window.ThreadsStudio?.cleanup()")
        }
        return captures
    }

    private func downloadImage(_ raw: String) async throws -> String {
        guard let url = URL(string: raw),url.scheme == "https",url.user == nil,url.password == nil,
              ["fbcdn.net","cdninstagram.com","threads.com","threads.net"].contains(where: { url.host == $0 || (url.host ?? "").hasSuffix("."+$0) }) else {
            throw StudioError.message("Địa chỉ ảnh nằm ngoài CDN Threads.")
        }
        let config = URLSessionConfiguration.ephemeral;config.timeoutIntervalForRequest = 30
        let session = URLSession(configuration: config,delegate: NoRedirects(),delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes,response) = try await session.bytes(from: url)
        guard let http = response as? HTTPURLResponse,http.statusCode == 200,response.expectedContentLength <= 25_000_000 else {
            throw StudioError.message("Không tải được ảnh hoặc ảnh quá 25 MB.")
        }
        var data = Data()
        for try await byte in bytes { data.append(byte);if data.count > 25_000_000 { throw StudioError.message("Ảnh quá 25 MB.") } }
        guard let image = UIImage(data: data),image.size.width*image.size.height <= 40_000_000,let png = image.pngData() else { throw StudioError.message("Ảnh không hợp lệ.") }
        return try ProjectStore.store(png,extension: "png")
    }
}

private final class NoRedirects: NSObject,URLSessionTaskDelegate {
    func urlSession(_ session: URLSession,task: URLSessionTask,willPerformHTTPRedirection response: HTTPURLResponse,newRequest request: URLRequest,completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

struct ThreadsBrowserView: UIViewRepresentable {
    let scanner: ThreadScanner
    func makeUIView(context: Context) -> WKWebView { scanner.webView }
    func updateUIView(_ view: WKWebView,context: Context) {}
}
