import SwiftUI
import AVKit
import Photos
import UniformTypeIdentifiers

@MainActor final class ExportJob: ObservableObject {
    @Published var busy = false
    @Published var progress = 0.0
    @Published var status = "Sẵn sàng xuất 1080×1920 · MP4"
    @Published var output: URL?
    private var task: Task<Void,Never>?
    func start(store: ProjectStore) {
        guard !busy else { return };store.save();busy = true
        let snapshot = store.project
        UIApplication.shared.isIdleTimerDisabled = true
        task = Task {
            defer { busy = false;UIApplication.shared.isIdleTimerDisabled = false }
            do {
                let result = try await VideoRenderer().render(project: snapshot) { [weak self] value,message in self?.progress = value;self?.status = message }
                output = result
            } catch is CancellationError { status = "Đã dừng; video đã xuất trước đó được giữ nguyên." }
            catch { status = "Xuất thất bại";store.message = error.localizedDescription }
        }
    }
    func cancel() { task?.cancel() }
    func saveToPhotos(store: ProjectStore) {
        guard let output else { return }
        Task {
            let permission = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard permission == .authorized || permission == .limited else { store.message = "Chưa được phép thêm video vào Ảnh. Bạn vẫn có thể dùng nút Chia sẻ để lưu vào Tệp.";return }
            do {
                try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: output) }
                status = "Đã lưu video vào Ảnh."
            } catch { store.message = error.localizedDescription }
        }
    }
}

enum ImportRole: String,Identifiable {
    case photos,logo,sounds,backgrounds,auxiliaryVideos,music
    var id: String { rawValue }
    var types: [UTType] {
        switch self { case .photos,.logo:return [.image];case .backgrounds,.auxiliaryVideos:return [.movie];case .sounds,.music:return [.audio] }
    }
}

struct ContentView: View {
    @StateObject private var store = ProjectStore()
    @StateObject private var scanner = ThreadScanner()
    @StateObject private var export = ExportJob()
    @Environment(\.scenePhase) private var scenePhase
    @State private var browser = false
    @State private var autoScan = false
    @State private var importing = false
    @State private var importRole = ImportRole.photos
    @State private var commentSoundTarget: String?
    @State private var voicePreview = AVSpeechSynthesizer()

    var body: some View {
        TabView {
            NavigationStack { draft.navigationTitle("Threads Studio") }.tabItem { Label("Bài viết",systemImage: "text.bubble.fill") }
            NavigationStack { voice.navigationTitle("Giọng & nhịp đọc") }.tabItem { Label("Giọng đọc",systemImage: "waveform") }
            NavigationStack { media.navigationTitle("Video & âm thanh") }.tabItem { Label("Media",systemImage: "film.stack.fill") }
            NavigationStack { layout.navigationTitle("Bố cục & xuất") }.tabItem { Label("Xuất video",systemImage: "square.and.arrow.up.fill") }
        }
        .tint(Color(red: 0.57,green: 0.53,blue: 1))
        .preferredColorScheme(.dark)
        .safeAreaInset(edge: .top,spacing: 0) {
            HStack { Image(systemName: "circle.dotted.circle.fill");Text("THREADS STUDIO").font(.caption.bold());Spacer();Text(store.saveStatus).font(.caption2).foregroundStyle(store.saveStatus == "Lưu thất bại" ? Color.red : Color.secondary) }.padding(.horizontal,20).padding(.vertical,8).background(.ultraThinMaterial)
        }
        .sheet(isPresented: $browser,onDismiss: { scanner.stop() }) { browserSheet }
        .fileImporter(isPresented: $importing,allowedContentTypes: importRole.types,allowsMultipleSelection: importRole != .logo) { result in
            do {
                for url in try result.get() {
                    let asset = try ProjectStore.importFile(url,image: importRole == .photos || importRole == .logo)
                    store.project.assetNames[asset] = url.lastPathComponent
                    switch importRole {
                    case .photos:guard store.project.photos.count < 20 else { throw StudioError.message("Tối đa 20 ảnh bài viết.") };store.project.photos.append(PostPhoto(asset: asset))
                    case .logo:store.project.channelLogo = asset
                    case .sounds:
                        if let id = commentSoundTarget,let index = store.project.comments.firstIndex(where: { $0.id == id }) { store.project.comments[index].sounds.append(asset) }
                        else { store.project.sounds.append(asset) }
                    case .backgrounds:store.project.backgrounds.append(asset)
                    case .auxiliaryVideos:store.project.auxiliaryVideos.append(asset)
                    case .music:store.project.music.append(asset)
                    }
                }
            } catch { store.message = error.localizedDescription }
        }
        .alert("Threads Studio",isPresented: Binding(get: { store.message != nil },set: { if !$0 { store.message = nil } })) { Button("Đóng",role: .cancel) { store.message = nil } } message: { Text(store.message ?? "") }
        .onChange(of: scenePhase) { _,phase in if phase != .active { store.save() } }
    }

