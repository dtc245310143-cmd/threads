# Threads Studio · iPhone độc lập

Ứng dụng SwiftUI cho iPhone **iOS 17 trở lên**, xử lý và xuất MP4 bằng AVFoundation trên điện thoại. Không cần chạy bản Windows hoặc máy chủ xử lý video. Internet cần khi đăng nhập/quét Threads; sau khi đã có dữ liệu, media và giọng iOS trên máy, có thể dựng video tại chỗ.

## Build IPA bằng GitHub Actions

1. Mở **Actions → Build iPhone IPA → Run workflow**, hoặc push thay đổi lên `main`.
2. Workflow kiểm tra bộ quét, biên dịch và chạy kiểm tra native trên Simulator, xuất thử MP4 có ảnh/thẻ theo thời gian và sound effect, rồi build **arm64 cho iPhone thật**.
3. Sau khi thành công, tải artifact **ThreadsStudio-iPhone-unsigned**, giải nén lấy `ThreadsStudio.ipa` và tệp SHA-256.
4. Mở iLoader trên máy tính, chọn IPA để ký/cài bằng tài khoản Apple của bạn. Tài khoản Apple chỉ đăng nhập trong iLoader; không đưa mật khẩu vào app hoặc GitHub.

IPA chưa ký là định dạng đầu vào cho công cụ sideload ký lại; không phải file EXE đổi đuôi. Thời hạn/điều kiện cài phụ thuộc tài khoản ký và iLoader. Hướng dẫn chính thức: https://github.com/nab138/iloader

Nếu có Mac/Xcode: chạy `bash scripts/build_ipa.sh`; kết quả ở `dist/ThreadsStudio.ipa`. Mã không cần dependency bên thứ ba hoặc khóa API để build.

## Chức năng trong mã iOS

- Đăng nhập trong WKWebView riêng của app, dùng lại phiên trên iPhone. Quét tự động ảnh gốc theo thứ tự và dữ liệu bình luận từ trang/GraphQL mà trang Threads đã tải. Không lấy phiên Cốc Cốc từ Windows, không lưu mật khẩu vào dự án.
- Ưu tiên bình luận có tương tác từ tác giả, tim/trả lời; chọn số lượng. Chỉ xác nhận tác giả trả lời khi chuỗi dữ liệu có bằng chứng; không suy đoán từ việc bình luận gửi đến tác giả.
- Chụp khung Threads thật nếu tìm được DOM; bình luận dài phân trang và đọc đủ. Nếu không chụp được, dựng thẻ chữ đầy đủ và báo trong app. Sửa chữ hoặc che tên sẽ dùng thẻ dựng lại.
- Mở ảnh lần lượt sau caption; chỉnh thời gian từng ảnh; OCR và đọc chữ khi mở ảnh; giữ ảnh đến hết lời. Có thể tự sửa chữ OCR.
- Giọng tiếng Việt do iOS cung cấp, tốc độ mặc định 0,95×; nghỉ giữa câu 0,45 giây, xuống dòng 0,7 giây. Chỉnh tốc độ/khoảng nghỉ/bảng từ viết tắt.
- Nhập nhiều ảnh, video, MP3 từ Tệp; chọn ngẫu nhiên nền, video phụ, nhạc mỗi lần xuất. Video phụ giữ tỉ lệ gốc, chỉnh vị trí và kích thước; tự giữ dưới thẻ. Giọng và nhạc/hiệu ứng được trộn riêng.
- Sound effect sau bình luận; chọn số lượng và âm lượng, gán riêng cho từng bình luận; giữ thẻ đến hết toàn bộ tiếng. Kho tích hợp chọn theo nhóm từ khóa, không hiểu ngữ cảnh sâu.
- Logo, tên kênh và lời kêu gọi được đọc ở cuối. Tự lưu bản nháp và toàn bộ tùy chỉnh, sao lưu trước khi ghi đè. Media nhập được chép vào vùng dữ liệu app.
- MP4 dọc 1080×1920, 24 fps; chia sẻ, lưu vào Tệp hoặc Ảnh. Khi xuất thất bại/hủy, video cũ được giữ.

## Khác biệt và giới hạn cần biết

- **Chưa chuyển bộ giọng VieNeu/giọng mẫu IMG_8430 sang iOS.** Bản này dùng giọng tiếng Việt của iPhone, ghi rõ trong UI. Tải giọng nếu thiết bị chưa có. Không giả vờ giọng iOS giống giọng mẫu.
- Chưa có trình tải TikTok/YouTube/Myinstants hot trực tiếp. Nhập video/âm thanh đã có từ Tệp. Kho Myinstants tích hợp là snapshot đã chọn từ bản Windows, có nguồn kèm theo; không phải bảng hot thời gian thực.
- Chưa có làm mờ nền và nghe ngẫu nhiên nhiều giọng theo từng bình luận như bản Windows.
- OCR phụ thuộc ngôn ngữ Vision mà iOS hỗ trợ, có thể sai tiếng Việt; kiểm tra/sửa phần chữ ảnh trước khi xuất.
- Threads có thể đổi DOM, giới hạn bình luận, yêu cầu xác minh hoặc không cho đăng nhập trong WebView. App sẽ báo lỗi/thiếu dữ liệu thay vì bịa kết quả. Số bình luận được xếp hạng chỉ là số quét được.
- Giữ app mở khi dựng video; iOS có thể dừng tác vụ khi ra nền. Giới hạn 120 cảnh/30 phút mỗi lần xuất để tránh hết bộ nhớ, không âm thầm cắt bình luận. Media nhập tối đa 300 MB/tệp; ảnh gốc tải tối đa 25 MB.
- Xóa ứng dụng sẽ xóa bản nháp và media trong app; hãy lưu MP4 vào Ảnh/Tệp trước khi gỡ.

Kho nhạc/video/hiệu ứng có ghi nguồn trong `ThreadsStudio/Library/SOURCES.txt` và manifest. Các giấy phép nguồn vẫn áp dụng. Các video TikTok riêng và media riêng của người dùng không được đưa lên repository này.

## Kiểm tra

`node Tests/scan.test.cjs` chạy trên Windows/macOS. Kiểm tra Swift và xuất MP4 thật cần Xcode/iOS Simulator; không coi kiểm tra mã tĩnh trên Windows là biên dịch iOS thành công. Workflow phải xanh và IPA phải qua `scripts/verify_ipa.py` trước khi đưa ra cài.
