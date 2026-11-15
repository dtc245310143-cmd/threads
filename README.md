# Threads Studio · iPhone độc lập 1.1.0

Ứng dụng SwiftUI cho iPhone **iOS 17 trở lên**, xử lý và xuất MP4 bằng AVFoundation trên điện thoại. Không cần chạy bản Windows hoặc máy chủ xử lý video. Internet cần khi đăng nhập/quét Threads; sau khi đã có dữ liệu, media và bộ giọng PC tích hợp trên máy, có thể dựng video tại chỗ.

## Build IPA bằng GitHub Actions

1. Mở **Actions → Build iPhone IPA → Run workflow**, hoặc push thay đổi lên `main`.
2. Workflow kiểm tra bộ quét, biên dịch và chạy kiểm tra native trên Simulator, xuất thử MP4 có ảnh/thẻ theo thời gian và sound effect, rồi build **arm64 cho iPhone thật**.
3. Sau khi thành công, tải artifact **ThreadsStudio-iPhone-unsigned**, giải nén lấy `ThreadsStudio.ipa` và tệp SHA-256.
4. Mở iLoader trên máy tính, chọn IPA để ký/cài bằng tài khoản Apple của bạn. Tài khoản Apple chỉ đăng nhập trong iLoader; không đưa mật khẩu vào app hoặc GitHub.

IPA chưa ký là định dạng đầu vào cho công cụ sideload ký lại; không phải file EXE đổi đuôi. Thời hạn/điều kiện cài phụ thuộc tài khoản ký và iLoader. Hướng dẫn chính thức: https://github.com/nab138/iloader

Nếu có Mac/Xcode: chạy `bash scripts/build_ipa.sh`; kết quả ở `dist/ThreadsStudio.ipa`. Build bộ giọng native cần CMake và Rust (rustup), được chuẩn bị trong workflow; không cần khóa API. Mô hình và từ điển được tải/kiểm tra SHA-256 ở bước build, sau đó đóng gói trong IPA.

## Chức năng trong mã iOS

- Đăng nhập trong WKWebView riêng của app, dùng lại phiên trên iPhone. Quét kín giữ trang trong cùng cửa sổ, phía sau màn hình điều khiển; chụp bằng API WebKit của chính app. Khi lỗi/cần xác minh sẽ mở trang để xử lý. Không truy cập hay chụp giao diện app Threads riêng. Quét tự động ảnh gốc theo thứ tự và dữ liệu bình luận từ trang/GraphQL mà trang Threads đã tải. Không lấy phiên Cốc Cốc từ Windows, không lưu mật khẩu vào dự án.
- Ưu tiên bình luận có tương tác từ tác giả, tim/trả lời; chọn số lượng. Chỉ xác nhận tác giả trả lời khi chuỗi dữ liệu có bằng chứng; không suy đoán từ việc bình luận gửi đến tác giả.
- Chụp khung Threads thật nếu tìm được DOM; bình luận dài phân trang và đọc đủ. Nếu không chụp được, dựng thẻ chữ đầy đủ và báo trong app. Sửa chữ hoặc che tên sẽ dùng thẻ dựng lại.
- Mở ảnh lần lượt sau caption; chỉnh thời gian từng ảnh; OCR và đọc chữ khi mở ảnh; giữ ảnh đến hết lời. Có thể tự sửa chữ OCR.
- Giọng PC: VieNeu v3 Turbo cùng phiên bản mô hình và cùng dữ liệu mẫu giọng của Windows 2.9.3. Chạy native CPU trên iPhone, có nút nghe thử; giọng iOS chỉ là lựa chọn dự phòng. Tốc độ mặc định 0,95×; nghỉ giữa câu 0,45 giây, xuống dòng 0,7 giây. Chỉnh tốc độ/khoảng nghỉ/bảng từ viết tắt.
- Nhập nhiều ảnh, video, MP3 từ Tệp; chọn ngẫu nhiên nền, video phụ, nhạc mỗi lần xuất. Video phụ giữ tỉ lệ gốc, chỉnh vị trí và kích thước; tự giữ dưới thẻ. Giọng và nhạc/hiệu ứng được trộn riêng.
- Sound effect sau bình luận: mọi bình luận, mỗi N bình luận hoặc xác suất độc lập (mặc định 35%, cho phép phát liên tiếp). Mỗi bình luận có lựa chọn Theo chế độ chung / Có / Không. Chọn số lượng và âm lượng, gán riêng cho từng bình luận; giữ thẻ đến hết toàn bộ tiếng. Kho tích hợp chọn theo nhóm từ khóa, không hiểu ngữ cảnh sâu.
- Logo, tên kênh và lời kêu gọi được đọc ở cuối. Tự lưu bản nháp và toàn bộ tùy chỉnh, sao lưu trước khi ghi đè. Media nhập được chép vào vùng dữ liệu app.
- MP4 dọc 1080×1920, 24 fps; chia sẻ, lưu vào Tệp hoặc Ảnh. Khi xuất thất bại/hủy, video cũ được giữ.

