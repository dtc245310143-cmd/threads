import AVFoundation
import UIKit
import Vision
import CoreVideo

struct VideoScene {
    var author: String
    var text: String
    var asset = ""
    var photo = false
    var outro = false
    var minimum = 1.0
    var hooks: [String] = []
    var start = 0.0
    var duration = 0.0
}
private struct AudioClip { var url: URL;var start: Double;var duration: Double;var effect: Bool }

@MainActor enum CardDrawing {
    static let canvas = CGSize(width: 1080,height: 1920)
    static func image(_ scene: VideoScene,project: Project) throws -> UIImage {
        if !scene.asset.isEmpty {
            guard let source = UIImage(contentsOfFile: try ProjectStore.url(scene.asset).path) else { throw StudioError.message("Không đọc được ảnh của cảnh.") }
            let factor = min(1000/source.size.width,(scene.photo ? 1800.0 : 950.0)/source.size.height,1)
            let size = CGSize(width: source.size.width*factor,height: source.size.height*factor)
            let format = UIGraphicsImageRendererFormat();format.scale = 1
            return UIGraphicsImageRenderer(size: size,format: format).image { _ in source.draw(in: CGRect(origin: .zero,size: size)) }
        }
        let width = 960.0, padding = 50.0
        let paragraph = NSMutableParagraphStyle();paragraph.lineSpacing = 12
        let attrs: [NSAttributedString.Key:Any] = [.font:UIFont.systemFont(ofSize: 40),.foregroundColor:UIColor.label,.paragraphStyle:paragraph]
        let text = NSAttributedString(string: scene.text,attributes: attrs)
        let measured = text.boundingRect(with: CGSize(width: width-padding*2,height: 1300),options: [.usesLineFragmentOrigin,.usesFontLeading],context: nil)
        let logoSpace = scene.outro && !project.channelLogo.isEmpty ? 180.0 : 0.0
        let height = max(220,ceil(measured.height)+170+logoSpace)
        let format = UIGraphicsImageRendererFormat();format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width,height: height),format: format).image { context in
            UIColor.white.setFill();UIBezierPath(roundedRect: CGRect(x: 0,y: 0,width: width,height: height),cornerRadius: 38).fill()
            if logoSpace > 0,let path = try? ProjectStore.url(project.channelLogo),let logo = UIImage(contentsOfFile: path.path) {
                let factor = min(140/logo.size.width,140/logo.size.height)
                logo.draw(in: CGRect(x: (width-logo.size.width*factor)/2,y: 28,width: logo.size.width*factor,height: logo.size.height*factor))
            }
            let name = scene.outro ? project.channelName : project.hideNames ? "Người dùng Threads" : scene.author
            let heading = name.isEmpty ? "Threads Studio" : name
            let circle = CGRect(x: padding,y: 40+logoSpace,width: 54,height: 54)
            UIColor.systemIndigo.setFill();context.cgContext.fillEllipse(in: circle)
            ("@" as NSString).draw(at: CGPoint(x: padding+9,y: 39+logoSpace),withAttributes: [.font:UIFont.boldSystemFont(ofSize: 36),.foregroundColor:UIColor.white])
            (heading as NSString).draw(in: CGRect(x: padding+74,y: 47+logoSpace,width: width-padding*2-74,height: 45),withAttributes: [.font:UIFont.boldSystemFont(ofSize: 30),.foregroundColor:UIColor.black])
            // Explicit colors keep exported cards legible even when the app uses dark mode.
            let exportText = NSMutableAttributedString(attributedString: text)
            exportText.addAttribute(.foregroundColor,value: UIColor.black,range: NSRange(location: 0,length: exportText.length))
            exportText.draw(in: CGRect(x: padding,y: 125+logoSpace,width: width-padding*2,height: ceil(measured.height)+10))
        }
    }
    static func rect(_ image: UIImage,scene: VideoScene,project: Project) -> CGRect {
        if scene.photo {
            let factor = min(1032/image.size.width,1840/image.size.height)
            let size = CGSize(width: image.size.width*factor,height: image.size.height*factor)
            return CGRect(x: (1080-size.width)/2,y: (1920-size.height)/2,width: size.width,height: size.height)
        }
        let factor = min(1080*project.cardScale/image.size.width,1400/image.size.height)
        let size = CGSize(width: image.size.width*factor,height: image.size.height*factor)
        let x = scene.outro ? 540 : 1080*project.cardX, y = scene.outro ? 960 : 1920*project.cardY
        return CGRect(x: min(1080-size.width,max(0,x-size.width/2)),y: min(1920-size.height,max(0,y-size.height/2)),width: size.width,height: size.height)
    }
}

