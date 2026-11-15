import XCTest
import AVFoundation
import Vision
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
        for key in ["voiceEngine","effectMode","effectProbability","effectEvery","blurBackground"] { json.removeValue(forKey: key) }
        let restored = try Project.decodeSaved(JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(restored.channelName,"My old channel");XCTAssertEqual(restored.speed,0.8)
        XCTAssertEqual(restored.voiceEngine,"desktop");XCTAssertEqual(restored.effectMode,"random")
    }

    func testDesktopVoiceActuallyGeneratesSpeech() async throws {
        let destination = FileManager.default.urls(for: .documentDirectory,in: .userDomainMask)[0].appendingPathComponent("native-voice-test.wav")
        try await DesktopVoice().write("Xin chào các bạn. Đây là giọng mẫu trên máy tính.",destination: destination)
        let length = try await audioDuration(destination)
        XCTAssertGreaterThan(length,1);XCTAssertLessThan(length,30)
        let file = try AVAudioFile(forReading: destination)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)
        let samples = UnsafeBufferPointer(start: buffer.floatChannelData![0],count: Int(buffer.frameLength))
        XCTAssertGreaterThan(samples.map { abs($0) }.max() ?? 0,0.01)
    }
}
