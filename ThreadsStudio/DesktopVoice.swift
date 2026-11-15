import Foundation

final class DesktopVoice: @unchecked Sendable {
    private let queue = DispatchQueue(label: "ThreadsStudio.VieNeu",qos: .userInitiated)
    private var handle: UnsafeMutableRawPointer?
    deinit { if let handle { studio_voice_close(handle) } }
    func write(_ text: String,destination: URL) async throws {
        try Task.checkCancellation()
        guard let root = Bundle.main.resourceURL?.appendingPathComponent("Library/voice") else { throw StudioError.message("Thiếu bộ giọng PC.") }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void,Error>) in
            queue.async { [self] in
                var error = [CChar](repeating: 0,count: 2048)
                if handle == nil { handle = studio_voice_open(root.path,&error,error.count) }
                guard let handle else { continuation.resume(throwing: StudioError.message("Không mở được giọng PC: "+String(cString: error)));return }
                let success = studio_voice_write(handle,text,destination.path,&error,error.count)
                if success == 1 { continuation.resume() }
                else { continuation.resume(throwing: StudioError.message("Lỗi giọng PC: "+String(cString: error))) }
            }
        }
        try Task.checkCancellation()
    }
}