@MainActor final class VideoRenderer {
    private let speech = NativeSpeech()
    private var lastSound = ""
    private func ct(_ seconds: Double) -> CMTime { CMTime(seconds: seconds,preferredTimescale: 48000) }

    private func photoText(_ photo: PostPhoto) throws -> String {
        if !photo.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return photo.text }
        guard let image = UIImage(contentsOfFile: try ProjectStore.url(photo.asset).path)?.cgImage else { throw StudioError.message("Không đọc được ảnh để nhận diện chữ.") }
        let request = VNRecognizeTextRequest();request.recognitionLevel = .accurate
        let supported = try request.supportedRecognitionLanguages()
        request.recognitionLanguages = ["vi-VN","en-US"].filter { supported.contains($0) }
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    private func scenes(_ p: Project) throws -> [VideoScene] {
        var items: [VideoScene] = []
        func add(author: String,text: String,captures: [Capture]) {
            let source = text.filter { !$0.isWhitespace }, captureText = captures.map(\.text).joined().filter { !$0.isWhitespace }
            if !p.hideNames && !captures.isEmpty && captureText == source {
                items += captures.map { VideoScene(author: author,text: $0.text,asset: $0.asset) }
            } else { items += SpeechText.pages(text).map { VideoScene(author: author,text: $0) } }
        }
        if !p.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { add(author: p.author,text: p.text,captures: p.capturedText == p.text ? p.captures : []) }
        if p.openPhotos {
            for photo in p.photos {
                let text = p.readPhotos ? try photoText(photo) : ""
                guard text.count <= 16000 else { throw StudioError.message("Ảnh có quá 16.000 ký tự. Hãy sửa phần chữ ảnh hoặc tắt đọc ảnh này.") }
                items.append(VideoScene(author: p.author,text: text,asset: photo.asset,photo: true,minimum: photo.seconds))
            }
        }
        for comment in p.selectedComments() {
            add(author: comment.author,text: comment.text,captures: comment.captures)
            if p.soundsEnabled && p.soundCount > 0 {
                var pool = !comment.sounds.isEmpty ? comment.sounds : !p.sounds.isEmpty ? p.sounds : ProjectStore.library("sounds",extensions: ["mp3","wav","m4a"])
                if comment.sounds.isEmpty && p.sounds.isEmpty {
                    let lower = comment.text.lowercased()
                    let category = [(["cười","haha","hài",":))","😂"],"laugh"),(["trời","sốc","sao vậy","ủa"],"surprise"),(["đúng","chuẩn","đồng ý"],"agree"),(["buồn","sai","thua","toang"],"fail")].first { $0.0.contains(where: lower.contains) }?.1 ?? "neutral"
                    let matching = pool.filter { $0.contains("/"+category+"/") };if !matching.isEmpty { pool = matching }
                }
                for _ in 0..<p.soundCount {
                    let options = pool.filter { $0 != lastSound }, chosen = (options.isEmpty ? pool : options).randomElement()
                    if let chosen { items[items.count-1].hooks.append(chosen);lastSound = chosen }
                }
            }
        }
        if p.outroEnabled { items += SpeechText.pages(p.outroText).map { VideoScene(author: p.channelName,text: $0,outro: true,minimum: 4) } }
        guard !items.isEmpty,items.count <= 120 else { throw StudioError.message("Video trống hoặc quá 120 cảnh. Hãy giảm số bình luận để iPhone đủ bộ nhớ; nội dung sẽ không bị tự cắt bớt.") }
        return items
    }

