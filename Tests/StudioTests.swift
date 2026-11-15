import XCTest
import AVFoundation
import Vision
import WebKit
import UIKit
import Darwin
@testable import ThreadsStudio

@MainActor final class StudioTests: XCTestCase {
    func testLongTextAndSpeechRhythm() throws {
        let project = Project(),source = String(repeating: "Bình luận dài.\nÝ tiếp theo :)) ",count: 90)
        XCTAssertEqual(SpeechText.pages(source).joined(),source)
        let spoken = try SpeechText.spoken("kh vội.\nđc rồi :))",project: project)
        XCTAssertTrue(spoken.contains("không vội"));XCTAssertTrue(spoken.contains("được rồi"));XCTAssertTrue(spoken.contains("ha ha"))
        let sentences = SpeechText.sentences("Câu thứ nhất. Câu thứ hai!\nCâu thứ ba.",project: project)
        XCTAssertEqual(sentences.count,3);XCTAssertEqual(sentences[0].1,0.45);XCTAssertEqual(sentences[1].1,0.7);XCTAssertEqual(sentences[2].1,0)
        let link = "https://example.com/ko user@ko.com"
        XCTAssertEqual(try SpeechText.spoken(link,project: project),link)
    }
    func testRankingAndRoundTrip() throws {
        var project = Project();project.author = "owner";project.commentCount = 1
        project.comments = [ThreadComment(id: "1",author: "popular",text: "Hi",likes: 99),ThreadComment(id: "2",author: "author-liked",text: "Hello",authorLiked: true)]
        project.photos = [PostPhoto(asset: "Media/first.png",seconds: 17),PostPhoto(asset: "Media/second.png",seconds: 4)]
        project.sounds = ["Media/effect.mp3"];project.channelName = "Channel";project.outroEnabled = true
        let loaded = try JSONDecoder().decode(Project.self,from: JSONEncoder().encode(project))
        XCTAssertEqual(loaded.selectedComments().first?.id,"2");XCTAssertEqual(loaded.photos.map(\.seconds),[17,4]);XCTAssertEqual(loaded.channelName,"Channel")
    }
    func testURLAndMediaPathBoundaries() throws {
        XCTAssertNoThrow(try ThreadScanner.postURL("https://www.threads.com/@owner/post/Abc_123"))
        for path in ["http://threads.com/@a/post/b","https://threads.com.evil.test/@a/post/b","https://x:y@threads.com/@a/post/b","https://threads.com/@a"] { XCTAssertThrowsError(try ThreadScanner.postURL(path)) }
        for path in ["../project.json","/etc/passwd","bundle:../Info.plist","Media/../../Info.plist"] { XCTAssertThrowsError(try ProjectStore.url(path)) }
    }
    func testExportsRealPortraitMP4WithTimedCardsAndFullEffect() async throws {
        var project = Project();project.text = "First sentence";project.author = "first"
        project.comments = [ThreadComment(id: "1",author: "second",text: "Second comment")]
        project.readAloud = false;project.backgroundEnabled = false;project.auxiliaryEnabled = false;project.musicEnabled = false
        project.effectMode = "every"
        project.outroEnabled = true;project.channelName = "Channel";project.outroText = "Follow the channel"
        var wave = Data("RIFF".utf8)
        func u32(_ value: UInt32) -> Data { var number = value.littleEndian;return withUnsafeBytes(of: &number) { Data($0) } }
        func u16(_ value: UInt16) -> Data { var number = value.littleEndian;return withUnsafeBytes(of: &number) { Data($0) } }
        let samples: UInt32 = 28800
        wave.append(u32(36+samples*2));wave.append(Data("WAVEfmt ".utf8));wave.append(u32(16));wave.append(u16(1));wave.append(u16(1));wave.append(u32(48000));wave.append(u32(96000));wave.append(u16(2));wave.append(u16(16));wave.append(Data("data".utf8));wave.append(u32(samples*2));wave.append(Data(repeating: 0,count: Int(samples)*2))
        let sound = try ProjectStore.store(wave,extension: "wav");project.sounds = [sound]
        defer { if let url = try? ProjectStore.url(sound) { try? FileManager.default.removeItem(at: url) } }
        let output = try await VideoRenderer().render(project: project) { _,_ in }
        defer { try? FileManager.default.removeItem(at: output) }
        let asset = AVURLAsset(url: output),duration = try await asset.load(.duration).seconds
        XCTAssertEqual(duration,6.6,accuracy: 0.15)
        let videos = try await asset.loadTracks(withMediaType: .video)
        let size = try await videos.first?.load(.naturalSize)
        XCTAssertEqual(size,CGSize(width: 1080,height: 1920))
        let audio = try await asset.loadTracks(withMediaType: .audio);XCTAssertFalse(audio.isEmpty)
        let generator = AVAssetImageGenerator(asset: asset);generator.appliesPreferredTrackTransform = true
        for (seconds,expected) in [(0.4,"first"),(2.35,"second"),(3.3,"follow")] {
            let image = try await generator.image(at: CMTime(seconds: seconds,preferredTimescale: 600)).image
            let request = VNRecognizeTextRequest();request.recognitionLanguages = ["en-US"]
            try VNImageRequestHandler(cgImage: image).perform([request])
            let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ").lowercased()
            XCTAssertTrue(text.contains(expected),"Wrong/blank card at \(seconds): \(text)")
        }
    }

