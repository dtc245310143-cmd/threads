import AVFoundation
import Foundation

private final class AudioSink: @unchecked Sendable {
    let path: URL
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void,Error>?
    private var file: AVAudioFile?
    init(path: URL, continuation: CheckedContinuation<Void,Error>) { self.path = path;self.continuation = continuation }
    func accept(_ buffer: AVAudioBuffer) {
        lock.lock();defer { lock.unlock() }
        guard continuation != nil,let pcm = buffer as? AVAudioPCMBuffer else { return }
        do {
            if pcm.frameLength == 0 {
                guard file != nil else { throw StudioError.message("Giọng iPhone không tạo được âm thanh. Hãy tải giọng tiếng Việt trong Cài đặt > Trợ năng > Nội dung được đọc.") }
                file = nil;let result = continuation;continuation = nil;result?.resume();return
            }
            if file == nil { file = try AVAudioFile(forWriting: path,settings: pcm.format.settings,commonFormat: pcm.format.commonFormat,interleaved: pcm.format.isInterleaved) }
            try file?.write(from: pcm)
        } catch { let result = continuation;continuation = nil;file = nil;result?.resume(throwing: error) }
    }
    func fail(_ error: Error) {
        lock.lock();defer { lock.unlock() }
        let result = continuation;continuation = nil;file = nil;result?.resume(throwing: error)
    }
}

@MainActor final class NativeSpeech {
    private let synthesizer = AVSpeechSynthesizer()
    private var sink: AudioSink?
    func write(_ text: String, project: Project, destination: URL) async throws {
        try Task.checkCancellation()
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("vi") }
        guard let voice = voices.first(where: { $0.identifier == project.voiceID }) ?? voices.sorted(by: { $0.quality.rawValue > $1.quality.rawValue }).first else {
            throw StudioError.message("Chưa có giọng tiếng Việt. Tải giọng trong Cài đặt > Trợ năng > Nội dung được đọc > Giọng nói > Tiếng Việt rồi mở lại app.")
        }
        let utterance = AVSpeechUtterance(string: text);utterance.voice = voice
        utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate,max(AVSpeechUtteranceMinimumSpeechRate,AVSpeechUtteranceDefaultSpeechRate*Float(project.speed)))
        let timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(90));self?.synthesizer.stopSpeaking(at: .immediate);self?.sink?.fail(StudioError.message("Tạo giọng quá 90 giây. Hãy thử lại hoặc chọn giọng khác.")) } catch {}
        }
        defer { timeout.cancel();sink = nil }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void,Error>) in
                let target = AudioSink(path: destination,continuation: continuation);sink = target
                synthesizer.write(utterance,toBufferCallback: { target.accept($0) })
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.synthesizer.stopSpeaking(at: .immediate);self?.sink?.fail(CancellationError()) }
        }
    }
}