    private var draft: some View {
        Form {
            Section {
                TextField("Dán link bài viết Threads",text: $store.project.sourceURL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button { do { try scanner.open(store.project.sourceURL);autoScan = true;browser = true } catch { store.message = error.localizedDescription } } label: { Label("Quét bài viết tự động",systemImage: "sparkle.magnifyingglass") }.disabled(export.busy)
                Button("Đăng nhập Threads") { autoScan = false;scanner.login();browser = true }
                Text("Bạn tự đăng nhập trong trình duyệt của app. Phiên được giữ trên iPhone; không nhập mật khẩu vào ô cấu hình.").font(.caption).foregroundStyle(.secondary)
                if !scanner.storeWarning.isEmpty { Text(scanner.storeWarning).font(.caption).foregroundStyle(.orange) }
            } header: { Text("01 · Nguồn bài viết") }
            Section("Nội dung") {
                TextField("Tên tác giả",text: $store.project.author)
                TextEditor(text: $store.project.text).frame(minHeight: 130)
                Toggle("Che tên khi xuất",isOn: $store.project.hideNames)
            }
            Section {
                Toggle("Mở lần lượt ảnh sau caption",isOn: $store.project.openPhotos)
                Toggle("Đọc chữ trong ảnh khi mở",isOn: $store.project.readPhotos)
                Button { pick(.photos) } label: { Label("Thêm ảnh từ Tệp",systemImage: "photo.badge.plus") }
                ForEach($store.project.photos) { $photo in
                    VStack(alignment: .leading,spacing: 10) {
                        HStack {
                            thumbnail(photo.asset).frame(width: 64,height: 64).clipShape(RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading) { Text("Ảnh \((store.project.photos.firstIndex(where: { $0.id == photo.id }) ?? 0)+1)").font(.headline);Text("\(Int(photo.seconds)) giây · giữ lâu hơn nếu lời đọc chưa hết").font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            Button(role: .destructive) { store.project.photos.removeAll { $0.id == photo.id } } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                        }
                        Slider(value: $photo.seconds,in: 2...120,step: 1)
                        TextField("Chữ ảnh (để trống: tự nhận diện OCR)",text: $photo.text,axis: .vertical).font(.caption)
                        HStack {
                            Button("↑ Lên") { movePhoto(photo.id,offset: -1) }.buttonStyle(.borderless)
                            Button("↓ Xuống") { movePhoto(photo.id,offset: 1) }.buttonStyle(.borderless)
                        }.font(.caption)
                    }.padding(.vertical,6)
                }
            } header: { Text("Ảnh bài viết · \(store.project.photos.count)") }
            Section {
                Stepper("Đọc \(store.project.commentCount) bình luận",value: $store.project.commentCount,in: 0...100)
                Toggle("Ưu tiên tương tác từ tác giả",isOn: $store.project.prioritizeAuthor)
                Toggle("Chỉ bình luận có tương tác tác giả",isOn: $store.project.onlyAuthorInteraction)
                Toggle("Bao gồm bình luận của tác giả",isOn: $store.project.includeAuthor)
                Toggle("Xếp theo tim (tắt: tim + trả lời)",isOn: $store.project.sortByLikes)
                Text("Đã quét \(store.project.comments.count) · sẽ đọc \(store.project.selectedComments().count). Chỉ xếp hạng dữ liệu Threads đã tải được.").font(.caption).foregroundStyle(.secondary)
                ForEach($store.project.comments) { $comment in
                    VStack(alignment: .leading) {
                        HStack { Text(comment.author).font(.subheadline.bold());Spacer();Text("♥ \(comment.likes) · ↩ \(comment.replies)").font(.caption).foregroundStyle(.secondary) }
                        TextField("Bình luận",text: $comment.text,axis: .vertical)
                        if comment.authorLiked || comment.authorReplied { Label("Có tương tác của tác giả",systemImage: "checkmark.seal.fill").font(.caption2).foregroundStyle(.green) }
                        HStack {
                            Button("Gán tiếng riêng (\(comment.sounds.count))") { commentSoundTarget = comment.id;importRole = .sounds;importing = true }.buttonStyle(.borderless)
                            if !comment.sounds.isEmpty { Button("Bỏ tiếng riêng",role: .destructive) { comment.sounds = [] }.buttonStyle(.borderless) }
                        }.font(.caption)
                    }.padding(.vertical,3)
                }
                Button("Thêm bình luận thủ công") { store.project.comments.append(ThreadComment(id: UUID().uuidString,author: "nguoixem",text: "")) }
            } header: { Text("Bình luận") }
        }.scrollDismissesKeyboard(.interactively)
    }

    private var voice: some View {
        Form {
            Section {
                Toggle("Đọc nội dung bằng giọng nói",isOn: $store.project.readAloud)
                Picker("Giọng tiếng Việt trên iPhone",selection: $store.project.voiceID) {
                    Text("Tự chọn giọng tốt nhất").tag("")
                    ForEach(AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("vi") },id: \.identifier) { voice in Text(voice.name).tag(voice.identifier) }
                }
                Text("Dùng giọng iOS, không phải giọng VieNeu trong video mẫu Windows. Có thể tải thêm giọng tiếng Việt trong Cài đặt > Trợ năng > Nội dung được đọc.").font(.caption).foregroundStyle(.secondary)
                valueSlider("Tốc độ",value: $store.project.speed,range: 0.5...2,step: 0.05,suffix: "×")
                valueSlider("Nghỉ giữa câu",value: $store.project.sentencePause,range: 0...2,step: 0.05,suffix: "giây")
                valueSlider("Nghỉ xuống dòng",value: $store.project.paragraphPause,range: 0...3,step: 0.05,suffix: "giây")
                Text("Khoảng nghỉ được ghép vào video, giữ nguyên khi đổi tốc độ. Đặt dấu câu hoặc xuống dòng để ngắt đúng ý.").font(.caption).foregroundStyle(.secondary)
                Button("Nghe giọng iPhone") {
                    voicePreview.stopSpeaking(at: .immediate)
                    let utterance = AVSpeechUtterance(string: "Mình sẽ đọc chậm và rõ. Còn đây là câu tiếp theo.")
                    utterance.voice = AVSpeechSynthesisVoice(identifier: store.project.voiceID) ?? AVSpeechSynthesisVoice(language: "vi-VN")
                    utterance.rate = AVSpeechUtteranceDefaultSpeechRate*Float(store.project.speed);voicePreview.speak(utterance)
                }
            } header: { Text("02 · Giọng đọc độc lập trên iPhone") }
            Section("Cách đọc") {
                Toggle("Chuẩn hóa từ viết tắt, :)) và emoji",isOn: $store.project.normalizeWords)
                TextEditor(text: $store.project.speechRules).frame(minHeight: 180).font(.system(.body,design: .monospaced))
                Text("Mỗi dòng: từ=cách đọc. Chỉ đổi lời đọc, giữ nguyên chữ trên thẻ.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var media: some View {
        Form {
            Section {
                Toggle("Sound effect sau bình luận",isOn: $store.project.soundsEnabled)
                Stepper("\(store.project.soundCount) sound effect / bình luận",value: $store.project.soundCount,in: 0...5)
                valueSlider("Âm lượng hiệu ứng",value: $store.project.soundVolume,range: 0...1,step: 0.05,suffix: "")
                Button("Thêm nhiều MP3 / âm thanh") { pick(.sounds) }
                mediaList($store.project.sounds)
                Text("Thẻ bình luận giữ nguyên đến hết toàn bộ tiếng hiệu ứng. Để trống danh sách để dùng kho tích hợp, chọn ngẫu nhiên theo nhóm từ khóa. Kho tích hợp là bản chụp đã chọn, không tự cập nhật bảng hot.").font(.caption).foregroundStyle(.secondary)
            } header: { Text("03 · Hiệu ứng") }
            Section {
                Toggle("Video nền",isOn: $store.project.backgroundEnabled)
                Button("Thêm nhiều video nền") { pick(.backgrounds) };mediaList($store.project.backgrounds)
                Toggle("Video thu hút bên dưới thẻ",isOn: $store.project.auxiliaryEnabled)
                Button("Thêm nhiều video phụ") { pick(.auxiliaryVideos) };mediaList($store.project.auxiliaryVideos)
                Text("Mỗi lần xuất chọn một video ngẫu nhiên từ từng danh sách. Nếu để trống, dùng kho video tích hợp. Video giữ trọn tỉ lệ gốc và phát lặp đến cuối.").font(.caption).foregroundStyle(.secondary)
            } header: { Text("Video") }
            Section {
                Toggle("Nhạc nền",isOn: $store.project.musicEnabled)
                valueSlider("Âm lượng nhạc",value: $store.project.musicVolume,range: 0...1,step: 0.02,suffix: "")
                Button("Thêm nhiều bài nhạc") { pick(.music) };mediaList($store.project.music)
                Text("Mỗi lần xuất chọn ngẫu nhiên một bài. Để trống để dùng kho tích hợp.").font(.caption).foregroundStyle(.secondary)
            } header: { Text("Nhạc nền") }
        }
    }

    private var layout: some View {
        Form {
            Section("04 · Vị trí thẻ") {
                valueSlider("Ngang",value: $store.project.cardX,range: 0...1,step: 0.01,suffix: "")
                valueSlider("Dọc",value: $store.project.cardY,range: 0...1,step: 0.01,suffix: "")
                valueSlider("Kích thước",value: $store.project.cardScale,range: 0.3...1,step: 0.01,suffix: "")
            }
            Section("Video phụ") {
                Toggle("Tự giữ dưới thẻ",isOn: $store.project.auxiliaryBelowCard)
                valueSlider("Ngang",value: $store.project.auxiliaryX,range: 0...1,step: 0.01,suffix: "")
                valueSlider("Dọc",value: $store.project.auxiliaryY,range: 0...1,step: 0.01,suffix: "")
                valueSlider("Kích thước",value: $store.project.auxiliaryScale,range: 0.3...1,step: 0.01,suffix: "")
            }
            Section("Kết video") {
                Toggle("Thêm kết video và đọc lời kêu gọi",isOn: $store.project.outroEnabled)
                TextField("Tên kênh",text: $store.project.channelName)
                Button("Chọn logo kênh") { pick(.logo) }
                if !store.project.channelLogo.isEmpty { thumbnail(store.project.channelLogo).frame(height: 70);Button("Bỏ logo",role: .destructive) { store.project.channelLogo = "" } }
                TextField("Lời kêu gọi cuối video",text: $store.project.outroText,axis: .vertical)
            }
            Section {
                Button { export.start(store: store) } label: { Label("Tạo video MP4 trên iPhone",systemImage: "sparkles").frame(maxWidth: .infinity).padding(.vertical,8) }.buttonStyle(.borderedProminent).disabled(export.busy)
                ProgressView(value: export.progress)
                Text(export.status).font(.caption)
                if export.busy { Button("Dừng",role: .destructive) { export.cancel() } }
                Text("Giữ app mở trong khi xuất. Video lưu trong Tệp > Trên iPhone > Threads Studio. Xuất 1080×1920, 24 fps; không gửi video lên máy chủ.").font(.caption).foregroundStyle(.secondary)
                if let url = export.output {
                    VideoPlayer(player: AVPlayer(url: url)).frame(height: 300).clipShape(RoundedRectangle(cornerRadius: 16))
                    ShareLink(item: url) { Label("Chia sẻ / Lưu vào Tệp",systemImage: "square.and.arrow.up") }
                    Button("Lưu vào Ảnh") { export.saveToPhotos(store: store) }
                }
            } header: { Text("Xuất video") }
        }.disabled(scanner.busy)
    }

    private var browserSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text(scanner.status).font(.caption).frame(maxWidth: .infinity,alignment: .leading).padding()
                HStack {
                    Button("Quét lại") { scanner.start(store: store) { browser = false } }.disabled(scanner.busy)
                    Spacer()
                    if scanner.busy { ProgressView();Button("Dừng") { scanner.stop() } }
                }.padding(.horizontal).padding(.bottom,10)
                ThreadsBrowserView(scanner: scanner)
            }.navigationTitle("Threads · đăng nhập & quét").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Đóng") { scanner.stop();browser = false } } }
                .task { if autoScan { autoScan = false;scanner.start(store: store) { browser = false } } }
        }
    }

    private func pick(_ role: ImportRole) { commentSoundTarget = nil;importRole = role;importing = true }
    private func movePhoto(_ id: UUID,offset: Int) {
        guard let index = store.project.photos.firstIndex(where: { $0.id == id }),store.project.photos.indices.contains(index+offset) else { return }
        store.project.photos.swapAt(index,index+offset)
    }
    private func valueSlider(_ title: String,value: Binding<Double>,range: ClosedRange<Double>,step: Double,suffix: String) -> some View {
        VStack(alignment: .leading) { HStack { Text(title);Spacer();Text("\(value.wrappedValue,specifier: "%.2f") \(suffix)").foregroundStyle(.secondary).monospacedDigit() };Slider(value: value,in: range,step: step) }
    }
    @ViewBuilder private func thumbnail(_ asset: String) -> some View {
        if let url = try? ProjectStore.url(asset),let image = UIImage(contentsOfFile: url.path) { Image(uiImage: image).resizable().scaledToFit() }
        else { Image(systemName: "photo").foregroundStyle(.secondary) }
    }
    private func mediaList(_ files: Binding<[String]>) -> some View {
        ForEach(files.wrappedValue,id: \.self) { asset in
            HStack { Text(store.project.assetNames[asset] ?? URL(fileURLWithPath: asset).lastPathComponent).font(.caption).lineLimit(1);Spacer();Button(role: .destructive) { files.wrappedValue.removeAll { $0 == asset } } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.borderless) }
        }
    }
}