    func testEffectScheduleAllowsGapsConsecutiveAndPerCommentChoices() throws {
        var project = Project();project.effectMode = "random";project.effectProbability = 0.35
        var draws = [0.8,0.7,0.1,0.2]
        XCTAssertEqual((0..<4).map { EffectSchedule.shouldPlay(project,index: $0,override: nil,draw: { draws.removeFirst() }) },[false,false,true,true])
        project.effectMode = "fixed";project.effectEvery = 3
        XCTAssertEqual((0..<6).map { EffectSchedule.shouldPlay(project,index: $0,override: nil) },[false,false,true,false,false,true])
        XCTAssertTrue(EffectSchedule.shouldPlay(project,index: 0,override: true))
        XCTAssertFalse(EffectSchedule.shouldPlay(project,index: 2,override: false))
        project.soundsEnabled = false
        XCTAssertFalse(EffectSchedule.shouldPlay(project,index: 0,override: true))
    }

    func testOldDraftKeepsValuesAndGetsNewVoiceAndEffectDefaults() throws {
        var project = Project();project.channelName = "My old channel";project.speed = 0.8
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(project)) as! [String:Any]
        for key in ["voiceEngine","effectMode","effectProbability","effectEvery","blurBackground","quietScan"] { json.removeValue(forKey: key) }
        let restored = try Project.decodeSaved(JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(restored.channelName,"My old channel");XCTAssertEqual(restored.speed,0.8)
        XCTAssertEqual(restored.voiceEngine,"desktop");XCTAssertEqual(restored.effectMode,"random")
        XCTAssertTrue(restored.quietScan)
    }