## Khác biệt và giới hạn cần biết

- Bộ giọng PC tích hợp dùng gói GGUF Q8_0 do tác giả phát hành, codec f16; Windows dùng ONNX fp32. Cùng speaker embedding và 75 khung mã giọng từ mẫu gốc, nhưng không hứa đầu ra giống từng bit vì lượng tử hóa và việc sinh giọng ngẫu nhiên. Thông tin/checksum tại `Library/voice/reference-info.json`, nguồn và phiên bản tại `Native/DEPENDENCIES.md`. Chưa đo tốc độ/bộ nhớ trên iPhone 14 Plus thật.
- Chưa có trình tải TikTok/YouTube/Myinstants hot trực tiếp. Nhập video/âm thanh đã có từ Tệp. Kho Myinstants tích hợp là snapshot đã chọn từ bản Windows, có nguồn kèm theo; không phải bảng hot thời gian thực.
- Có làm mờ nền; chưa có đổi ngẫu nhiên nhiều giọng theo từng bình luận như bản Windows.
- OCR phụ thuộc ngôn ngữ Vision mà iOS hỗ trợ, có thể sai tiếng Việt; kiểm tra/sửa phần chữ ảnh trước khi xuất.
- Threads có thể đổi DOM, giới hạn bình luận, yêu cầu xác minh hoặc không cho đăng nhập trong WebView. App sẽ báo lỗi/thiếu dữ liệu thay vì bịa kết quả. Số bình luận được xếp hạng chỉ là số quét được.
- Giữ app mở khi dựng video; iOS có thể dừng tác vụ khi ra nền. Giới hạn 120 cảnh/30 phút mỗi lần xuất để tránh hết bộ nhớ, không âm thầm cắt bình luận. Media nhập tối đa 300 MB/tệp; ảnh gốc tải tối đa 25 MB.
- Xóa ứng dụng sẽ xóa bản nháp và media trong app; hãy lưu MP4 vào Ảnh/Tệp trước khi gỡ.

Kho nhạc/video/hiệu ứng có ghi nguồn trong `ThreadsStudio/Library/SOURCES.txt` và manifest. Các giấy phép nguồn vẫn áp dụng. Kho hiện tại lấy từ bản PC 2.9.3: 6 bài nhạc, 9 video nền khác, video parkour TikTok đã chọn và kho Myinstants đang dùng đã cập nhật gồm 19 tiếng. Giữ nguồn/giấy phép trong manifest; không coi mọi asset là miễn bản quyền. Các tệp tải lên riêng khác không được tự lấy thêm.

## Kiểm tra

`node Tests/scan.test.cjs` chạy trên Windows/macOS. Kiểm tra Swift và xuất MP4 thật cần Xcode/iOS Simulator; không coi kiểm tra mã tĩnh trên Windows là biên dịch iOS thành công. Workflow phải xanh và IPA phải qua `scripts/verify_ipa.py` trước khi đưa ra cài.

Bản nháp 1.0 được nâng cấp bằng cách bổ sung các trường mới còn thiếu, giữ nguyên các tùy chỉnh cũ. Lựa chọn hiệu ứng riêng/tiếng riêng theo ID bình luận được giữ khi quét lại. Khi chọn giọng PC, dừng xuất có thể cần chờ hết cụm đang sinh; giọng không được gửi đi máy chủ.

## Quét kín

Bật **Quét kín · giữ màn hình điều khiển**, dán link rồi bấm Quét. Trang Threads được giữ trong WebView của app, gắn vào cửa sổ nhưng được màn hình điều khiển che lại; không đặt WebView ra ngoài màn hình hoặc `isHidden` để tránh ảnh trắng. Đăng nhập một lần bằng nút Đăng nhập Threads. Phiên này độc lập với phiên trong app Threads chính thức.

iOS không cho ứng dụng này đọc/chụp tùy ý giao diện ứng dụng khác. Quét kín cần Threads Studio ở foreground; khi chuyển app, tác vụ quét sẽ dừng và giữ dữ liệu trước đó. Chỉ sau khi quét thành công mới thay bản nháp.
