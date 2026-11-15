import AVFoundation
import CoreImage

struct VisualFrame {
    var start: Double
    var end: Double
    var image: CGImage
    var rect: CGRect
    var auxiliaryTransform: CGAffineTransform?
}

final class FrameInstruction: NSObject,AVVideoCompositionInstructionProtocol {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID = kCMPersistentTrackID_Invalid
    let background: CMPersistentTrackID
    let auxiliary: CMPersistentTrackID?
    let backgroundTransform: CGAffineTransform
    let frames: [VisualFrame]
    init(duration: CMTime,background: CMPersistentTrackID,auxiliary: CMPersistentTrackID?,backgroundTransform: CGAffineTransform,frames: [VisualFrame]) {
        timeRange = CMTimeRange(start: .zero,duration: duration)
        self.background = background;self.auxiliary = auxiliary;self.backgroundTransform = backgroundTransform;self.frames = frames
        requiredSourceTrackIDs = ([background]+(auxiliary.map { [$0] } ?? [])).map { NSNumber(value: $0) }
        super.init()
    }
}

final class FrameCompositor: NSObject,AVVideoCompositing {
    private let queue = DispatchQueue(label: "ThreadsStudio.frames",qos: .userInitiated)
    private let context = CIContext(options: [.cacheIntermediates:false])
    private let lock = NSLock()
    private var generation = 0
    var sourcePixelBufferAttributes: [String:Any]? { [kCVPixelBufferPixelFormatTypeKey as String:[kCVPixelFormatType_32BGRA]] }
    var requiredPixelBufferAttributesForRenderContext: [String:Any] {
        [kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA,kCVPixelBufferIOSurfacePropertiesKey as String:[:]]
    }
    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}
    func cancelAllPendingVideoCompositionRequests() { lock.lock();generation += 1;lock.unlock() }
    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        lock.lock();let token = generation;lock.unlock()
        queue.async { [self] in
            lock.lock();let cancelled = token != generation;lock.unlock()
            if cancelled { request.finishCancelledRequest();return }
            autoreleasepool { render(request) }
        }
    }
    private func source(_ pixel: CVPixelBuffer,transform: CGAffineTransform,outputHeight: CGFloat) -> CIImage {
        let flipInput = CGAffineTransform(a: 1,b: 0,c: 0,d: -1,tx: 0,ty: CGFloat(CVPixelBufferGetHeight(pixel)))
        let flipOutput = CGAffineTransform(a: 1,b: 0,c: 0,d: -1,tx: 0,ty: outputHeight)
        return CIImage(cvPixelBuffer: pixel).transformed(by: flipInput.concatenating(transform).concatenating(flipOutput))
    }
    private func render(_ request: AVAsynchronousVideoCompositionRequest) {
        guard let instruction = request.videoCompositionInstruction as? FrameInstruction,
              let background = request.sourceFrame(byTrackID: instruction.background),
              let pixel = request.renderContext.newPixelBuffer() else {
            request.finish(with: StudioError.message("Không tạo được khung video hoặc không đủ bộ nhớ."));return
        }
        let size = request.renderContext.size,bounds = CGRect(origin: .zero,size: size)
        var image = source(background,transform: instruction.backgroundTransform,outputHeight: size.height)
            .composited(over: CIImage(color: CIColor(red: 0.06,green: 0.09,blue: 0.16)).cropped(to: bounds))
        let time = request.compositionTime.seconds
        if let frame = instruction.frames.first(where: { time >= $0.start-0.00001 && time < $0.end-0.00001 }) {
            if let id = instruction.auxiliary,let transform = frame.auxiliaryTransform,let sourcePixel = request.sourceFrame(byTrackID: id) {
                image = source(sourcePixel,transform: transform,outputHeight: size.height).composited(over: image)
            }
            let overlay = CIImage(cgImage: frame.image)
            let transform = CGAffineTransform(scaleX: frame.rect.width/overlay.extent.width,y: frame.rect.height/overlay.extent.height)
                .concatenating(CGAffineTransform(translationX: frame.rect.minX,y: size.height-frame.rect.maxY))
            image = overlay.transformed(by: transform).composited(over: image)
        }
        context.render(image.cropped(to: bounds),to: pixel,bounds: bounds,colorSpace: CGColorSpaceCreateDeviceRGB())
        request.finish(withComposedVideoFrame: pixel)
    }
}