    func testDesktopVoiceActuallyGeneratesSpeech() async throws {
        let began = Date()
        let destination = FileManager.default.urls(for: .documentDirectory,in: .userDomainMask)[0].appendingPathComponent("native-voice-test.wav")
        try await DesktopVoice().write("Xin chào các bạn. Đây là giọng mẫu trên máy tính.",destination: destination)
        let length = try await audioDuration(destination)
        XCTAssertGreaterThan(length,1);XCTAssertLessThan(length,30)
        let file = try AVAudioFile(forReading: destination)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)
        let samples = UnsafeBufferPointer(start: buffer.floatChannelData![0],count: Int(buffer.frameLength))
        XCTAssertGreaterThan(samples.map { abs($0) }.max() ?? 0,0.01)
        var usage = rusage();getrusage(RUSAGE_SELF,&usage)
        print("Desktop voice: audio \(length) s, wall \(Date().timeIntervalSince(began)) s, peak RSS \(Double(usage.ru_maxrss)/1048576) MiB (Simulator)")
    }

    func testOwnWebViewCanSnapshotWhileCoveredByNativeUI() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene),controller = UIViewController()
        window.rootViewController = controller;window.makeKeyAndVisible()
        defer { window.isHidden = true;previous?.makeKeyAndVisible() }
        let scanner = ThreadScanner(),web = scanner.webView
        web.frame = CGRect(x: 0,y: 80,width: 320,height: 240);controller.view.addSubview(web)
        let cover = UIView(frame: web.frame);cover.backgroundColor = .black;controller.view.addSubview(cover)
        web.loadHTMLString("<html><meta name='viewport' content='width=device-width'><body style='margin:0;background:rgb(230,20,30);color:white;font:24px sans-serif'>Own WebView snapshot</body></html>",baseURL: nil)
        for _ in 0..<100 { if scanner.loaded { break };try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertTrue(scanner.loaded)
        try await Task.sleep(for: .milliseconds(300))
        let config = WKSnapshotConfiguration();config.rect = CGRect(x: 0,y: 0,width: 300,height: 180)
        let snapshot = try await web.takeSnapshot(configuration: config)
        let image = try XCTUnwrap(snapshot.cgImage),request = VNRecognizeTextRequest();request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: image).perform([request])
        let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ").lowercased()
        XCTAssertTrue(text.contains("webview"),"Covered WebView produced a blank snapshot: \(text)")
        XCTAssertTrue(cover.superview === controller.view)
    }

    func testFullDesktopVoiceVideoIncludesSpeechAndRealSentencePause() async throws {
        var project = Project();project.text = "Xin chào các bạn. Đây là một câu khác."
        project.comments = [];project.backgroundEnabled = false;project.auxiliaryEnabled = false;project.musicEnabled = false
        project.voiceEngine = "desktop";project.speed = 0.8;project.sentencePause = 1.1
        let output = try await VideoRenderer().render(project: project) { _,_ in }
        defer { try? FileManager.default.removeItem(at: output) }
        let asset = AVURLAsset(url: output),tracks = try await asset.loadTracks(withMediaType: .audio)
        let track = try XCTUnwrap(tracks.first),reader = try AVAssetReader(asset: asset)
        let decoded = AVAssetReaderTrackOutput(track: track,outputSettings: [AVFormatIDKey:kAudioFormatLinearPCM,AVLinearPCMBitDepthKey:32,AVLinearPCMIsFloatKey:true,AVLinearPCMIsNonInterleaved:false])
        reader.add(decoded);XCTAssertTrue(reader.startReading())
        var all: [Float] = [],channels = 0,rate = 0.0
        while let sample = decoded.copyNextSampleBuffer() {
            if let format = CMSampleBufferGetFormatDescription(sample),let description = CMAudioFormatDescriptionGetStreamBasicDescription(format) {
                channels = Int(description.pointee.mChannelsPerFrame);rate = description.pointee.mSampleRate
            }
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            let size = CMBlockBufferGetDataLength(block)
            var samples = [Float](repeating: 0,count: size/4)
            let status = samples.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(block,atOffset: 0,dataLength: size,destination: $0.baseAddress!) }
            XCTAssertEqual(status,kCMBlockBufferNoErr);all += samples
        }
        XCTAssertEqual(reader.status,.completed);XCTAssertGreaterThan(all.map { abs($0) }.max() ?? 0,0.01)
        XCTAssertGreaterThan(channels,0);XCTAssertGreaterThan(rate,0)
        let window = max(1,Int(rate*Double(channels)*0.05))
        var quiet = 0,longest = 0
        for start in stride(from: 0,to: all.count,by: window) {
            let values = all[start..<min(start+window,all.count)]
            let energy = values.reduce(0.0) { $0+Double($1*$1) }/Double(values.count)
            if energy < 0.000001 { quiet += 1;longest = max(longest,quiet) } else { quiet = 0 }
        }
        XCTAssertGreaterThanOrEqual(Double(longest)*0.05,0.8,"Configured sentence silence was lost during pitch-preserving speed change/export")
        let length = try await mediaDuration(output)
        XCTAssertGreaterThan(length,3)
    }
}
