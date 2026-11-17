# Roadmap mobile

Định hướng: **theo dõi tiến độ + thao tác nhanh**, ưu tiên Student/Team Leader. Web đảm nhiệm lập kế hoạch phức tạp, soạn hồ sơ dài, quản trị học vụ, chấm điểm và công bố. Mobile và web dùng chung backend/database.

## Tiến độ ngày 16/11/2026

Cập nhật **17/11 — 0.5.0**: redesign UX toàn app với các agent phụ trách riêng AI/chat, task/video và QA độc lập. Giảm cụm nút, thống nhất điều hướng/typography, thêm rail cuộn ngang và vuốt tab, form lưu cố định; đã sửa các lỗi keyboard, stale data/reply và focus. Xem [báo cáo UX](MOBILE_UX_REVIEW.md). Chưa mở thêm nghiệp vụ hoặc thay provider BE trong lượt này.

**0.5.1** tiếp tục đóng lỗi tương tác sau redesign: giữ bản đang soạn AI/chat khi Back, sheet/dialog màn ngang, phục hồi truy vấn lỗi, đồng bộ trang sau khi dữ liệu thay đổi và chặn phản hồi phòng họp đến muộn khôi phục quyền cũ. Nghiệm thu thiết bị vẫn được theo dõi riêng.

Bản **0.4.0** bổ sung tạo/sửa/phân công task, xem việc toàn đồ án và dùng gợi ý AI để điền form. Trợ lý có chế độ PROGRESS theo dữ liệu BE để xem tiến độ/deadline ngay cả khi mô hình hỏi tự do chưa sẵn sàng. Chưa thay cấu hình provider AI trên BE.

Theo ưu tiên mới của người dùng, **đồng bộ tính năng trước**; không chặn chat/call/AI để chờ nghiệm thu thiết bị đầy đủ. Bản 0.3.0 đưa chat, phòng họp tích hợp, trợ lý AI và kết quả công bố vào mobile; xem [phạm vi triển khai](MOBILE_COLLABORATION.md). Format/analyze/test/build vẫn là kiểm tra ngắn bắt buộc trước merge.

MOB-04 đến MOB-08 đã có phần triển khai MVP sinh viên trong 0.2.0: project/milestone/thành viên, việc của tôi và trạng thái theo capability, lời mời, inbox, lịch/RSVP, đọc báo cáo/phản hồi. Xem [contract và giới hạn](MOBILE_MVP.md). Dashboard và các màn dùng chung backend staging; không dùng dữ liệu giả khi chạy app.

MOB-03A đã kiểm tra luồng web với staging; nghiệm thu native secure storage/restart và mutation trên bộ dữ liệu thử riêng còn cần thiết. MOB-09 còn nghiệm thu thiết bị Android/iOS, external deep link/OS lifecycle và bản phát hành ký. CI đóng gói debug APK trỏ staging để hỗ trợ bước này. Không đánh dấu toàn bộ sản phẩm đạt production chỉ từ test/build.

## MOB-03 — Nền tảng Flutter

Nền tảng chuyển sang **Flutter/Dart** theo lựa chọn của người dùng: cấu hình API origin qua `API_BASE_URL`, auth/session, hai tab Tổng quan/Tài khoản, dashboard theo contract backend, setup và CI. Xem [quyết định chuyển đổi](FLUTTER_MIGRATION.md) và [validation Flutter](FLUTTER_VALIDATION.md).

## MOB-03A — Nghiệm thu tích hợp trước khi mở rộng

Kết nối với môi trường backend/database thật được phép dùng, bằng tài khoản sinh viên thử nghiệm. Kiểm tra login → `/auth/me` → dashboard, refresh khi hết access token, mở lại app, logout và dữ liệu/quyền bị thay đổi. Chạy trên Android/emulator hoặc thiết bị mục tiêu, xác minh secure storage, safe area, bàn phím và mạng. Ghi môi trường, thiết bị, kết quả và bằng chứng đã che dữ liệu nhạy cảm. Mock/unit/widget test và build không thay thế mốc này.

