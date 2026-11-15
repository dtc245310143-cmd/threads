# Kiểm tra iOS 1.0.0

Build đã thành công trên GitHub Actions, commit mã ứng dụng `45c3e55724336a22c517ace5a990bdb5a7c4c945`:
https://github.com/dtc245310143-cmd/threads/actions/runs/43699900856

- Bộ quét JavaScript: giữ bản chữ dài nhất, ảnh đúng thứ tự, đúng gốc bài, chỉ xác nhận tác giả trả lời khi có bằng chứng trong chuỗi phản hồi.
- 4 kiểm tra XCTest đạt: phân trang/chuẩn hóa/nhịp đọc; chọn bình luận và round-trip cấu hình; kiểm tra URL/đường dẫn media; xuất MP4 thật có thẻ và sound effect.
- Video thử 1080×1920 dài 6,6 giây: kiểm tra caption tại 0,4 giây, bình luận vẫn hiện tại 2,35 giây trong lúc phát hiệu ứng, lời kết tại 3,3 giây. Dùng OCR trên các khung hình đã giải mã từ MP4 để xác nhận nội dung hiện đúng thời điểm. Có audio track trong video.
- Đã sửa crash của Core Animation trong bộ ghép ảnh bằng một bộ compositor Core Image; cùng bộ compositor được dùng cho Simulator và bản iPhone.
- Release build cho `iphoneos`/arm64 đạt. IPA qua kiểm tra ZIP, plist nền tảng iPhoneOS và Mach-O arm64; SHA-256 khớp artifact đã tải. Đã xem ảnh chụp màn hình app thật trong Simulator, nhãn/nút và tab hiện rõ.

Chưa kiểm tra cài bằng iLoader hoặc chạy trên iPhone thật; chưa đăng nhập/quét bằng tài khoản Threads thật trên iOS. Chưa kiểm tra giọng tiếng Việt trên máy thật vì Simulator không có giọng đó; kiểm tra nhịp đọc hiện xác nhận việc tách câu và mốc nghỉ, không thay thế việc nghe thử trên thiết bị.

Giọng VieNeu/giọng mẫu Windows chưa được chuyển sang bản iOS này. Các khác biệt khác được ghi trong README và giao diện.

IPA SHA-256:
`84041d9bf7077024d3b5166f3c4581d2d79bf4f1f2550f75dbe4fd2871493c62`
