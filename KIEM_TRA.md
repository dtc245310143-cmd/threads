# Kiểm tra iOS 1.1.0

Build thành công trên GitHub Actions, commit mã ứng dụng `336c33484f235d7b93364f5b1100cb56401ee70b`:
https://github.com/dtc245310143-cmd/threads/actions/runs/43709681595

- Bộ quét JavaScript: giữ bản chữ dài nhất, ảnh đúng thứ tự, đúng gốc bài, chỉ xác nhận tác giả trả lời khi có bằng chứng trong chuỗi phản hồi.
- Cả 9 XCTest đạt trên Simulator arm64, Xcode 26.6: các kiểm tra cũ và giọng native, MP4 có giọng/khoảng nghỉ, lựa chọn sound effect, nâng cấp bản nháp, chụp WebView bị giao diện native che kín.
- Video thử 1080×1920 dài 6,6 giây: kiểm tra caption tại 0,4 giây, bình luận vẫn hiện tại 2,35 giây trong lúc phát hiệu ứng, lời kết tại 3,3 giây. Dùng OCR trên các khung hình đã giải mã từ MP4 để xác nhận nội dung hiện đúng thời điểm. Có audio track trong video.
- Giọng VieNeu native tạo được WAV 48 kHz dài 2,8 giây; toàn bộ mở mô hình và tạo giọng mất 3,17 giây, phần sinh giọng 1,33 giây. Peak RSS của tiến trình lúc đó khoảng 889 MiB. Đây là số đo Simulator, không phải số đo trên iPhone thật.
- MP4 dùng giọng native thật, tốc độ 0,8× và nghỉ 1,1 giây giữa câu: giải mã audio PCM từ MP4 để xác nhận có tiếng và khoảng im lặng ít nhất 0,8 giây; bài thử đạt. Thay đổi tốc độ giữ cao độ.
- WebView vẫn gắn trong cửa sổ, được UIView màu đen che kín: chụp bằng WebKit và dùng OCR xác nhận có chữ của trang. Bài thử dùng HTML cục bộ, chưa xác nhận tài khoản/DOM Threads thật.
- Lịch sound effect kiểm tra chuỗi bỏ hai bình luận rồi phát hai bình luận liên tiếp, chế độ mỗi N bình luận, chọn Có/Không riêng và công tắc tắt toàn bộ.
- Bản nháp 1.0 giữ tên kênh/tốc độ cũ và nhận mặc định mới cho giọng PC, quét kín, sound effect. Không xóa dữ liệu cũ khi xuất thất bại.
- Dùng Core Image compositor cho cả Simulator và iPhone. Giảm số luồng ggml theo số lõi CPU để tránh tranh CPU với các barrier chờ bận; bản cố định 4 luồng trước đó đã quá thời gian trên VM 3 lõi.
- Release build cho `iphoneos`/arm64 đạt. IPA qua kiểm tra ZIP, plist nền tảng iPhoneOS và Mach-O arm64; SHA-256 khớp artifact đã tải. Đã xem ảnh chụp màn hình app thật trong Simulator, nhãn/nút và tab hiện rõ.

IPA tải về: 247.102.250 byte, phiên bản 1.1.0 (2), minimum iOS 17. Đã kiểm tra SHA-256 toàn IPA, mô hình GGUF và từ điển; dữ liệu giọng gồm speaker embedding 192 chiều và 75 khung mã, đúng hash mẫu PC. So sánh SHA-256 từng media trong IPA với kho PC: 19 sound effect + 6 nhạc + 9 video + 1 video parkour, tất cả khớp.

Giọng dùng cùng phiên bản mô hình và mẫu của Windows 2.9.3. iPhone dùng GGUF Q8_0/codec f16, Windows dùng ONNX fp32; không hứa âm thanh giống từng bit. Không cần gửi lại video mẫu, không cần máy chủ giọng. Có WAV mẫu trong artifact để nghe thử.

Chưa kiểm tra cài bằng iLoader, chạy trên iPhone 14 Plus/iOS 27 thật, đăng nhập/quét bằng tài khoản Threads thật hoặc tốc độ/bộ nhớ trên điện thoại. WebView riêng không lấy phiên đăng nhập từ app Threads khác. Quét kín vẫn cần tool ở foreground; chuyển app sẽ dừng quét. Các giới hạn khác trong README.

IPA SHA-256:
`207769aa7f8e6d0e8299a81e12fde7eac57247a6e890d95ad3ab5747f2bec8cb`