## Các bước tiếp theo

| Task | Nội dung | Điều kiện hoàn thành |
| --- | --- | --- |
| **MOB-04 — Project và milestone** | Project hiện tại, trạng thái, GVHD, thành viên, milestone và tiến độ | Dùng contract hiện hành; xử lý chưa có team/project, mất quyền, lỗi và làm mới; không hiển thị project ngoài phạm vi |
| **MOB-05 — Việc của tôi** | Danh sách/chi tiết task, deadline, quá hạn, bị chặn; cập nhật trạng thái | Lấy capability từ backend; gửi concurrency token; stale state trả 409 phải làm mới; thay đổi hiển thị được trên web |
| **MOB-06 — Lời mời nhóm** | Danh sách lời mời, nhận/từ chối | Theo đúng trạng thái và quyền API; chống gửi lặp; xử lý lời mời hết hiệu lực; team/context được cập nhật sau thành công |
| **MOB-07 — Inbox thông báo** | Chưa đọc/đã đọc, đọc tất cả, điều hướng về đối tượng | Đúng người nhận, trạng thái đọc được lưu; điểm đến kiểm tra lại quyền khi mở; không nhầm inbox với external push |
| **MOB-08 — Lịch và phản hồi** | Xem lịch họp, liên kết tham gia, report và feedback; RSVP nếu contract phù hợp | Hiển thị giờ theo thiết bị, đúng quyền và trạng thái; đọc được nội dung dài; kiểm thử liên kết và RSVP trên thiết bị |
| **MOB-09 — Hoàn thiện bản thử nghiệm** | UX, mạng yếu, bàn phím, accessibility, đóng gói thử | Smoke test Android/iOS mục tiêu; kiểm tra hết phiên, logout, khởi động lại, back/deep link và dữ liệu bị sửa đồng thời; ghi thiết bị và bằng chứng |

MOB-03A/MOB-09 được theo dõi riêng, không còn là điều kiện chặn mở rộng tính năng theo ưu tiên mới. Mỗi task đi qua nhánh/PR vào `develop`; kiểm tra contract BE hiện hành trước khi nối tính năng.

## Sau MVP

- **Supervisor:** project đang hướng dẫn, nhóm cần chú ý, lịch và đọc/viết phản hồi ngắn. Đối chiếu lại phạm vi với SRS vì bảng actor ghi Web/Responsive, còn external interface nhắc selected supervisor journeys. SRS còn ghi React Native và cần đồng bộ quyết định Flutter; task này không tự sửa tài liệu ở repo docs.
- **Chat/call/AI và kết quả công bố:** đã triển khai trong 0.3.0; dùng chung BE với web, giữ quyền và thời điểm công bố tại BE. Còn nghiệm thu trao đổi giữa hai thiết bị, chất lượng media và quyền OS.
- **External push:** task riêng cho backend lẫn app, gồm đăng ký/thu hồi device token, provider delivery, quyền thông báo, mở đúng màn hình và kiểm thử foreground/background/app đóng. Không cam kết push chỉ bằng việc bổ sung màn hình inbox.
- **Ưu tiên tiếp theo:** soạn/nộp báo cáo gọn và phản hồi ngắn theo quyền; external push, tối ưu SignalR cho chat và nghiệm thu native trước phát hành. Tạo/sửa/phân công task đã có từ 0.4.0. Chưa đưa offline mutation, quản trị học vụ hoặc chấm điểm vào mobile.

## Mốc nghiệm thu

Luồng đầu tiên trên Flutter: đăng nhập → dashboard từ backend/database thật → mở lại app → khôi phục phiên hoặc xử lý hết phiên đúng → đăng xuất. Ghi trạng thái nghiệm thu riêng với kết quả test/build.

Sau MOB-04 đến MOB-08: xem việc sắp đến hạn → mở task → đổi trạng thái theo capability → web thấy thay đổi → đọc feedback/lịch/thông báo. Không dùng dữ liệu giả để thay cho backend chưa kết nối.