    func render(project p: Project,progress: @escaping (Double,String) -> Void) async throws -> URL {
        try p.validate();try Task.checkCancellation()
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,isDirectory: true)
        try FileManager.default.createDirectory(at: temp,withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        progress(0,"Đang nhận diện chữ và chuẩn bị các cảnh…")
        var items = try scenes(p),clips: [AudioClip] = [],cursor = 0.0,number = 0
        for index in items.indices {
            try Task.checkCancellation();items[index].start = cursor
            let start = cursor
            progress(Double(index)/Double(items.count)*0.6,"Đang đọc cảnh \(index+1)/\(items.count)…")
            if p.readAloud {
                let text = try SpeechText.spoken(items[index].text,project: p)
                for (sentence,pause) in SpeechText.sentences(text,project: p) {
                    let file = temp.appendingPathComponent("speech-\(number).caf");number += 1
                    try await speech.write(sentence,project: p,destination: file)
                    let length = try await mediaDuration(file)
                    clips.append(AudioClip(url: file,start: cursor,duration: length,effect: false));cursor += length+pause
                }
            }
            cursor = max(cursor+0.25,start+items[index].minimum)
            for hook in items[index].hooks {
                try Task.checkCancellation();let file = try ProjectStore.url(hook),length = try await mediaDuration(file)
                clips.append(AudioClip(url: file,start: cursor,duration: length,effect: true));cursor += length
            }
            items[index].duration = cursor-start
        }
        guard cursor <= 1800 else { throw StudioError.message("Video dài quá 30 phút. Hãy giảm bình luận hoặc hiệu ứng.") }
        progress(0.62,"Đang ghép video, giọng đọc và nhạc…")
        let composition = AVMutableComposition()
        guard let background = composition.addMutableTrack(withMediaType: .video,preferredTrackID: kCMPersistentTrackID_Invalid) else { throw StudioError.message("Không tạo được lớp video.") }
        let videos = ProjectStore.library("videos",extensions: ["mp4","mov","m4v"])
        let backgroundChoice = p.backgroundEnabled ? (p.backgrounds.isEmpty ? videos : p.backgrounds).randomElement() : nil
        let base: URL
        if let backgroundChoice { base = try ProjectStore.url(backgroundChoice) }
        else { base = try await makeCanvas(in: temp) }
        let baseTrack = try await loop(base,into: background,duration: cursor,type: .video)
        let bgLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: background)
        bgLayer.setTransform(try await transform(baseTrack,rect: CGRect(origin: .zero,size: CardDrawing.canvas),fill: true),at: .zero)
        var layers: [AVMutableVideoCompositionLayerInstruction] = []
        let auxChoice = p.auxiliaryEnabled ? (p.auxiliaryVideos.isEmpty ? videos : p.auxiliaryVideos).randomElement() : nil
        var aux: AVMutableVideoCompositionLayerInstruction?,auxSource: AVAssetTrack?
        if let choice = auxChoice,let track = composition.addMutableTrack(withMediaType: .video,preferredTrackID: kCMPersistentTrackID_Invalid) {
            auxSource = try await loop(ProjectStore.url(choice),into: track,duration: cursor,type: .video)
            aux = AVMutableVideoCompositionLayerInstruction(assetTrack: track);layers.append(aux!)
        }
        layers.append(bgLayer)
        let parent = CALayer();parent.frame = CGRect(origin: .zero,size: CardDrawing.canvas);parent.isGeometryFlipped = true
        let video = CALayer();video.frame = parent.bounds;parent.addSublayer(video)
        for item in items {
            try Task.checkCancellation()
            let image = try CardDrawing.image(item,project: p),rect = CardDrawing.rect(image,scene: item,project: p)
            let layer = CALayer();layer.contents = image.cgImage;layer.frame = rect;layer.opacity = 0;layer.contentsGravity = .resizeAspect
            let animation = CABasicAnimation(keyPath: "opacity");animation.fromValue = 1;animation.toValue = 1
            animation.beginTime = AVCoreAnimationBeginTimeAtZero+item.start;animation.duration = item.duration
            animation.isRemovedOnCompletion = false;animation.fillMode = .removed;layer.add(animation,forKey: "show")
            parent.addSublayer(layer)
            if let aux,let auxSource {
                let hidden = item.photo || item.outro
                aux.setOpacity(hidden ? 0 : 1,at: ct(item.start))
                let natural = try await auxSource.load(.naturalSize),preferred = try await auxSource.load(.preferredTransform)
                let bounds = CGRect(origin: .zero,size: natural).applying(preferred)
                var width = 1080*p.auxiliaryScale,height = min(1800,width*bounds.height/max(1,bounds.width))
                if p.auxiliaryBelowCard {
                    let available = max(0,1920-rect.maxY-56)
                    let factor = min(1,available/max(1,height));width *= factor;height *= factor
                    if available < 80 { aux.setOpacity(0,at: ct(item.start)) }
                }
                let x = min(1080-width,max(0,1080*p.auxiliaryX-width/2))
                let desired = p.auxiliaryBelowCard ? max(rect.maxY+32,1920*p.auxiliaryY-height/2) : 1920*p.auxiliaryY-height/2
                let y = min(1920-height-24,max(0,desired))
                aux.setTransform(try await transform(auxSource,rect: CGRect(x: x,y: y,width: width,height: height),fill: false),at: ct(item.start))
            }
        }
        var mixInputs: [AVMutableAudioMixInputParameters] = []
        for effect in [false,true] {
            let selected = clips.filter { $0.effect == effect };if selected.isEmpty { continue }
            guard let track = composition.addMutableTrack(withMediaType: .audio,preferredTrackID: kCMPersistentTrackID_Invalid) else { throw StudioError.message("Không tạo được lớp âm thanh.") }
            for clip in selected {
                let asset = AVURLAsset(url: clip.url)
                guard let source = try await asset.loadTracks(withMediaType: .audio).first else { throw StudioError.message("Tệp không có tiếng: \(clip.url.lastPathComponent)") }
                try track.insertTimeRange(CMTimeRange(start: .zero,duration: ct(clip.duration)),of: source,at: ct(clip.start))
            }
            let input = AVMutableAudioMixInputParameters(track: track);input.setVolume(Float(effect ? p.soundVolume : 1),at: .zero);mixInputs.append(input)
        }
        if p.musicEnabled,let choice = (p.music.isEmpty ? ProjectStore.library("music",extensions: ["mp3","m4a","wav"]) : p.music).randomElement(),let track = composition.addMutableTrack(withMediaType: .audio,preferredTrackID: kCMPersistentTrackID_Invalid) {
            _ = try await loop(ProjectStore.url(choice),into: track,duration: cursor,type: .audio)
            let input = AVMutableAudioMixInputParameters(track: track);input.setVolume(Float(p.musicVolume),at: .zero)
            input.setVolumeRamp(fromStartVolume: Float(p.musicVolume),toEndVolume: 0,timeRange: CMTimeRange(start: ct(max(0,cursor-1)),duration: ct(min(1,cursor))))
            mixInputs.append(input)
        }
        let mix = AVMutableAudioMix();mix.inputParameters = mixInputs
        let instruction = AVMutableVideoCompositionInstruction();instruction.timeRange = CMTimeRange(start: .zero,duration: ct(cursor));instruction.layerInstructions = layers
        let videoComposition = AVMutableVideoComposition();videoComposition.renderSize = CardDrawing.canvas;videoComposition.frameDuration = CMTime(value: 1,timescale: 24)
        videoComposition.instructions = [instruction];videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: video,in: parent)
        guard let exporter = AVAssetExportSession(asset: composition,presetName: AVAssetExportPreset1920x1080) else { throw StudioError.message("iPhone không hỗ trợ xuất video này.") }
        let output = temp.appendingPathComponent("video.mp4");exporter.outputURL = output;exporter.outputFileType = .mp4
        exporter.videoComposition = videoComposition;exporter.audioMix = mix;exporter.shouldOptimizeForNetworkUse = true
        let monitoring = Task {
            while !Task.isCancelled { progress(0.65+Double(exporter.progress)*0.34,"Đang xuất MP4 trên iPhone…");try? await Task.sleep(for: .milliseconds(500)) }
        }
        defer { monitoring.cancel() }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void,Error>) in
                exporter.exportAsynchronously {
                    if exporter.status == .completed { continuation.resume() }
                    else if exporter.status == .cancelled { continuation.resume(throwing: CancellationError()) }
                    else { continuation.resume(throwing: exporter.error ?? StudioError.message("Xuất MP4 thất bại.")) }
                }
            }
        } onCancel: { exporter.cancelExport() }
        try Task.checkCancellation()
        let documents = FileManager.default.urls(for: .documentDirectory,in: .userDomainMask)[0]
        let final = documents.appendingPathComponent("ThreadsStudio-\(UUID().uuidString.prefix(8)).mp4")
        try FileManager.default.moveItem(at: output,to: final)
        if let credits = Bundle.main.url(forResource: "SOURCES",withExtension: "txt",subdirectory: "Library") {
            try? FileManager.default.copyItem(at: credits,to: final.deletingPathExtension().appendingPathExtension("nguon.txt"))
        }
        progress(1,"Đã xuất MP4. Có thể chia sẻ hoặc lưu vào Ảnh.");return final
    }

    private func loop(_ url: URL,into track: AVMutableCompositionTrack,duration: Double,type: AVMediaType) async throws -> AVAssetTrack {
        let asset = AVURLAsset(url: url),length = try await mediaDuration(url)
        guard let source = try await asset.loadTracks(withMediaType: type).first else { throw StudioError.message("Media thiếu \(type.rawValue): \(url.lastPathComponent)") }
        var cursor = 0.0
        while cursor < duration-0.00001 {
            try Task.checkCancellation();let amount = min(length,duration-cursor)
            try track.insertTimeRange(CMTimeRange(start: .zero,duration: ct(amount)),of: source,at: ct(cursor));cursor += amount
        }
        return source
    }
    private func transform(_ track: AVAssetTrack,rect: CGRect,fill: Bool) async throws -> CGAffineTransform {
        let natural = try await track.load(.naturalSize),preferred = try await track.load(.preferredTransform)
        let bounds = CGRect(origin: .zero,size: natural).applying(preferred)
        guard bounds.width > 0,bounds.height > 0 else { throw StudioError.message("Video có kích thước không hợp lệ.") }
        let scale = fill ? max(rect.width/bounds.width,rect.height/bounds.height) : min(rect.width/bounds.width,rect.height/bounds.height)
        return preferred.concatenating(CGAffineTransform(translationX: -bounds.minX,y: -bounds.minY))
            .concatenating(CGAffineTransform(scaleX: scale,y: scale))
            .concatenating(CGAffineTransform(translationX: rect.midX-bounds.width*scale/2,y: rect.midY-bounds.height*scale/2))
    }

    private func makeCanvas(in folder: URL) async throws -> URL {
        let path = folder.appendingPathComponent("canvas.mov"),writer = try AVAssetWriter(outputURL: path,fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video,outputSettings: [AVVideoCodecKey:AVVideoCodecType.h264,AVVideoWidthKey:1080,AVVideoHeightKey:1920])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32ARGB,kCVPixelBufferWidthKey as String:1080,kCVPixelBufferHeightKey as String:1920])
        writer.add(input);guard writer.startWriting() else { throw writer.error ?? StudioError.message("Không tạo được nền video.") }
        writer.startSession(atSourceTime: .zero)
        var buffer: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault,1080,1920,kCVPixelFormatType_32ARGB,[kCVPixelBufferCGImageCompatibilityKey:true,kCVPixelBufferCGBitmapContextCompatibilityKey:true] as CFDictionary,&buffer) == kCVReturnSuccess,let pixel = buffer else { throw StudioError.message("Không đủ bộ nhớ tạo nền video.") }
        CVPixelBufferLockBaseAddress(pixel,[])
        if let context = CGContext(data: CVPixelBufferGetBaseAddress(pixel),width: 1080,height: 1920,bitsPerComponent: 8,bytesPerRow: CVPixelBufferGetBytesPerRow(pixel),space: CGColorSpaceCreateDeviceRGB(),bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) {
            context.setFillColor(UIColor(red: 0.06,green: 0.09,blue: 0.16,alpha: 1).cgColor);context.fill(CGRect(x: 0,y: 0,width: 1080,height: 1920))
        }
        CVPixelBufferUnlockBaseAddress(pixel,[])
        for time in [0.0,0.5] {
            while !input.isReadyForMoreMediaData { try Task.checkCancellation();try await Task.sleep(for: .milliseconds(10)) }
            guard adaptor.append(pixel,withPresentationTime: ct(time)) else { throw writer.error ?? StudioError.message("Không ghi được nền video.") }
        }
        writer.endSession(atSourceTime: ct(1));input.markAsFinished();await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? StudioError.message("Không hoàn tất được nền video.") }
        return path
    }
}
