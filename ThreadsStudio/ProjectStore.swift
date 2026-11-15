import Foundation
import Combine
import UIKit
import UniformTypeIdentifiers

@MainActor final class ProjectStore: ObservableObject {
    @Published var project = Project() { didSet { scheduleSave() } }
    @Published var saveStatus = "Tự lưu bật"
    @Published var message: String?
    private var saveTask: Task<Void,Never>?
    private var loading = true
    static let root: URL = {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory,in: .userDomainMask)[0].appendingPathComponent("ThreadsStudio",isDirectory: true)
        try? FileManager.default.createDirectory(at: folder,withIntermediateDirectories: true)
        return folder
    }()
    private var session: URL { Self.root.appendingPathComponent("project.json") }
    private var backup: URL { Self.root.appendingPathComponent("project.backup.json") }

    init() {
        let decoder = JSONDecoder()
        for path in [session,backup] where FileManager.default.fileExists(atPath: path.path) {
            do {
                let data = try Data(contentsOf: path)
                guard data.count <= 8_000_000 else { throw StudioError.message("Bản nháp quá lớn.") }
                project = try decoder.decode(Project.self,from: data)
                saveStatus = path == session ? "Đã khôi phục" : "Khôi phục dự phòng"
                break
            } catch { message = "Không đọc được \(path.lastPathComponent): \(error.localizedDescription)" }
        }
        loading = false
    }

    private func scheduleSave() {
        guard !loading else { return }
        saveStatus = "Đang lưu…";saveTask?.cancel()
        saveTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(600));self?.save() } catch {}
        }
    }

    func save() {
        do {
            let data = try JSONEncoder().encode(project)
            guard data.count <= 8_000_000 else { throw StudioError.message("Bản nháp quá 8 MB.") }
            if let old = try? Data(contentsOf: session), (try? JSONDecoder().decode(Project.self,from: old)) != nil {
                try old.write(to: backup,options: .atomic)
            }
            try data.write(to: session,options: .atomic)
            saveStatus = "Đã tự lưu"
        } catch { saveStatus = "Lưu thất bại";message = error.localizedDescription }
    }

    static func url(_ asset: String) throws -> URL {
        let bundled = asset.hasPrefix("bundle:")
        let path = bundled ? String(asset.dropFirst(7)) : asset
        guard !path.isEmpty, !path.hasPrefix("/"), !path.split(separator: "/").contains(".."), !path.contains("\\") else {
            throw StudioError.message("Đường dẫn media không hợp lệ.")
        }
        let base = bundled ? Bundle.main.resourceURL!.appendingPathComponent("Library",isDirectory: true) : root
        let result = base.appendingPathComponent(path).standardizedFileURL
        guard result.path.hasPrefix(base.standardizedFileURL.path + "/"), FileManager.default.fileExists(atPath: result.path) else {
            throw StudioError.message("Không tìm thấy media \(URL(fileURLWithPath: path).lastPathComponent). Hãy nhập lại tệp.")
        }
        return result
    }

    static func store(_ data: Data, extension ext: String) throws -> String {
        guard !data.isEmpty, data.count <= 300_000_000, ext.range(of: #"^[a-zA-Z0-9]{1,8}$"#, options: .regularExpression) != nil else {
            throw StudioError.message("Tệp rỗng, quá 300 MB hoặc định dạng không hợp lệ.")
        }
        let name = "Media/\(UUID().uuidString).\(ext.lowercased())"
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Media"),withIntermediateDirectories: true)
        try data.write(to: root.appendingPathComponent(name),options: .atomic)
        return name
    }

    static func importFile(_ url: URL, image: Bool = false) throws -> String {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 300_000_000 else { throw StudioError.message("Mỗi tệp tối đa 300 MB.") }
        let data = try Data(contentsOf: url,options: .mappedIfSafe)
        if image {
            guard let source = UIImage(data: data), source.size.width*source.size.height <= 40_000_000 else {
                throw StudioError.message("Không đọc được ảnh hoặc ảnh quá 40 megapixel.")
            }
            let scale = min(1,2400/max(source.size.width,source.size.height))
            let format = UIGraphicsImageRendererFormat();format.scale = 1
            let rendered = UIGraphicsImageRenderer(size: CGSize(width: source.size.width*scale,height: source.size.height*scale),format: format).image { _ in source.draw(in: CGRect(x: 0,y: 0,width: source.size.width*scale,height: source.size.height*scale)) }
            guard let jpeg = rendered.jpegData(compressionQuality: 0.93) else { throw StudioError.message("Không lưu được ảnh.") }
            return try store(jpeg,extension: "jpg")
        }
        return try store(data,extension: url.pathExtension)
    }

    static func library(_ subfolder: String, extensions: Set<String>) -> [String] {
        guard let root = Bundle.main.resourceURL?.appendingPathComponent("Library/\(subfolder)"),
              let walker = FileManager.default.enumerator(at: root,includingPropertiesForKeys: nil) else { return [] }
        return walker.compactMap { item in
            guard let url = item as? URL, extensions.contains(url.pathExtension.lowercased()) else { return nil }
            return "bundle:\(subfolder)/" + String(url.path.dropFirst(root.path.count+1))
        }.sorted()
    }
}
